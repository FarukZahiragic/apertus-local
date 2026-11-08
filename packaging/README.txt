Apertus Local — offline text chat

Recommended: 16 GB RAM, space for a 5.3 GiB model plus runtime and update overhead.

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

After preparation, disconnect networking, relaunch and chat at
http://127.0.0.1:8080/. Chat and pasted text stay on the local machine.

CPU is available on every packaged platform. Metal is experimental on Apple
Silicon and remains opt-in until Apertus checks pass on that hardware.
Developer overrides: BACKEND=cpu|metal, THREADS, CTX, PORT, MODEL.

Unsigned Mac previews have an ad-hoc code seal, without Apple Developer ID
verification or notarization. After trying to open the app, use System Settings >
Privacy & Security > Open Anyway if offered, then confirm. Approve only the app
you intentionally downloaded from this project. Read MACOS_FIRST_START.txt beside
the app. No Apple Developer membership is needed. Keep system-wide security checks
enabled. An administrator may need to approve installation on a managed Mac.
Windows packages are not yet provided or validated.

Source, hardware measurements and troubleshooting:
https://github.com/FarukZahiragic/apertus-local
