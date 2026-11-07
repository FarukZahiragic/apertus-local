#!/usr/bin/env bash
# Real-model native CI smoke check. Hosted-runner results are VM checks, not laptop benchmarks.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/platform.sh
export HARDWARE_KIND='GitHub-hosted VM (NOT laptop)' PORT=18087 CTX=512 THREADS=2
launcher=''
cleanup() {
  if [[ -n "$launcher" ]]; then
    kill "$launcher" 2>/dev/null || true
    wait "$launcher" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
backends=(cpu)
if [[ "$(ap_os)" == Darwin ]]; then backends+=(metal); fi
for backend in "${backends[@]}"; do
  export BACKEND="$backend"
  # The hosted M1 VM has 7 GB RAM and a limited Metal working set.
  # Partial offload exercises Metal without treating full-offload OOM as a
  # model compatibility result. Physical 16 GB+ Macs still need full validation.
  # Avoid mmap: sparse GPU tensors (early output head/rope plus last layers)
  # otherwise map almost the entire GGUF into Metal even at partial offload.
  if [[ "$backend" == metal ]]; then
    export GPU_LAYERS=8 LOAD_MODE=none
  else
    export GPU_LAYERS=0 LOAD_MODE=auto
  fi
  if [[ "$backend" == cpu ]]; then export BUILD_DIR="$PWD/vendor/llama.cpp/build-portable"; else export BUILD_DIR="$PWD/vendor/llama.cpp/build-metal-portable"; fi
  if [[ "$backend" == metal ]] && ! ap_device_available "$BUILD_DIR/bin/llama-server" metal; then
    echo 'Hosted Mac VM exposes no Metal device; Metal build passed, inference requires a physical Mac.'
    echo '{"status":"unavailable","reason":"hosted VM exposes no Metal device"}' > dist/validation-metal.json
    continue
  fi
  scripts/launch.sh --no-browser > "dist/launcher-$backend.log" 2>&1 &
  launcher=$!
  ready=0
  for ((i=0; i<300; i++)); do
    kill -0 "$launcher" 2>/dev/null || { cat "dist/launcher-$backend.log"; exit 1; }
    if grep -q 'Ready:' "dist/launcher-$backend.log"; then ready=1; break; fi
    sleep 1
  done
  [[ "$ready" -eq 1 ]] || { cat "dist/launcher-$backend.log"; exit 1; }
  if ! scripts/validate_local.sh --repeat 1 --max-tokens 16 --report "dist/validation-$backend.json"; then
    tail -n 50 ".apertus-state/server-$PORT-$backend.log"
    exit 1
  fi
  scripts/launch.sh --stop
  wait "$launcher"
  launcher=''
done
