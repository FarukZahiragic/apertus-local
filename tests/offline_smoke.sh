#!/usr/bin/env bash
# Run inside a fresh Linux network namespace created by CI (sudo unshare --net).
# Prove fresh startup, UI rendering and actual inference with only loopback.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ip link set lo up
if curl --noproxy '*' --connect-timeout 1 --max-time 3 -sf https://huggingface.co >/dev/null; then
  echo 'error: external networking unexpectedly available' >&2
  exit 1
fi
echo 'External networking blocked; only loopback is enabled.'
export CHECK_OFFLINE_BROWSER=1
/bin/bash tests/native_smoke.sh
