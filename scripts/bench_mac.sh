#!/usr/bin/env bash
# Record a controlled CPU/Metal comparison on an actual Apple Silicon machine.
# Usage: scripts/bench_mac.sh [--quick]
# Env: MODEL, THREADS, NOTES, RESULTS; defaults to Q4_K_M, performance cores,
#      benchmarks/results.md. --quick still runs and records real inference.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
size=(-p 512 -n 128 -r 3)
case "${1:-}" in
  --quick) size=(-p 256 -n 64 -r 1); shift ;;
  -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
esac
[[ $# -eq 0 ]] || { echo 'error: see --help' >&2; exit 1; }
[[ "$(ap_os) $(ap_arch)" == 'Darwin arm64' ]] || { echo 'error: requires native Apple Silicon macOS' >&2; exit 1; }
echo 'Use AC power, close other applications, and record memory pressure and thermal conditions.'
echo "Hardware: $(ap_hardware)"
model="${MODEL:-$REPO_ROOT/models/apertus-v1.5-8b-Q4_K_M.gguf}"
threads="${THREADS:-$(ap_threads)}"
for backend in cpu metal; do
  "$REPO_ROOT/scripts/bench.sh" -m "$model" -t "$threads" "${size[@]}" \
    --backend "$backend" --notes "Apple Silicon CPU/Metal comparison; ${NOTES:-conditions not supplied}"
done
