#!/usr/bin/env bash
# Convert a speculative-decoding draft head for Apertus v1.5 to GGUF.
# Drafts share the target's token embedding (and, for DSpark, its output head) at
# runtime, so only the target's config and tokenizer files are needed (not its weights).
#
# Usage: scripts/convert_draft.sh [--head dspark|eagle3] [--hf-dir DIR] [TYPE ...]
#   --head      draft preset (default: dspark):
#                 dspark  faruk-zahiragic/Apertus-v1.5-8B-DSpark-e10-thinking-off (5 layers)
#                 eagle3  faruk-zahiragic/Apertus-v1.5-8B-EAGLE3.1-e10-thinking-off (1 layer)
#   TYPE        llama-quantize types to produce besides F16 (default: Q4_0)
#   --hf-dir    use an existing local draft checkpoint instead of downloading
# Env: HF_TOKEN        token with access to the (private) draft repos and the target
#      DRAFT_MODEL, DRAFT_REVISION, NAME   override the preset's repo, revision, file prefix
#      TARGET_HF_DIR   target checkpoint dir (default: models/hf/Apertus-v1.5-8B); missing
#                      config/tokenizer files are downloaded at the pinned target revision
#      MODELS_DIR      (default: models/)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$REPO_ROOT/models}"
VENV="$REPO_ROOT/.venv"

TARGET_MODEL="swiss-ai/Apertus-v1.5-8B"
TARGET_REVISION="0be762a6a58dad2a3b3f71b2e0f46d34339fa836"
TARGET_HF_DIR="${TARGET_HF_DIR:-$MODELS_DIR/hf/Apertus-v1.5-8B}"

head="dspark"
hf_dir="" types=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head) head="$2"; shift 2 ;;
    --hf-dir) hf_dir="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) types+=("$1"); shift ;;
  esac
done
[[ ${#types[@]} -gt 0 ]] || types=(Q4_0)

case "$head" in
  dspark)
    DRAFT_MODEL="${DRAFT_MODEL:-faruk-zahiragic/Apertus-v1.5-8B-DSpark-e10-thinking-off}"
    DRAFT_REVISION="${DRAFT_REVISION:-f1741d68803a4837499dcefc65aca114eaa0837b}"
    NAME="${NAME:-apertus-v1.5-8b-dspark-e10}" ;;
  eagle3)
    DRAFT_MODEL="${DRAFT_MODEL:-faruk-zahiragic/Apertus-v1.5-8B-EAGLE3.1-e10-thinking-off}"
    DRAFT_REVISION="${DRAFT_REVISION:-4c9d4c9e250a83ebeee43563ecf71c1118b735cd}"
    NAME="${NAME:-apertus-v1.5-8b-eagle3.1-e10}" ;;
  *) echo "error: unknown --head $head (dspark or eagle3)" >&2; exit 1 ;;
esac

QUANTIZE="$LLAMA_CPP_DIR/build/bin/llama-quantize"
[[ -x "$QUANTIZE" ]] || { echo "error: $QUANTIZE missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }
[[ -x "$VENV/bin/hf" ]] || { echo "error: $VENV missing; run scripts/convert_quantize.sh once" >&2; exit 1; }

if [[ -z "$hf_dir" ]]; then
  hf_dir="$MODELS_DIR/hf/$(basename "$DRAFT_MODEL")"
  echo "== downloading $DRAFT_MODEL@$DRAFT_REVISION -> $hf_dir"
  "$VENV/bin/hf" download "$DRAFT_MODEL" --revision "$DRAFT_REVISION" --local-dir "$hf_dir" \
    --include config.json model.safetensors SHA256SUMS
  (cd "$hf_dir" && grep -E ' (config\.json|model\.safetensors)$' SHA256SUMS | sha256sum -c -)
fi

if [[ ! -f "$TARGET_HF_DIR/tokenizer.json" ]]; then
  echo "== downloading target config and tokenizer -> $TARGET_HF_DIR"
  "$VENV/bin/hf" download "$TARGET_MODEL" --revision "$TARGET_REVISION" --local-dir "$TARGET_HF_DIR" \
    --include "*.json" "*.jinja"
fi

mkdir -p "$MODELS_DIR"
base="$MODELS_DIR/$NAME-F16.gguf"
echo "== converting $hf_dir -> $base"
"$VENV/bin/python" "$LLAMA_CPP_DIR/convert_hf_to_gguf.py" "$hf_dir" \
  --target-model-dir "$TARGET_HF_DIR" --outtype f16 --outfile "$base"

outputs=("$base")
for type in "${types[@]}"; do
  out="$MODELS_DIR/$NAME-$type.gguf"
  echo "== quantizing $type -> $out"
  "$QUANTIZE" "$base" "$out" "$type"
  outputs+=("$out")
done

echo "== sha256"
(cd "$MODELS_DIR" && sha256sum "${outputs[@]##*/}" | tee -a SHA256SUMS)
ls -lh "${outputs[@]}"
