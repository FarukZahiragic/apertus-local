---
base_model: swiss-ai/Apertus-v1.5-8B
license: apache-2.0
library_name: gguf
pipeline_tag: text-generation
tags:
- gguf
- apertus
- offline
- multimodal
- image-input
- audio-input
---
# Apertus-v1.5-8B Q4_K_M for Apertus Local

Language-weight conversion of [Swiss AI's Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B),
source revision `0be762a6`, using the Apertus-compatible llama.cpp fork at
`442b0444168a0f72788b40a16c8289bd1eb217f5`. Its full input vocabulary supports
the source's image/audio codes when paired with the separate F32 encoders below.
Quantization changes model outputs; check task suitability.

File: `apertus-v1.5-8b-Q4_K_M.gguf`, 5,656,804,512 bytes.
SHA-256: `e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c`.

Image/audio encoders: `apertus-v1.5-8b-mmproj-F32.gguf`, 914,229,792 bytes.
SHA-256: `765b3b22e91022c2e300480a882456433d416962e8cb28a6c300528fd5efa543`.
Both encoders are F32, as required by the source's precision-sensitive tokenizers.
Inputs are text, images and audio; outputs are text. The launcher defaults to
256 image codes and CPU encoders. See `docs/MULTIMODAL.md` in the source repository.
Download both GGUF files for image/audio chat. The language GGUF alone supports
text chat. Use the [native app download page](https://huggingface.co/spaces/faruk-zahiragic/apertus-local)
for Windows, Apple Silicon Mac, or Linux; it prepares the files automatically.
The native packages may download the encoders from the matching GitHub mirror;
the file bytes and SHA-256 are identical to this repository's copy.

Conversion, validation and exact runtime patches:
[apertus-local](https://github.com/FarukZahiragic/apertus-local).
The original model's license, attribution and notices accompany distribution.
CPU support and integrated GPU acceleration do not require a dedicated GPU.
16 GB RAM is the recommended starting point; 8 GB operation is unvalidated.
There are no measured Apple Silicon performance results yet.
