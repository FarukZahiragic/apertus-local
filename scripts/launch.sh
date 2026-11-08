#!/usr/bin/env bash
# Start verified local chat and open the browser after llama-server is ready.
# Usage: scripts/launch.sh [--no-browser|--stop|--check]
# Env: BACKEND, THREADS, CTX, PORT, MODEL, MODEL_SHA256, MODELS_DIR, BUILD_DIR,
#      APERTUS_STATE_DIR, STARTUP_TIMEOUT (seconds, default 300).
# Keep this terminal open. Ctrl+C or the Stop launcher stops only this server.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
source "$REPO_ROOT/config/model.env"
open_browser=1 action=start
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-browser) open_browser=0 ;;
    --stop) action=stop ;;
    --check) action=check ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "error: unknown argument $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
export PORT="${PORT:-8080}" HOST=127.0.0.1
[[ "$PORT" =~ ^[1-9][0-9]*$ ]] && ((PORT <= 65535)) || { echo 'error: invalid PORT' >&2; exit 1; }
state="${APERTUS_STATE_DIR:-$REPO_ROOT/.apertus-state}"
lock="$state/port-$PORT"
if [[ "$action" == stop ]]; then
  if [[ ! -d "$lock" ]]; then echo "Apertus is not running on port $PORT."; exit 0; fi
  # Request shutdown; never kill a process based on a potentially stale PID file.
  touch "$lock/stop"
  for ((i=0; i<30; i++)); do
    if [[ ! -d "$lock" ]]; then echo 'Apertus stopped.'; exit 0; fi
    sleep 1
  done
  echo "error: launcher did not respond; close its terminal, then remove stale directory $lock" >&2; exit 1
fi
requested="${BACKEND:-auto}"
ap_runtime "$REPO_ROOT"
export BACKEND="$AP_BACKEND" BUILD_DIR THREADS
[[ -x "$BUILD_DIR/bin/llama-server" ]] || {
  echo 'error: no runtime found. Download a platform package, or run scripts/setup_llamacpp.sh.' >&2; exit 1;
}
echo "Hardware: $(ap_hardware)"
echo "Selected: $BACKEND, $THREADS threads, ${CTX:-4096}-token context"
if (( $(ap_memory_bytes) < 15000000000 )); then
  echo 'Memory note: 16 GB is recommended; 8 GB operation has not been validated.'
fi
if [[ "$action" == check ]]; then
  echo "Runtime: $BUILD_DIR"
  echo "Model location: ${MODEL:-${MODELS_DIR:-$REPO_ROOT/models}/$APERTUS_MODEL_FILE}"
  exit 0
fi
mkdir -p "$state"
mkdir "$lock" 2>/dev/null || {
  echo "error: another launcher owns port $PORT; use the Stop launcher or inspect $lock" >&2; exit 1;
}
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$lock/stop"
  rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -z "${MODEL:-}" ]]; then
  "$REPO_ROOT/scripts/get_model.sh" --apertus
  MODEL="${MODELS_DIR:-$REPO_ROOT/models}/$APERTUS_MODEL_FILE"
else
  [[ -f "$MODEL" ]] || { echo "error: model not found: $MODEL" >&2; exit 1; }
  if [[ -n "${MODEL_SHA256:-}" ]]; then
    ap_verify "$MODEL" "$MODEL_SHA256" || { echo 'error: MODEL_SHA256 mismatch' >&2; exit 1; }
  else
    echo 'Developer MODEL override: checksum not specified.'
  fi
fi
export MODEL
if curl --noproxy '*' --connect-timeout 1 --max-time 2 -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  echo "error: port $PORT is already serving another application; choose PORT or stop it" >&2; exit 1
fi
timeout="${STARTUP_TIMEOUT:-300}"
[[ "$timeout" =~ ^[1-9][0-9]*$ ]] || { echo 'error: invalid STARTUP_TIMEOUT' >&2; exit 1; }
start_server() {
  local deadline ready=0
  log="$state/server-$PORT-$BACKEND.log"
  echo "Loading Apertus; startup log: $log"
  "$REPO_ROOT/scripts/serve.sh" > "$log" 2>&1 &
  server_pid=$!
  deadline=$((SECONDS + timeout))
  while ((SECONDS < deadline)); do
    [[ ! -f "$lock/stop" ]] || return 2
    kill -0 "$server_pid" 2>/dev/null || break
    if grep -q "listening on .*:$PORT" "$log" && curl --noproxy '*' --connect-timeout 1 --max-time 2 -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
      ready=1; break
    fi
    sleep 1
  done
  if [[ "$ready" -eq 1 ]]; then return 0; fi
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=''
  return 1
}
if start_server; then
  :
else
  code=$?
  [[ "$code" -ne 2 ]] || exit 0
  if [[ "$requested" == auto && "$BACKEND" == metal ]]; then
    echo "Metal startup failed (see $log); retrying on CPU."
    unset BUILD_DIR
    BACKEND=cpu ap_runtime "$REPO_ROOT"
    export BACKEND=cpu BUILD_DIR THREADS
    start_server || { tail -n 20 "$log" >&2; exit 1; }
  else
    tail -n 20 "$log" >&2
    echo 'error: startup failed; the log above is retained. Try BACKEND=cpu or close other applications.' >&2
    exit 1
  fi
fi
url="http://127.0.0.1:$PORT/"
echo "Ready: $url"
echo 'Keep this terminal open. Press Ctrl+C or open Stop to stop Apertus.'
if [[ "$open_browser" -eq 1 ]]; then
  case "$(ap_os)" in
    Darwin) open "$url" || echo "Open $url in your browser." ;;
    *) if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 || echo "Open $url in your browser."; else echo "Open $url in your browser."; fi ;;
  esac
fi
while kill -0 "$server_pid" 2>/dev/null; do
  [[ ! -f "$lock/stop" ]] || { echo 'Stopping Apertus.'; exit 0; }
  sleep 1
done
wait "$server_pid" || { echo "error: server exited unexpectedly; see $log" >&2; exit 1; }
