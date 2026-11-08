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
| Linux, actual Bash 3.2 | Download corruption/resumption/completed-part recovery; Darwin detection; runtime overrides/auto gating; launcher ownership, readiness, startup failure, Metal-to-CPU retry and archive contents | 16 tests pass |
| Linux, actual Bash 3.2 | Standalone Mac setup: clone/start from a single file, paths with spaces, preserve existing edits/folders, reject unsupported hardware and stop safely when Apple tools need interactive installation | 5 fixture tests pass; fresh physical Mac setup remains pending |
| Node | Download availability, required checksums and safe URLs | 3 tests pass |
| GitHub-hosted Apple M1 VM, 7 GB RAM, macOS 15 | Portable CPU/Metal builds, relocated app packaging, real CPU and partial Metal inference (`GPU_LAYERS=8 LOAD_MODE=none`) | pass in [native CI](https://github.com/FarukZahiragic/apertus-local/actions/runs/42386944980); hosted VM is not a participant laptop |
| GitHub-hosted Linux VM, only loopback networking | Fresh Apertus startup, embedded assets, streamed usage, document Q&A and rendered chat input/model in actual Chrome | pass in the same run |
| Reference Linux laptop, actual Chrome | Render embedded chat input and model name through the DevTools pipe | pass; networking enabled during this local check |

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

## Metal correctness investigation

The hosted Mac CPU run passes real Apertus chat, streamed usage and document Q&A.
All five full-offload diagnostic profiles show explicit Metal out-of-memory
errors before the server advertises readiness. Later requests fail with a compute
error, which the earlier streaming validator incorrectly described as an empty
answer. The validator now reports the actual server error, and the launcher
checks a real decode before opening chat.

Eight-layer offload with `LOAD_MODE=none` is the CI profile for the 7 GB VM.
Packed loading avoids mapping the entire GGUF into Metal through sparse early
tensors. That profile passed real document Q&A and streaming checks. Full offload on physical 16 GB+ Macs remains unvalidated; Metal stays
experimental and auto-selection remains gated. The manual diagnostic workflow
accepts a previous Mac artifact run ID and retains raw responses/server logs.

The isolated Linux browser check originally used virtual time and dumped the DOM
before asynchronous browser storage and UI startup completed. The check now polls
the real rendered chat input and model name through Chrome's DevTools pipe, with
a bounded wall-clock timeout. Both the actual API inference and the corrected
browser check passed with only loopback networking in the linked native CI run.
