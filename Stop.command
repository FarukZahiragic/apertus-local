#!/usr/bin/env bash
# Stop the server owned by the Apertus launcher.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
scripts/launch.sh --stop
