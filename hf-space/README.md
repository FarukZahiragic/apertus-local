---
title: Apertus Local
emoji: 🏔️
colorFrom: blue
colorTo: blue
sdk: static
app_file: index.html
pinned: false
short_description: Download Apertus 8B for private, offline laptop chat
---

# Apertus Local

A download page for native Apertus-v1.5-8B Q4_K_M chat through llama-server.
Text, images and audio are processed on the participant's laptop; this Space does not process prompts or attachments. Answers are text. Model files total about 6.1 GiB, including separate F32 encoders.

Source and measured results: https://github.com/FarukZahiragic/apertus-local

Release availability is controlled by `config.json`. Enable a platform only after
its archive, checksum, model URL and native checks are ready. The Mac unsigned
preview requires no Apple Developer membership and includes per-app first-open
instructions in `macos-first-start.html`; the physical Finder-opening rehearsal
is labelled pending. Developer ID signing/notarization are optional.
The command selector has two choices: macOS / Linux and Windows. The setup
scripts detect the native OS and processor. Hardware-specific archive links
remain in the optional download section, with their own checksum, system
requirements and first-start guides. The current official Apertus wordmark and
blue palette are documented in `assets/README.md` and served with the page.
Keep each entry unavailable until its own native archive, checksum and inference
checks pass. Minimum OS/library capabilities are release metadata, separate from
the runner version used for testing. `scripts/publish_hf.sh` uploads this directory
and both verified GGUF files.
