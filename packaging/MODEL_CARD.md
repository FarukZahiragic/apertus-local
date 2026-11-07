---
base_model: swiss-ai/Apertus-v1.5-8B
license: apache-2.0
library_name: gguf
pipeline_tag: text-generation
tags:
- gguf
- apertus
- offline
---
# Apertus-v1.5-8B Q4_K_M for Apertus Local

Text-only conversion of [Swiss AI's Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B),
source revision `0be762a6`, using the Apertus-compatible llama.cpp fork at
`442b0444168a0f72788b40a16c8289bd1eb217f5`. It excludes the source model's vision
and audio components. Quantization changes model outputs; check task suitability.

File: `apertus-v1.5-8b-Q4_K_M.gguf`, 5,656,804,512 bytes.
SHA-256: `e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c`.

Conversion, validation and exact runtime patches:
[apertus-local](https://github.com/FarukZahiragic/apertus-local).
The original model's license, attribution and notices accompany distribution.
CPU support and integrated GPU acceleration do not require a dedicated GPU.
16 GB RAM is the recommended starting point; 8 GB operation is unvalidated.
There are no measured Apple Silicon performance results yet.
