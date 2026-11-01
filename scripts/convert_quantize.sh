#!/usr/bin/env bash
# Convert swiss-ai/Apertus-v1.5-8B to GGUF and quantize it. Run on a cloud VM:
# it needs about 17 GB for the HF download, 16 GB for the F16 GGUF and about
# 5 GB per quantized file. Only the language model is converted (text only).
#
# Usage: scripts/convert_quantize.sh [--hf-dir DIR] [--keep-f16] [TYPE ...]
#   TYPE        llama-quantize types to produce (default: Q4_K_M Q4_0)
#   --hf-dir    use an existing local HF checkpoint instead of downloading
#   --keep-f16  keep the F16 GGUF after quantizing
# Env: HF_TOKEN     read token of an account that accepted the model's terms
#      HF_MODEL     (default: swiss-ai/Apertus-v1.5-8B)
#      HF_REVISION  (default: pinned below)
#      NAME         output file prefix (default: apertus-v1.5-8b)
#      OUTTYPE      convert_hf_to_gguf.py --outtype (default: f16)
#      MODELS_DIR   (default: models/)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
MODELS_DIR="${MODELS_DIR:-$REPO_ROOT/models}"
VENV="$REPO_ROOT/.venv"

HF_MODEL="${HF_MODEL:-swiss-ai/Apertus-v1.5-8B}"
HF_REVISION="${HF_REVISION:-0be762a6a58dad2a3b3f71b2e0f46d34339fa836}"
NAME="${NAME:-apertus-v1.5-8b}"
OUTTYPE="${OUTTYPE:-f16}"

hf_dir="" keep_f16=0 types=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hf-dir) hf_dir="$2"; shift 2 ;;
    --keep-f16) keep_f16=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) types+=("$1"); shift ;;
  esac
done
[[ ${#types[@]} -gt 0 ]] || types=(Q4_K_M Q4_0)

QUANTIZE="$LLAMA_CPP_DIR/build/bin/llama-quantize"
[[ -x "$QUANTIZE" ]] || { echo "error: $QUANTIZE missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "== creating $VENV with llama.cpp conversion requirements"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$LLAMA_CPP_DIR/requirements/requirements-convert_hf_to_gguf.txt" huggingface_hub
fi

if [[ -z "$hf_dir" ]]; then
  hf_dir="$MODELS_DIR/hf/$(basename "$HF_MODEL")"
  auth=()
  [[ -n "${HF_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $HF_TOKEN")
  code="$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" \
    "https://huggingface.co/$HF_MODEL/resolve/$HF_REVISION/config.json")"
  if [[ "$code" != "200" ]]; then
    echo "error: HTTP $code for $HF_MODEL@$HF_REVISION." >&2
    echo "  The model is gated: open https://huggingface.co/$HF_MODEL while logged in, accept the" >&2
    echo "  terms, then export HF_TOKEN=<read token of that account> and re-run." >&2
    exit 1
  fi
  echo "== downloading $HF_MODEL@$HF_REVISION -> $hf_dir"
  "$VENV/bin/hf" download "$HF_MODEL" --revision "$HF_REVISION" --local-dir "$hf_dir" \
    --exclude "*.pdf" "assets/*" ".eval_results/*"
fi

mkdir -p "$MODELS_DIR"
base="$MODELS_DIR/$NAME-${OUTTYPE^^}.gguf"
echo "== converting $hf_dir -> $base"
"$VENV/bin/python" "$LLAMA_CPP_DIR/convert_hf_to_gguf.py" "$hf_dir" \
  --outtype "$OUTTYPE" --outfile "$base"

# The output head (131,072 x 4096) is read for every generated token; keep it and
# the token embedding at Q6_K in every variant (see docs/ARCHITECTURE.md).
outputs=()
for type in "${types[@]}"; do
  out="$MODELS_DIR/$NAME-$type.gguf"
  echo "== quantizing $type -> $out"
  "$QUANTIZE" --output-tensor-type q6_k --token-embedding-type q6_k "$base" "$out" "$type"
  outputs+=("$out")
done

if [[ "$keep_f16" -eq 0 ]]; then
  rm -f "$base"
else
  outputs+=("$base")
fi

echo "== sha256"
(cd "$MODELS_DIR" && sha256sum "${outputs[@]##*/}" | tee -a SHA256SUMS)
ls -lh "${outputs[@]}"
