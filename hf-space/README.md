---
title: Apertus Local
emoji: 🏔️
colorFrom: red
colorTo: gray
sdk: static
app_file: index.html
pinned: false
short_description: Download Apertus 8B for private, offline laptop chat
---

# Apertus Local

A download page for native Apertus-v1.5-8B Q4_K_M chat through llama-server.
The model runs on the participant's laptop; this Space does not process prompts.

Source and measured results: https://github.com/FarukZahiragic/apertus-local

Release availability is controlled by `config.json`. Enable a platform only after
its archive, checksum, model URL and native checks are ready. The Mac unsigned
preview requires no Apple Developer membership and includes per-app first-open
instructions in `macos-first-start.html`; the physical Finder-opening rehearsal
is labelled pending. Developer ID signing/notarization are optional.
Windows remains unavailable until implemented
and tested. `scripts/publish_hf.sh` uploads this directory and the exact GGUF.
