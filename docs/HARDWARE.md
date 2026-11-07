# Hardware

## Target laptop (the "regular laptop" reference)

| Part | Spec |
| --- | --- |
| CPU | Intel Core i5-1135G7 (Tiger Lake), 4 cores / 8 threads |
| SIMD | AVX2, AVX-512 with VNNI (used by llama.cpp for faster matrix math) |
| GPU | Intel Iris Xe (integrated, shares system RAM) |
| RAM | 2 x 8 GB DDR4-3200, dual channel (16 GB) |
| Memory bandwidth | 51.2 GB/s theoretical, about 35 to 40 GB/s in practice |
| OS | Ubuntu 24.04 |
| Free disk | about 11 GB: room for one or two Q4 GGUF files (about 5 GiB each), not the F16 file |

## What this means for speed

- Generation on CPU is limited by memory bandwidth. The Q4_K_M file is 5.3 GiB;
  measured generation is **about 5.8 to 5.9 tok/s** in the fair baseline and server
  chat runs. Prompt processing measured about 18 to 23 tok/s. See the laptop rows in
  [benchmarks/results.md](../benchmarks/results.md).
- The 10 tok/s target is not reached. EAGLE k=3 measured 5.38 tok/s against 5.82
  without a draft on the laptop; the cloud VM's gain did not transfer.
- A long pasted document takes over a minute before the first token appears. Keep
  the default 4K context unless the document needs more room.
- Memory: the model and F16 KV cache (about 0.5 GiB at 4K) fit in 16 GB, but leave
  room by closing other applications before measuring.
- Iris Xe Vulkan shares system RAM. In the recorded full-offload server tests it
  was slower: 3.55 tok/s without a draft, at best 4.58 with EAGLE k=1, and about
  11 to 12 tok/s prompt processing. CPU stays the default.
- A machine with faster memory (LPDDR5x on Intel Lunar Lake, or Apple M-series at
  100 GB/s or more) would likely reach 10 tok/s or more without speculative decoding.

## Cloud VM (conversion and script testing only)

The scripts are developed and tested on a cloud VM: Intel Xeon (Sapphire Rapids class,
AVX-512 with VNNI and AMX), 4 vCPU, 16 GB RAM (about 5 GB available), no GPU. It also
runs the HF to GGUF conversion. Its benchmark rows are labelled `cloud VM (NOT laptop)`
and say nothing about laptop speed.

## Threads

The i5-1135G7 has 4 physical cores. Generation usually peaks at 4 threads (one per
core); 8 threads (hyper-threading) rarely helps a bandwidth-bound workload. The
tuning phase measures both.
