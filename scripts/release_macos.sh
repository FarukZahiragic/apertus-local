#!/usr/bin/env bash
# Build a versioned Apple Silicon app on a Mac or a GitHub-hosted Mac runner.
# Usage: scripts/release_macos.sh --version VERSION [--unsigned] [--check]
# Signed builds read MACOS_CERTIFICATE_P12_BASE64, MACOS_CERTIFICATE_PASSWORD,
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD from the environment.
# Credentials use a temporary keychain and are removed on success or failure.
# --unsigned prepares a development artifact; it is not a public workshop app.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
version='' signed=1 check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || { echo 'error: --version needs a value' >&2; exit 1; }; version="$2"; shift ;;
    --unsigned) signed=0 ;;
    --check) check=1 ;;
    -h|--help) sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/!p; }' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
pattern='^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$'
[[ "$version" =~ $pattern ]] || { echo 'error: use --version v0.1.0-preview.2 (or another unused version)' >&2; exit 1; }
[[ "$(uname -s) $(uname -m)" == 'Darwin arm64' ]] || { echo 'error: release builds require native Apple Silicon macOS; use the GitHub Mac runner' >&2; exit 1; }
if [[ "$signed" -eq 1 ]]; then
  missing=0
  for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    if [[ -z "${!name:-}" ]]; then echo "error: missing release credential $name" >&2; missing=1; fi
  done
  [[ "$missing" -eq 0 ]] || exit 1
fi
output="${OUTPUT_DIR:-$REPO_ROOT/dist/release}"
archive="$output/apertus-local-$version-macos-arm64.zip"
[[ ! -e "$archive" && ! -e "$archive.sha256" ]] || { echo 'error: release output already exists; choose an unused version or output directory' >&2; exit 1; }
if [[ "$check" -eq 1 ]]; then echo "Mac release configuration checked: $version; signing=$signed"; exit 0; fi
work="$(mktemp -d "${TMPDIR:-/tmp}/apertus-release.XXXXXX")"
keychain=''
original_keychains=()
cleanup() {
  if [[ -n "$keychain" ]]; then
    security list-keychains -d user -s "${original_keychains[@]+"${original_keychains[@]}"}" >/dev/null 2>&1 || true
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$signed" -eq 1 ]]; then
  previous_umask="$(umask)"
  umask 077
  while IFS= read -r line; do
    line="${line#*\"}"; line="${line%\"*}"
    [[ -z "$line" ]] || original_keychains+=("$line")
  done < <(security list-keychains -d user)
  keychain="$work/signing.keychain-db"
  keychain_password="$(openssl rand -hex 24)"
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then echo "::add-mask::$keychain_password"; fi
  printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$work/certificate.p12"
  echo 'Importing the Developer ID certificate into a temporary keychain.'
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$work/certificate.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -t cert -f pkcs12 \
    -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
  security list-keychains -d user -s "$keychain" "${original_keychains[@]+"${original_keychains[@]}"}"
  MACOS_SIGN_IDENTITY="$(security find-identity -v -p codesigning "$keychain" | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p')"
  [[ -n "$MACOS_SIGN_IDENTITY" && "$MACOS_SIGN_IDENTITY" != *$'\n'* ]] || {
    echo 'error: the P12 must contain exactly one valid Developer ID Application certificate and its private key' >&2; exit 1;
  }
  export MACOS_SIGN_IDENTITY MACOS_KEYCHAIN="$keychain" MACOS_NOTARY_PROFILE=apertus-local-release
  echo 'Checking Apple notarization credentials.'
  xcrun notarytool store-credentials "$MACOS_NOTARY_PROFILE" --keychain "$keychain" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
  rm -f "$work/certificate.p12"
  umask "$previous_umask"
fi
echo "Building portable CPU and Metal runtimes for $version."
scripts/setup_llamacpp.sh --cpu --portable
scripts/setup_llamacpp.sh --metal --portable
arguments=(--version "$version")
if [[ "$signed" -eq 1 ]]; then arguments+=(--sign); fi
OUTPUT_DIR="$output" scripts/package_release.sh "${arguments[@]}"
if [[ "$signed" -eq 1 ]]; then
  # Check the delivered ZIP, rather than only the app before archiving.
  ditto -x -k "$archive" "$work/delivered"
  app="$work/delivered/Apertus Local.app"
  codesign --verify --deep --strict "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute "$app"
  echo 'Signed archive and stapled notarization ticket verified.'
else
  echo 'Unsigned development archive ready. Public Mac downloads still require signing.'
fi
