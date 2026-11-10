# One-command participant setup

Personal prototype by Faruk Zahiragić, not supported by EPFL.
[Report issues on GitHub](https://github.com/FarukZahiragic/apertus-local/issues);
support and updates are not guaranteed.

Open Terminal on macOS/Linux, or PowerShell on Windows, and paste one command.
It downloads the native runtime only when missing, prepares the model and opens
the same llama-server chat at http://127.0.0.1:8080/.

macOS and Linux:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.sh)"
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.ps1)))
```

The commands use a fixed setup version: [run.sh](https://github.com/FarukZahiragic/apertus-local/blob/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.sh) or
[run.ps1](https://github.com/FarukZahiragic/apertus-local/blob/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.ps1). The inference runtime and model have pinned SHA-256
checksums. No compiler, Git checkout, Python, Homebrew, administrator installation
or global PATH change is needed. The bootstrap uses the platform's download,
hashing and archive tools.

Setup saves a small launcher with your selected file paths for offline starts.
Chat runs as your normal user, without an OS sandbox, and listens only on
`127.0.0.1:8080` by default. It adds no background service or automatic startup.

## Downloads and local files

The model files total 6.1 GiB: a 5.3 GiB language model and 872 MiB F32 image/audio encoders. A computer also needs an inference runtime:
model weights cannot execute on their own. The current runtime packages are about
12 MB on Windows, 17 MB on Linux and 20 MB on Mac. The archive is removed after
verification and extraction; the installed runtime and model are reused.

The runtime is downloaded from the already published native releases:
`v0.2.0-preview.2` on all four platforms. The Mac bootstrap
extracts the server payload from the ZIP and discards the app wrapper. It runs
directly in the Terminal you opened; there is no Finder app launch or app-to-Terminal
automation request. It does not change Gatekeeper or remove quarantine attributes.
Device-management policies can still restrict running software.

Files are stored in these locations:

| Platform | Default folder | Later start, including offline |
| --- | --- | --- |
| macOS | `~/Library/Application Support/Apertus Local` | `bash "$HOME/Library/Application Support/Apertus Local/start.sh"` |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/apertus-local` | `bash "${XDG_DATA_HOME:-$HOME/.local/share}/apertus-local/start.sh"` |
| Windows | `%LOCALAPPDATA%\Apertus Local` | Open `Start.cmd` in that folder |

Keep the terminal window open while chatting. Ctrl+C stops the server. The saved
POSIX entry point also accepts `--stop`; Windows includes `Stop.cmd`.
The Windows entry point uses the same process-local execution-policy option as
the downloadable launcher; it does not change the machine's execution policy.

The small online bootstrap command needs connectivity each time it is fetched.
Use the printed local entry point for offline starts. If the runtime or model is
not prepared yet, inference cannot start offline.

## Remove Apertus Local

1. Stop chat with Ctrl+C or the Stop launcher.
2. Delete your platform's default folder listed above, or your chosen
   `APERTUS_INSTALL_DIR`. This removes its runtime, launchers, logs and downloaded
   models. To keep the downloads, move the `models` folder elsewhere first.
   Reused models or runtimes outside the install folder are left alone.
3. Clear browser site data for the local chat address (normally
   `http://127.0.0.1:8080`) to remove saved chats and settings.

If you downloaded an archive, also delete its extracted folder or
`Apertus Local.app`, and the downloaded ZIP/tar.gz. Mac and Windows archives use
the data folders above; Linux archives keep data inside the extracted folder.
If you chose separate model or state folders, remove those too if no longer needed.

## Prepare before the workshop

To download and verify without starting chat:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.sh)" -- --prepare-only
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FarukZahiragic/apertus-local/7be7121b402832d72bbe8ab04328214e8bd4f02a/run.ps1))) -PrepareOnly
```

Start using the printed local command, try a conversation, stop, disable networking
and start again. The browser UI and API are served locally. Text, image and audio input are enabled by default. Preparation downloads both
files, and the saved entry point retains this mode. Set `MULTIMODAL=0` before
setup for a lighter text-only installation; it skips the encoders.

## Reuse a model or runtime

An existing model in the default data folder is verified and reused. The bootstrap
also checks `models/` in the current directory and `~/apertus-1.5-local/models/` for
the expected file. It does not scan other folders.

A prepared Apertus checkout/package in the current directory or
`~/apertus-1.5-local` is also reused when its model metadata matches and a built
CPU runtime includes the participant UI. Image-enabled setup also requires
multimodal metadata. Older runtimes are upgraded while existing weights are
reused; a current participant runtime avoids that download as well.

These overrides avoid copies:

| Setting | Meaning |
| --- | --- |
| `MODELS_DIR` | Existing folder containing the exact model; also used for future downloads |
| `MODEL` | Exact existing GGUF path; the default Apertus checksum is enforced |
| `MODEL_SHA256` | Explicit checksum when deliberately testing another model |
| `MULTIMODAL` | `1` by default; set `0` for text-only setup |
| `MMPROJ` | Existing encoder GGUF; verified during preparation and retained in the saved entry point |
| `MMPROJ_SHA256` | Explicit encoder checksum for a developer override |
| `APERTUS_RUNTIME_DIR` | Existing Apertus package or prepared checkout; skip runtime download |
| `APERTUS_INSTALL_DIR` | Alternate data folder for the bootstrap |

For example, with an already downloaded model on Mac/Linux:

```bash
MODEL="$HOME/Downloads/apertus-v1.5-8b-Q4_K_M.gguf" bash run.sh
```

In PowerShell, set `$env:MODEL` to that file before running the one-command setup.
The saved local entry point retains the chosen model location.
An arbitrary system `llama-server` or LM Studio runtime is not auto-selected:
Apertus 1.5 needs the model-specific support in our pinned runtime.

`BACKEND`, `THREADS`, `CTX`, `PORT`, `GPU_LAYERS` and the existing serving overrides
still apply. The runtime's CPU baseline remains the default; explicit Metal on a
compatible Mac is available through `BACKEND=metal`. See [MACOS.md](MACOS.md).

## Supported systems and verification

- Apple Silicon macOS 13.3 or later, using the built-in Bash, curl, ditto and shasum.
- x86_64 Linux with Bash, curl, tar, SHA-256 tooling and the native package's
  glibc/libstdc++ requirements. A minimal Linux installation may lack curl.
- 64-bit Windows 10 or later on Intel/AMD or ARM/Snapdragon, with Windows
  PowerShell 5.1 or newer and .NET archive support.
- 16 GB RAM recommended. Intel Macs, Linux ARM64, musl distributions and 8 GB
  systems remain outside the validated compatibility contract.

The bootstrap adds no inference engine and changes no server defaults. Tests cover
inline invocation, package verification, interrupted setup, file reuse and generated
offline entry points. Cross-platform CI exercises the published runtime and actual
model through first launch, streaming/document Q&A, stop and cached restart. A
hosted Mac/Windows runner is a VM check, not a physical attendee-device rehearsal
or speed measurement.

Use [OFFLINE.md](OFFLINE.md) for the network-disabled participant rehearsal.
