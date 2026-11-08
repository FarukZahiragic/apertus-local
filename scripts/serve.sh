#!/usr/bin/env bash
# Serve Apertus locally with llama-server: chat web UI and OpenAI-compatible API.
# Works with networking disabled; see docs/OFFLINE.md.
#
# Usage: scripts/serve.sh [-- extra llama-server args]
# Env:   MODEL    GGUF file   (default: models/apertus-v1.5-8b-Q4_K_M.gguf)
#        HOST     bind address (default: 127.0.0.1, this machine only)
#        PORT     (default: 8080)
#        THREADS  (default: physical cores, performance cores on Apple Silicon)
#        BACKEND  auto|cpu|metal|vulkan (auto: CPU until Metal is validated)
#        APERTUS_METAL_VALIDATED=1 enables automatic Metal on Apple Silicon
#        CTX      context size in tokens (default: 4096; 8192 for longer documents)
#        THINKING 1 to let Apertus deliberate before answering (default: 0, off)
#        LLAMA_CPP_DIR checkout location (default: vendor/llama.cpp)
#        BUILD_DIR build location (default: $LLAMA_CPP_DIR/build)
# CPU-only by default. For Iris Xe use BUILD_DIR=vendor/llama.cpp/build-vulkan
# and pass -- --n-gpu-layers 99 (after building with setup_llamacpp.sh --vulkan).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0
fi
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
ap_runtime "$REPO_ROOT"
SERVER="$BUILD_DIR/bin/llama-server"

MODEL="${MODEL:-$REPO_ROOT/models/apertus-v1.5-8b-Q4_K_M.gguf}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
CTX="${CTX:-4096}"
THINKING="${THINKING:-0}"
for value in "$PORT" "$CTX"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'error: PORT and CTX must be positive integers' >&2; exit 1; }
done
((PORT <= 65535)) || { echo 'error: PORT must be at most 65535' >&2; exit 1; }
[[ "$THINKING" == 0 || "$THINKING" == 1 ]] || { echo 'error: THINKING must be 0 or 1' >&2; exit 1; }

[[ "${1:-}" == "--" ]] && shift
[[ -x "$SERVER" ]] || { echo "error: $SERVER missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "error: model not found: $MODEL (see README step 2)" >&2; exit 1; }

# The upstream template enables deliberation by default; on a CPU that adds tens of
# seconds of reasoning before every answer, so it is off unless THINKING=1.
if [[ "$THINKING" == "1" ]]; then enable_thinking=true; else enable_thinking=false; fi

echo "Web UI:     http://$HOST:$PORT/"
echo "OpenAI API: http://$HOST:$PORT/v1  (any API key)"
echo "Runtime:    $AP_BACKEND; $THREADS threads; context $CTX; thinking $THINKING"
echo "Build:      $BUILD_DIR"

# The chat template comes from the GGUF (Apertus 1.5 format, rendered with jinja).
# One slot: a single local user gets the whole context and all cores.
exec "$SERVER" \
  --model "$MODEL" \
  --alias "$(basename "$MODEL" .gguf)" \
  --host "$HOST" --port "$PORT" \
  --threads "$THREADS" \
  --ctx-size "$CTX" \
  --parallel 1 \
  --n-gpu-layers "$AP_GPU_LAYERS" \
  --jinja \
  --chat-template-kwargs "{\"enable_thinking\":$enable_thinking}" \
  --offline \
  "$@"
