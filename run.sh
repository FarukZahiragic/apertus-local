#!/usr/bin/env bash
# One-command participant setup for macOS and Linux; no build tools required.
# Usage: bash run.sh [--prepare-only] [--no-browser]
# Env: APERTUS_INSTALL_DIR, APERTUS_RUNTIME_DIR, MODELS_DIR, MODEL, BACKEND, CTX.
# APERTUS_PACKAGE_URL and APERTUS_PACKAGE_SHA256 must be overridden together.
set -euo pipefail

prepare=0 no_browser=0
for argument in "$@"; do
  case "$argument" in
    --prepare-only) prepare=1 ;;
    --no-browser) no_browser=1 ;;
    -h|--help)
      echo 'Usage: bash run.sh [--prepare-only] [--no-browser]'
      echo 'Get the verified native runtime if missing, prepare the model, and open local chat.'
      echo 'No compiler, Python, Homebrew, Git checkout, or app wrapper is installed.'
      exit 0 ;;
    *) echo "error: unknown option $argument" >&2; exit 1 ;;
  esac
done

# Choose a native package and its fixed checksum; no build tools are installed.
case "$(uname -s) $(uname -m)" in
  'Darwin arm64') platform=macos-arm64 ;;
  'Darwin x86_64')
    if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then
      platform=macos-arm64
    else
      echo 'error: the Mac runtime requires an Apple Silicon (M-series) chip.' >&2; exit 1
    fi ;;
  'Linux x86_64') platform=linux-x86_64 ;;
  *) echo 'error: use Apple Silicon macOS, x86_64 Linux, or run.ps1 on Windows.' >&2; exit 1 ;;
esac
version=v0.2.0-preview.2
export MULTIMODAL="${MULTIMODAL:-1}"
[[ "$MULTIMODAL" == 0 || "$MULTIMODAL" == 1 ]] || { echo 'error: MULTIMODAL must be 0 or 1' >&2; exit 1; }
case "$platform" in
  macos-arm64)
    archive="apertus-local-$version-$platform.zip"
    digest=ffcfb7a8be0b0f1f11f1bb71056ba94c6b97c1f0b2ab9f8a4ac1bb664d42a6ea
    default_root="$HOME/Library/Application Support/Apertus Local" ;;
  linux-x86_64)
    archive="apertus-local-$version-$platform.tar.gz"
    digest=a3cfbc425314d7367ebe552963743fcd562ec0301fd62e0e7503a126510113b1
    default_root="${XDG_DATA_HOME:-$HOME/.local/share}/apertus-local" ;;
esac
url="https://github.com/FarukZahiragic/apertus-local/releases/download/$version/$archive"
if [[ -n "${APERTUS_PACKAGE_URL:-}${APERTUS_PACKAGE_SHA256:-}" ]]; then
  [[ -n "${APERTUS_PACKAGE_URL:-}" && "${APERTUS_PACKAGE_SHA256:-}" =~ ^[a-fA-F0-9]{64}$ ]] || {
    echo 'error: a package URL override requires APERTUS_PACKAGE_SHA256 as well.' >&2; exit 1;
  }
  url="$APERTUS_PACKAGE_URL" digest="$APERTUS_PACKAGE_SHA256"
fi
digest="$(printf '%s' "$digest" | tr 'A-F' 'a-f')"
case "$url" in
  https://*|http://127.0.0.1:*/*|http://localhost:*/*) ;;
  *) echo 'error: package downloads require HTTPS (HTTP loopback is allowed for tests).' >&2; exit 1 ;;
esac
if [[ -n "${MODEL:-}" && ! -f "$MODEL" ]]; then
  echo "error: MODEL does not exist: $MODEL" >&2; exit 1
fi

# Keep new files in the user's data folder; reuse a prepared runtime when found.
data="${APERTUS_INSTALL_DIR:-$default_root}"
mkdir -p "$data"
data="$(cd "$data" && pwd)"
if [[ -z "${APERTUS_RUNTIME_DIR:-}" ]]; then
  for candidate in "$PWD" "$HOME/apertus-1.5-local"; do
    # An older prepared runtime would bring the generic UI back after an update.
    if [[ -x "$candidate/runtime/cpu/bin/llama-server" ]]; then
      grep -q '"0006-apertus-workshop-ui.patch"' "$candidate/release.json" 2>/dev/null || continue
    else
      cache="$candidate/vendor/llama.cpp/build/CMakeCache.txt"
      grep -q '^LLAMA_BUILD_UI:BOOL=ON$' "$cache" 2>/dev/null &&
        grep -q '^LLAMA_USE_PREBUILT_UI:BOOL=OFF$' "$cache" 2>/dev/null || continue
    fi
    if [[ -f "$candidate/scripts/launch.sh" && -f "$candidate/config/model.env" ]] &&
       [[ "$MULTIMODAL" == 0 || -f "$candidate/config/multimodal.env" ]] &&
       grep -q '^APERTUS_MODEL_SHA256=e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c$' "$candidate/config/model.env" &&
       [[ -x "$candidate/runtime/cpu/bin/llama-server" || -x "$candidate/vendor/llama.cpp/build/bin/llama-server" ]]; then
      APERTUS_RUNTIME_DIR="$candidate"; break
    fi
  done
fi
runtime="${APERTUS_RUNTIME_DIR:-$data/packages/$platform-$version}"
lock='' stage=''
cleanup() {
  [[ -z "$stage" ]] || rm -rf "$stage"
  [[ -z "$lock" ]] || rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
valid_runtime() {
  [[ -f "$runtime/scripts/launch.sh" && -f "$runtime/scripts/get_model.sh" && -f "$runtime/config/model.env" ]] || return 1
  [[ "$MULTIMODAL" == 0 || -f "$runtime/config/multimodal.env" ]] || return 1
  if [[ -n "${APERTUS_RUNTIME_DIR:-}" ]]; then return 0; fi
  [[ -f "$runtime/.bootstrap-sha256" && "$(cat "$runtime/.bootstrap-sha256")" == "$digest" ]]
}

echo 'Apertus Local - one-command setup'
echo "Local files: $data"
echo 'Model files total 6.1 GiB (5.3 GiB in text-only mode). A missing native runtime downloads once.'
# Verify the downloaded archive before extracting it into the data folder.
if ! valid_runtime; then
  [[ -z "${APERTUS_RUNTIME_DIR:-}" ]] || { echo 'error: APERTUS_RUNTIME_DIR is not an Apertus runtime folder.' >&2; exit 1; }
  [[ ! -e "$runtime" ]] || { echo "error: unrecognized runtime at $runtime; nothing was overwritten." >&2; exit 1; }
  lock="$data/.bootstrap-lock"
  mkdir "$lock" 2>/dev/null || { lock=''; echo 'error: another setup is running; close it and retry.' >&2; exit 1; }
  mkdir -p "$data/downloads" "$data/packages"
  partial="$data/downloads/$archive.part"
  if [[ ! -f "$partial" || "$(hash_file "$partial")" != "$digest" ]]; then
    echo "Downloading the native $platform runtime. Interrupted transfers can resume."
    curl --fail --location --show-error --connect-timeout 20 --retry 3 --retry-delay 2 \
      --continue-at - --output "$partial" "$url"
  fi
  if [[ "$(hash_file "$partial")" != "$digest" ]]; then
    rm -f "$partial"
    echo 'error: runtime checksum mismatch; incorrect download removed.' >&2; exit 1
  fi
  stage="$(mktemp -d "$data/.install.XXXXXX")"
  if [[ "$platform" == macos-arm64 ]]; then
    ditto -x -k "$partial" "$stage"
    payload="$stage/Apertus Local.app/Contents/Resources/apertus-local"
  else
    tar -xzf "$partial" -C "$stage"
    payload="$stage/apertus-local-$version-$platform"
    # The preview promotes tested CI archive bytes without repacking their payload.
    if [[ ! -d "$payload" ]]; then payload="$stage/apertus-local-ci-$platform"; fi
  fi
  [[ -f "$payload/scripts/launch.sh" && -x "$payload/runtime/cpu/bin/llama-server" ]] || {
    echo 'error: the runtime archive is missing its launcher or server.' >&2; exit 1;
  }
  printf '%s\n' "$digest" > "$payload/.bootstrap-sha256"
  mv "$payload" "$runtime"
  rm -f "$partial"
  cleanup
  stage='' lock=''
else
  echo "Reusing the local runtime: $runtime"
fi
runtime="$(cd "$runtime" && pwd)"
# Reuse existing weights where possible; otherwise download into this install.
models="${MODELS_DIR:-$data/models}"
if [[ -z "${MODELS_DIR:-}${MODEL:-}" ]]; then
  for candidate in "$PWD/models" "$HOME/apertus-1.5-local/models"; do
    if [[ -f "$candidate/apertus-v1.5-8b-Q4_K_M.gguf" ]]; then models="$candidate"; break; fi
  done
fi
mkdir -p "$models"
models="$(cd "$models" && pwd)"
export MODELS_DIR="$models"
export APERTUS_STATE_DIR="${APERTUS_STATE_DIR:-$data/state}"
if [[ -n "${MMPROJ:-}" ]]; then
  [[ -f "$MMPROJ" ]] || { echo "error: encoder does not exist: $MMPROJ" >&2; exit 1; }
  export MMPROJ="$(cd "$(dirname "$MMPROJ")" && pwd)/$(basename "$MMPROJ")"
fi
if [[ -n "${MODEL:-}" ]]; then
  MODEL="$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL")"
  export MODEL MODEL_SHA256="${MODEL_SHA256:-e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c}"
fi

# Save a small offline launcher with the selected paths and mode. It delegates
# to the packaged launch.sh; model execution stays in the shared runtime.
temporary="$(mktemp "$data/.start.XXXXXX")"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'if [[ -z "${MODELS_DIR:-}" ]]; then export MODELS_DIR=%q; fi\n' "$models"
  printf 'if [[ -z "${APERTUS_STATE_DIR:-}" ]]; then export APERTUS_STATE_DIR=%q; fi\n' "$APERTUS_STATE_DIR"
  printf 'export MULTIMODAL="${MULTIMODAL:-%s}"\n' "$MULTIMODAL"
  if [[ -n "${MMPROJ:-}" ]]; then
    printf 'if [[ -z "${MMPROJ:-}" ]]; then export MMPROJ=%q; fi\n' "$MMPROJ"
    if [[ -n "${MMPROJ_SHA256:-}" ]]; then printf 'export MMPROJ_SHA256=%q\n' "$MMPROJ_SHA256"; fi
  fi
  if [[ -n "${MODEL:-}" ]]; then
    printf 'if [[ -z "${MODEL:-}" ]]; then export MODEL=%q; fi\n' "$MODEL"
    printf 'if [[ -z "${MODEL_SHA256:-}" ]]; then export MODEL_SHA256=%q; fi\n' "$MODEL_SHA256"
  fi
  printf 'exec /bin/bash %q "$@"\n' "$runtime/scripts/launch.sh"
} > "$temporary"
chmod 755 "$temporary"
mv -f "$temporary" "$data/start.sh"
printf 'Next time, including offline: bash %q\n' "$data/start.sh"
# Preparation only downloads/verifies files; normal setup starts local chat.
if [[ "$prepare" == 1 ]]; then
  if [[ -n "${MODEL:-}" ]]; then
    [[ "$(hash_file "$MODEL")" == "$MODEL_SHA256" ]] || { echo 'error: MODEL_SHA256 mismatch.' >&2; exit 1; }
  else
    /bin/bash "$runtime/scripts/get_model.sh" --apertus
  fi
  if [[ "$MULTIMODAL" == 1 ]]; then
    if [[ -n "${MMPROJ:-}" ]]; then
      mmsha="${MMPROJ_SHA256:-$(source "$runtime/config/multimodal.env"; printf '%s' "$APERTUS_MODEL_SHA256")}"
      [[ "$(hash_file "$MMPROJ")" == "$mmsha" ]] || { echo 'error: MMPROJ_SHA256 mismatch.' >&2; exit 1; }
    else
      /bin/bash "$runtime/scripts/get_model.sh" --multimodal
    fi
  fi
  echo 'Preparation complete. Start local chat with the command above.'
else
  if [[ "$no_browser" == 1 ]]; then exec /bin/bash "$data/start.sh" --no-browser
  else exec /bin/bash "$data/start.sh"; fi
fi
