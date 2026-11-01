#!/usr/bin/env bash
# Build llama.cpp for CPU at a pinned release, tuned for the local CPU
# (-march=native: AVX2, AVX-512 and VNNI on the i5-1135G7).
#
# Usage: scripts/setup_llamacpp.sh
# Env:   LLAMA_CPP_DIR  checkout location   (default: vendor/llama.cpp)
#        LLAMA_CPP_REF  release tag         (default: pinned below)
#        JOBS           parallel build jobs (default: nproc)
#        CC, CXX        compilers           (default: gcc, g++)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned llama.cpp release. Bump deliberately and re-run the baseline benchmark.
PINNED_REF="b12032"
PINNED_COMMIT="dde879bc4f954b809892fd0d660515f42536394a"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
LLAMA_CPP_REF="${LLAMA_CPP_REF:-$PINNED_REF}"
JOBS="${JOBS:-$(nproc)}"

for tool in git cmake g++; do
  command -v "$tool" >/dev/null || {
    echo "error: '$tool' not found. On Ubuntu: sudo apt install -y git cmake build-essential" >&2
    exit 1
  }
done

if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
  git clone --filter=blob:none https://github.com/ggml-org/llama.cpp "$LLAMA_CPP_DIR"
fi

git -C "$LLAMA_CPP_DIR" fetch --tags --quiet origin
git -C "$LLAMA_CPP_DIR" checkout --quiet "$LLAMA_CPP_REF"
commit="$(git -C "$LLAMA_CPP_DIR" rev-parse HEAD)"
if [[ "$LLAMA_CPP_REF" == "$PINNED_REF" && "$commit" != "$PINNED_COMMIT" ]]; then
  echo "error: $PINNED_REF resolved to $commit, expected $PINNED_COMMIT" >&2
  exit 1
fi

cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC:-gcc}" \
  -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
  -DGGML_NATIVE=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF

cmake --build "$LLAMA_CPP_DIR/build" -j "$JOBS" \
  --target llama-cli llama-bench llama-server llama-quantize

BIN="$LLAMA_CPP_DIR/build/bin"
echo
echo "llama.cpp $LLAMA_CPP_REF ($commit) built in $BIN"
"$BIN/llama-cli" --version 2>&1 | tail -n 2
echo "CPU features seen by ggml:"
grep -o -w -E 'avx2|avx512f|avx512_vnni|avx_vnni' /proc/cpuinfo | sort -u | tr '\n' ' '
echo
