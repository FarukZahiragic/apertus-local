#!/usr/bin/env bash
# Sign a packaged app, submit it for notarization and staple the accepted ticket.
# Usage: MACOS_SIGN_IDENTITY=... MACOS_NOTARY_PROFILE=... scripts/sign_macos.sh APP
# The profile must already exist in the macOS keychain. Credentials stay outside git.
set -euo pipefail
[[ "$(uname -s)" == Darwin && $# -eq 1 && -d "$1/Contents" ]] || { echo 'error: provide a macOS app bundle on a Mac' >&2; exit 1; }
: "${MACOS_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${MACOS_NOTARY_PROFILE:?Set a notarytool keychain profile}"
app="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Signing $app"
while IFS= read -r -d '' binary; do
  codesign --force --options runtime --timestamp --sign "$MACOS_SIGN_IDENTITY" "$binary"
done < <(find "$app/Contents/Resources/apertus-local/runtime" -type f \( -name '*.dylib' -o -name 'llama-*' \) -print0)
python3 - "$app/Contents/Resources/apertus-local" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root/'release.json').read_text())
manifest['signing'] = 'signed-and-notarized'
manifest['files'] = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sorted(root.rglob('*'))
                     if p.is_file() and not p.is_symlink() and p.name != 'release.json'}
(root/'release.json').write_text(json.dumps(manifest, indent=2)+'\n')
PY
codesign --force --options runtime --timestamp --entitlements "$REPO_ROOT/packaging/macos-entitlements.plist" --sign "$MACOS_SIGN_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
work="$(mktemp -d "${TMPDIR:-/tmp}/apertus-notary.XXXXXX")"
trap 'rm -rf "$work"' EXIT
ditto -c -k --keepParent "$app" "$work/notarize.zip"
echo 'Submitting to Apple notarization; waiting for the result.'
xcrun notarytool submit "$work/notarize.zip" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
spctl --assess --type execute "$app"
echo 'Notarization and Gatekeeper assessment passed.'
