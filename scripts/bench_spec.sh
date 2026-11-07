#!/usr/bin/env bash
# Measure speculative decoding through llama-server (chat template, thinking off,
# greedy) against plain decoding, and append one row per configuration to
# benchmarks/results.md. Each configuration answers the same 6 chat prompts.
#
# Usage: scripts/bench_spec.sh [--k "3 5"] [-n 256] [--hw LABEL] [--dry-run]
#   --k        draft lengths to test (default: "3 5"); a no-draft baseline always runs first
#   -n         max tokens per answer (default: 256)
#   --hw       hardware label (default: "laptop i5-1135G7" on the laptop, else the CPU name)
#   --dry-run  print rows instead of appending them
# Env: MODEL, DRAFT, SPEC_TYPE, THREADS, CTX as in scripts/serve.sh and scripts/serve_spec.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${RESULTS:-$REPO_ROOT/benchmarks/results.md}"
MODEL="${MODEL:-$REPO_ROOT/models/apertus-v1.5-8b-Q4_K_M.gguf}"
DRAFT="${DRAFT:-$REPO_ROOT/models/apertus-v1.5-8b-eagle3.1-e10-Q4_0.gguf}"
export MODEL DRAFT PORT=8097 THINKING=0

ks="3 5" n_predict=256 hw="" dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --k) ks="$2"; shift 2 ;;
    -n) n_predict="$2"; shift 2 ;;
    --hw) hw="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

if [[ -z "$hw" ]]; then
  cpu="$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
  if [[ "$cpu" == *"i5-1135G7"* ]]; then hw="laptop i5-1135G7"; else hw="$cpu, $(nproc) threads"; fi
fi

server_pid=""
stop_server() { [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null && wait "$server_pid" 2>/dev/null; server_pid=""; }
trap stop_server EXIT

run_config() {  # run_config K   (K=0: no draft)
  local k="$1" log="/tmp/bench_spec_server_$1.log"
  if [[ "$k" == 0 ]]; then
    "$REPO_ROOT/scripts/serve.sh" > "$log" 2>&1 &
  else
    K="$k" "$REPO_ROOT/scripts/serve_spec.sh" > "$log" 2>&1 &
  fi
  server_pid=$!
  for _ in $(seq 300); do
    curl -sf "http://127.0.0.1:$PORT/health" > /dev/null && break
    kill -0 "$server_pid" 2>/dev/null || { echo "error: server failed, see $log" >&2; exit 1; }
    sleep 1
  done
  echo "== k=$k" >&2
  K_RUN="$k" N_PREDICT="$n_predict" HW="$hw" MODEL="$MODEL" DRAFT="$DRAFT" python3 - <<'EOF'
import json, os, statistics, urllib.request
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
gen, pp, n_drafted, n_accepted, n_tokens = [], [], 0, 0, 0
for prompt in PROMPTS:
    body = {"messages": [{"role": "user", "content": prompt}], "max_tokens": int(os.environ["N_PREDICT"]),
            "temperature": 0, "top_k": 1, "seed": 1}
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    t = json.load(urllib.request.urlopen(req, timeout=1800))["timings"]
    gen.append(t["predicted_per_second"]); pp.append(t["prompt_per_second"]); n_tokens += t["predicted_n"]
    n_drafted += t.get("draft_n", 0); n_accepted += t.get("draft_n_accepted", 0)
    print(f"  {t['predicted_n']:4d} tok  {t['predicted_per_second']:6.2f} tok/s  "
          f"draft {t.get('draft_n_accepted', 0)}/{t.get('draft_n', 0)}", flush=True)
def ms(xs):
    return f"{statistics.mean(xs):.2f} ± {statistics.stdev(xs):.2f}"
if k:
    rate = n_accepted / n_drafted if n_drafted else 0.0
    accept = f"{rate:.2f} (τ {1 + k * rate:.2f})"
    spec = next((t for t in ("eagle3", "dspark") if t in os.path.basename(os.environ["DRAFT"])), "draft")
    settings = f"server chat, thinking off, greedy, 6 prompts ≤{os.environ['N_PREDICT']} tok, {spec} k={k}, " \
               f"draft {os.path.basename(os.environ['DRAFT']).removesuffix('.gguf')}"
else:
    accept = "-"
    settings = f"server chat, thinking off, greedy, 6 prompts ≤{os.environ['N_PREDICT']} tok, no draft"
import datetime, subprocess
build = subprocess.run(["git", "-C", os.path.join(os.path.dirname(os.environ["MODEL"]), "..", "vendor/llama.cpp"),
                        "rev-parse", "--short=8", "HEAD"], capture_output=True, text=True).stdout.strip()
quant = os.path.basename(os.environ["MODEL"]).removesuffix(".gguf").rsplit("-", 1)[-1]
cells = [datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"), os.environ["HW"], "Apertus-v1.5-8B",
         quant, "CPU", os.environ.get("THREADS", "4"), settings, ms(pp), ms(gen), accept,
         f"{build} + patches", f"{n_tokens} tokens generated"]
with open("/tmp/bench_spec_rows.md", "a") as f:
    f.write("| " + " | ".join(cells) + " |\n")
EOF
  stop_server
}

rm -f /tmp/bench_spec_rows.md
run_config 0
for k in $ks; do run_config "$k"; done

cat /tmp/bench_spec_rows.md
if [[ "$dry_run" -eq 0 ]]; then
  cat /tmp/bench_spec_rows.md >> "$RESULTS"
  echo "appended to $RESULTS" >&2
fi
