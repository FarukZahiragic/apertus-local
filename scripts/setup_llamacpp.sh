#!/usr/bin/env bash
# Build llama.cpp for CPU at a pinned commit, tuned for the local CPU
# (-march=native: AVX2, AVX-512 and VNNI on the i5-1135G7).
#
# The pin is a community branch that adds Apertus v1.5 support (split input/output
# vocabulary, chat template) on top of upstream b11347, which already has the DSpark
# drafter (--spec-type draft-dspark). See docs/ARCHITECTURE.md.
#
# Usage: scripts/setup_llamacpp.sh
# Env:   LLAMA_CPP_DIR     checkout location   (default: vendor/llama.cpp)
#        LLAMA_CPP_REPO    git remote          (default: pinned below)
#        LLAMA_CPP_BRANCH  branch to fetch     (default: pinned below)
#        LLAMA_CPP_COMMIT  commit to build     (default: pinned below)
#        JOBS              parallel build jobs (default: nproc)
#        CC, CXX           compilers           (default: gcc, g++)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned llama.cpp. Bump deliberately and re-run the baseline benchmark.
PINNED_REPO="https://github.com/MichelRosselli/llama.cpp"
PINNED_BRANCH="model/apertus-v1.5-refresh-20260914"
PINNED_COMMIT="442b0444168a0f72788b40a16c8289bd1eb217f5"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
LLAMA_CPP_REPO="${LLAMA_CPP_REPO:-$PINNED_REPO}"
LLAMA_CPP_BRANCH="${LLAMA_CPP_BRANCH:-$PINNED_BRANCH}"
LLAMA_CPP_COMMIT="${LLAMA_CPP_COMMIT:-$PINNED_COMMIT}"
JOBS="${JOBS:-$(nproc)}"

for tool in git cmake g++; do
  command -v "$tool" >/dev/null || {
    echo "error: '$tool' not found. On Ubuntu: sudo apt install -y git cmake build-essential" >&2
    exit 1
  }
done

if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$LLAMA_CPP_REPO" "$LLAMA_CPP_DIR"
fi
git -C "$LLAMA_CPP_DIR" remote set-url origin "$LLAMA_CPP_REPO"
git -C "$LLAMA_CPP_DIR" fetch --quiet origin "$LLAMA_CPP_BRANCH"
git -C "$LLAMA_CPP_DIR" checkout --quiet --detach "$LLAMA_CPP_COMMIT"

# Examples stay configured so tools like llama-debug can be built on demand.
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC:-gcc}" \
  -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
  -DGGML_NATIVE=ON \
  -DLLAMA_BUILD_TESTS=OFF

cmake --build "$LLAMA_CPP_DIR/build" -j "$JOBS" \
  --target llama-cli llama-bench llama-server llama-quantize

BIN="$LLAMA_CPP_DIR/build/bin"
echo
echo "llama.cpp $LLAMA_CPP_COMMIT ($LLAMA_CPP_REPO) built in $BIN"
"$BIN/llama-cli" --version 2>&1 | tail -n 2
echo "CPU features seen by ggml:"
grep -o -w -E 'avx2|avx512f|avx512_vnni|avx_vnni' /proc/cpuinfo | sort -u | tr '\n' ' '
echo
