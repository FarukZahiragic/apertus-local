#!/usr/bin/env bash
# Start Apertus from a Linux terminal or a file manager that runs shell scripts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec scripts/launch.sh "$@"
