#!/usr/bin/env bash
# CPU tuning matrix for the laptop. Each run appends one row to
# benchmarks/results.md through scripts/bench.sh. Close other applications and
# keep the laptop on AC power. A full run takes about 35 to 45 minutes.
#
# Usage: scripts/bench_matrix.sh [--quick] [--metal|--vulkan] [--dry-run] [MODEL.gguf ...]
#   MODEL     GGUF files to compare. Default: those of models/apertus-v1.5-8b-{Q4_K_M,
#             Q4_0,IQ4_XS}.gguf that exist. The first one is the reference model.
#   --quick   1 repetition, pp256/tg64, context depth 1024 only: checks the setup fast
#   --vulkan  add a run with the Vulkan build (scripts/setup_llamacpp.sh --vulkan),
#             all layers offloaded to the Iris Xe iGPU
#   --dry-run print the rows instead of writing them
#
# Each axis changes one setting from the reference (first model, 4 threads, F16 KV
# cache, empty context):
#   threads   4 vs 8
#   quant     every model at 4 threads
#   kv        F16 vs Q8_0 KV cache (flash attention on), empty and filled context
#   ctx       generation and prompt speed with 2048 / 4096 tokens already in context
#   vulkan    optional, see above
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
export RESULTS="${RESULTS:-$REPO_ROOT/benchmarks/results.md}"

quick=0 vulkan=0 metal=0 dry=() models=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) quick=1; shift ;;
    --vulkan) vulkan=1; shift ;;
    --metal) metal=1; shift ;;
    --dry-run) dry=(--dry-run); shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) models+=("$1"); shift ;;
  esac
done

if [[ ${#models[@]} -eq 0 ]]; then
  for q in Q4_K_M Q4_0 IQ4_XS; do
    f="$REPO_ROOT/models/apertus-v1.5-8b-$q.gguf"
    if [[ -f "$f" ]]; then models+=("$f"); else echo "skipping missing $f" >&2; fi
  done
fi
[[ ${#models[@]} -gt 0 ]] || { echo "error: no models found (see README step 2)" >&2; exit 1; }
ref="${models[0]}"

if [[ "$quick" -eq 1 ]]; then
  size=(-p 256 -n 64 -r 1) depths=(1024)
else
  size=(-p 512 -n 128 -r 3) depths=(2048 4096)
fi

failed=0
run() {  # run AXIS MODEL THREADS [llama-bench args...]
  local axis="$1" model="$2" threads="$3"
  shift 3
  echo "== $axis: $(basename "$model") -t $threads $*" >&2
  local selected=cpu
  case "$axis" in metal|vulkan) selected="$axis" ;; esac
  "$REPO_ROOT/scripts/bench.sh" -m "$model" -t "$threads" "${size[@]}" \
    --backend "$selected" --notes "matrix: $axis" "${dry[@]+"${dry[@]}"}" -- "$@" || failed=$((failed + 1))
}

run threads "$ref" 4
run threads "$ref" 8

for m in "${models[@]:1}"; do
  run quant "$m" 4
done

for kv in f16 q8_0; do
  run kv "$ref" 4 -fa 1 -ctk "$kv" -ctv "$kv"
  run kv "$ref" 4 -fa 1 -ctk "$kv" -ctv "$kv" -d "${depths[${#depths[@]}-1]}"
done

for ((i=0; i<${#depths[@]}-1; i++)); do
  run ctx "$ref" 4 -d "${depths[$i]}"
done

if [[ "$vulkan" -eq 1 ]]; then
  if [[ -x "$LLAMA_CPP_DIR/build-vulkan/bin/llama-bench" ]]; then
    BUILD_DIR="$LLAMA_CPP_DIR/build-vulkan" run vulkan "$ref" 4 -ngl 99
  else
    echo "skipping vulkan: run scripts/setup_llamacpp.sh --vulkan first" >&2
  fi
fi

if [[ "$metal" -eq 1 ]]; then
  run metal "$ref" 4
fi

echo "done: rows in $RESULTS ($failed failed runs)" >&2
[[ "$failed" -eq 0 ]]
