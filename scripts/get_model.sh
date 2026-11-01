#!/usr/bin/env bash
# Download one GGUF file from Hugging Face into models/ and verify its sha256.
#
# Usage: scripts/get_model.sh [HF_REPO FILE]
#   default: Qwen/Qwen2.5-1.5B-Instruct-GGUF qwen2.5-1.5b-instruct-q4_k_m.gguf
# Env:   HF_TOKEN    used for gated or private repos (optional)
#        MODELS_DIR  destination directory (default: models/)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HF_REPO="${1:-Qwen/Qwen2.5-1.5B-Instruct-GGUF}"
FILE="${2:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"
MODELS_DIR="${MODELS_DIR:-$REPO_ROOT/models}"
URL="https://huggingface.co/$HF_REPO/resolve/main/$FILE"
DEST="$MODELS_DIR/$FILE"

auth=()
[[ -n "${HF_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $HF_TOKEN")

mkdir -p "$MODELS_DIR"

# For LFS files, Hugging Face returns the sha256 in the X-Linked-Etag header.
expected="$(curl -sfI "${auth[@]}" "$URL" | tr -d '\r"' \
  | awk 'tolower($1) == "x-linked-etag:" { print $2 }')" || {
  echo "error: cannot access $URL (gated/private repo without HF_TOKEN, or wrong name?)" >&2
  exit 1
}

if [[ -f "$DEST" && -n "$expected" ]] && echo "$expected  $DEST" | sha256sum -c --status; then
  echo "already present and verified: $DEST"
  exit 0
fi

echo "downloading $HF_REPO/$FILE -> $DEST"
curl -fL --retry 5 --retry-delay 4 -C - "${auth[@]}" -o "$DEST" "$URL"

if [[ -n "$expected" ]]; then
  echo "$expected  $DEST" | sha256sum -c -
else
  echo "warning: no sha256 published for $FILE; skipping verification" >&2
fi
