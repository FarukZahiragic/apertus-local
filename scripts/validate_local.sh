#!/usr/bin/env bash
# Verify a running local server's UI, document Q&A, streaming and reliability.
# Usage: scripts/validate_local.sh [--repeat N] [--max-tokens N] [--report FILE]
# Env: PORT (8080), VALIDATION_TIMEOUT (300 seconds per request).
# This is a functional check, not a benchmark. It does not disable networking.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
repeat=1 tokens=16 report=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repeat|--max-tokens|--report)
      [[ $# -ge 2 && -n "$2" ]] || { echo "error: $1 requires a value" >&2; exit 1; }
      case "$1" in --repeat) repeat="$2";; --max-tokens) tokens="$2";; --report) report="$2";; esac
      shift ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo 'error: see --help' >&2; exit 1 ;;
  esac
  shift
done
for value in "$repeat" "$tokens" "${PORT:-8080}"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'error: expected positive integers' >&2; exit 1; }
done
hardware="$(ap_hardware)"
exec python3 "$REPO_ROOT/scripts/validate_local.py" --repeat "$repeat" --max-tokens "$tokens" --report "$report" --hardware "$hardware"
