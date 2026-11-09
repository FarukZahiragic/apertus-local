# Apple Silicon deployment

Use a native ARM64 terminal (`uname -m` must print `arm64`), rather than Rosetta.
Record the chip, RAM and macOS version with `scripts/platform.sh`. Plan for 16 GB
RAM; 8 GB machines are not validated. The Q4_K_M file is 5.3 GiB, plus runtime,
context and operating-system memory. Keep enough free disk for downloads and updates.

## Prepare while online

For participants, use the [one-command setup](ONE_COMMAND.md). It downloads the
prebuilt native runtime and missing model, then opens local chat directly from
Terminal. It does not install development tools or open the `.app` wrapper.

The source-building path below is for preparing a development checkout.

For a fresh Mac, only the repository's `setup.sh` file needs to be sent. Save it
in Downloads, open Terminal and run:

```bash
bash ~/Downloads/setup.sh
```

The script installs Apple command line tools if missing (complete the macOS
window), installs missing CMake/Python/Node build tools using Homebrew if needed, clones
`main` into `~/apertus-1.5-local`, builds CPU and Metal, and downloads
the checksum-verified public model. It opens CPU chat and prints commands for
future starts and CPU/Metal benchmarks. No signing identity or Hugging Face
account is required. Allow around 20 GB free for this development setup.

`bash ~/Downloads/setup.sh --no-start` performs preparation without starting chat.
You can then disconnect networking and run
`cd ~/apertus-1.5-local && ./Start.command`. Stop with Control+C, then test
`BACKEND=metal ./Start.command` from that directory. Setup does not automatically
run benchmarks or certify Metal; follow the checks below before enabling it.

Setup logs append to `~/Library/Logs/Apertus Local/setup.log`. Rerun the same
command after an interrupted installation; existing builds and verified model
downloads are reused. Existing project checkouts are reused without fetching,
switching branches or discarding edits; unrelated folders are refused.
`APERTUS_INSTALL_DIR` chooses another installation folder. Running `bash setup.sh`
inside a clone uses that clone by default. The script targets native Apple
Silicon macOS; packaged workshop downloads are a separate distribution path.

For manual installation instead:

Install Xcode command line tools with `xcode-select --install`, then CMake and
Node.js 24/npm (for example `brew install cmake node` with Homebrew). Clone this repository.
The build uses Apple Clang, the pinned Apertus-compatible llama.cpp fork and the
same patches as Linux. A stock Homebrew llama.cpp is not a substitute for this pin.

```bash
git clone https://github.com/FarukZahiragic/apertus-local apertus-1.5-local
cd apertus-1.5-local
scripts/setup_llamacpp.sh --cpu
```

Deployment PRs #16–#24 are merged into `main`. New portable builds target macOS
13.3 or later and compile the app wrapper explicitly; see
[COMPATIBILITY.md](COMPATIBILITY.md) for the difference between a minimum target
and the build/test host. The older preview.2 wrapper inherited macOS 15.8.

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
The owner reports that source setup, manual chat and an offline restart passed
on the friend's physical Mac. Chip/RAM/OS/backend details and controlled speed
measurements were not retained. This accepts the source/offline rehearsal; formal
CPU/Metal comparisons can follow later and do not block packaging.
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

Use [MACOS_RELEASE.md](MACOS_RELEASE.md) to run the unsigned preview build on
GitHub's Mac runner without Apple credentials or a connected physical Mac.
The ZIP includes first-open instructions; the downloaded-app opening rehearsal
remains a separate distribution check. Developer ID signing is optional.

`scripts/setup_llamacpp.sh --cpu --portable` uses `build-portable/` with runtime
CPU dispatch. `--metal --portable` uses `build-metal-portable/`. Release packaging
must include the backend libraries and embedded Metal resources; copying only the
server executable is insufficient. Native builds without `--portable` are for
local measurements, not redistribution to arbitrary CPUs.

## Limited GPU memory

The hosted Apple M1 VM has 7 GB RAM. Full GPU offload exceeded its Metal memory
budget even though the server advertised readiness. This does not establish a
numerical/model compatibility bug. CPU inference passed. A partial-offload CI
profile uses eight GPU layers and packed weight loading:

```bash
BACKEND=metal GPU_LAYERS=8 LOAD_MODE=none ./Start.command
GPU_LAYERS=8 LOAD_MODE=none scripts/bench_mac.sh --quick
```

Use this as an experimental memory profile, not an 8 GB laptop certification.
With this GGUF, mmap can map almost the whole file into Metal even when only a
few layers are offloaded, because the output head and RoPE tensors are early in
the file. `LOAD_MODE=none` packs only the selected GPU tensors. It also changes
CPU memory use; compare profiles under the same conditions. Normal 16 GB+ Mac
full-offload measurements and offline checks remain pending.

The launcher performs a one-token local inference check after `/health`. It can
therefore retry CPU in auto mode if a backend becomes unhealthy during warmup.
Explicit Metal keeps its error visible; use CPU or a smaller GPU profile if memory
is insufficient. Startup check responses are retained in the launcher state folder.
