# Benchmark results

One row per run, appended by `scripts/bench.sh`. Column meanings are in
[docs/IO.md](../docs/IO.md#benchmarks). Always check the Hardware column: cloud VM rows
are not laptop numbers.

| Date | Hardware | Model | Quant | Backend | Threads | Settings | Prompt tok/s | Gen tok/s | Draft accept | llama.cpp | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-01 | cloud VM (NOT laptop): Intel Xeon, 4 vCPU, AVX-512, 16 GB | qwen2.5-1.5b-instruct | Q4_K_M | CPU | 4 | pp512 tg128 r3 kv=f16/f16 | 316.51 ± 28.84 | 22.40 ± 0.53 | - | b12032 (dde879bc4) | phase 1 baseline smoke test |
