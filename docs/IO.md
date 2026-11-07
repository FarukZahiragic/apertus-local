# Inputs and outputs

## Models

| Model | Source | Access |
| --- | --- | --- |
| Apertus-v1.5-8B (target) | [`swiss-ai/Apertus-v1.5-8B`](https://huggingface.co/swiss-ai/Apertus-v1.5-8B), BF16 safetensors | Gated: accept the terms on the model page, then export `HF_TOKEN` (a read token of that account) |
| Qwen2.5-1.5B-Instruct (smoke test) | [`Qwen/Qwen2.5-1.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) | Public |
| DSpark draft for Apertus-v1.5-8B (thinking off, epoch 10) | `faruk-zahiragic/Apertus-v1.5-8B-DSpark-e10-thinking-off` @ `f1741d68`, BF16 safetensors (3.4 GB) | Private: `HF_TOKEN` of that account |
| EAGLE 3.1 draft for Apertus-v1.5-8B (thinking off, epoch 10) | `faruk-zahiragic/Apertus-v1.5-8B-EAGLE3.1-e10-thinking-off` @ `4c9d4c9e`, BF16 safetensors (1.7 GB) | Private: `HF_TOKEN` of that account |

`HF_TOKEN` is only read from the environment and only needed on the machine that
downloads the gated weights (the cloud VM). Never commit it.

The Apertus revision is pinned in `scripts/convert_quantize.sh` (`HF_REVISION`, default
`0be762a6`, the `main` head on 2026-11-01). The DSpark drafter was trained against
revision `a411d838`, like the EAGLE 3.1 drafter; the weights, config and tokenizer files
are identical at both revisions (same LFS hashes).

## Conversion (cloud VM)

```bash
scripts/setup_llamacpp.sh
export HF_TOKEN=...                       # account that accepted the model terms
scripts/convert_quantize.sh               # Q4_K_M and Q4_0; add IQ4_XS etc. as arguments
```

Needs about 40 GB of disk and 8 GB of free RAM. Only the language model is converted;
the vision and audio tokenizers are skipped. `models/SHA256SUMS` gets one line per
output file.

Draft heads (need the target's config and tokenizer files, not its weights):

```bash
scripts/convert_draft.sh --head eagle3   # F16 + Q4_0 (output head Q4_0), the default draft
scripts/convert_draft.sh --head dspark   # F16 + Q4_0; add Q4_K_M etc. as arguments
```

Logit check against the reference implementation (separate venv, because the
converter pins `transformers==4.57.6`):

```bash
python3 -m venv .venv-ref
.venv-ref/bin/pip install --extra-index-url https://download.pytorch.org/whl/cpu torch==2.11.0 \
  numpy safetensors "transformers @ git+https://github.com/swiss-ai/transformers@3797303dda74844e3d1f8977ff5518bb91f818b4"
.venv-ref/bin/python scripts/check_logits.py --hf-dir models/hf/Apertus-v1.5-8B \
  --gguf models/apertus-v1.5-8b-Q4_K_M.gguf
```

Draft check against the Speculators code the draft was trained with
(`vllm-project/speculators` @ `7046ac6` plus the checkpoint's `speculators.patch`):

```bash
git clone https://github.com/vllm-project/speculators /tmp/speculators
git -C /tmp/speculators checkout 7046ac63fac4eeb218dc2e92a385c7d1ec8c4e00
git -C /tmp/speculators apply models/hf/Apertus-v1.5-8B-DSpark-e10-thinking-off/speculators.patch
.venv-ref/bin/python scripts/check_dspark.py --speculators /tmp/speculators/src \
  --target-hf models/hf/Apertus-v1.5-8B --draft-hf models/hf/Apertus-v1.5-8B-DSpark-e10-thinking-off \
  --target-gguf models/apertus-v1.5-8b-F16.gguf --draft-gguf models/apertus-v1.5-8b-dspark-e10-F16.gguf
```

(`convert_draft.sh` downloads only `config.json`, `model.safetensors` and `SHA256SUMS`;
fetch `speculators.patch` from the same repo.)

EAGLE 3.1 check against the TorchSpec / vLLM math (no extra checkout needed):

```bash
.venv-ref/bin/python scripts/check_eagle3.py --target-hf models/hf/Apertus-v1.5-8B \
  --draft-hf models/hf/Apertus-v1.5-8B-EAGLE3.1-e10-thinking-off \
  --target-gguf models/apertus-v1.5-8b-F16.gguf --draft-gguf models/apertus-v1.5-8b-eagle3.1-e10-F16.gguf
```

## GGUF files

All model files live in `models/` (ignored by git).

| File | Size | Use | sha256 (HF rev `0be762a6`, llama.cpp `442b0444`) |
| --- | --- | --- | --- |
| `apertus-v1.5-8b-F16.gguf` | 16.0 GiB | Intermediate, VM only (`--keep-f16`) | `f8282ab55311b6710620b040e62daa7e73c56b804a8bb114a48cd39385adac21` |
| `apertus-v1.5-8b-Q4_K_M.gguf` | 5.3 GiB | Default for the laptop | `e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c` |
| `apertus-v1.5-8b-Q4_0.gguf` | 4.9 GiB | Tuning comparison (fast CPU repack paths) | `a1f9585e5e60294eea62d5540dc4b2dd15da6faa20a620e42aa1becb46fc5882` |
| `apertus-v1.5-8b-IQ4_XS.gguf` | 4.8 GiB | Tuning comparison | `999946833b89d5b6f9bf2ddd93a56af7fc58a728a359537db0a84bb6e2ac757e` |
| `apertus-v1.5-8b-dspark-e10-F16.gguf` | 3.2 GiB | DSpark draft, reference checks | `4023e2278a0de0fea57ecd72b668ae20a6bde46bf6e4bd00cefaa099821ed696` |
| `apertus-v1.5-8b-dspark-e10-Q4_K_M.gguf` | 0.96 GiB | DSpark draft, comparison | `eb53928d1625ecf342ab659579747f6c57b7a7e9110e73db0ab2fc4ea01431d9` |
| `apertus-v1.5-8b-dspark-e10-Q4_0.gguf` | 0.91 GiB | DSpark draft, comparison (faster than Q4_K_M on CPU at the same acceptance) | `a0025139277aaa3a02eebab2183d2876d10498a2e43bb9a0ccb60151c26a4318` |
| `apertus-v1.5-8b-eagle3.1-e10-F16.gguf` | 1.6 GiB | EAGLE 3.1 draft, reference checks | `137e9466f73296f051fe6702db55aa72f0daf52892dfa5ef5547b46e1ed5c67f` |
| `apertus-v1.5-8b-eagle3.1-e10-Q4_0.gguf` | 0.45 GiB | Default experimental draft; output head Q4_0 | `244903daa6dc2218daef08c84d5b4d2377019e4283108646d0d7c62a3dc0695d` |

The draft GGUFs (llama.cpp `442b0444` + `patches/`) hold no token embedding, and the
DSpark ones no output head either: they borrow the target's at load time, so they only
work next to an Apertus v1.5 target.

The target's output head and token embedding are Q6_K in every quantized variant (see
[ARCHITECTURE.md](ARCHITECTURE.md#quantization-choices)). The laptop has about 11 GB of
free disk: copy only the Q4 file(s) it needs, never the F16 file or the HF download.

## llama-server

- Binds to `127.0.0.1:8080` by default (localhost only).
- Web UI: `http://127.0.0.1:8080/`
- OpenAI-compatible API: `http://127.0.0.1:8080/v1` (`/v1/chat/completions`,
  `/v1/models`); any API key string is accepted.
- Health: `http://127.0.0.1:8080/health`
- Model name in the API: the GGUF file name without `.gguf`, e.g. `apertus-v1.5-8b-Q4_K_M`.
- Flags set by `scripts/serve.sh`: detected physical/performance-core `--threads`
  (4 on the reference laptop), `--ctx-size 4096`, `--parallel 1`,
  `--n-gpu-layers 0` (CPU) or `99` (explicit Metal/Vulkan),
  `--jinja` (Apertus 1.5 chat template from the GGUF),
  `--chat-template-kwargs '{"enable_thinking":false}'` (no deliberation before answers;
  `THINKING=1` turns it back on), `--offline` (no downloads).
  Override with `MODEL`, `HOST`, `PORT`, `THREADS`, `CTX`, `THINKING`, `BACKEND`, or pass extra flags
  after `--`.
- `LLAMA_CPP_DIR` defaults to `vendor/llama.cpp`; `BUILD_DIR` defaults to its `build/`.
  `BACKEND=metal` selects `build-metal/`; `BACKEND=vulkan` selects `build-vulkan/`.
  Packaged launches prefer `runtime/<backend>/`. Auto mode uses CPU unless
  `APERTUS_METAL_VALIDATED=1` on Apple Silicon and Metal device enumeration succeeds.
  To use Iris Xe after `scripts/setup_llamacpp.sh --vulkan`:
  `BUILD_DIR=vendor/llama.cpp/build-vulkan scripts/serve.sh -- --n-gpu-layers 99`.
- KV cache: about 0.13 MB per token at F16 (32 layers x 8 KV heads x 128 x 2), so
  0.5 GB at 4,096 tokens and 1 GB at 8,192.
- Client example: `examples/openai_client.py` (official `openai` package; `--file` for
  document Q&A, `--repeat N` for a reliability run). Streamed token counts come from
  the API's final usage event; a response without usage is reported without a token count.
- `scripts/serve_spec.sh` adds a draft head: `--model-draft $DRAFT`,
  `--spec-type $SPEC_TYPE` (from the draft file name), `--spec-draft-n-max $K` (default 3), `--threads-draft`.
  The draft also defaults to CPU (`--n-gpu-layers-draft 0`). For Vulkan, select the
  Vulkan build and pass both `--n-gpu-layers 99` and `--n-gpu-layers-draft 99` after `--`.
  Same endpoint and flags otherwise; the default EAGLE 3.1 draft adds 0.45 GiB of weights.
  Plain CPU serving remains the laptop default because the recorded draft and Vulkan
  runs were slower.

## Benchmarks

Command format:

```bash
scripts/bench.sh -m models/<file>.gguf [-t THREADS] [-p 512] [-n 128] [-r 3] \
  [--backend cpu|metal|vulkan] [--hw LABEL] [--notes TEXT] [--dry-run] [-- extra llama-bench args]
```

It runs `llama-bench -o json` and turns the result into one table row. Extra
`llama-bench` flags (for example `-ctk q8_0 -ctv q8_0`) are recorded in Settings.
`BUILD_DIR=vendor/llama.cpp/build-vulkan` selects the Vulkan build.
`--backend` defaults to CPU and fixes `-ngl 0`; Metal and Vulkan require an
enumerated device and use `-ngl 99`, recorded in Settings. This final offload flag
takes precedence over extra arguments. Use `--backend vulkan` for a GPU comparison,
not just an alternative build path. `scripts/bench_mac.sh` records paired Apple
Silicon CPU/Metal rows with detected performance-core threads.

`scripts/bench_spec.sh [--k "3 5"] [-n 256] [--hw LABEL] [--vulkan] [--dry-run]` measures speculative
decoding end to end through `llama-server` (6 chat prompts, thinking off, greedy): a
no-draft baseline, then one run per draft length. CPU is the default; `--vulkan` selects
`build-vulkan/`, labels rows `Vulkan`, and offloads both target and draft with 99 layers.
It fails before inference if the selected build lists no Vulkan device, so a CPU
fallback cannot be recorded as a Vulkan result. `BUILD_DIR` overrides the build path.
Context and target/draft offload settings are
recorded in Settings. The llama.cpp source commit is read from `LLAMA_CPP_DIR`, with
`+ local changes` when tracked files differ (including our patches).

Its Draft accept column contains `acceptance rate (τ≈1 + k × acceptance rate)`.
This estimates tokens per target step assuming full-length drafts; it is not a measured
step count. Older rows labelled `τ` use the same estimate and are kept as recorded.

The benchmark forces localhost, thinking off, and direct local HTTP requests. `PORT`
defaults to 8097 and must be free; `STARTUP_TIMEOUT` defaults to 300 seconds. Each run
has its own temporary directory. On failure the server is stopped, logs are kept at
the printed path, and previously completed rows stay in `RESULTS` (default:
`benchmarks/results.md`). `--dry-run` runs inference and prints rows without saving.

The tuning matrix writes the same row format to
[benchmarks/results.md](../benchmarks/results.md). Historical tuning rows remain in
`benchmarks/cpu-tuning.md`:

```bash
scripts/bench_matrix.sh [--quick] [--vulkan] [--dry-run] [MODEL.gguf ...]
```

Each run appends one row to [benchmarks/results.md](../benchmarks/results.md):

| Column | Meaning |
| --- | --- |
| Date | UTC date of the run |
| Hardware | Machine label, e.g. `laptop i5-1135G7` or `cloud VM (...)`. VM numbers are never laptop numbers |
| Model | Model name, e.g. `Apertus-v1.5-8B` |
| Quant | GGUF quantization type, e.g. `Q4_K_M` |
| Backend | llama.cpp backend, e.g. `CPU`, `Vulkan` |
| Threads | `-t` value |
| Settings | Prompt / generation lengths, repetitions, KV-cache type, other non-default flags |
| Prompt tok/s | Prompt processing throughput (mean ± std) |
| Gen tok/s | Generation throughput (mean ± std) |
| Draft accept | Speculative draft acceptance rate, `-` when not used |
| llama.cpp | llama.cpp build (release tag and short commit) |
| Notes | Anything needed to interpret the row |
