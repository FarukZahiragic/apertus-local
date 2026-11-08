# Workshop packages

The shortest participant path is now a single Terminal/PowerShell command from
[ONE_COMMAND.md](ONE_COMMAND.md). It obtains the native runtime automatically,
downloads only missing weights and opens chat. On Mac it runs the server directly
from Terminal without the app wrapper. It retains a local entry point for offline
starts and requires no compiler, Python, Homebrew or repository checkout.

The downloadable alternative is: download a native package, open its launcher, download the
language GGUF and F32 encoders once, then chat locally. Both files total about
6.1 GiB. Preparation needs internet; inference does not. The
native runtime serves its embedded UI at `http://127.0.0.1:8080/`.

## Run from a checkout

After building and placing the model in `models/`:

```bash
./Start.sh                          # Linux; ./Start.command on macOS
./Stop.sh                           # Linux; ./Stop.command on macOS
scripts/launch.sh --no-browser       # keep the URL in the terminal
scripts/launch.sh --check            # hardware/runtime check without downloading
./Start-Text.sh                     # optional lighter text-only mode
```

The launcher verifies the pinned model before use, resumes first-run downloads,
waits for an owned server's health check, and opens the browser. Ctrl+C stops its
child server. `--stop` requests shutdown through the launcher's state directory;
it never kills an arbitrary PID from a stale file. One launcher owns each port.
Logs are retained in `.apertus-state/`. `APERTUS_STATE_DIR` overrides that location.
If a machine loses power, inspect and remove the stale `port-8080` lock directory
before restarting. A `MODEL` override is for developer checks; set `MODEL_SHA256`
to verify that file too. Default participant downloads always require a checksum.

`BACKEND`, `THREADS`, `CTX`, `PORT` and `BUILD_DIR` override detected defaults.
Auto mode remains CPU until Metal is explicitly validated on the Mac. Once
`APERTUS_METAL_VALIDATED=1` is set, the launcher can try Metal and report a CPU retry
if startup fails. Explicit Metal errors remain visible without an automatic retry.
No draft model or thinking is enabled by default.

## Build a native package

On Linux x86_64:

```bash
scripts/setup_llamacpp.sh --cpu --portable
APERTUS_MODEL_REPO=YOUR_ACCOUNT/YOUR_GGUF_REPO \
  APERTUS_MODEL_REVISION=YOUR_UPLOADED_COMMIT \
  scripts/package_release.sh --version v0.1.0
```

On a native Apple Silicon Mac, build both runtime paths:

```bash
scripts/setup_llamacpp.sh --cpu --portable
scripts/setup_llamacpp.sh --metal --portable
APERTUS_MODEL_REPO=YOUR_ACCOUNT/YOUR_GGUF_REPO \
  APERTUS_MODEL_REVISION=YOUR_UPLOADED_COMMIT \
  scripts/package_release.sh --version v0.1.0
```

Outputs are ignored under `dist/`: a Linux `.tar.gz` or a macOS `.zip` containing
`Apertus Local.app`, plus an archive checksum. Each package includes portable CPU
backend libraries, runtime binaries, licenses, a model card and a provenance/hash
manifest. Weights are downloaded separately or copied from USB. The package command
checks that the binaries can run after relocation. Build on the oldest OS baseline
you intend to support and test on that OS; portable CPU dispatch does not make
system libraries compatible with every Linux distribution or macOS release.

The Mac app opens Terminal and launches local chat. Its mutable model and log
folders live under `~/Library/Application Support/Apertus Local/`, outside the
signed bundle. macOS may ask to allow the app to control Terminal. Keep that window
open and use Ctrl+C to stop. For an offline workshop, populate its `models/`
subdirectory with the verified GGUF before the workshop starts.

## Mac previews and optional signing

The source setup and offline rehearsal have passed on a physical Apple Silicon
Mac (reported by the owner; hardware details and formal benchmarks can follow).
Those benchmarks do not block packaging. [MACOS_RELEASE.md](MACOS_RELEASE.md)
provides the hosted release workflow. Its default is an unsigned preview requiring
no Apple Developer membership or Apple credentials. The workflow creates a draft
after code-seal and delivered-runtime inference checks pass. The ZIP includes
`MACOS_FIRST_START.txt`; the download page links to a first-open guide. Complete
the downloaded-app opening rehearsal before treating the preview as workshop-ready.

Developer ID signing is optional. On a Mac with an installed Developer
ID Application identity and an existing `notarytool` keychain profile:

```bash
MACOS_SIGN_IDENTITY='Developer ID Application: ...' \
  MACOS_NOTARY_PROFILE=YOUR_KEYCHAIN_PROFILE \
  APERTUS_MODEL_REPO=YOUR_ACCOUNT/YOUR_GGUF_REPO \
  scripts/package_release.sh --version v0.1.0 --sign
```

The script signs nested Mach-O files, updates the package hash manifest, seals the
app with hardened runtime, submits to Apple, staples the ticket and checks
Gatekeeper. Credentials are never written into the repository or package. A real
signed download/open test is still required; signing cannot be validated on Linux.
Development apps get an ad-hoc seal after resources are installed; that seal is
checked but does not establish an identified publisher or notarization.
[Apple's distribution guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Release readiness

Publishing requires a versioned GGUF location and a tested runtime archive for each
advertised platform. An unsigned Mac preview may be available with its first-open
instructions, code-seal/inference checks and pending physical-download rehearsal
clearly labelled. Windows uses native Intel/AMD and ARM64 archives, each with its
own build and inference checks; see [WINDOWS.md](WINDOWS.md). Intel Macs, Linux
ARM64 and musl-only Linux still need separate packages. Compatibility minimums
come from [the capability policy](COMPATIBILITY.md), not a distro-name whitelist.

Before promoting a version, follow [OFFLINE.md](OFFLINE.md), [MACOS.md](MACOS.md) and
the roadmap hardware checks. The automated suite exercises download corruption,
resumption, backend selection, launcher readiness and shutdown with fixture servers.
These fixtures do not prove Apertus quality, macOS performance, or offline hardware
operation. Record actual benchmark runs in `benchmarks/results.md`.

## Hugging Face publication

The [model repository](https://huggingface.co/faruk-zahiragic/Apertus-v1.5-8B-GGUF)
and [download Space](https://huggingface.co/spaces/faruk-zahiragic/apertus-local)
are in the project owner's namespace. The verified GGUF is public and the model
URL is pinned in `config/model.env`. Platform download buttons stay disabled until
validated release URLs and checksum URLs are present in `hf-space/config.json`.
The page uses static HTML/CSS/JS with no third-party fonts, scripts or telemetry.

Maintainers can prepare the upload tools once (not needed by participants):

```bash
python3 -m venv .venv-release
.venv-release/bin/pip install 'huggingface_hub>=0.34,<3'
.venv-release/bin/hf auth login
scripts/publish_hf.sh                 # publish both pinned GGUF files and the static Space
scripts/publish_hf.sh --model-only    # prepare the model repository before updating the page
scripts/publish_hf.sh --space-only    # verify both remote hashes/sizes, then update only the page
```

`HF_TOKEN` is read from the environment or supplied to the process from the normal
HF credential cache outside this repo. It is never printed, saved in source or
bundled. By default the script creates public repositories in the authenticated
personal namespace; `--private` creates private repositories instead. Existing
repository visibility is preserved. `MODEL_REPO` and `SPACE_REPO` override names.
The model upload includes the full-vocabulary language weights, F32 encoders,
provenance, both SHA256SUMS entries and the original Apache license. The Space
publisher verifies both remote hashes and byte counts before advertising a release.
Publication metadata is written under ignored `dist/hf-publication.json`.

To enable a native platform, first validate its archive, publish that archive and
its checksum under a fixed release version, then set `available`, `url`,
`checksum_url`, `status` and the top-level `version` in `hf-space/config.json`.
The `model` and `encoders` entries pin the two model files. The page keeps downloads
disabled if the encoder URL or checksum is missing. The publisher stages immutable
Hugging Face URLs for both files at the verified model-repository revision.
Publish with `--space-only`. For unsigned Mac previews, include the per-app approval
guide and accurately label the pending Finder-opening rehearsal. Signing is not a
prerequisite. GitHub CI artifacts are development builds until promoted to a
versioned release with its checksum and preview notes.

## Automated and recorded checks

`python3 -m unittest discover -s tests -v` and
`node --test tests/test_*.cjs` exercise the portable control paths and browser cleanup.
Windows adds `tests/test_windows.ps1` under Windows PowerShell 5.1, native PE
dependency checks and actual-model smoke tests from the extracted ZIP. The same
`scripts/validate_local.py` checks the API on all platforms; Python is a maintainer
validation dependency, not a participant requirement.
GitHub Actions builds native Linux and Apple Silicon packages, downloads the exact
GGUF and runs real-model UI/API checks. The Mac VM may expose no usable Metal
GPU; that case is reported as unavailable rather than counted as a GPU test.

`scripts/validate_local.sh --repeat 50 --report dist/local-check.json` checks a
running localhost server without installing the OpenAI SDK. It is a functional
check, not a benchmark or a network-isolation tool. Current results and preview
limitations are listed in [VALIDATION.md](VALIDATION.md). The source workspace can
be renamed; rerunning setup refreshes CMake's generated paths when needed.

The launcher also performs one real token decode before opening the UI. Some
backends can return a healthy HTTP response after a warmup compute failure; the
inference check detects that case and lets auto mode retry CPU. Explicit GPU mode
reports the error. `GPU_LAYERS` and `LOAD_MODE` allow a tested memory profile to be
selected; see [MACOS.md](MACOS.md). Streamed validation preserves server error
messages rather than reporting an empty answer for a compute error.
