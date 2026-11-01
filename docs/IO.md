# Inputs and outputs

## Models

| Model | Source | Access |
| --- | --- | --- |
| Apertus-v1.5-8B (target) | [`swiss-ai/Apertus-v1.5-8B`](https://huggingface.co/swiss-ai/Apertus-v1.5-8B), BF16 safetensors | Gated: accept the terms on the model page, then export `HF_TOKEN` (a read token of that account) |
| Qwen2.5-1.5B-Instruct (smoke test) | [`Qwen/Qwen2.5-1.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) | Public |

`HF_TOKEN` is only read from the environment and only needed on the machine that
downloads the gated weights (the cloud VM). Never commit it.

The Apertus revision is pinned in `scripts/convert_quantize.sh` (`HF_REVISION`, default
`0be762a6`, the `main` head on 2026-11-01). The DSpark drafter was trained against
revision `a411d838`; check that the weights did not change between the two before
phase 5.

## Conversion (cloud VM)

```bash
scripts/setup_llamacpp.sh
export HF_TOKEN=...                       # account that accepted the model terms
scripts/convert_quantize.sh               # Q4_K_M and Q4_0; add IQ4_XS etc. as arguments
```

Needs about 40 GB of disk and 8 GB of free RAM. Only the language model is converted;
the vision and audio tokenizers are skipped. `models/SHA256SUMS` gets one line per
output file.

Logit check against the reference implementation (separate venv, because the
converter pins `transformers==4.57.6`):

```bash
python3 -m venv .venv-ref
.venv-ref/bin/pip install --extra-index-url https://download.pytorch.org/whl/cpu torch==2.11.0 \
  numpy safetensors "transformers @ git+https://github.com/swiss-ai/transformers@3797303dda74844e3d1f8977ff5518bb91f818b4"
.venv-ref/bin/python scripts/check_logits.py --hf-dir models/hf/Apertus-v1.5-8B \
  --gguf models/apertus-v1.5-8b-Q4_K_M.gguf
```

## GGUF files

All model files live in `models/` (ignored by git).

| File | Size | Use | sha256 (HF rev `0be762a6`, llama.cpp `442b0444`) |
| --- | --- | --- | --- |
| `apertus-v1.5-8b-F16.gguf` | 16.0 GiB | Intermediate, VM only (`--keep-f16`) | `f8282ab55311b6710620b040e62daa7e73c56b804a8bb114a48cd39385adac21` |
| `apertus-v1.5-8b-Q4_K_M.gguf` | 5.3 GiB | Default for the laptop | `e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c` |
| `apertus-v1.5-8b-Q4_0.gguf` | 4.9 GiB | Tuning comparison (fast CPU repack paths) | `a1f9585e5e60294eea62d5540dc4b2dd15da6faa20a620e42aa1becb46fc5882` |
| `apertus-v1.5-8b-IQ4_XS.gguf` | 4.8 GiB | Tuning comparison | `999946833b89d5b6f9bf2ddd93a56af7fc58a728a359537db0a84bb6e2ac757e` |

The output head and token embedding are Q6_K in every variant (see
[ARCHITECTURE.md](ARCHITECTURE.md#quantization-choices)). The laptop has about 11 GB of
free disk: copy only the Q4 file(s) it needs, never the F16 file or the HF download.

## llama-server

- Binds to `127.0.0.1:8080` by default (localhost only).
- Web UI: `http://127.0.0.1:8080/`
- OpenAI-compatible API: `http://127.0.0.1:8080/v1` (`/v1/chat/completions`,
  `/v1/models`); any API key string is accepted.
- Health: `http://127.0.0.1:8080/health`
- Flags: set in `scripts/serve.sh` (phase 3).

## Benchmarks

Command format:

```bash
scripts/bench.sh -m models/<file>.gguf [-t THREADS] [-p 512] [-n 128] [-r 3] \
  [--hw LABEL] [--notes TEXT] [--dry-run] [-- extra llama-bench args]
```

It runs `llama-bench -o json` and turns the result into one table row. Extra
`llama-bench` flags (for example `-ctk q8_0 -ctv q8_0`) are recorded in Settings.

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
