#!/usr/bin/env bash
# Serve Apertus locally with llama-server: chat web UI and OpenAI-compatible API.
# Works with networking disabled; see docs/OFFLINE.md.
#
# Usage: scripts/serve.sh [-- extra llama-server args]
# Env:   MODEL    GGUF file   (default: models/apertus-v1.5-8b-Q4_K_M.gguf)
#        HOST     bind address (default: 127.0.0.1, this machine only)
#        PORT     (default: 8080)
#        THREADS  (default: 4, one per physical core on the i5-1135G7)
#        CTX      context size in tokens (default: 4096; 8192 for longer documents)
#        THINKING 1 to let Apertus deliberate before answering (default: 0, off)
#        LLAMA_CPP_DIR checkout location (default: vendor/llama.cpp)
#        BUILD_DIR build location (default: $LLAMA_CPP_DIR/build)
# CPU-only by default. For Iris Xe use BUILD_DIR=vendor/llama.cpp/build-vulkan
# and pass -- --n-gpu-layers 99 (after building with setup_llamacpp.sh --vulkan).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_CPP_DIR/build}"
SERVER="$BUILD_DIR/bin/llama-server"

MODEL="${MODEL:-$REPO_ROOT/models/apertus-v1.5-8b-Q4_K_M.gguf}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
THREADS="${THREADS:-4}"
CTX="${CTX:-4096}"
THINKING="${THINKING:-0}"

[[ "${1:-}" == "--" ]] && shift
[[ -x "$SERVER" ]] || { echo "error: $SERVER missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "error: model not found: $MODEL (see README step 2)" >&2; exit 1; }

# The upstream template enables deliberation by default; on a CPU that adds tens of
# seconds of reasoning before every answer, so it is off unless THINKING=1.
if [[ "$THINKING" == "1" ]]; then enable_thinking=true; else enable_thinking=false; fi

echo "Web UI:     http://$HOST:$PORT/"
echo "OpenAI API: http://$HOST:$PORT/v1  (any API key)"

# The chat template comes from the GGUF (Apertus 1.5 format, rendered with jinja).
# One slot: a single local user gets the whole context and all cores.
exec "$SERVER" \
  --model "$MODEL" \
  --alias "$(basename "$MODEL" .gguf)" \
  --host "$HOST" --port "$PORT" \
  --threads "$THREADS" \
  --ctx-size "$CTX" \
  --parallel 1 \
  --n-gpu-layers 0 \
  --jinja \
  --chat-template-kwargs "{\"enable_thinking\":$enable_thinking}" \
  --offline \
  "$@"
