#!/usr/bin/env bash
# Download a GGUF, resume interruptions, verify SHA-256, then install atomically.
# Usage: scripts/get_model.sh [--apertus | --multimodal | HF_REPO FILE]
# Default: Qwen/Qwen2.5-1.5B-Instruct-GGUF qwen2.5-1.5b-instruct-q4_k_m.gguf
# --apertus uses config/model.env, including the pinned checksum; a verified local
# copy works without networking. Set APERTUS_MODEL_REPO or MODEL_URL for download.
# Env: HF_TOKEN, MODELS_DIR, MODEL_URL, MODEL_REVISION, MODEL_SHA256, MODEL_BYTES.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
  --apertus)
    [[ $# -eq 1 ]] || { echo 'error: --apertus takes no arguments' >&2; exit 1; }
    source "$REPO_ROOT/config/model.env"
    HF_REPO="$APERTUS_MODEL_REPO" FILE="$APERTUS_MODEL_FILE"
    MODEL_SHA256="${MODEL_SHA256:-$APERTUS_MODEL_SHA256}"
    MODEL_BYTES="${MODEL_BYTES:-$APERTUS_MODEL_BYTES}"
    MODEL_REVISION="${MODEL_REVISION:-$APERTUS_MODEL_REVISION}"
    ;;
  --multimodal)
    [[ $# -eq 1 ]] || { echo 'error: --multimodal takes no arguments' >&2; exit 1; }
    source "$REPO_ROOT/config/multimodal.env"
    HF_REPO="$APERTUS_MODEL_REPO" FILE="$APERTUS_MODEL_FILE"
    # Language-model URL/checksum overrides must never leak into this download.
    MODEL_SHA256="$APERTUS_MODEL_SHA256" MODEL_BYTES="$APERTUS_MODEL_BYTES"
    MODEL_REVISION="$APERTUS_MODEL_REVISION"
    MODEL_URL="${MMPROJ_URL:-$APERTUS_MODEL_URL}"
    ;;
  *)
    [[ $# -eq 0 || $# -eq 2 ]] || { echo 'error: provide HF_REPO FILE, or --apertus' >&2; exit 1; }
    HF_REPO="${1:-Qwen/Qwen2.5-1.5B-Instruct-GGUF}"
    FILE="${2:-qwen2.5-1.5b-instruct-q4_k_m.gguf}"
    ;;
esac
[[ "$FILE" != */* && "$FILE" != .* ]] || { echo 'error: FILE must be a file name, without directories' >&2; exit 1; }
MODELS_DIR="${MODELS_DIR:-$REPO_ROOT/models}"
DEST="$MODELS_DIR/$FILE"
mkdir -p "$MODELS_DIR"
expected="${MODEL_SHA256:-}"
if [[ -n "$expected" ]] && [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
  echo 'error: MODEL_SHA256 must be a 64-character SHA-256 digest' >&2; exit 1
fi
expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
if [[ -f "$DEST" && -n "$expected" ]] && ap_verify "$DEST" "$expected"; then
  echo "already present and verified: $DEST"; exit 0
fi
if [[ -z "${MODEL_URL:-}" && -z "$HF_REPO" ]]; then
  echo "error: copy $FILE into $MODELS_DIR, or set APERTUS_MODEL_REPO / MODEL_URL (see README.md)" >&2
  exit 1
fi
URL="${MODEL_URL:-https://huggingface.co/$HF_REPO/resolve/${MODEL_REVISION:-main}/$FILE}"
auth=()
if [[ "$URL" == https://huggingface.co/* && -n "${HF_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer $HF_TOKEN")
fi
if [[ -z "$expected" ]]; then
  expected="$(curl -sfI "${auth[@]+"${auth[@]}"}" "$URL" | tr -d '\r"' | awk 'tolower($1) == "x-linked-etag:" {print $2}')" || {
    echo 'error: cannot access model; check the repository name, access terms, and HF_TOKEN' >&2; exit 1;
  }
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || {
    echo 'error: no SHA-256 published; provide MODEL_SHA256 explicitly' >&2; exit 1;
  }
fi
if [[ -f "$DEST" ]] && ap_verify "$DEST" "$expected"; then
  echo "already present and verified: $DEST"; exit 0
fi
lock="$DEST.download-lock"
mkdir "$lock" 2>/dev/null || {
  echo "error: download already running; if interrupted, remove the empty directory $lock" >&2; exit 1;
}
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
partial="$DEST.part"
# A download may have finished immediately before an interruption. Recover it
# without sending a Range request beyond EOF (which some servers reject).
if [[ -f "$partial" ]] && ap_verify "$partial" "$expected"; then
  mv -f "$partial" "$DEST"
  echo "recovered completed download: $DEST"
  exit 0
fi
if [[ -n "${MODEL_BYTES:-}" ]]; then
  [[ "$MODEL_BYTES" =~ ^[1-9][0-9]*$ ]] || { echo 'error: invalid MODEL_BYTES' >&2; exit 1; }
  received=0
  [[ ! -f "$partial" ]] || received="$(wc -c < "$partial" | tr -d ' ')"
  available="$(df -Pk "$MODELS_DIR" | awk 'NR==2 {printf "%.0f", $4*1024}')"
  if ((available < MODEL_BYTES - received + 104857600)); then
    echo 'error: insufficient free disk space for the model (including 100 MiB reserve)' >&2; exit 1
  fi
fi
echo "downloading $FILE into $MODELS_DIR (interrupt and rerun to resume)"
curl -fL --retry 5 --retry-delay 4 -C - "${auth[@]+"${auth[@]}"}" -o "$partial" "$URL"
echo "verifying SHA-256: $FILE"
if ! ap_verify "$partial" "$expected"; then
  rm -f "$partial"
  echo 'error: checksum mismatch; incomplete or incorrect model removed; rerun to download again' >&2; exit 1
fi
mv -f "$partial" "$DEST"
echo "ready: $DEST"
