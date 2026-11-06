#!/usr/bin/env bash
# Serve Apertus with DSpark speculative decoding: same as scripts/serve.sh (web UI,
# OpenAI API, thinking off, offline) plus the DSpark draft. The draft reuses the
# target's token embedding and output head, so it adds about 1 GB of weights.
#
# Usage: scripts/serve_dspark.sh [-- extra llama-server args]
# Env:   DRAFT   draft GGUF (default: models/apertus-v1.5-8b-dspark-e10-Q4_K_M.gguf)
#        K       tokens drafted per step (default: 3; the block allows up to 8)
#        plus everything scripts/serve.sh reads (MODEL, HOST, PORT, THREADS, CTX, THINKING)
#
# The draft was trained on thinking-off answers; with THINKING=1 acceptance drops.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRAFT="${DRAFT:-$REPO_ROOT/models/apertus-v1.5-8b-dspark-e10-Q4_K_M.gguf}"
K="${K:-3}"

[[ "${1:-}" == "--" ]] && shift
[[ -f "$DRAFT" ]] || { echo "error: draft not found: $DRAFT (see README step 5)" >&2; exit 1; }

echo "DSpark draft: $DRAFT (k=$K)"
exec "$REPO_ROOT/scripts/serve.sh" -- \
  --model-draft "$DRAFT" \
  --spec-type draft-dspark \
  --spec-draft-n-max "$K" \
  --threads-draft "${THREADS:-4}" \
  "$@"
