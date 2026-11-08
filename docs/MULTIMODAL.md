# Image and audio candidate

This candidate adds image/audio input and text output on Windows x64/ARM64,
Apple Silicon macOS and Linux x86_64. It uses the existing pinned Apertus language
model, its full input vocabulary, and the matching source's separate F32 encoders.
No GPU is required. Recommended RAM remains 16 GB; 8 GB operation is unvalidated.
**Do not merge into main until the project owner has tested it locally.**
The public Hugging Face Space and existing production downloads are unchanged.

## Try the packaged candidate

Download your platform archive from the
[candidate release](https://github.com/FarukZahiragic/apertus-local/releases/tag/v0.2.0-mm-candidate.1).
Extract it to a new folder; keep your previous working copy for comparison.
Use these archives for the candidate; the previously shared standalone `setup.sh`
fetches main and prepares the current text-only release.

- Windows: extract the whole matching ZIP and open `Start.cmd`.
- Mac: extract the ZIP and open `Apertus Local.app`. For this unsigned candidate,
  follow `MACOS_FIRST_START.txt` if macOS asks for first-open approval.
- Linux: extract the tar.gz, open a terminal there and run `./Start.sh`.

First start downloads and verifies the 5.3 GiB language model and 872 MiB encoders.
An existing verified model in the same cache is reused. Windows and packaged Mac
apps reuse their usual user model folders; on Linux copy or link the previous
`models/apertus-v1.5-8b-Q4_K_M.gguf` into the new folder's `models/` to avoid
downloading it again. Interrupted downloads resume. Subsequent runs work offline.
To prepare via USB, copy both exact GGUF files into the model folder.

Use the chat attachment button to upload one clear photo, then ask about it.
Image processing takes extra time before generation starts. Images are resized
to a small laptop budget by default; tiny text and fine details may be missed.
Try a short speech clip, initially under 15 seconds, and ask for a transcription.
Use short messages and start a new chat if the 4096-token context fills.
Audio counts roughly 40 input codes per second, plus prompt and framing tokens.
This candidate does not promise video support or generate images/audio.

## Your local acceptance test

1. Start the candidate and attach a photo with recognizable objects. Confirm a
   sensible description, then ask a follow-up about the same photo.
2. Ask a regular text question and check streaming and Stop still work.
3. Restart offline. Confirm it reuses both model files and accepts another image.
4. Optionally test a short speech clip and compare the transcription with it.
5. Report the OS, RAM, answers, and any error. Keep launcher logs if it fails.

Automatic checks must also pass on the delivered Windows, Mac and Linux runtimes.
Hosted-runner checks establish compatibility; they are not laptop benchmarks.

## Text-only mode and optional detail

Windows: open `Start-Text.cmd`. Linux: run `./Start-Text.sh`.
Mac, from Terminal (change the app path if you put it elsewhere):

```bash
MULTIMODAL=0 "/Applications/Apertus Local.app/Contents/Resources/apertus-local/Start.command"
```

Text-only mode skips the encoder download/load and preserves the old text-only
runtime options, including context shifting. Ordinary text prompts in multimodal
mode do not run image/audio encoding, but the encoders stay in memory. The runtime
disables context shifting when multimodal is loaded; common-prefix prompt caching
still works. Use a new chat when the context fills.

`IMAGE_MAX_TOKENS=512` or `1024` allows more image detail, with more CPU work,
memory and prompt-processing time. The default is 256. Encoders use CPU on all
platforms; the existing language-model backend selection is retained.
`MULTIMODAL=0` disables image/audio. `MMPROJ` and optional `MMPROJ_SHA256` override
the encoder path for developer testing; `MMPROJ_URL` overrides only its download.
Language-model URL/checksum overrides never apply to the encoder download.

## Source and developer verification

`config/multimodal.env` pins the encoder bytes, SHA-256, source revision and
candidate asset URL. The language model in `config/model.env` is unchanged.
`patches/0005-apertus-image-token-budget.patch` fixes the pinned runtime's missing
Apertus image-budget handling. Normalization, resizing algorithm and tensor math
are unchanged. Conversion preserves F32 and omits the unused audio decoder.

To reproduce, install the pinned llama.cpp conversion requirements and
`huggingface_hub` in a developer virtual environment, authenticate for access to
the source model, then run:

```bash
python scripts/convert_multimodal.py
scripts/get_model.sh --apertus
scripts/get_model.sh --multimodal
./Start.sh --no-browser
# In a second terminal, against that running candidate:
python3 scripts/validate_multimodal.py
```

The converter downloads only the source's two encoder shards, approximately
1.1 GiB, rather than the full language checkpoint. It preserves the original
index for provenance and builds a reduced local index for those shards.
Real checks distinguish large red and blue test images, verify image resizing,
exercise visual follow-up context, and transcribe a known speech fixture.
