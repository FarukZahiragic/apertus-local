#!/usr/bin/env bash
# Measure speculative decoding through llama-server (chat template, thinking off,
# greedy) against plain decoding, and append one row per configuration to
# benchmarks/results.md. Each configuration answers the same 6 chat prompts.
#
# Usage: scripts/bench_spec.sh [--k "3 5"] [-n 256] [--hw LABEL] [--vulkan] [--dry-run]
#   --k        draft lengths to test (default: "3 5"); a no-draft baseline always runs first
#   -n         max tokens per answer (default: 256)
#   --hw       hardware label (default: "laptop i5-1135G7" on the laptop, else the CPU name)
#   --vulkan   use build-vulkan, offloading target and draft to Iris Xe (99 layers)
#   --dry-run  print rows instead of appending them
# Env: MODEL, DRAFT, SPEC_TYPE, THREADS, CTX, LLAMA_CPP_DIR, BUILD_DIR as in serve_spec.sh;
#      PORT (default: 8097), STARTUP_TIMEOUT (seconds, default: 300), RESULTS
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
RESULTS="${RESULTS:-$REPO_ROOT/benchmarks/results.md}"
MODEL="${MODEL:-$REPO_ROOT/models/apertus-v1.5-8b-Q4_K_M.gguf}"
DRAFT="${DRAFT:-$REPO_ROOT/models/apertus-v1.5-8b-eagle3.1-e10-Q4_0.gguf}"
export LLAMA_CPP_DIR MODEL DRAFT
export PORT="${PORT:-8097}" HOST=127.0.0.1 THINKING=0
export THREADS="${THREADS:-4}" CTX="${CTX:-4096}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-300}"

ks="3 5" n_predict=256 hw="" dry_run=0 vulkan=0
require_value() {
  [[ $# -ge 2 && -n "$2" ]] || { echo "error: $1 requires a value" >&2; exit 1; }
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --k) require_value "$@"; ks="$2"; shift 2 ;;
    -n) require_value "$@"; n_predict="$2"; shift 2 ;;
    --hw) require_value "$@"; hw="$2"; shift 2 ;;
    --vulkan) vulkan=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

for value in "$n_predict" "$STARTUP_TIMEOUT" "$THREADS" "$CTX" "$PORT"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "error: expected a positive integer, got '$value'" >&2; exit 1; }
done
read -r -a lengths <<< "$ks"
[[ ${#lengths[@]} -gt 0 ]] || { echo "error: --k requires at least one draft length" >&2; exit 1; }
for k in "${lengths[@]}"; do
  [[ "$k" =~ ^[1-9][0-9]*$ ]] || { echo "error: invalid draft length '$k'" >&2; exit 1; }
done

backend=CPU build_dir=build gpu_layers=0
if [[ "$vulkan" -eq 1 ]]; then backend=Vulkan build_dir=build-vulkan gpu_layers=99; fi
export BUILD_DIR="${BUILD_DIR:-$LLAMA_CPP_DIR/$build_dir}"
server_args=(--n-gpu-layers "$gpu_layers" --n-gpu-layers-draft "$gpu_layers")
[[ -x "$BUILD_DIR/bin/llama-server" ]] || { echo "error: $BUILD_DIR/bin/llama-server missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }
if [[ "$vulkan" -eq 1 ]]; then
  devices="$("$BUILD_DIR/bin/llama-server" --list-devices 2>&1)"
  [[ "$devices" =~ Vulkan[0-9]+: ]] || {
    echo "error: no Vulkan device available in $BUILD_DIR; run scripts/setup_llamacpp.sh --vulkan and check the driver" >&2
    exit 1
  }
fi
for model in "$MODEL" "$DRAFT"; do
  [[ -f "$model" ]] || { echo "error: model not found: $model" >&2; exit 1; }
done

if [[ -z "$hw" ]]; then
  cpu="$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
  if [[ "$cpu" == *"i5-1135G7"* ]]; then hw="laptop i5-1135G7"; else hw="$cpu, $(nproc) threads"; fi
fi

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/apertus-bench-spec.XXXXXX")"
server_pid="" completed=0
stop_server() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
cleanup() {
  stop_server
  if [[ "$completed" -eq 1 ]]; then
    rm -r -- "$run_dir"
  else
    echo "benchmark logs kept in $run_dir" >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_config() {  # run_config K   (K=0: no draft)
  local k="$1" log="$run_dir/server-$1.log" ready=0 deadline
  # Refuse an occupied port before starting, so another server cannot supply timings.
  python3 - <<'EOF'
import os, socket
with socket.socket() as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", int(os.environ["PORT"])))
    except OSError as error:
        raise SystemExit(f"error: benchmark port {os.environ['PORT']} unavailable: {error}")
EOF
  if [[ "$k" == 0 ]]; then
    "$REPO_ROOT/scripts/serve.sh" -- "${server_args[@]}" > "$log" 2>&1 &
  else
    K="$k" "$REPO_ROOT/scripts/serve_spec.sh" -- "${server_args[@]}" > "$log" 2>&1 &
  fi
  server_pid=$!
  deadline=$((SECONDS + STARTUP_TIMEOUT))
  while (( SECONDS < deadline )); do
    kill -0 "$server_pid" 2>/dev/null || { echo "error: server failed, see $log" >&2; exit 1; }
    if curl --noproxy '*' --connect-timeout 1 --max-time 2 -sf "http://127.0.0.1:$PORT/health" > /dev/null; then
      kill -0 "$server_pid" 2>/dev/null || { echo "error: server exited, see $log" >&2; exit 1; }
      ready=1
      break
    fi
    sleep 1
  done
  [[ "$ready" -eq 1 ]] || { echo "error: server not ready after ${STARTUP_TIMEOUT}s, see $log" >&2; exit 1; }
  echo "== k=$k" >&2
  K_RUN="$k" N_PREDICT="$n_predict" HW="$hw" BACKEND="$backend" GPU_LAYERS="$gpu_layers" python3 - "$run_dir/row.md" <<'EOF'
import datetime
import json
import os
import statistics
import subprocess
import sys
import urllib.request

PROMPTS = [
    "Explain in a short paragraph why running a language model offline helps protect sensitive data.",
    "Translate into French: The workshop starts at 9 am. Please bring your laptop and charger.",
    "Write a polite email asking a partner organisation to share their field report by Friday.",
    "List five practical tips for keeping a project budget under control.",
    "Summarise in three bullet points: Solar lamps reduce kerosene use, lower household costs, "
    "and let children study after dark, but they need spare parts and local repair skills.",
    "What is the difference between a virus and a bacterium? Answer in four sentences.",
]
url = f"http://127.0.0.1:{os.environ.get('PORT', '8097')}/v1/chat/completions"
k = int(os.environ["K_RUN"])
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
gen, pp, n_drafted, n_accepted, n_tokens = [], [], 0, 0, 0
for prompt in PROMPTS:
    body = {"messages": [{"role": "user", "content": prompt}], "max_tokens": int(os.environ["N_PREDICT"]),
            "temperature": 0, "top_k": 1, "seed": 1}
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with opener.open(req, timeout=1800) as response:
        t = json.load(response)["timings"]
    gen.append(t["predicted_per_second"]); pp.append(t["prompt_per_second"]); n_tokens += t["predicted_n"]
    n_drafted += t.get("draft_n", 0); n_accepted += t.get("draft_n_accepted", 0)
    print(f"  {t['predicted_n']:4d} tok  {t['predicted_per_second']:6.2f} tok/s  "
          f"draft {t.get('draft_n_accepted', 0)}/{t.get('draft_n', 0)}", flush=True)
def ms(xs):
    return f"{statistics.mean(xs):.2f} ± {statistics.stdev(xs):.2f}"
if k:
    if not n_drafted:
        raise SystemExit("error: no draft tokens were reported; refusing to record a speculative result")
    rate = n_accepted / n_drafted
    accept = f"{rate:.2f} (τ≈{1 + k * rate:.2f})"
    spec = os.environ.get("SPEC_TYPE") or next(("draft-" + t for t in ("eagle3", "dspark")
                                              if t in os.path.basename(os.environ["DRAFT"])), "draft")
    settings = f"server chat, thinking off, greedy, 6 prompts ≤{os.environ['N_PREDICT']} tok, {spec} k={k}, " \
               f"draft {os.path.basename(os.environ['DRAFT']).removesuffix('.gguf')}"
else:
    accept = "-"
    settings = f"server chat, thinking off, greedy, 6 prompts ≤{os.environ['N_PREDICT']} tok, no draft"
settings += f", ctx={os.environ['CTX']}, ngl={os.environ['GPU_LAYERS']}"
if k:
    settings += f", ngld={os.environ['GPU_LAYERS']}"
build = subprocess.check_output(["git", "-C", os.environ["LLAMA_CPP_DIR"],
                                 "rev-parse", "--short=8", "HEAD"], text=True).strip()
dirty = subprocess.run(["git", "-C", os.environ["LLAMA_CPP_DIR"], "diff", "--quiet"], check=False)
if dirty.returncode == 1:
    build += " + local changes"
elif dirty.returncode:
    raise SystemExit("error: cannot inspect llama.cpp source changes")
quant = os.path.basename(os.environ["MODEL"]).removesuffix(".gguf").rsplit("-", 1)[-1]
cells = [datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"), os.environ["HW"], "Apertus-v1.5-8B",
         quant, os.environ["BACKEND"], os.environ["THREADS"], settings, ms(pp), ms(gen), accept,
         build, f"{n_tokens} tokens generated"]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("| " + " | ".join(" ".join(c.replace("|", "/").splitlines()) for c in cells) + " |\n")
EOF
  stop_server
  cat "$run_dir/row.md"
  if [[ "$dry_run" -eq 0 ]]; then
    cat "$run_dir/row.md" >> "$RESULTS"
    echo "appended to $RESULTS" >&2
  fi
}

run_config 0
for k in "${lengths[@]}"; do run_config "$k"; done
completed=1
