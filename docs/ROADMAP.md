# Roadmap

Each phase is its own branch and PR. Stack only work that depends on an unmerged
phase; once it lands, base the next branch on current `main`. Build the minimal
working slice first, then improve it. Merged code and completed laptop validation
are tracked separately below.

Workshop target (Nov 10): phases 0 to 3, plus a light pass of phase 4.
Phase 5 was implemented ahead of the workshop. Speed target: about 10 tok/s
generation (tentative, not reached on the reference laptop).

| Phase | Branch | Goal | Status |
| --- | --- | --- | --- |
| 0 | `chore/bootstrap` | Repo skeleton, working rules, docs, README | merged |
| 1 | `feat/baseline-smoke` | Build llama.cpp for CPU, run a small supported GGUF, log a `llama-bench` baseline | merged (validated on cloud VM and laptop i5-1135G7) |
| 2 | `feat/apertus-gguf` | Check v1.5 against llama.cpp's `apertus` architecture, convert to F16 GGUF and quantize to Q4_K_M on a VM, run and benchmark on the laptop | merged (converted and validated against the reference on the cloud VM; laptop Q4_K_M: pp512 23.16 tok/s, tg128 5.89 tok/s) |
| 3 | `feat/serving` | `serve.sh` with `llama-server` (web UI + OpenAI API), verified with networking off; the workshop demo | merged; laptop server chat measured, but network-disabled Apertus UI/API checks remain pending; 50 streamed requests at 4K context pass on the reference laptop (Nov 7, max 16 tokens) (earlier VM offline check used a stand-in model) |
| 4 | `perf/cpu-tuning` | Benchmark matrix (threads, quant types, KV-cache quant, context, optional Vulkan); pick the fastest acceptable config | merged; full laptop matrix pending, CPU/no-draft retained after the recorded Vulkan and EAGLE comparisons |
| 5 | `feat/dspark-spec-decoding`, `feat/eagle3-spec-decoding` | Run draft heads (DSpark, EAGLE 3.1) through llama.cpp, measure acceptance rate and tok/s | merged via PRs #13 and #14; reference checks pass, VM gains recorded; laptop CPU EAGLE k=3: 5.38 vs 5.82 tok/s without draft, Vulkan also slower; experimental only |
| Cleanup | `chore/repo-cleanup` | Consolidate phase 5, fix benchmark lifecycle and build selection, sync measured results and handoff docs | merged; serving smoke and benchmark failure-path checks pass; remaining validation is listed below |
| 6 | `feat/macos-support` | Portable builds, downloads and benchmark scripts on macOS and Linux | merged; owner reports physical Mac setup, manual chat and fresh offline start pass; hardware label pending |
| 7 | `perf/apple-silicon` | Reproducible CPU/Metal comparison on an Apple Silicon Mac | harness merged; owner observed faster chat informally; controlled measurements pending and do not block CPU-default packaging |
| 8 | `feat/hardware-defaults` | Detect hardware, choose conservative settings, allow explicit overrides | merged; Bash 3.2 selection and override checks pass; automatic Metal remains gated on hardware validation |
| 9 | `feat/workshop-launcher`, `feat/macos-setup`, `feat/macos-release`, `feat/unsigned-macos-download` | Downloadable native runtime, local-chat launcher and Mac setup/release workflow | physical Mac source/offline rehearsal passed per owner; unsigned preview is the default and needs no Apple credentials; first-open guide bundled and hosted; physical downloaded-app opening rehearsal remains separate; Windows is tracked in phase 12; signing optional |
| 10 | `feat/hf-distribution`, `feat/unsigned-macos-download` | Static Hugging Face download page and versioned model distribution | model and static Space published in faruk-zahiragic namespace; preview.3 adds native Windows x64/ARM64 alongside Linux and unsigned Apple Silicon downloads, checksums and first-open guides; physical Finder-opening rehearsal pending |
| 11 | `chore/workshop-validation` | Automated checks and fresh-install/offline rehearsal | local Bash 3.2 checks pass; extracted Linux package passes document Q&A and 50 requests; native CI passes; physical Mac source/offline rehearsal passed per owner; packaged app first-open and Linux offline hardware rehearsals pending |
| 12 | `feat/windows-support` | Native Windows x64/ARM64 downloads and broad OS compatibility requirements | implemented in PR #25; native x64/ARM64 launcher and real-model checks pass; preview.3 publishes four native packages; Mac wrapper targets 13.3 and Linux symbol floors are recorded; Ubuntu/Debian consumer checks pass; physical Windows installation and performance remain separate |
| 13 | `feat/one-command-launcher` | One pasted command on Mac/Linux/Windows; reuse verified native runtimes and weights; direct Terminal launch on Mac | in progress; standalone bootstrap and failure/reuse tests pass locally; published-runtime Linux inference and native CI validation in progress |

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
a 4K to 8K context. The cleanup smoke test exercised the real Apertus target through
health, the embedded web UI, streamed chat and final token usage, with and without
EAGLE (512-token context for the check). The network-disabled laptop demo, document
Q&A and 50-request reliability run remain to be verified. The earlier offline VM
check used a stand-in model.

### 4. CPU tuning (light pass before the workshop)
Threads 4 vs 8; Q4_K_M vs Q4_0 vs IQ4_XS; KV-cache quantization; context size;
optionally the Vulkan backend on Iris Xe for prompt processing.

### 5. Speculative decoding
The pinned llama.cpp already runs DSpark and EAGLE-3 drafts. Three small patches in
`patches/` adapt them to Apertus v1.5: the target graph exposes its layer inputs, the
DSpark converter handles the split vocabulary, llama3 RoPE and the trained block-causal
mask, and EAGLE 3.1 gets per-target `fc_norm` and `norm_output`. `scripts/check_dspark.py`
and `scripts/check_eagle3.py` match the training references step by step. The EAGLE 3.1
draft is the default for explicit speculative runs: similar acceptance to DSpark with
a draft half the size. On the laptop it did not beat plain CPU serving; phase 5's
implementation and initial EAGLE laptop comparison are complete, without meeting the
speed target. A DSpark laptop comparison is still unmeasured.

## Handoff to the next speed work

The working configuration is `scripts/serve.sh`: Q4_K_M, CPU, 4 threads, F16 KV cache,
4K context, thinking off, no draft. Keep this as the comparison point.

1. Finish the phase 3 demo checks on the laptop: follow `docs/OFFLINE.md` with Apertus,
   test the web UI and document Q&A with networking disabled, then run the 50-request
   reliability check. A localhost smoke test alone does not prove offline operation.
2. Continue phase 4 on a new `perf/cpu-tuning-followup` branch from `main`. Close other
   applications, use AC power, and run `scripts/bench_matrix.sh`; record hardware,
   memory/background load, and each new row in `benchmarks/results.md`.
3. Compare Q4_0 and Q4_K_M under the same conditions, then threads, KV cache and filled
   contexts. Check answer quality before selecting a faster configuration. Update
   `benchmarks/cpu-tuning.md` and the defaults only when the results support a change.

Do not assume the VM's speculative speedup transfers to the laptop. Further draft or
Vulkan experiments should justify themselves against the CPU baseline before becoming
the default. No new inference engine, UI framework or training work is planned here.
