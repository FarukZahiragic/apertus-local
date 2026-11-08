# Laptop compatibility policy

Support is defined by architecture and minimum capabilities, rather than an exact
OS release or laptop brand. Newer compatible OS versions remain eligible. Build
hosts and test runners are recorded separately from the intended minimum.

| Family | Native architectures currently packaged | Compatibility contract |
| --- | --- | --- |
| Windows | Intel/AMD x64; ARM64/Snapdragon | 64-bit Windows 10 or later; Windows PowerShell 5.1 or PowerShell 7; C++ runtime DLLs included |
| macOS | Apple Silicon ARM64 | New portable builds target macOS 13.3 or later; the native app wrapper and every bundled Mach-O are checked against that target |
| Linux | Intel/AMD x86_64 | glibc-based distributions with the GLIBC/GLIBCXX/CXXABI symbol versions recorded in the archive's `compatibility.json` |

Every family uses the same pinned GGUF and CPU baseline. Hardware features and
thread counts are detected; native x86/ARM backend variants are chosen only when
the CPU/OS reports their capabilities. No particular Intel, AMD, Snapdragon or
Apple chip is required beyond the archive's architecture and memory needs.

16 GB RAM is recommended. The 5.3 GiB model, context, OS and other applications all
consume memory. An 8 GB machine is not certified by the hosted runner checks.
Unsupported architectures, 32-bit Windows and musl-only Linux distributions need
separate native builds/validation; a broad policy is not a claim that every
historical OS or ABI can run these binaries.

## macOS baseline

The pin enables Accelerate's new ILP64 BLAS/LAPACK interfaces, introduced in
[macOS 13.3](https://developer.apple.com/documentation/macos-release-notes/macos-13_3-release-notes).
Portable builds explicitly set that deployment target and treat unguarded use of
newer APIs as a compile error. The package scanner checks every Mach-O, including
the app's executable, and rejects a higher minimum than the intended target.

The older preview.2 used `osacompile`, which copied an ARM64 applet requiring
macOS 15.8 from its build host. Lowering only llama.cpp's target would not fix that
wrapper. New packages compile `packaging/Launch.m` against the intended baseline.
The wrapper still opens Terminal and runs the shared launcher. Older immutable
preview archives keep their original requirements; use the updated release for
broader compatibility.

## Linux baseline

Build on the oldest CI baseline and inspect actual imported library symbol
versions with `scripts/runtime_requirements.py`. The archive includes that report
and its hash in `release.json`. This avoids labelling a binary as compatible with
all distributions merely because its CPU instructions are portable.

Native CI builds on Ubuntu 22.04 and checks the delivered archive there. Additional
consumer checks use the same archive on Ubuntu 24.04 and Debian 12, without a
compiler and with container networking disabled. These tests verify local model
inference and UI/API assets. The producer's browser check also renders the actual
chat UI with external networking blocked. Completed results are recorded in
[VALIDATION.md](VALIDATION.md).

## Releases and overrides

Keep minimum requirements next to each platform's download, with first-start
instructions. Do not use an exact-version equality gate in launchers. Environment
overrides remain available for thread count, context, port and memory profiles.
Windows GPU acceleration and automatic Mac Metal defaults need their own evidence;
CPU support remains available regardless of those experiments.
