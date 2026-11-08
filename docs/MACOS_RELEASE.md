# Prepare and publish the Mac download

The source setup and a fresh offline start passed on the friend's physical Apple
Silicon Mac, as reported by the project owner on 7 November 2026. Formal CPU/Metal
benchmarks can follow later; they do not block a conservative CPU-default package.
The next acceptance check concerns opening the **downloaded app**, which also
exercises macOS distribution checks and the Terminal automation prompt.

The current distribution path is an **unsigned preview**. Neither the publisher
nor participants need Apple Developer membership or signing credentials. The app
retains an ad-hoc code seal needed for bundle integrity; that seal does not establish
an Apple-verified publisher or notarization. macOS may require per-app first-open
approval. Keep system-wide security checks enabled.

GitHub's Apple Silicon runner builds the app without a connected physical Mac.
Participants receive both runtimes and do not install Homebrew, Python or compiler
tools. The ZIP includes `MACOS_FIRST_START.txt` beside the app. The download page
links to [the participant guide](../hf-space/macos-first-start.html).

Signing and notarization remain an optional future distribution choice. Skip the
credential section below when preparing the unsigned preview.

## Optional signing credentials

Use the Apple Developer Program account that will identify the publisher. Creating
a Developer ID certificate through the portal requires the Account Holder role.
This is the **Developer ID Application** certificate, used for apps distributed
outside the Mac App Store. An Apple Development or Developer ID Installer
certificate is a different certificate and will not satisfy this release script.
See [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).

If the account already has this certificate and its private key on a Mac, export
both together from Keychain Access > My Certificates as a password-protected `.p12`
file. Use that file in the upload step below. A `.cer` alone lacks the private key.

If there is no existing certificate, the following preparation can be done from
Linux, without borrowing the Mac again. Keep these files outside the project:

```bash
mkdir -p "$HOME/apertus-signing"
chmod 700 "$HOME/apertus-signing"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -aes-256-cbc \
  -out "$HOME/apertus-signing/developer-id.key.pem"
```

Choose a private-key password when prompted. Then create the request; enter the
email address used for the Apple Developer account:

```bash
read -r -p 'Apple account email: ' signing_email
openssl req -new -sha256 \
  -key "$HOME/apertus-signing/developer-id.key.pem" \
  -out "$HOME/apertus-signing/developer-id.certSigningRequest" \
  -subj "/CN=Apertus Local/emailAddress=$signing_email"
```

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list):

1. Click **+** to create a certificate.
2. Choose **Developer ID**, then **Developer ID Application**.
3. Upload `developer-id.certSigningRequest` from the folder above.
4. Download the resulting certificate and save it as
   `~/apertus-signing/developer-id.cer`.

Convert it and combine it with the matching private key. The export asks for the
private-key password, then a new P12 export password; keep the export password for
the GitHub secret below. These encoding options support Apple's P12 importer.

```bash
openssl x509 -inform DER \
  -in "$HOME/apertus-signing/developer-id.cer" \
  -out "$HOME/apertus-signing/developer-id.cert.pem"
openssl pkcs12 -export \
  -inkey "$HOME/apertus-signing/developer-id.key.pem" \
  -in "$HOME/apertus-signing/developer-id.cert.pem" \
  -out "$HOME/apertus-signing/developer-id.p12" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
```

For notarization, obtain these three values:

- **Apple ID:** the email address for the Developer Program account.
- **Team ID:** the identifier shown under membership details in the
  [developer account](https://developer.apple.com/account/).
- **App-specific password:** at [Apple Account](https://account.apple.com/), open
  **Sign-In and Security > App-Specific Passwords**, generate one named
  `Apertus Local notarization`, and copy it for the secret upload. Use this generated
  password for notarization. See [Apple's notarization authentication guide](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

Upload the five repository secrets from a trusted computer with `gh` authenticated
to this repository. These commands read values from stdin or a hidden prompt;
credentials stay out of git, chat, command history and release artifacts.
For an exported P12 elsewhere, substitute its path in the first command.

```bash
base64 < "$HOME/apertus-signing/developer-id.p12" | \
  gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo FarukZahiragic/apertus-local
gh secret set MACOS_CERTIFICATE_PASSWORD --repo FarukZahiragic/apertus-local
gh secret set APPLE_ID --repo FarukZahiragic/apertus-local
gh secret set APPLE_TEAM_ID --repo FarukZahiragic/apertus-local
gh secret set APPLE_APP_PASSWORD --repo FarukZahiragic/apertus-local
```

The P12 secret holds the certificate **and private key**. GitHub masks secret
values in logs. The runner imports them into a temporary keychain, restores its
previous keychain search list and removes temporary credentials on success or
failure. The approach follows [GitHub's Mac signing guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

## Run the release workflow

The **Native deployment checks** workflow accepts `macos_release_version` and
`sign_macos_release`. Once this branch is available to Actions, run:

```bash
gh workflow run native.yml --repo FarukZahiragic/apertus-local \
  --ref feat/unsigned-macos-download \
  -f macos_release_version=v0.1.0-preview.2 \
  -f sign_macos_release=false
```

Use `--ref main` after the implementation PRs merge. Dispatch of the registered
native workflow on implementation branches has been verified while the PR stack is
under review. If the web UI does not show its new inputs yet, use the CLI command
above. No signing secrets are used by pull-request CI jobs.

In the GitHub UI, open **Actions > Native deployment checks > Run workflow**, select
the implementation branch (or `main` after merge), enter the version, and leave
signing disabled. Choose an unused version; existing release assets are preserved.

The workflow checks the scripts, builds portable CPU and Metal runtimes, verifies
the ad-hoc code seal, checks the delivered archive, and tests actual Apertus inference
through the extracted app's launch scripts. The hosted runner's Metal check uses eight GPU
layers and packed weights because it has only 7 GB RAM. This is a functional VM
check, not a physical-Mac speed measurement. A successful run creates a
**draft** GitHub prerelease with the ZIP and its SHA-256 checksum.

The unsigned route also retains an Actions artifact. The
[first candidate run](https://github.com/FarukZahiragic/apertus-local/actions/runs/42422097790)
passed, including real CPU and partial Metal inference from the extracted app.
Its `macos-release-v0.1.0-preview.2` artifact contains the 19.6 MB ZIP, checksum
and inference reports. All 55 payload hashes and the archive hash were checked
after downloading it; no model weights are bundled. This is a development
candidate with an ad-hoc code seal, not a Developer ID signed release.
Set `sign_macos_release=true` only if opting into the optional Developer ID route:
it imports the five Apple secrets, signs, requires an accepted notarization response,
and staples/verifies the ticket. No real Apple signing has been claimed as passed.
Run `gh run list --workflow native.yml` to find the run,
then `gh run watch RUN_ID --exit-status` to follow it.

On a local Mac, the unsigned default needs no Apple environment variables:

```bash
scripts/release_macos.sh --version v0.1.0-preview.2
```

Output: `dist/release/apertus-local-v0.1.0-preview.2-macos-arm64.zip` and `.sha256`.
Model weights are downloaded separately on first launch. CPU remains the default;
this release does not change automatic Metal selection or advertise a measured Mac
speed. An interrupted Apple submission may need its submission ID checked before
rerunning; the ID and response are printed in the signing log.

## Download check and Hugging Face availability

When a Mac is available, download the preview's ZIP through a browser, extract it,
and open **Apertus Local.app** from Finder. If macOS blocks this unsigned app,
use **System Settings > Privacy & Security > Open Anyway** for that app and confirm.
Follow `MACOS_FIRST_START.txt`. Allow Terminal automation if asked.
Confirm that the browser opens chat, an answer completes, and Control+C stops it.
This checks the packaged app; the earlier `setup.sh` rehearsal checked the source
installation. The same prepared GGUF can be copied into
`~/Library/Application Support/Apertus Local/models/` to avoid another download.

An unsigned preview may be published with the pending Finder-opening rehearsal
clearly labelled. Complete that rehearsal before treating it as workshop-ready.
Publish the draft and verify the public ZIP and checksum URLs from an
unauthenticated connection. In `hf-space/config.json`, change only the Mac entry
to its tested versioned download URLs, set `available` to `true`, and update its
status and the top-level version. Retain the Linux entry's existing versioned URLs.
Publish the updated page with `scripts/publish_hf.sh --space-only`.

The current Space hosts the verified model and Linux preview. Its Mac entry labels
the unsigned preview and links to first-open instructions. Neither payment nor an
Apple Developer account is required by this path.
Formal CPU/Metal benchmark numbers can be added after publication; they are
required for performance claims and broader automatic-acceleration defaults,
rather than for making the conservative package available.
