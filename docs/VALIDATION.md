# Native deployment validation

Implementation and hardware acceptance are tracked separately. PRs #16–#21 form a
dependent stack; `main` is not changed until they are reviewed and merged.

## Recorded on 7 November 2026

| Environment | Check | Result |
| --- | --- | --- |
| Reference laptop, i5-1135G7, 16 GB DDR4, Ubuntu 24.04 | Build portable CPU dispatch runtime at the pinned fork and patches | pass |
| Same laptop | Extract native archive into a separate directory and run without build-directory loader paths | pass |
| Same laptop, Apertus Q4_K_M, CPU, 4 threads, 4K context | Start through extracted launcher; health, embedded UI assets, streamed final usage, document Q&A | pass; document answer `Sarajevo` |
| Same configuration | 50 streamed requests, maximum 16 generated tokens each | 50/50 pass |
| Linux, actual Bash 3.2 | Download corruption/resumption/completed-part recovery; Darwin detection; runtime overrides/auto gating; launcher ownership, readiness, startup failure, Metal-to-CPU retry and archive contents | 13 tests pass |
| Node | Download availability, required checksums and safe URLs | 3 tests pass |
| GitHub-hosted Apple M1 VM, 7 GB RAM, macOS 15 | Portable CPU build, Metal build and relocated app packaging | pass in initial CI; hosted VM is not a participant laptop |

The functional report is generated under ignored `dist/validation-reference-laptop.json`.
The short Qwen throughput regression run is recorded in `benchmarks/results.md`.
Functional request checks are not performance benchmarks. No Apple Silicon speed
numbers have been measured or advertised.

The first native CI pass exposed two validation issues: HTTPServer fixture startup
could wait on reverse DNS on macOS, and the embedded UI requires gzip support in
the HTTP validator. The fixtures now avoid reverse DNS, the validator decodes gzip,
and local checks pass. A later Mac run exposed an absent app bundle identifier;
packaging now sets it explicitly and verifies a refreshed development code seal.
The fixture suite compiles a tiny real Mac app and checks its metadata before the
longer native builds start. Runtime results are tracked in
[native CI](https://github.com/FarukZahiragic/apertus-local/actions/workflows/native.yml).

## Preview scope

`v0.1.0-preview.1` targets x86_64 Ubuntu 24.04. It contains the native runtime and
launcher; the pinned public 5.3 GiB GGUF downloads separately. This is a preview,
with a real local chat and reliability check. It is not a completed workshop
hardware certification. Other Linux distributions require their own compatibility
check; CPU dispatch does not remove libc requirements.

## Still pending

- Restart with networking disabled and verify the actual browser UI, API and
  document workflow on each participant platform. This environment blocks network
  namespaces; its network connection was not disabled during the automated check.
- Test the friend's physical Mac: chip/RAM/OS label, CPU versus Metal, coherent
  answers, first-token latency, fixed document, memory pressure and sustained load.
  Use `scripts/bench_mac.sh` and record every benchmark row. Keep auto Metal gated
  until this succeeds.
- Sign/notarize the Mac app with a Developer ID, then test a downloaded app on a
  clean Mac, including the Terminal automation prompt and offline relaunch.
- Implement and validate native Windows packaging before offering Windows downloads.
- Rehearse the workshop installation with a person who has not developed the repo.

Follow [MACOS.md](MACOS.md), [OFFLINE.md](OFFLINE.md) and
[DISTRIBUTION.md](DISTRIBUTION.md) for the commands and expected behavior.
