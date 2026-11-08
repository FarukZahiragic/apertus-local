#!/usr/bin/env bash
# Publish the verified GGUF and a static download Space in your own HF namespace.
# Usage: scripts/publish_hf.sh [--private] [--space-only | --model-only]
# Env: HF_TOKEN, HF_PYTHON, MODEL_REPO, SPACE_REPO, MODEL, MMPROJ.
# Uses the SDK only for publishing; participants do not need Python or this SDK.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
source "$REPO_ROOT/config/model.env"
private=0 space_only=0 model_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --private) private=1 ;;
    --space-only) space_only=1 ;;
    --model-only) model_only=1 ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
((space_only + model_only <= 1)) || { echo 'error: choose --space-only or --model-only' >&2; exit 1; }
python="${HF_PYTHON:-$REPO_ROOT/.venv-release/bin/python}"
[[ -x "$python" ]] || { echo 'error: create .venv-release and install huggingface_hub (see docs/DISTRIBUTION.md)' >&2; exit 1; }
# A normal HF login caches credentials outside the repository. API calls receive
# that credential through the environment; never print or package it.
if [[ -z "${HF_TOKEN:-}" ]]; then
  HF_TOKEN="$("$python" -c 'from huggingface_hub import get_token; import sys; sys.stdout.write(get_token() or "")')"
  export HF_TOKEN
fi
[[ -n "$HF_TOKEN" ]] || { echo 'error: run .venv-release/bin/hf auth login first' >&2; exit 1; }
model="${MODEL:-$REPO_ROOT/models/$APERTUS_MODEL_FILE}"
mmfile="$(source "$REPO_ROOT/config/multimodal.env"; printf '%s' "$APERTUS_MODEL_FILE")"
mmsha="$(source "$REPO_ROOT/config/multimodal.env"; printf '%s' "$APERTUS_MODEL_SHA256")"
mmproj="${MMPROJ:-$REPO_ROOT/models/$mmfile}"
if [[ "$space_only" -eq 0 ]]; then
  echo "Verifying $APERTUS_MODEL_FILE before upload."
  ap_verify "$model" "$APERTUS_MODEL_SHA256" || { echo 'error: model does not match the pinned checksum' >&2; exit 1; }
  ap_verify "$mmproj" "$mmsha" || { echo 'error: encoders do not match the pinned checksum' >&2; exit 1; }
fi
"$python" -u - "$REPO_ROOT" "$model" "$mmproj" "$private" "$space_only" "$model_only" "$APERTUS_MODEL_SHA256" "$mmsha" <<'PY'
import json, os, shutil, sys, tempfile
from pathlib import Path
from huggingface_hub import CommitOperationAdd, HfApi
root, model, mmproj = map(Path, sys.argv[1:4])
private, space_only, model_only = (value == '1' for value in sys.argv[4:7])
expected, mm_expected = sys.argv[7:9]
source_config = json.loads((root/'hf-space/config.json').read_text())
artifacts = [('model', model, expected), ('encoders', mmproj, mm_expected)]
for key, path, digest in artifacts:
    if source_config[key]['sha256'] != digest:
        raise SystemExit('error: download-page checksum disagrees with pinned ' + key)
    if not space_only and path.stat().st_size != source_config[key]['bytes']:
        raise SystemExit('error: local artifact size disagrees with pinned ' + key)
api = HfApi(token=os.environ['HF_TOKEN'])
account = api.whoami()['name']
model_repo = os.environ.get('MODEL_REPO', account + '/Apertus-v1.5-8B-GGUF')
space_repo = os.environ.get('SPACE_REPO', account + '/apertus-local')
if any(repo.split('/')[0] != account for repo in [model_repo, space_repo]):
    raise SystemExit('error: repositories must be in the authenticated personal namespace')
if not space_only:
    api.create_repo(model_repo, repo_type='model', private=private, exist_ok=True)
    print('Model repository: https://huggingface.co/' + model_repo, flush=True)
    operations = [
        *(CommitOperationAdd(path_in_repo=source_config[key]['filename'], path_or_fileobj=str(path))
          for key, path, digest in artifacts),
        CommitOperationAdd(path_in_repo='README.md', path_or_fileobj=str(root/'packaging/MODEL_CARD.md')),
        CommitOperationAdd(path_in_repo='LICENSE.txt', path_or_fileobj=str(root/'packaging/APERTUS-LICENSE.txt')),
        CommitOperationAdd(path_in_repo='SHA256SUMS', path_or_fileobj=''.join(
            digest + '  ' + source_config[key]['filename'] + '\n' for key, path, digest in artifacts).encode()),
    ]
    commit = api.create_commit(model_repo, repo_type='model', operations=operations,
                               commit_message='Publish verified Apertus language weights and F32 input encoders')
    revision = commit.oid
else:
    revision = api.model_info(model_repo).sha
# Verify both remote artifacts before advertising any native download.
info = api.model_info(model_repo, revision=revision, files_metadata=True)
for key, path, digest in artifacts:
    filename = source_config[key]['filename']
    sibling = next((file for file in info.siblings if file.rfilename == filename), None)
    if sibling is None or sibling.lfs is None or sibling.lfs.sha256 != digest or sibling.size != source_config[key]['bytes']:
        raise SystemExit('error: published ' + key + ' does not match the pinned artifact')
space_commit = None
if not model_only:
    with tempfile.TemporaryDirectory(prefix='apertus-hf-space-') as stage:
        stage = Path(stage)
        shutil.copytree(root/'hf-space', stage, dirs_exist_ok=True)
        config = json.loads((stage/'config.json').read_text())
        for key, path, digest in artifacts:
            config[key].update(repo=model_repo, revision=revision,
                                url=f'https://huggingface.co/{model_repo}/resolve/{revision}/{config[key]["filename"]}')
        (stage/'config.json').write_text(json.dumps(config, indent=2)+'\n')
        api.create_repo(space_repo, repo_type='space', space_sdk='static', private=private, exist_ok=True)
        commit = api.upload_folder(repo_id=space_repo, repo_type='space', folder_path=str(stage),
                                   allow_patterns=['README.md','index.html','macos-first-start.html','windows-first-start.html','style.css','app.js','config.json','assets/*'],
                                   commit_message='Publish native Apertus Local download page')
        space_commit = commit.oid
result = {'model_repo': model_repo, 'model_revision': revision,
          'model_url': f'https://huggingface.co/{model_repo}',
          'space_url': f'https://huggingface.co/spaces/{space_repo}', 'space_commit': space_commit}
(root/'dist').mkdir(exist_ok=True)
(root/'dist/hf-publication.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2), flush=True)
PY
