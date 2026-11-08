"""Build a tiny fixture package, using the real Mac app compiler when on macOS."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')


class PackageTests(unittest.TestCase):
    def test_native_archive_and_mac_identity(self):
        with tempfile.TemporaryDirectory(prefix='apertus package ') as directory:
            root = Path(directory)
            for folder in ['scripts','config','packaging']:
                (root/folder).mkdir()
            for name in ['package_release.sh','platform.sh','get_model.sh','serve.sh','launch.sh']:
                shutil.copy2(ROOT/'scripts'/name, root/'scripts'/name)
            shutil.copy2(ROOT/'config/model.env', root/'config/model.env')
            for source in (ROOT/'packaging').iterdir():
                if source.is_file():
                    shutil.copy2(source, root/'packaging'/source.name)
            for name in ['Start.command','Stop.command','Start.sh','Stop.sh']:
                shutil.copy2(ROOT/name, root/name)
            vendor = root/'vendor/llama.cpp'
            vendor.mkdir(parents=True)
            (vendor/'LICENSE').write_text('Fixture runtime, not a distributable model engine.\n')
            for repo in [root, vendor]:
                subprocess.run(['git','init','-q',str(repo)],check=True)
                subprocess.run(['git','-C',str(repo),'-c','user.name=Test','-c','user.email=test@example.invalid',
                                'commit','-q','--allow-empty','-m','Fixture'],check=True)
            for backend in ['build-portable','build-metal-portable']:
                build = vendor/backend
                (build/'bin').mkdir(parents=True)
                (build/'CMakeCache.txt').write_text('GGML_NATIVE:BOOL=OFF\nGGML_BACKEND_DL:BOOL=ON\n'
                                                  f'GGML_METAL:BOOL={"ON" if "metal" in backend else "OFF"}\n')
                for name in ['llama-server','llama-bench','llama-cli']:
                    path = build/'bin'/name
                    path.write_text('#!/bin/sh\necho "fixture executable"\n')
                    path.chmod(0o755)
            env = dict(os.environ, OUTPUT_DIR=str(root/'dist'))
            # Keep this fixture independent of developer overrides.
            for name in ['CPU_BUILD_DIR','METAL_BUILD_DIR','MODEL_URL','APERTUS_MODEL_REPO','APERTUS_MODEL_REVISION']:
                env.pop(name,None)
            result = subprocess.run([BASH,str(root/'scripts/package_release.sh'),'--version','fixture'],
                                    env=env,text=True,capture_output=True,timeout=90)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            if sys.platform == 'darwin':
                archive = root/'dist/apertus-local-fixture-macos-arm64.zip'
                with zipfile.ZipFile(archive) as handle:
                    info = plistlib.loads(handle.read('Apertus Local.app/Contents/Info.plist'))
                    self.assertEqual(info['CFBundleIdentifier'],'io.github.FarukZahiragic.apertus-local')
                    self.assertIn('Terminal',info['NSAppleEventsUsageDescription'])
                    manifest = json.loads(handle.read('Apertus Local.app/Contents/Resources/apertus-local/release.json'))
            else:
                archive = root/'dist/apertus-local-fixture-linux-x86_64.tar.gz'
                with tarfile.open(archive) as handle:
                    manifest = json.load(handle.extractfile('apertus-local-fixture-linux-x86_64/release.json'))
            self.assertEqual(manifest['version'],'fixture')
            self.assertIn('scripts/launch.sh',manifest['files'])
            self.assertTrue(Path(str(archive)+'.sha256').exists())
            self.assertFalse(any(name.startswith('models/') for name in manifest['files']))


if __name__ == '__main__':
    unittest.main()
