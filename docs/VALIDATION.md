# Native deployment validation

Implementation and hardware acceptance are tracked separately. Native deployment
PRs #16–#24 are merged into `main`. Windows and broader compatibility work is in
the follow-up PR; do not infer physical laptop validation from a build target.

## Recorded on 7–8 November 2026

| Environment | Check | Result |
| --- | --- | --- |
| Reference laptop, i5-1135G7, 16 GB DDR4, Ubuntu 24.04 | Build portable CPU dispatch runtime at the pinned fork and patches | pass |
| Same laptop | Extract native archive into a separate directory and run without build-directory loader paths | pass |
| Same laptop, Apertus Q4_K_M, CPU, 4 threads, 4K context | Start through extracted launcher; health, embedded UI assets, streamed final usage, document Q&A | pass; document answer `Sarajevo` |
| Same configuration | 50 streamed requests, maximum 16 generated tokens each | 50/50 pass |
| Linux, actual Bash 3.2 | Download corruption/resumption/completed-part recovery; Darwin detection; runtime overrides/auto gating; launcher ownership, readiness, startup failure, Metal-to-CPU retry and archive contents | 16 tests pass |
| Linux, actual Bash 3.2 | Standalone Mac setup: clone/start from a single file, paths with spaces, preserve existing edits/folders, reject unsupported hardware and stop safely when Apple tools need interactive installation | 5 fixture tests pass |
| Linux, system Bash and actual Bash 3.2 | Mac release preflight, unsigned output preservation, credential rejection, temporary keychain cleanup/restoration on success and failure, rejected notarization response | 5 fixture tests pass; Apple commands/services are simulated, not real signing |
| Friend's physical Apple Silicon Mac; chip/RAM/macOS/backend not recorded | Standalone setup, tests, manual chat and fresh offline start | pass, reported by project owner; no automated report supplied |
| Node | Download availability, required checksums, safe URLs, unsigned Mac first-open guidance and delayed browser shutdown/profile cleanup | 5 tests pass; cleanup fixture fails against the previous implementation |
| GitHub-hosted Apple M1 VM, 7 GB RAM, macOS 15 | Versioned Mac release candidate: build, extract, code seal, actual CPU and partial Metal inference through delivered launch scripts | pass in [release preparation](https://github.com/FarukZahiragic/apertus-local/actions/runs/42422097790); unsigned development artifact, no public Mac release |
| GitHub-hosted Mac/Linux runners | Unsigned-preview implementation: 26 Python tests, five Node tests, native builds and actual model checks, including Linux browser rendering with external networking blocked | pass in [preview CI](https://github.com/FarukZahiragic/apertus-local/actions/runs/42478430452) |
| GitHub-hosted Apple M1 VM, 7 GB RAM, macOS 15 | Public unsigned preview: first-open guide in ZIP, code-seal verification, actual CPU and eight-layer packed Metal inference through extracted app | pass in [preview release build](https://github.com/FarukZahiragic/apertus-local/actions/runs/42478427184); both document answers `Sarajevo` |
| Linux verification of Mac release | ZIP SHA-256 and all 55 payload hashes, bundled first-open guide, CPU executable deployment target and anonymous release download | pass; CPU minimum 15.0.0, but the outer ARM64 applet was later found to require 15.8; 19,633,339 bytes; SHA-256 `605e0283e02ede132838bd794ebf0f970780c96925bec3275aee149268ff3686` |
| GitHub-hosted Apple M1 VM, 7 GB RAM, macOS 15 | Portable CPU/Metal builds, relocated app packaging, real CPU and partial Metal inference (`GPU_LAYERS=8 LOAD_MODE=none`) | pass in [native CI](https://github.com/FarukZahiragic/apertus-local/actions/runs/42386944980); hosted VM is not a participant laptop |
| GitHub-hosted Linux VM, only loopback networking | Fresh Apertus startup, embedded assets, streamed usage, document Q&A and rendered chat input/model in actual Chrome | pass in the same run |
| Reference Linux laptop, actual Chrome | Render embedded chat input and model name through the DevTools pipe | pass; networking enabled during this local check |

The functional report is generated under ignored `dist/validation-reference-laptop.json`.
The short Qwen throughput regression run is recorded in `benchmarks/results.md`.
The complete Python fixture suite now contains 26 passing tests, alongside five
passing Node download-page and browser-cleanup tests.
Functional request checks are not performance benchmarks. The owner informally
observed generation in the thirty-something tokens/s range on the friend's Mac,
with faster prompt processing too. The configuration and raw results were not
retained; this is not a comparable benchmark row or a published speed claim.
Formal measurements can follow later and do not block a CPU-default Mac package.

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

`v0.1.0-preview.2` adds the public [unsigned Apple Silicon Mac preview](https://github.com/FarukZahiragic/apertus-local/releases/tag/v0.1.0-preview.2).
Its outer ARM64 applet requires macOS 15.8+, includes a first-open guide beside the app, and needs no
Apple Developer membership. It has an ad-hoc code seal and has not been notarized.
New portable builds replace that host-provided applet with a native launcher
targeting macOS 13.3 and scan every bundled Mach-O against that maximum minimum.
The physical browser-download/Finder-opening rehearsal remains pending, as stated
in the release notes and download page. This is separate from the completed
physical Mac source/offline rehearsal and hosted delivered-runtime checks.

## Still pending

- The physical Mac source/offline rehearsal is accepted from the owner's report.
  Linux offline hardware rehearsal remains pending; hosted Linux isolation passed.
  Detailed Mac hardware labels and CPU/Metal latency, quality, memory and sustained
  measurements can follow when that machine is available. Use `scripts/bench_mac.sh`
  for benchmark rows. Keep global automatic Metal selection gated in the meantime.
- Rehearse the unsigned app's browser download and Finder first-open approval
  on a physical Mac, including its Terminal automation prompt and offline relaunch.
  The unsigned default in `scripts/release_macos.sh` needs no Apple credentials.
  Workflow commands and optional signing are in [MACOS_RELEASE.md](MACOS_RELEASE.md).
  The preview can be published with this remaining check clearly labelled;
  Developer ID signing is not a release prerequisite for this chosen route.
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

The later [release PR CI run](https://github.com/FarukZahiragic/apertus-local/actions/runs/42422171966)
passed its actual Linux offline API and rendered-browser checks, then failed while
deleting Chrome's profile before Chrome had finished writing it. The harness now
waits for its owned browser to exit and removes the profile asynchronously. A
delayed-write regression fixture fails against the old cleanup and passes with
the fix. This cleanup failure was separate from inference and Mac packaging.
