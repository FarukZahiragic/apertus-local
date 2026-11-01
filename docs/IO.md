# Inputs and outputs

## Models

| Model | Source | Access |
| --- | --- | --- |
| Apertus-v1.5-8B (target) | [`swiss-ai/Apertus-v1.5-8B`](https://huggingface.co/swiss-ai/Apertus-v1.5-8B), BF16 safetensors | Gated: accept the terms on the model page, then export `HF_TOKEN` (a read token of that account) |
| Qwen2.5-1.5B-Instruct (smoke test) | [`Qwen/Qwen2.5-1.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF) | Public |

`HF_TOKEN` is only read from the environment and only needed on the machine that
downloads the gated weights (the cloud VM). Never commit it.

## GGUF files

All model files live in `models/` (ignored by git).

| File | Size (approx.) | Use |
| --- | --- | --- |
| `apertus-v1.5-8b-F16.gguf` | 16 GB | Intermediate, VM only |
| `apertus-v1.5-8b-Q4_K_M.gguf` | 5 GB | Default for the laptop |
| `apertus-v1.5-8b-Q4_0.gguf` | 4.7 GB | Tuning comparison (fast CPU repack paths) |
| `apertus-v1.5-8b-IQ4_XS.gguf` | 4.5 GB | Tuning comparison |

The output head is kept at Q6_K or better in every variant (see
[ARCHITECTURE.md](ARCHITECTURE.md#references)).

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
