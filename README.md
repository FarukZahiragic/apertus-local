# apertus-local

Personal workshop prototype by Faruk Zahiragić. Not supported by EPFL.
[Report issues on GitHub](https://github.com/FarukZahiragic/apertus-local/issues);
support and updates are not guaranteed.

Text, image and audio input are supported on Windows x64/ARM64, Apple Silicon Mac
and Linux x86_64. The launcher reuses the language model and downloads matching
F32 encoders. See [image/audio setup and validation](docs/MULTIMODAL.md).

Run [Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B) on a machine
you control, with no dedicated GPU required and no internet during inference, using
[llama.cpp](https://github.com/ggml-org/llama.cpp). The use is private chat and
questions about a document: the data stays on that machine, including when
connectivity is poor.

The measured run is a laptop ([docs/HARDWARE.md](docs/HARDWARE.md),
[benchmarks/results.md](benchmarks/results.md)). The same path is a server you
administer: local weights, llama.cpp, and a chat UI or an OpenAI-compatible API
on that machine (`HOST` in `scripts/serve.sh`; the default bind is localhost).
It is also the pattern for other open-weight models llama.cpp already supports.
The Qwen file in the quickstart is that case. Apertus 1.5 is the special case:
stock llama.cpp does not load it yet, so this repository converts it to a 4-bit
GGUF first.

A split onto a small added GPU is outside this repository. On the reference
laptop the fair Q4_K_M run is about 5.9 tokens/s generation and 23 tokens/s
prompt processing (the 1 November 2026 row in `benchmarks/results.md`).

## One-command local chat

On **Apple Silicon macOS or x86_64 Linux**, paste this into Terminal:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.sh)"
```

On **Windows x64 or ARM64**, paste this into PowerShell:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.ps1)))
```

The command gets a checksum-verified native runtime if missing (about 12 MB on
Windows, 17–20 MB on Linux/Mac), reuses or downloads the 5.3 GiB language model and 872 MiB image/audio encoders, and opens
local chat. It installs no compiler, Python, Homebrew, or repository checkout.
The Mac path runs the server directly in Terminal, without opening the app wrapper.
Keep the terminal open; Ctrl+C stops chat. The command prints a local entry point
for later starts, including offline. See [docs/ONE_COMMAND.md](docs/ONE_COMMAND.md)
for preparation without starting, existing model/runtime reuse, and OS requirements.
The setup command is pinned to a fixed source version. It runs with your user
permissions, without an OS sandbox. See [install folders](docs/ONE_COMMAND.md#downloads-and-local-files)
and [removal steps](docs/ONE_COMMAND.md#remove-apertus-local).

The bundled [participant chat UI](docs/WORKSHOP_UI.md) keeps text, image and audio
input and supported chat settings. It omits generic reasoning levels and
unconfigured tool, MCP and agent controls.

## Downloadable launcher

Download the matching archive from the [Hugging Face download page](https://huggingface.co/spaces/faruk-zahiragic/apertus-local)
and extract it. Windows users double-click `Start.cmd`, Mac users open
`Apertus Local.app`, and Linux users run `./Start.sh`. Native archives include
their runtime; participants do not need a compiler or Python.

The first start downloads and verifies both model files (about 6.1 GiB total), starts local chat, and opens
the browser after health and a one-token inference check. Later starts reuse the
verified model offline. Keep the launcher's window open; Ctrl+C or the matching
Stop launcher shuts it down. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)
for resumable downloads and offline preparation.
See [Windows setup](docs/WINDOWS.md) and [compatibility requirements](docs/COMPATIBILITY.md)
for architecture choices and minimum capabilities across OS releases.
The Mac source setup and offline rehearsal passed on a physical Mac. An unsigned
Apple Silicon preview is available without Apple Developer membership; first launch
may need **System Settings > Privacy & Security > Open Anyway**. Its downloaded-app
opening rehearsal remains pending. See [validation status](docs/VALIDATION.md)
and [Mac release steps](docs/MACOS_RELEASE.md). Formal speed measurements can follow later.
Native CI checks actual inference on Windows x64/ARM64, Linux and Apple Silicon; the Linux offline
check also waits for the embedded chat to render in a real browser.

## Quickstart

For a Mac development checkout, send the standalone [setup.sh](setup.sh) file and
run `bash ~/Downloads/setup.sh` in Terminal. It installs missing prerequisites,
clones `main` into `~/apertus-1.5-local`, builds CPU and Metal,
verifies the model download and opens CPU chat. Complete any macOS/Homebrew
installation prompts. Use `bash ~/Downloads/setup.sh --no-start` to prepare before
an offline session. See [docs/MACOS.md](docs/MACOS.md) for logs and Metal testing.

Apple Silicon: follow [docs/MACOS.md](docs/MACOS.md) to build natively and compare
CPU with Metal. The same GGUF works on both platforms; Mac performance is not yet
measured. CPU serving remains supported.
`scripts/bench_mac.sh` records a controlled CPU/Metal comparison after both builds
are available; every row identifies the hardware and backend.

Source-build prerequisites (Ubuntu 24.04): install Node.js 24/npm for the bundled
UI, then the native build tools below. Participant downloads include the UI and
need no Node.js.

```bash
sudo apt install -y git cmake build-essential python3 python3-venv curl
git clone https://github.com/FarukZahiragic/apertus-local && cd apertus-local
```

### 1. Build llama.cpp and run a smoke test

```bash
scripts/setup_llamacpp.sh        # pinned llama.cpp, CPU build with -march=native (~10 min)
scripts/get_model.sh             # Qwen2.5-1.5B-Instruct Q4_K_M (1.1 GB), sha256-checked
vendor/llama.cpp/build/bin/llama-cli -m models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  -t 4 -n 64 -st -p "In one sentence, why does running a model locally help privacy?"
scripts/bench.sh -m models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 4 --notes "baseline"
```

`bench.sh` appends a row to [benchmarks/results.md](benchmarks/results.md); on the
laptop the Hardware column is filled in as `laptop i5-1135G7` automatically.

### 2. Get Apertus-v1.5-8B as a 4-bit GGUF

Download the verified Q4_K_M file (5.3 GiB) from
[our Hugging Face repository](https://huggingface.co/faruk-zahiragic/Apertus-v1.5-8B-GGUF).
It uses a pinned revision and checksum; conversion is needed only when producing a
new artifact (see [docs/IO.md](docs/IO.md#conversion-cloud-vm)).

```bash
scripts/get_model.sh --apertus
vendor/llama.cpp/build/bin/llama-cli -m models/apertus-v1.5-8b-Q4_K_M.gguf \
  -t 4 -c 4096 -n 128 -st -p "Explain in two sentences what Apertus is."
scripts/bench.sh -m models/apertus-v1.5-8b-Q4_K_M.gguf -t 4 --name Apertus-v1.5-8B
```

### 3. Serve it offline

```bash
scripts/serve.sh                      # http://127.0.0.1:8080/ web UI, /v1 OpenAI API
python3 -m venv .venv-client && .venv-client/bin/pip install openai   # once, while online
.venv-client/bin/python examples/openai_client.py "What is Apertus?"
```

Defaults: physical CPU cores (4 on the reference laptop; performance cores on
Apple Silicon), 4,096-token context (`CTX=8192 scripts/serve.sh` for longer
documents), one slot, thinking off (`THINKING=1 scripts/serve.sh` to let Apertus
deliberate first, which is much slower on a CPU), CPU only. `BUILD_DIR` selects an
alternative build; `BACKEND=cpu|metal|vulkan` selects a backend. `GPU_LAYERS` and `LOAD_MODE` control GPU memory use. Auto mode keeps CPU
until Metal is validated on the Mac (see [MACOS.md](docs/MACOS.md)). The client reports
the server's token usage, including for streamed answers. How to prove it works with networking disabled:
[docs/OFFLINE.md](docs/OFFLINE.md).

### 4. Tune for the laptop (optional)

```bash
scripts/bench_matrix.sh --quick       # 5-minute setup check
scripts/bench_matrix.sh               # full matrix, about 35 to 45 minutes
```

It compares 4 vs 8 threads, Q4_K_M / Q4_0 / IQ4_XS (whichever files are in `models/`),
F16 vs Q8_0 KV cache, and filled contexts, and writes rows to
[benchmarks/results.md](benchmarks/results.md). Earlier tuning rows remain in
[benchmarks/cpu-tuning.md](benchmarks/cpu-tuning.md). For the Iris Xe iGPU, build once
with `scripts/setup_llamacpp.sh --vulkan` (see the script header for packages) and add
`--vulkan`. With 11 GB of free disk, test one extra quant file at a time.

### 5. Speculative decoding (experimental)

Re-run `scripts/setup_llamacpp.sh` first: it applies the patches in `patches/`. Put the
draft GGUF (EAGLE 3.1, 0.45 GB, converted with `scripts/convert_draft.sh --head eagle3`
on the VM) into `models/` next to the target, then:

```bash
scripts/bench_spec.sh --k "3 4"       # no draft vs k=3 vs k=4, rows go to benchmarks/results.md
scripts/serve_spec.sh                 # same as serve.sh, plus the draft (K=3 by default)
```

The drafts were trained with thinking off. On the cloud VM EAGLE 3.1 at k=3 gave about
1.4x and DSpark about 1.2x. On the laptop, EAGLE k=3 slowed generation from 5.82 to
5.38 tokens/s. Iris Xe Vulkan was slower too: 3.55 tokens/s without a draft and at best
4.58 with EAGLE k=1. Keep `scripts/serve.sh` as the laptop default. These are the
6 November 2026 rows in [benchmarks/results.md](benchmarks/results.md).

For the DSpark draft:
`DRAFT=models/apertus-v1.5-8b-dspark-e10-Q4_0.gguf scripts/serve_spec.sh`.
To repeat an Iris Xe comparison after building with `scripts/setup_llamacpp.sh --vulkan`:

```bash
scripts/bench_spec.sh --vulkan --k "1 2 3"   # explicitly offloads both target and draft
BUILD_DIR=vendor/llama.cpp/build-vulkan scripts/serve_spec.sh -- \
  --n-gpu-layers 99 --n-gpu-layers-draft 99
```

The benchmark uses localhost port 8097 (`PORT` overrides it), keeps logs on failure,
and appends each completed configuration immediately. `--dry-run` still runs inference
but only prints the rows.

Remaining validation and the next speed work are tracked in [docs/ROADMAP.md](docs/ROADMAP.md).

## Docs

- [AGENTS.md](AGENTS.md): working rules for contributors and agents
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): components, data flow, why llama.cpp
- [docs/IO.md](docs/IO.md): model files, server endpoint, benchmark format
- [docs/ROADMAP.md](docs/ROADMAP.md): phases and status
- [docs/HARDWARE.md](docs/HARDWARE.md): laptop specs and speed expectations
- [docs/OFFLINE.md](docs/OFFLINE.md): verifying the demo with networking disabled
- [benchmarks/results.md](benchmarks/results.md): all benchmark runs
