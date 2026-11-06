# Roadmap

Each phase is its own branch and PR, stacked on the previous one. Build the minimal
working slice first, then improve it.

Workshop target (Nov 10): phases 0 to 3, plus a light pass of phase 4.
Post-workshop: phase 5. Speed target: about 10 tok/s generation (tentative).

| Phase | Branch | Goal | Status |
| --- | --- | --- | --- |
| 0 | `chore/bootstrap` | Repo skeleton, working rules, docs, README | merged |
| 1 | `feat/baseline-smoke` | Build llama.cpp for CPU, run a small supported GGUF, log a `llama-bench` baseline | merged (validated on cloud VM and laptop i5-1135G7) |
| 2 | `feat/apertus-gguf` | Check v1.5 against llama.cpp's `apertus` architecture, convert to F16 GGUF and quantize to Q4_K_M on a VM, run and benchmark on the laptop | merged (converted and validated against the reference on the cloud VM; laptop Q4_K_M: pp512 23.16 tok/s, tg128 5.89 tok/s) |
| 3 | `feat/serving` | `serve.sh` with `llama-server` (web UI + OpenAI API), verified with networking off; the workshop demo | merged (verified offline on the cloud VM with a stand-in model; laptop run with Apertus pending) |
| 4 | `perf/cpu-tuning` | Benchmark matrix (threads, quant types, KV-cache quant, context, optional Vulkan); pick the fastest acceptable config | merged (script ready; laptop run and config choice pending) |
| 5 | `feat/dspark-spec-decoding`, `feat/eagle3-spec-decoding` | Run draft heads (DSpark, EAGLE 3.1) through llama.cpp, measure acceptance rate and tok/s | in review (both drafts match their references; cloud VM k=3: about 0.5 acceptance, 2.5 tokens per target step; EAGLE 3.1 1.38x, DSpark 1.22x; laptop run pending) |

## Phase details

### 0. Bootstrap
`AGENTS.md`, `docs/` (this file, `ARCHITECTURE.md`, `IO.md`, `HARDWARE.md`),
`README.md` quickstart, `benchmarks/results.md` schema.

### 1. Baseline smoke test
Build llama.cpp at a pinned commit with native CPU flags. Download
Qwen2.5-1.5B-Instruct Q4_K_M, run it with `llama-cli`, record a `llama-bench` row.
This is the minimal end-to-end slice and the reference point for later numbers.

### 2. Apertus GGUF
- Compare the v1.5 `config.json` with llama.cpp's `apertus` support.
- On a cloud VM: convert the BF16 weights to an F16 GGUF (about 16 GB), quantize to
  Q4_K_M (about 5 GB) and Q4_0.
- Copy the Q4_K_M file to the laptop, sanity-check generation, benchmark.

### 3. Serving
`serve.sh` launches `llama-server` with the Apertus GGUF, its chat template, `-t 4` and
a 4K to 8K context. Verified with networking disabled through the web UI and an
OpenAI-client request. This is the workshop demo: chat and document Q&A.

### 4. CPU tuning (light pass before the workshop)
Threads 4 vs 8; Q4_K_M vs Q4_0 vs IQ4_XS; KV-cache quantization; context size;
optionally the Vulkan backend on Iris Xe for prompt processing.

### 5. Speculative decoding (post-workshop)
The pinned llama.cpp already runs DSpark and EAGLE-3 drafts. Three small patches in
`patches/` adapt them to Apertus v1.5: the target graph exposes its layer inputs, the
DSpark converter handles the split vocabulary, llama3 RoPE and the trained block-causal
mask, and EAGLE 3.1 gets per-target `fc_norm` and `norm_output`. `scripts/check_dspark.py`
and `scripts/check_eagle3.py` match the training references step by step. The EAGLE 3.1
draft is the default: same acceptance as DSpark with a draft half the size. Next: run
`scripts/bench_spec.sh` on the laptop and keep the draft only if generation gets faster
there.
