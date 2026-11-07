#!/usr/bin/env bash
# Run llama-bench on one model and append one row to benchmarks/results.md.
#
# Usage: scripts/bench.sh -m MODEL.gguf [options] [-- extra llama-bench args]
#   -m FILE    GGUF model (required)
#   -t N       threads (default: 4)
#   -p N       prompt tokens (default: 512)
#   -n N       generated tokens (default: 128)
#   -r N       repetitions (default: 3)
#   --hw TEXT  hardware label (default: auto; "laptop i5-1135G7" on the laptop)
#   --name TEXT  model name for the table (default: derived from the file name)
#   --notes TEXT free text for the Notes column
#   --dry-run  print the row instead of appending it
#   --backend cpu|metal|vulkan (default: cpu; GPU modes require a visible device)
# Extra args after "--" go to llama-bench verbatim and are recorded in Settings,
# e.g. -- -ctk q8_0 -ctv q8_0 -fa 1
# Env: LLAMA_CPP_DIR (default: vendor/llama.cpp), BUILD_DIR (default: $LLAMA_CPP_DIR/build),
#      RESULTS (default: benchmarks/results.md)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
RESULTS="${RESULTS:-$REPO_ROOT/benchmarks/results.md}"
model="" threads=4 n_prompt=512 n_gen=128 reps=3 hw="" name="" notes="" dry_run=0 backend=cpu
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|-t|-p|-n|-r|--hw|--name|--notes|--backend)
      [[ $# -ge 2 && -n "$2" ]] || { echo "error: $1 requires a value" >&2; exit 1; } ;;
  esac
  case "$1" in
    -m) model="$2"; shift 2 ;;
    -t) threads="$2"; shift 2 ;;
    -p) n_prompt="$2"; shift 2 ;;
    -n) n_gen="$2"; shift 2 ;;
    -r) reps="$2"; shift 2 ;;
    --hw) hw="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --notes) notes="$2"; shift 2 ;;
    --backend) backend="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --) shift; extra=("$@"); break ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done
for value in "$threads" "$n_prompt" "$n_gen" "$reps"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'error: benchmark sizes and threads must be positive integers' >&2; exit 1; }
done
gpu_layers=0 build_dir=build label=CPU
load_mode="${LOAD_MODE:-auto}"
case "$load_mode" in
  auto|none|mmap|mlock|mmap+mlock|dio) ;;
  *) echo 'error: invalid LOAD_MODE' >&2; exit 1 ;;
esac
case "$backend" in
  cpu) ;;
  metal) gpu_layers=99 build_dir=build-metal label=Metal ;;
  vulkan) gpu_layers=99 build_dir=build-vulkan label=Vulkan ;;
  *) echo 'error: --backend must be cpu, metal, or vulkan' >&2; exit 1 ;;
esac
if [[ "$backend" != cpu ]]; then
  gpu_layers="${GPU_LAYERS:-$gpu_layers}"
  [[ "$gpu_layers" =~ ^[1-9][0-9]*$ ]] || { echo 'error: GPU_LAYERS must be positive' >&2; exit 1; }
fi
BUILD_DIR="${BUILD_DIR:-$LLAMA_CPP_DIR/$build_dir}"
BENCH="$BUILD_DIR/bin/llama-bench"

[[ -n "$model" ]] || { echo "error: -m MODEL.gguf is required" >&2; exit 1; }
[[ -f "$model" ]] || { echo "error: model not found: $model" >&2; exit 1; }
[[ -x "$BENCH" ]] || { echo "error: $BENCH missing; run scripts/setup_llamacpp.sh" >&2; exit 1; }
if [[ "$backend" != cpu ]] && ! ap_device_available "$BENCH" "$backend"; then
  echo "error: no $backend device in $BUILD_DIR; refusing to label CPU fallback as $label" >&2; exit 1
fi

if [[ -z "$hw" ]]; then
  hw="$(ap_hardware)"
fi

cmd=("$BENCH" -m "$model" -t "$threads" -p "$n_prompt" -n "$n_gen" -r "$reps" -o json "${extra[@]+"${extra[@]}"}" -ngl "$gpu_layers" --load-mode "$load_mode")
echo "+ ${cmd[*]}" >&2
json="$("${cmd[@]}")"

row="$(BENCH_JSON="$json" python3 - "$model" "$hw" "$name" "$notes" "$reps" "${extra[*]:-}" "$label" "$gpu_layers" "$load_mode" <<'EOF'
import json, os, re, sys, datetime

model_path, hw, name, notes, reps, extra, backend, gpu_layers, load_mode = sys.argv[1:10]
runs = json.loads(os.environ["BENCH_JSON"])
pp = next((r for r in runs if r["n_prompt"] > 0 and r["n_gen"] == 0), None)
tg = next((r for r in runs if r["n_gen"] > 0 and r["n_prompt"] == 0), None)
first = runs[0]

base = os.path.basename(model_path)
if base.endswith('.gguf'):
    base = base[:-5]
m = re.search(r"(?i)[-._](I?Q\d[\w]*|F16|BF16|F32)$", base)
quant = m.group(1).upper() if m else first["model_type"]
if not name:
    name = base[: m.start()] if m else base

def ts(r):
    return f'{r["avg_ts"]:.2f} ± {r["stddev_ts"]:.2f}' if r else "-"

settings = [f'pp{pp["n_prompt"] if pp else 0}', f'tg{tg["n_gen"] if tg else 0}', f"r{reps}",
            f'kv={first["type_k"]}/{first["type_v"]}', f'ngl={gpu_layers}', f'load={load_mode}']
if any(int(r['n_gpu_layers']) != int(gpu_layers) for r in runs):
    raise SystemExit('error: benchmark offload does not match requested backend')
if extra:
    settings.append(extra)
cells = [
    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
    hw, name, quant, backend, str(first["n_threads"]), " ".join(settings),
    ts(pp), ts(tg), "-", f'b{first["build_number"]} ({first["build_commit"]})', notes or "-",
]
print("| " + " | ".join(c.replace("|", "/") for c in cells) + " |")
EOF
)"

echo "$row"
if [[ "$dry_run" -eq 0 ]]; then
  echo "$row" >> "$RESULTS"
  echo "appended to $RESULTS" >&2
fi
