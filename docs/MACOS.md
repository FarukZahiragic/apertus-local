# Apple Silicon deployment

Use a native ARM64 terminal (`uname -m` must print `arm64`), rather than Rosetta.
Record the chip, RAM and macOS version with `scripts/platform.sh`. Plan for 16 GB
RAM; 8 GB machines are not validated. The Q4_K_M file is 5.3 GiB, plus runtime,
context and operating-system memory. Keep enough free disk for downloads and updates.

## Prepare while online

Install Xcode command line tools with `xcode-select --install`, then CMake (for
example `brew install cmake` if you already use Homebrew). Clone this repository.
The build uses Apple Clang, the pinned Apertus-compatible llama.cpp fork and the
same patches as Linux. A stock Homebrew llama.cpp is not a substitute for this pin.

```bash
git clone --branch chore/workshop-validation https://github.com/FarukZahiragic/apertus-local apertus-1.5-local
cd apertus-1.5-local
scripts/setup_llamacpp.sh --cpu
```

The implementation is currently in stacked PRs #16–#21. The command above checks
out the full implementation branch while review is pending; after those PRs merge,
the same deployment will be available from `main`.

Copy `apertus-v1.5-8b-Q4_K_M.gguf` into `models/` using USB or an authorized model
repository. No conversion is needed on the Mac. Verify an existing copy offline:

```bash
scripts/get_model.sh --apertus
```

The same command downloads from the pinned public GGUF repository if the file is
missing. No Hugging Face account is required. `APERTUS_MODEL_REPO` and `MODEL_URL`
allow alternate locations. Downloads resume into `.part` and are installed after
SHA-256 checks.

## CPU baseline

```bash
BACKEND=cpu scripts/serve.sh
```

Open http://127.0.0.1:8080/. Keep thinking off, one slot, a 4K context, no draft.
Turn Wi-Fi off and unplug Ethernet, then restart the server and reload the page
to verify a fresh offline start. See [OFFLINE.md](OFFLINE.md) for acceptance checks.

## Metal experiment

```bash
scripts/setup_llamacpp.sh --metal
BACKEND=metal scripts/serve.sh
```

Metal uses the integrated GPU. CPU support does not require Metal. Check the server
log for actual offloaded layers and coherent answers before comparing throughput.
Mac inference and performance remain pending until measured on the actual hardware.
`BACKEND=auto` keeps CPU until you explicitly set `APERTUS_METAL_VALIDATED=1`
after the Apertus offline, quality and performance checks pass on your machine.
Then auto mode selects an enumerated Metal device, or reports CPU fallback.
Explicit `BACKEND=metal` fails if Metal is unavailable. `THREADS`, `CTX` and
`BUILD_DIR` always allow manual overrides. Default CPU threads use the Mac's
performance-core count where available, falling back to physical cores.

## Record a comparable CPU/Metal run

```bash
NOTES='AC power; other apps closed; memory pressure green' scripts/bench_mac.sh --quick
NOTES='AC power; other apps closed; memory pressure green' scripts/bench_mac.sh
```

Both configurations use the same GGUF, token lengths, repetitions and CPU threads.
Every run appends a hardware-labelled row to `benchmarks/results.md`; keep quick
checks separate from full pp512/tg128 comparisons. `THREADS` overrides the detected
performance-core count. `scripts/bench_matrix.sh --metal` adds a Metal comparison
to the existing CPU quantization/context matrix. The benchmark refuses Metal if
the selected build cannot enumerate a Metal device and fixes the offload setting
for each backend. Examine stderr/server logs to confirm actual offload as well.

Also compare short chat and a fixed pasted document in the web UI, recording time
to first token, generation speed, memory pressure and answer quality. A raw benchmark
does not establish interactive latency or correctness. Recheck after sustained use
to expose thermal throttling. No Mac speed claim is made before these checks.

## Release builds

`scripts/setup_llamacpp.sh --cpu --portable` uses `build-portable/` with runtime
CPU dispatch. `--metal --portable` uses `build-metal-portable/`. Release packaging
must include the backend libraries and embedded Metal resources; copying only the
server executable is insufficient. Native builds without `--portable` are for
local measurements, not redistribution to arbitrary CPUs.
