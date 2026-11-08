#!/usr/bin/env bash
# Package portable native builds; never includes model weights or developer tools.
# Usage: scripts/package_release.sh [--version VERSION] [--sign]
# Env: CPU_BUILD_DIR, METAL_BUILD_DIR (macOS), APERTUS_MODEL_REPO,
#      APERTUS_MODEL_REVISION, MODEL_URL, OUTPUT_DIR (default dist/).
# --sign requires MACOS_SIGN_IDENTITY and MACOS_NOTARY_PROFILE on a Mac.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/platform.sh"
version="dev-$(git -C "$REPO_ROOT" rev-parse --short HEAD)" sign=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || { echo 'error: --version requires a value' >&2; exit 1; }; version="$2"; shift ;;
    --sign) sign=1 ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'error: invalid version' >&2; exit 1; }
case "$(ap_os) $(ap_arch)" in
  'Darwin arm64') platform=macos-arm64 ;;
  'Linux x86_64') platform=linux-x86_64 ;;
  *) echo 'error: package on native Apple Silicon macOS or x86_64 Linux' >&2; exit 1 ;;
esac
if [[ "$sign" -eq 1 && "$platform" != macos-arm64 ]]; then echo 'error: signing requires macOS' >&2; exit 1; fi
cpu="${CPU_BUILD_DIR:-$REPO_ROOT/vendor/llama.cpp/build-portable}"
metal="${METAL_BUILD_DIR:-$REPO_ROOT/vendor/llama.cpp/build-metal-portable}"
output="${OUTPUT_DIR:-$REPO_ROOT/dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/apertus-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
name="apertus-local-$version-$platform"
payload="$stage/$name"
mkdir -p "$payload/scripts" "$payload/config" "$payload/models" "$payload/licenses"
for file in platform.sh get_model.sh serve.sh launch.sh; do cp "$REPO_ROOT/scripts/$file" "$payload/scripts/"; done
cp "$REPO_ROOT/config/model.env" "$payload/config/"
cp "$REPO_ROOT/config/multimodal.env" "$payload/config/"
cp "$REPO_ROOT"/Start-Text.command "$REPO_ROOT"/Start-Text.sh "$payload/"
cp "$REPO_ROOT"/Start.command "$REPO_ROOT"/Stop.command "$REPO_ROOT"/Start.sh "$REPO_ROOT"/Stop.sh "$payload/"
cp "$REPO_ROOT/packaging/README.txt" "$payload/README.txt"
cp "$REPO_ROOT/packaging/MODEL_CARD.md" "$payload/MODEL_CARD.md"
cp "$REPO_ROOT/packaging/APERTUS-LICENSE.txt" "$payload/licenses/APERTUS-LICENSE.txt"
cp "$REPO_ROOT/vendor/llama.cpp/LICENSE" "$payload/licenses/llama.cpp-LICENSE"
# Preserve notices for bundled upstream dependencies and the embedded UI.
python3 - "$REPO_ROOT/vendor/llama.cpp" "$payload/licenses" <<'PY'
from pathlib import Path
import shutil, sys
root, dest = map(Path, sys.argv[1:])
for source in [root/'licenses', root/'vendor', root/'tools/ui']:
    for path in source.rglob('*'):
        if path.is_file() and (path.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE'))):
            target = dest / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
PY
copy_runtime() {
  local backend="$1" build="$2" file
  [[ -f "$build/CMakeCache.txt" ]] || { echo "error: missing build cache: $build" >&2; exit 1; }
  grep -q '^GGML_NATIVE:BOOL=OFF$' "$build/CMakeCache.txt" || { echo 'error: release build must use --portable' >&2; exit 1; }
  grep -q '^GGML_BACKEND_DL:BOOL=ON$' "$build/CMakeCache.txt" || { echo 'error: release build needs dynamic CPU dispatch' >&2; exit 1; }
  if [[ "$backend" == cpu ]]; then
    grep -q '^GGML_METAL:BOOL=OFF$' "$build/CMakeCache.txt" || { echo 'error: CPU fallback must be built without Metal' >&2; exit 1; }
  fi
  mkdir -p "$payload/runtime/$backend/bin"
  for file in llama-server llama-bench llama-cli; do
    [[ -x "$build/bin/$file" ]] || { echo "error: missing $build/bin/$file" >&2; exit 1; }
    cp "$build/bin/$file" "$payload/runtime/$backend/bin/"
  done
  for file in "$build"/bin/*.so* "$build"/bin/*.dylib "$build"/bin/*.metallib; do
    [[ -e "$file" ]] || continue
    cp -P "$file" "$payload/runtime/$backend/bin/"
  done
  cp "$build/CMakeCache.txt" "$payload/runtime/$backend/build-cache.txt"
}
copy_runtime cpu "$cpu"
if [[ "$platform" == macos-arm64 ]]; then copy_runtime metal "$metal"; fi
# Write values with shell quoting; tokens are deliberately excluded.
if [[ -n "${APERTUS_MODEL_REPO:-}" ]]; then printf 'APERTUS_MODEL_REPO=%q\n' "$APERTUS_MODEL_REPO" >> "$payload/config/model.env"; fi
if [[ -n "${APERTUS_MODEL_REVISION:-}" ]]; then printf 'APERTUS_MODEL_REVISION=%q\n' "$APERTUS_MODEL_REVISION" >> "$payload/config/model.env"; fi
if [[ -n "${MODEL_URL:-}" ]]; then printf 'export MODEL_URL=%q\n' "$MODEL_URL" >> "$payload/config/model.env"; fi
python3 - "$REPO_ROOT" "$payload" "$version" "$platform" "$sign" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
root, dest = map(Path, sys.argv[1:3])
manifest = {'version': sys.argv[3], 'platform': sys.argv[4],
            'source_commit': subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
            'llama_commit': subprocess.check_output(['git','-C',str(root/'vendor/llama.cpp'),'rev-parse','HEAD'],text=True).strip(),
            'patches': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'patches').glob('*.patch'))},
            'metal_validated': False, 'signing': 'notarization-requested' if sys.argv[5]=='1' else 'unsigned',
            'files': {}}
for path in sorted(dest.rglob('*')):
    if path.is_file() and not path.is_symlink():
        manifest['files'][str(path.relative_to(dest))] = hashlib.sha256(path.read_bytes()).hexdigest()
(dest/'release.json').write_text(json.dumps(manifest, indent=2)+'\n')
PY
# Exercise relocated binaries without a loader-path workaround.
"$payload/runtime/cpu/bin/llama-server" --version
"$payload/runtime/cpu/bin/llama-bench" --list-devices
record_compatibility() {
  local destination="$1" scan="$2"
  shift 2
  python3 "$REPO_ROOT/scripts/runtime_requirements.py" "$scan" "$@" > "$destination/compatibility.json"
  python3 - "$destination" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
path = root/'compatibility.json'
manifest = json.loads((root/'release.json').read_text())
manifest['compatibility'] = json.loads(path.read_text())
expected = 'arm64' if manifest['platform'].endswith('arm64') else 'x86_64'
assert manifest['compatibility']['architectures'] == [expected], 'Archive contains a different CPU architecture'
manifest['files']['compatibility.json'] = hashlib.sha256(path.read_bytes()).hexdigest()
(root/'release.json').write_text(json.dumps(manifest, indent=2)+'\n')
PY
}
if [[ "$platform" == macos-arm64 ]]; then
  app="$stage/Apertus Local.app"
  mac_target="${MACOSX_DEPLOYMENT_TARGET:-13.3}"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  xcrun clang -fobjc-arc "-mmacosx-version-min=$mac_target" -framework Cocoa \
    "$REPO_ROOT/packaging/Launch.m" -o "$app/Contents/MacOS/ApertusLocal"
  plist="$app/Contents/Info.plist"
  python3 - "$plist" "$mac_target" "$version" <<'PY'
import plistlib, re, sys
match = re.match(r'v?(\d+\.\d+\.\d+)', sys.argv[3])
version = match.group(1) if match else '0.0.0'
with open(sys.argv[1], 'wb') as output:
    plistlib.dump(dict(CFBundleIdentifier='io.github.FarukZahiragic.apertus-local',
        CFBundleName='Apertus Local', CFBundleDisplayName='Apertus Local',
        CFBundleExecutable='ApertusLocal', CFBundlePackageType='APPL',
        CFBundleVersion=version, CFBundleShortVersionString=version,
        LSMinimumSystemVersion=sys.argv[2],
        NSAppleEventsUsageDescription='Apertus Local opens Terminal to run the model and show startup messages.'), output)
PY
  mkdir -p "$app/Contents/Resources/apertus-local"
  cp -R "$payload/." "$app/Contents/Resources/apertus-local/"
  rm -rf "$payload"
  record_compatibility "$app/Contents/Resources/apertus-local" "$app" --max-macos-minimum "$mac_target"
  if [[ "$sign" -eq 1 ]]; then
    "$REPO_ROOT/scripts/sign_macos.sh" "$app"
  else
    # Seal the complete bundle, including the delivered runtimes and metadata.
    # Developer ID signing and notarization are optional through --sign.
    codesign --force --sign - "$app"
    codesign --verify --deep --strict "$app"
  fi
  archive="$output/$name.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
  if [[ "$sign" -eq 0 ]]; then
    # Keep first-open help beside the app, readable before macOS permits launch.
    python3 - "$REPO_ROOT/packaging/MACOS_FIRST_START.txt" "$stage/MACOS_FIRST_START.txt" "$mac_target" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('@MACOS_MINIMUM@', sys.argv[3]))
PY
    /usr/bin/zip -j "$archive" "$stage/MACOS_FIRST_START.txt"
  fi
else
  record_compatibility "$payload" "$payload/runtime"
  archive="$output/$name.tar.gz"
  tar -czf "$archive" -C "$stage" "$name"
fi
ap_sha256 "$archive" | awk -v name="$(basename "$archive")" '{print $1 "  " name}' > "$archive.sha256"
echo "Package: $archive"
echo "Checksum: $archive.sha256"
