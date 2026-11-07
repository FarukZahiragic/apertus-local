#!/usr/bin/env bash
# Build llama.cpp for CPU at a pinned commit, tuned for the local CPU
# (-march=native: AVX2, AVX-512 and VNNI on the i5-1135G7).
#
# The pin is a community branch that adds Apertus v1.5 support (split input/output
# vocabulary, chat template) on top of upstream b11347, which already has the DSpark
# drafter (--spec-type draft-dspark). See docs/ARCHITECTURE.md.
#
# The checkout is reset to the pin and patches/*.patch are applied in order on every
# run (small fixes for Apertus speculative decoding; see patches/README.md).
#
# Usage: scripts/setup_llamacpp.sh [--cpu|--metal|--vulkan] [--portable]
#   --cpu     CPU-only build (default), with Accelerate on macOS
#   --metal   Apple Silicon integrated GPU, built into build-metal/
#   --portable disable build-host instruction tuning for release packages
#   --vulkan  also enable the Vulkan backend (Iris Xe iGPU), built into build-vulkan/
#             next to the CPU build. Needs: sudo apt install -y libvulkan-dev glslc
#             spirv-headers mesa-vulkan-drivers vulkan-tools
# Env:   LLAMA_CPP_DIR     checkout location   (default: vendor/llama.cpp)
#        LLAMA_CPP_REPO    git remote          (default: pinned below)
#        LLAMA_CPP_BRANCH  branch to fetch     (default: pinned below)
#        LLAMA_CPP_COMMIT  commit to build     (default: pinned below)
#        JOBS              parallel build jobs (default: nproc)
#        CC, CXX           compilers           (default: gcc, g++)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"

# Pinned llama.cpp. Bump deliberately and re-run the baseline benchmark.
PINNED_REPO="https://github.com/MichelRosselli/llama.cpp"
PINNED_BRANCH="model/apertus-v1.5-refresh-20260914"
PINNED_COMMIT="442b0444168a0f72788b40a16c8289bd1eb217f5"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/vendor/llama.cpp}"
LLAMA_CPP_REPO="${LLAMA_CPP_REPO:-$PINNED_REPO}"
LLAMA_CPP_BRANCH="${LLAMA_CPP_BRANCH:-$PINNED_BRANCH}"
LLAMA_CPP_COMMIT="${LLAMA_CPP_COMMIT:-$PINNED_COMMIT}"
backend=cpu portable=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    --cpu) backend=cpu ;;
    --metal) backend=metal ;;
    --vulkan) backend=vulkan ;;
    --portable) portable=1 ;;
    *) echo "error: unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
JOBS="${JOBS:-$(ap_jobs)}"
if [[ "$(ap_os)" == Darwin ]]; then
  export CC="${CC:-clang}" CXX="${CXX:-clang++}"
else
  export CC="${CC:-gcc}" CXX="${CXX:-g++}"
fi
build_dir=build
extra_cmake=(-DGGML_VULKAN=OFF -DGGML_METAL=OFF -DGGML_NATIVE=ON)
if [[ "$backend" != cpu ]]; then build_dir="build-$backend"; fi
if [[ "$backend" == metal ]]; then
  [[ "$(ap_os) $(ap_arch)" == 'Darwin arm64' ]] || {
    echo 'error: --metal requires native Apple Silicon macOS (use an ARM64 terminal, without Rosetta)' >&2; exit 1;
  }
  extra_cmake+=(-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON)
fi
if [[ "$(ap_os)" == Darwin ]]; then extra_cmake+=(-DGGML_OPENMP=OFF); fi
if [[ "$portable" -eq 1 ]]; then
  build_dir="$build_dir-portable"
  extra_cmake+=(-DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON)
fi
if [[ "$backend" == vulkan ]]; then
  extra_cmake+=(-DGGML_VULKAN=ON)
  command -v glslc >/dev/null || {
    echo "error: glslc not found. On Ubuntu: sudo apt install -y libvulkan-dev glslc spirv-headers mesa-vulkan-drivers vulkan-tools" >&2
    exit 1
  }
fi

for tool in git cmake "$CC" "$CXX"; do
  command -v "$tool" >/dev/null || {
    echo "error: '$tool' not found. Ubuntu: install git cmake build-essential. macOS: install Xcode command line tools and CMake." >&2
    exit 1
  }
done

if [[ ! -d "$LLAMA_CPP_DIR/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$LLAMA_CPP_REPO" "$LLAMA_CPP_DIR"
fi
git -C "$LLAMA_CPP_DIR" remote set-url origin "$LLAMA_CPP_REPO"
git -C "$LLAMA_CPP_DIR" fetch --quiet origin "$LLAMA_CPP_BRANCH"
git -C "$LLAMA_CPP_DIR" checkout --quiet --force --detach "$LLAMA_CPP_COMMIT"
git -C "$LLAMA_CPP_DIR" reset --quiet --hard "$LLAMA_CPP_COMMIT"
for patch in "$REPO_ROOT"/patches/*.patch; do
  [[ -e "$patch" ]] || continue
  echo "applying $(basename "$patch")"
  git -C "$LLAMA_CPP_DIR" apply "$patch"
done

# Examples stay configured so tools like llama-debug can be built on demand.
cmake -S "$LLAMA_CPP_DIR" -B "$LLAMA_CPP_DIR/$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DLLAMA_BUILD_TESTS=OFF \
  "${extra_cmake[@]}"

cmake --build "$LLAMA_CPP_DIR/$build_dir" -j "$JOBS" \
  --target llama-cli llama-bench llama-server llama-quantize

BIN="$LLAMA_CPP_DIR/$build_dir/bin"
echo
echo "llama.cpp $LLAMA_CPP_COMMIT ($LLAMA_CPP_REPO) built in $BIN"
"$BIN/llama-cli" --version 2>&1 | tail -n 2
echo "Backend: $backend; portable: $portable"
echo "Hardware: $(ap_hardware)"
