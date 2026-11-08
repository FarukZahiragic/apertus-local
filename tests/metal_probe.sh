#!/usr/bin/env bash
# Compare Metal correctness profiles using a previously built Mac CI app.
# Usage: tests/metal_probe.sh PROFILE METAL_BUILD_DIR
# Profiles: default, flash-off, no-fusion, no-kv, no-op-offload.
# Diagnostic requests run on a labelled hosted VM; these are not benchmarks.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# -eq 2 ]] || { echo 'error: provide profile and Metal runtime directory' >&2; exit 1; }
profile="$1"
export BACKEND=metal BUILD_DIR="$2" PORT=18088 THREADS=2 CTX=512
export HARDWARE_KIND='GitHub-hosted Apple M1 VM (NOT laptop)'
args=()
case "$profile" in
  default) ;;
  flash-off) args=(--flash-attn off) ;;
  no-fusion) export GGML_METAL_FUSION_DISABLE=1 ;;
  no-kv) args=(--no-kv-offload) ;;
  no-op-offload) args=(--no-op-offload) ;;
  *) echo 'error: unknown profile' >&2; exit 1 ;;
esac
mkdir -p dist
scripts/serve.sh -- "${args[@]+"${args[@]}"}" > dist/metal-probe-server.log 2>&1 &
probe_pid=$!
cleanup() { kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
ready=0
for ((i=0; i<300; i++)); do
  kill -0 "$probe_pid" 2>/dev/null || { tail -n 40 dist/metal-probe-server.log; exit 1; }
  if curl --noproxy '*' -sf --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null; then ready=1; break; fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || { tail -n 40 dist/metal-probe-server.log; exit 1; }
python3 - "$profile" <<'PY'
import json, os, urllib.request
from pathlib import Path
import sys
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
base='http://127.0.0.1:'+os.environ['PORT']
with opener.open(base+'/v1/models') as response: model=json.load(response)['data'][0]['id']
def post(path, body):
 request=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
 with opener.open(request,timeout=300) as response: return json.load(response)
chat=post('/v1/chat/completions',dict(model=model,messages=[{'role':'user','content':'Document: The workshop takes place in Sarajevo. Question: Which city hosts the workshop? Answer with only the city name.'}],max_tokens=64,temperature=0))
raw=post('/completion',dict(prompt='The capital of Switzerland is',n_predict=8,temperature=0,n_probs=3))
result={'profile':sys.argv[1],'hardware':os.environ['HARDWARE_KIND'],
        'gpu_layers':os.environ.get('GPU_LAYERS','99'),'load_mode':os.environ.get('LOAD_MODE','auto'),
        'chat':chat,'raw':raw}
Path('dist/metal-probe.json').write_text(json.dumps(result,indent=2)+'\n')
message=chat.get('choices',[{}])[0].get('message',{})
print(json.dumps({'profile':sys.argv[1],'message':message,'usage':chat.get('usage'), 'raw_content':raw.get('content'),'raw_stop_type':raw.get('stop_type')},indent=2))
PY
