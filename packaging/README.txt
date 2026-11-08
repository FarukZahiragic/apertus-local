Apertus Local — offline text, image and audio chat

Recommended: 16 GB RAM, space for a 5.3 GiB model and 872 MiB encoders, plus runtime
and update overhead. No GPU is required.

macOS: open Apertus Local.app. It opens a Terminal window and then local chat.
Linux: extract the archive, open a terminal in the extracted folder, run ./Start.sh.
Keep the terminal open. Press Ctrl+C to stop the model and release its memory.
Linux also includes ./Stop.sh. Source checkouts include Stop.command on macOS.

The first start downloads and verifies the GGUF if a model URL was configured by
its publisher. You can instead copy the exact model from USB before starting.
macOS app model folder: ~/Library/Application Support/Apertus Local/models/
Linux/source model folder: models/ next to the launcher.
File: apertus-v1.5-8b-Q4_K_M.gguf
SHA256: e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c
Encoders: apertus-v1.5-8b-mmproj-F32.gguf (downloaded and verified automatically).
To prepare offline from USB, copy BOTH GGUF files into the model folder.

In chat, use the attachment button to add an image or a short audio clip. Begin
with one clear image or a clip shorter than 15 seconds. The app produces text.
Image detail is limited for laptop memory and speed; tiny text in images may be
hard to read. Image/audio processing adds time before the answer begins.
For text-only use without loading the encoders, open Start-Text.sh (Linux),
Start-Text.cmd (Windows), or run the Mac app with MULTIMODAL=0 as described at
https://github.com/FarukZahiragic/apertus-local/blob/main/docs/MULTIMODAL.md

After preparation, disconnect networking, relaunch and chat at
http://127.0.0.1:8080/. Chat, attachments and pasted text stay on the local machine.

CPU is available on every packaged platform. Metal is experimental on Apple
Silicon and remains opt-in until Apertus checks pass on that hardware.
Developer overrides: BACKEND=cpu|metal, THREADS, CTX, PORT, MODEL.

Unsigned Mac previews have an ad-hoc code seal, without Apple Developer ID
verification or notarization. After trying to open the app, use System Settings >
Privacy & Security > Open Anyway if offered, then confirm. Approve only the app
you intentionally downloaded from this project. Read MACOS_FIRST_START.txt beside
the app. No Apple Developer membership is needed. Keep system-wide security checks
enabled. An administrator may need to approve installation on a managed Mac.
Windows users should download the matching Windows ZIP and open Start.cmd.

Source, hardware measurements and troubleshooting:
https://github.com/FarukZahiragic/apertus-local
