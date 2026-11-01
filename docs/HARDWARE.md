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

## What this means for speed

- Generation on CPU is limited by memory bandwidth: every generated token reads the
  whole model once. Apertus-v1.5-8B at Q4_K_M is about 4.9 GB, so expect **about 6 to
  8 tok/s** generation without speculative decoding.
- Reaching about 10 tok/s on this laptop needs speculative decoding (the DSpark head,
  phase 5 in [ROADMAP.md](ROADMAP.md)).
- Prompt processing is compute bound: expect roughly 30 to 60 tok/s. A long pasted
  document takes tens of seconds before the first token appears.
- Memory: about 5 GB of weights plus the KV cache fits comfortably in 16 GB.
- The Iris Xe GPU (llama.cpp Vulkan backend) may speed up prompt processing, but not
  generation much, because it shares the same RAM bandwidth.
- A machine with faster memory (LPDDR5x on Intel Lunar Lake, or Apple M-series at
  100 GB/s or more) would likely reach 10 tok/s or more without speculative decoding.

## Threads

The i5-1135G7 has 4 physical cores. Generation usually peaks at 4 threads (one per
core); 8 threads (hyper-threading) rarely helps a bandwidth-bound workload. The
tuning phase measures both.
