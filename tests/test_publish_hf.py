"""Validate publication ordering and both artifact pins without any network calls."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FAKE_HUB = '''
import json, os
from pathlib import Path
from types import SimpleNamespace as S
def record(kind, **values):
    with open(os.environ['PUBLISH_LOG'], 'a') as f:
        f.write(json.dumps(dict(kind=kind, **values))+'\\n')
class CommitOperationAdd:
    def __init__(self, **values): self.__dict__.update(values)
class HfApi:
    def __init__(self, **kwargs): pass
    def whoami(self): return {'name':'fixture'}
    def create_repo(self, repo_id, **kwargs): record('create_repo', repo=repo_id)
    def create_commit(self, repo_id, operations, **kwargs):
        names=[op.path_in_repo for op in operations]
        sums=next(op.path_or_fileobj.decode() for op in operations if op.path_in_repo=='SHA256SUMS')
        record('model_commit', names=names, sums=sums)
        return S(oid='model-revision')
    def model_info(self, repo_id, **kwargs):
        config=json.loads(Path(os.environ['PUBLISH_CONFIG']).read_text())
        files=[]
        for key in ['model','encoders']:
            item=config[key]
            digest='0'*64 if key=='encoders' and os.environ.get('PUBLISH_BAD_REMOTE') else item['sha256']
            files.append(S(rfilename=item['filename'],size=item['bytes'],lfs=S(sha256=digest)))
        return S(sha='existing-revision',siblings=files)
    def upload_folder(self, repo_id, folder_path, **kwargs):
        config=json.loads((Path(folder_path)/'config.json').read_text())
        record('space_commit', config=config)
        return S(oid='space-revision')
'''


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='apertus publication ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ['scripts','config','models','hf-space','packaging','fake']:
            (self.root/directory).mkdir()
        for script in ['publish_hf.sh','platform.sh']:
            shutil.copy2(ROOT/'scripts'/script,self.root/'scripts'/script)
        for name in ['MODEL_CARD.md','APERTUS-LICENSE.txt']:
            shutil.copy2(ROOT/'packaging'/name,self.root/'packaging'/name)
        self.config = {}
        for key, filename, envfile in [('model','language.gguf','model.env'),('encoders','encoders.gguf','multimodal.env')]:
            data=(key+' fixture').encode()
            (self.root/'models'/filename).write_bytes(data)
            digest=hashlib.sha256(data).hexdigest()
            self.config[key]={'filename':filename,'sha256':digest,'bytes':len(data)}
            (self.root/'config'/envfile).write_text(
                f'APERTUS_MODEL_FILE={filename}\nAPERTUS_MODEL_SHA256={digest}\n')
        self.config_path=self.root/'hf-space/config.json'
        self.config_path.write_text(json.dumps(self.config))
        (self.root/'fake/huggingface_hub.py').write_text(FAKE_HUB)
        self.log=self.root/'calls.jsonl'
        self.env=dict(os.environ,HF_TOKEN='fixture',HF_PYTHON=sys.executable,
                      PYTHONPATH=str(self.root/'fake'),PUBLISH_CONFIG=str(self.config_path),PUBLISH_LOG=str(self.log))
        for name in ['MODEL','MMPROJ','MODEL_REPO','SPACE_REPO','PUBLISH_BAD_REMOTE']:
            self.env.pop(name,None)

    def publish(self,*args):
        return subprocess.run([os.environ.get('TEST_BASH','bash'),str(self.root/'scripts/publish_hf.sh'),*args],
                              env=self.env,capture_output=True,text=True,timeout=15)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_both_artifacts_and_checksums_precede_space_publication(self):
        result=self.publish()
        self.assertEqual(result.returncode,0,result.stderr)
        calls=self.calls()
        model=next(c for c in calls if c['kind']=='model_commit')
        for key in ['model','encoders']:
            item=self.config[key]
            self.assertIn(item['filename'],model['names'])
            self.assertIn(item['sha256']+'  '+item['filename'],model['sums'])
        page=calls[-1]
        self.assertEqual(page['kind'],'space_commit')
        for key in ['model','encoders']:
            self.assertEqual(page['config'][key]['revision'],'model-revision')
            self.assertIn('/resolve/model-revision/',page['config'][key]['url'])

    def test_model_only_prepares_weights_without_changing_space(self):
        result=self.publish('--model-only')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('model_commit',[c['kind'] for c in self.calls()])
        self.assertNotIn('space_commit',[c['kind'] for c in self.calls()])

    def test_space_only_rejects_wrong_remote_encoder(self):
        self.env['PUBLISH_BAD_REMOTE']='1'
        result=self.publish('--space-only')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('published encoders does not match',result.stderr)
        self.assertEqual(self.calls(),[])

    def test_corrupt_local_encoder_rejected_before_publication(self):
        (self.root/'models/encoders.gguf').write_bytes(b'corrupt')
        result=self.publish('--model-only')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('encoders do not match',result.stderr)
        self.assertEqual(self.calls(),[])

    def test_foreign_namespace_rejected(self):
        self.env['MODEL_REPO']='another-account/model'
        result=self.publish('--space-only')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('personal namespace',result.stderr)
        self.assertEqual(self.calls(),[])
