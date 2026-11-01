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

Not chosen yet: fill in after the laptop run (fastest settings whose quality is
acceptable), then update the defaults in `scripts/serve.sh`.

## Laptop results (i5-1135G7)

| Date | Hardware | Model | Quant | Backend | Threads | Settings | Prompt tok/s | Gen tok/s | Draft accept | llama.cpp | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
