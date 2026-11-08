#!/usr/bin/env bash
# Standalone Apple Silicon setup: send this file, then run bash ~/Downloads/setup.sh.
# Usage: bash setup.sh [--no-start]
# Env: APERTUS_INSTALL_DIR (~/apertus-1.5-local), APERTUS_SETUP_LOG, BACKEND (cpu).
# Preparation needs internet; subsequent chat uses only local files and localhost.
set -euo pipefail
set -E

start=1
case "${1:-}" in
  --no-start) start=0; shift ;;
  -h|--help)
    echo 'Usage: bash setup.sh [--no-start]'
    echo 'Install prerequisites, build CPU and Metal, verify the model, then open CPU chat.'
    echo 'Use --no-start to prepare now and launch later without internet.'
    exit 0 ;;
esac
[[ $# -eq 0 ]] || { echo 'error: use bash setup.sh [--no-start]' >&2; exit 1; }
[[ "$(uname -s) $(uname -m)" == 'Darwin arm64' ]] || {
  echo 'error: this setup is for an Apple Silicon Mac. Use its native Terminal (arm64).' >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${APERTUS_INSTALL_DIR:-$HOME/apertus-1.5-local}"
# Also work from an existing clone, without creating a second copy.
if [[ -z "${APERTUS_INSTALL_DIR:-}" && -f "$script_dir/scripts/setup_llamacpp.sh" && -e "$script_dir/.git" ]]; then
  install_dir="$script_dir"
fi
log="${APERTUS_SETUP_LOG:-$HOME/Library/Logs/Apertus Local/setup.log}"
mkdir -p "$(dirname "$log")"
exec > >(tee -a "$log") 2>&1
step='checking prerequisites'
installer=''
trap '[[ -z "$installer" ]] || rm -f "$installer"' EXIT
on_error() {
  local status=$?
  echo "Setup stopped while $step. Details: $log" >&2
  echo 'Fix the error above and run the same setup command again; verified downloads are reused.' >&2
  exit "$status"
}
trap on_error ERR
echo 'Apertus Local — Apple Silicon setup'
echo "Setup log: $log"
echo "Install folder: $install_dir"
echo 'Keep internet connected during setup. The model is 5.3 GiB; allow about 20 GB free for setup.'
if (( $(sysctl -n hw.memsize) < 15000000000 )); then
  echo 'Memory note: 16 GB RAM is recommended. Smaller Macs are experimental.'
fi

tools_ready() {
  xcrun --find clang >/dev/null 2>&1 && xcrun --show-sdk-path >/dev/null 2>&1
}
if ! tools_ready; then
  echo 'Installing Apple command line tools. Complete the macOS installation window.'
  xcode-select --install || true
  if [[ ! -t 0 ]]; then
    echo 'Finish installing the tools, then run this file again in Terminal.' >&2
    exit 1
  fi
  echo 'Waiting for installation. Press Control+C to cancel setup.'
  deadline=$((SECONDS + 1800))
  until tools_ready; do
    ((SECONDS < deadline)) || { echo 'error: command line tools are still unavailable; rerun after installation.' >&2; exit 1; }
    sleep 5
  done
fi

packages=()
command -v cmake >/dev/null 2>&1 || packages+=(cmake)
if ! command -v python3 >/dev/null 2>&1 || ! python3 --version >/dev/null 2>&1; then packages+=(python); fi
if [[ ${#packages[@]} -gt 0 ]]; then
  step='installing CMake/Python prerequisites'
  brew_cmd="$(command -v brew || true)"
  if [[ -x /opt/homebrew/bin/brew ]]; then brew_cmd=/opt/homebrew/bin/brew; fi
  if [[ -z "$brew_cmd" ]]; then
    echo 'Installing Homebrew using its official installer; follow its prompts.'
    installer="$(mktemp "${TMPDIR:-/tmp}/apertus-homebrew.XXXXXX")"
    curl --fail --location --show-error \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
    /bin/bash "$installer"
    rm -f "$installer"
    installer=''
    brew_cmd=/opt/homebrew/bin/brew
  fi
  eval "$("$brew_cmd" shellenv)"
  echo "Installing missing prerequisites: ${packages[*]}"
  "$brew_cmd" install "${packages[@]}"
fi

step='getting the project'
repo='https://github.com/FarukZahiragic/apertus-local'
if [[ ! -e "$install_dir" ]]; then
  mkdir -p "$(dirname "$install_dir")"
  git clone --branch feat/macos-setup --single-branch "$repo" "$install_dir"
else
  [[ -d "$install_dir" && -e "$install_dir/.git" ]] || {
    echo "error: $install_dir already exists and is not a project checkout; nothing was overwritten." >&2
    exit 1
  }
  origin="$(git -C "$install_dir" remote get-url origin)"
  case "$origin" in
    "$repo"|"$repo.git"|git@github.com:FarukZahiragic/apertus-local|git@github.com:FarukZahiragic/apertus-local.git) ;;
    *) echo "error: $install_dir belongs to another repository; nothing was overwritten." >&2; exit 1 ;;
  esac
  echo 'Reusing the existing project as-is; setup does not pull, reset or discard edits.'
fi
cd "$install_dir"
for file in scripts/platform.sh scripts/setup_llamacpp.sh scripts/get_model.sh Start.command; do
  [[ -f "$file" ]] || {
    echo "error: this checkout lacks $file. Use APERTUS_INSTALL_DIR to choose a new folder." >&2
    exit 1
  }
done
echo "Project revision: $(git rev-parse HEAD)"
/bin/bash scripts/platform.sh
step='building the CPU runtime'
echo 'Building CPU runtime. This can take several minutes.'
/bin/bash scripts/setup_llamacpp.sh --cpu
step='building the Metal runtime'
echo 'Building Metal runtime for optional integrated GPU acceleration.'
/bin/bash scripts/setup_llamacpp.sh --metal
step='downloading and verifying Apertus'
/bin/bash scripts/get_model.sh --apertus

echo
echo 'Setup complete. Future starts work without internet.'
printf 'Start CPU chat: cd %q && BACKEND=cpu ./Start.command\n' "$install_dir"
printf 'Test Metal:     cd %q && BACKEND=metal ./Start.command\n' "$install_dir"
printf 'Compare speed:  cd %q && scripts/bench_mac.sh\n' "$install_dir"
echo 'Stop chat with Control+C before comparing speed. Use AC power and close other apps.'
echo "The setup log stays at: $log"
if [[ "$start" -eq 1 ]]; then
  echo 'Opening local chat. Keep this terminal open; Control+C stops the server.'
  export BACKEND="${BACKEND:-cpu}"
  exec /bin/bash ./Start.command
fi
