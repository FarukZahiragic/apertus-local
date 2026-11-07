#!/usr/bin/env bash
# Serve Apertus with speculative decoding: same as scripts/serve.sh (web UI, OpenAI
# API, thinking off, offline) plus a draft head. The draft reuses the target's token
# embedding (and, for DSpark, its output head).
#
# Usage: scripts/serve_spec.sh [-- extra llama-server args]
# Env:   DRAFT      draft GGUF (default: models/apertus-v1.5-8b-eagle3.1-e10-Q4_0.gguf)
#        SPEC_TYPE  draft-eagle3 or draft-dspark (default: from the DRAFT file name)
#        K          tokens drafted per step (default: 3)
#        plus everything scripts/serve.sh reads, including BUILD_DIR
# CPU-only by default. Pass -- --n-gpu-layers 99 --n-gpu-layers-draft 99
# with the Vulkan build to offload both models to Iris Xe.
#
# The drafts were trained on thinking-off answers; with THINKING=1 acceptance drops.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
# Speculative runs keep their measured CPU default; acceleration remains explicit.
export BACKEND="${BACKEND:-cpu}" THREADS="${THREADS:-$(ap_threads)}"
DRAFT="${DRAFT:-$REPO_ROOT/models/apertus-v1.5-8b-eagle3.1-e10-Q4_0.gguf}"
K="${K:-3}"
if [[ -z "${SPEC_TYPE:-}" ]]; then
  case "$(basename "$DRAFT")" in
    *eagle3*) SPEC_TYPE=draft-eagle3 ;;
    *dspark*) SPEC_TYPE=draft-dspark ;;
    *) echo "error: set SPEC_TYPE (draft-eagle3 or draft-dspark) for $DRAFT" >&2; exit 1 ;;
  esac
fi

[[ "${1:-}" == "--" ]] && shift
[[ -f "$DRAFT" ]] || { echo "error: draft not found: $DRAFT (see README step 5)" >&2; exit 1; }

echo "Draft: $DRAFT ($SPEC_TYPE, k=$K)"
exec "$REPO_ROOT/scripts/serve.sh" -- \
  --model-draft "$DRAFT" \
  --spec-type "$SPEC_TYPE" \
  --spec-draft-n-max "$K" \
  --threads-draft "${THREADS:-4}" \
  --n-gpu-layers-draft 0 \
  "$@"
