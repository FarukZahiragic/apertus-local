# Benchmark results

One row per run, appended by `scripts/bench.sh`. Column meanings are in
[docs/IO.md](../docs/IO.md#benchmarks). Always check the Hardware column: cloud VM rows
are not laptop numbers. The CPU tuning matrix has its own file:
[cpu-tuning.md](cpu-tuning.md).

| Date | Hardware | Model | Quant | Backend | Threads | Settings | Prompt tok/s | Gen tok/s | Draft accept | llama.cpp | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | qwen2.5-1.5b-instruct | Q4_K_M | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 316.51 ± 28.84 | 22.40 ± 0.53 | - | b12032 (dde879bc4) | phase 1 baseline smoke test |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | qwen2.5-1.5b-instruct | Q4_K_M | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 342.90 ± 10.89 | 21.78 ± 0.34 | - | b11360 (442b0444) | baseline re-run on the pinned Apertus v1.5 fork build |
| 2026-11-01 | laptop i5-1135G7 | qwen2.5-1.5b-instruct | Q4_K_M | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 129.29 ± 7.62 | 26.95 ± 0.80 | - | b11360 (442b0444) | phase 1 baseline; governor powersave (intel_pstate, EPP performance), AC; MemAvailable 2.8 GiB, swap 4.0/4.0 GiB used; desktop apps running (load ~3.4) |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | apertus-v1.5-8b | Q4_K_M | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 58.88 ± 2.37 | 5.23 ± 0.08 | - | b11360 (442b0444) | phase 2 Apertus on the VM; HF rev 0be762a6 |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | apertus-v1.5-8b | Q4_0 | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 60.28 ± 6.24 | 8.59 ± 0.30 | - | b11360 (442b0444) | phase 2 Apertus on the VM; HF rev 0be762a6 |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | apertus-v1.5-8b | IQ4_XS | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 60.24 ± 5.66 | 5.01 ± 0.25 | - | b11360 (442b0444) | phase 2 Apertus on the VM; HF rev 0be762a6 |
