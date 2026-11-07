# CPU tuning (laptop)

Rows are appended by `scripts/bench_matrix.sh` (one `llama-bench` run each; columns as
in [docs/IO.md](../docs/IO.md#benchmarks)). The Notes column names the axis:

- `threads`: 4 vs 8 threads (the i5-1135G7 has 4 cores / 8 threads).
- `quant`: Q4_K_M vs Q4_0 vs IQ4_XS, all with the output head and embedding at Q6_K.
- `kv`: F16 vs Q8_0 KV cache with flash attention, on an empty and a filled context.
- `ctx`: speed with 2,048 tokens already in context (`-d`); 4,096 is in the `kv` rows.
- `vulkan`: optional run with all layers on the Iris Xe iGPU.

Generation speed (Gen tok/s) is what a chat user feels; prompt speed (Prompt tok/s)
decides the wait before the first token on pasted documents.

## Chosen configuration

Working default: Q4_K_M, CPU, 4 threads, F16 KV cache, 4,096-token context, thinking
off, no draft (`scripts/serve.sh`). The 6 November server comparison in
[results.md](results.md) measured 5.82 tok/s without a draft versus 5.38 with EAGLE
k=3; all recorded Iris Xe Vulkan configurations were slower than plain CPU too.

This is provisional: the full thread/quant/KV/context matrix below has not been run.
The earlier Q4_0 baseline reached 6.08 tok/s versus 5.89 for Q4_K_M under different
background load, so it is a candidate for a controlled comparison, not a selected
replacement. Run the matrix under the same conditions and check answer quality
before changing the serving defaults.

## Laptop results (i5-1135G7)

| Date | Hardware | Model | Quant | Backend | Threads | Settings | Prompt tok/s | Gen tok/s | Draft accept | llama.cpp | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
