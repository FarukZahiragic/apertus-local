#!/usr/bin/env bash
# Open Apertus local chat from Finder or a terminal.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ "$PWD" == *.app/Contents/Resources/apertus-local ]]; then
  # Keep downloads and logs outside the signed application bundle.
  export MODELS_DIR="${MODELS_DIR:-$HOME/Library/Application Support/Apertus Local/models}"
  export APERTUS_STATE_DIR="${APERTUS_STATE_DIR:-$HOME/Library/Application Support/Apertus Local/state}"
fi
if ! scripts/launch.sh "$@"; then
  echo 'Apertus could not start. See the message above.' >&2
  if [[ -t 0 ]]; then read -r -p 'Press Enter to close.' reply; fi
  exit 1
fi
