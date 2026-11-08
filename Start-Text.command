#!/usr/bin/env bash
# Optional lighter text-only mode; uses the same cached language model.
set -euo pipefail
export MULTIMODAL=0
exec "$(dirname "${BASH_SOURCE[0]}")/Start.command" "$@"
