# Native Windows deployment

Use 64-bit Windows 10 or later with Windows PowerShell 5.1 or newer. Windows
PowerShell is included with Windows; PowerShell 7 also works. The launcher checks
capabilities and processor architecture rather than matching one Windows edition,
release number or manufacturer. Intel/AMD x64 and native ARM64/Snapdragon have
separate archives. CPU support requires no GPU, WSL, Python or compiler installation.
Plan for 16 GB RAM and space for the 5.3 GiB model plus the small runtime.

## Participants

Use the [one-command PowerShell setup](ONE_COMMAND.md) to download the matching
native runtime, reuse or prepare the model and open local chat automatically.
It leaves `Start.cmd` and `Stop.cmd` in `%LOCALAPPDATA%\Apertus Local` for later
starts, including offline. It needs no Python, Git or compiler installation.

Download the matching Windows ZIP from the HF Space, extract the whole archive,
and double-click `Start.cmd`. Keep its window open. The first start resumes any
partial model download, verifies the pinned SHA-256, starts llama-server on
`127.0.0.1:8080`, checks one actual decode, and opens local chat. Subsequent starts
reuse the verified model without contacting HF. Stop with Control+C or `Stop.cmd`.

Checksum verification uses the built-in .NET streaming SHA-256 implementation,
so the launcher does not need to discover the `Get-FileHash` PowerShell command.
Files that cannot be read or fail verification stop startup with an error.

To update from preview.3, stop the current instance, extract the preview.4 ZIP
into a new folder, and open its `Start.cmd`. The model in the user data folder is
reused after verification; it does not need to be downloaded again. Keep any
local script changes in the old folder for comparison.

The package is unsigned. Its PowerShell invocation applies an execution-policy
option only to that process, without changing saved machine/user policy. Managed
organization policy still takes precedence; ask the administrator if installation
is blocked. No signing membership or paid account is needed.

The user model folder is `%LOCALAPPDATA%\Apertus Local\models\`. Put the exact
`apertus-v1.5-8b-Q4_K_M.gguf` there to prepare from USB. Use a filesystem that can
hold files larger than 4 GB, such as exFAT. Logs live in
`%LOCALAPPDATA%\Apertus Local\state\`. The launcher never kills an arbitrary process
from a PID file. Stop requests go to the owning launcher's control file; its
cleanup closes only the child it created.

Developer checks from PowerShell:

```powershell
scripts/windows/launch.ps1 -Check
scripts/windows/launch.ps1 -GetModel
scripts/windows/launch.ps1 -NoBrowser
scripts/windows/launch.ps1 -Stop
```

`PORT`, `THREADS`, `CTX`, `MODEL`, `MODEL_SHA256`, `MODELS_DIR`,
`APERTUS_STATE_DIR` and `BUILD_DIR` override defaults. Thinking is off, context is
4096, and one slot is used. CPU cores are detected with CIM, with an OS processor
count fallback if inventory is unavailable. No particular CPU model is hardcoded.

## Maintainer builds

Use a native Windows build host with Git, CMake, Python for validation, and Visual
Studio 2022 C++ tools. ARM64 builds use LLVM Clang and Ninja plus the ARM64 tools.
Participants do not need these build tools.

```powershell
scripts/setup_windows.ps1 -Architecture x64
scripts/package_windows.ps1 -Version v0.1.0-preview.4 -Architecture x64
```

On native ARM64 Windows, replace `x64` with `arm64`. The build uses the same
llama.cpp commit and `patches/` as Linux/macOS. It enables CPU runtime dispatch
and disables host instruction tuning and GPU/OpenMP dependencies. Patch 0004
registers ARMv8.0, dot-product, FP16 and I8MM variants using the pin's existing
Windows feature detector; unsupported variants receive a zero runtime score.

The engine exchanges CRT file handles across DLLs. Its DLLs therefore use a shared
MSVC runtime, with the required release redistributable DLLs shipped beside the
executables. Participants need no separate Visual C++ installer or administrator
access. The package includes a Microsoft redistribution notice. Native PE checks
verify architecture and that engine/compiler runtime DLL dependencies are present.
See [Microsoft's CRT boundary explanation](https://learn.microsoft.com/cpp/c-runtime-library/potential-errors-passing-crt-objects-across-dll-boundaries)
and [application-local deployment](https://learn.microsoft.com/cpp/windows/choosing-a-deployment-method).

## Validation and release

The Windows workflow uses both an x64 Windows Server runner and a native Windows
11 ARM64 runner. The product's minimum is Windows 10 plus PowerShell 5.1; a runner
version is a test environment rather than an application whitelist. Physical
Windows laptop measurements and fresh-user installation remain distinct checks.

`tests/test_windows.ps1` runs native Windows process fixtures covering range
resumption, corruption, offline cache recovery, paths with spaces, JSON argument
quoting, ownership, stop, compute failure and occupied-port preservation. No model
quality claim is inferred from fixture results.

`tests/test_windows_hash.ps1` independently checks known SHA-256 vectors and
literal/relative paths with `Get-FileHash` deliberately unavailable. Missing or
incorrect files are rejected, and file handles are released after hashing.

The actual model check extracts the delivered ZIP to a separate path, blocks
outbound networking for that server process with Windows Firewall, and validates
health, embedded assets, streaming usage, a fixed document and repeated requests.
The firewall rule is removed afterward. This checks server-process isolation;
it does not claim that the entire runner or browser has no network access.

Publish only verified archives and checksums under a new immutable version, update
the platform entries in `hf-space/config.json`, and publish the Space. The same
GGUF revision/hash is used on every platform. Signing and hardware performance
tuning can follow separately.
