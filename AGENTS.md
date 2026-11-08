# Working rules

These rules apply to every human and agent contributing to this repo.

## Scope

- The goal is fixed: run Apertus-v1.5-8B offline on a regular laptop (no dedicated
  GPU required, no internet during inference), serve it through `llama-server`,
  then make it faster. CPU remains supported; integrated acceleration is optional.
- Nothing outside local deployment, serving, and speed work. No new features,
  frameworks, or tooling that the roadmap does not call for.
- Build the minimal working version first, then improve it. A phase is done when
  its slice works end to end, not when it is polished.

## Branches and commits

- One branch per project part, named after the phase in [docs/ROADMAP.md](docs/ROADMAP.md):
  `chore/...`, `feat/...`, `perf/...`. Each branch is merged through its own PR.
- One logical change per commit (atomic commits). A commit adds one script, one
  doc update, or one fix, not a mix.
- Commit messages: imperative subject line, under 72 characters, with a body when the
  why is not obvious.

## Benchmarks

- Every benchmark run is recorded as one row in [benchmarks/results.md](benchmarks/results.md),
  using the schema described there and in [docs/IO.md](docs/IO.md).
- Always label the hardware. Numbers from a cloud VM must say so; they are not laptop
  numbers.
- Use `scripts/bench.sh` (or `scripts/bench_matrix.sh`) so rows stay comparable.

## Docs

- Docs are kept in sync with the code in the same PR: if a script, flag, file name or
  port changes, update `README.md` and `docs/` in that branch.
- `docs/ROADMAP.md` holds the phase status; update it when a phase starts or lands.

## Practical

- Large files (model weights, GGUF, the llama.cpp checkout) never go into git. They live
  under `models/` and `vendor/`, which are ignored.
- Scripts are bash with `set -euo pipefail`, run from the repo root, and print what they
  do. Secrets such as `HF_TOKEN` come from the environment, never from files in the repo.
- Participant launchers may use native macOS or Windows entry points. Keep shared
  inference behavior in llama-server and keep platform wrappers small.
