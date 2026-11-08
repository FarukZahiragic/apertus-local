"""Exercise credential cleanup and release failures; Apple services are fixtures."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')
CREDENTIALS = {
    'MACOS_CERTIFICATE_P12_BASE64': base64.b64encode(b'fixture certificate').decode(),
    'MACOS_CERTIFICATE_PASSWORD': 'fixture-p12-password',
    'APPLE_ID': 'fixture@example.invalid',
    'APPLE_TEAM_ID': 'FIXTURETEAM',
    'APPLE_APP_PASSWORD': 'fixture-app-password',
}


class MacReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='apertus release ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['scripts', 'bin', 'tmp']:
            (self.root/folder).mkdir()
        shutil.copy2(ROOT/'scripts/release_macos.sh', self.root/'scripts/release_macos.sh')
        self.env = dict(os.environ, PATH=str(self.root/'bin') + os.pathsep + os.environ['PATH'],
                        TMPDIR=str(self.root/'tmp'), TEST_RELEASE_ROOT=str(self.root), GITHUB_ACTIONS='false')
        for name in CREDENTIALS:
            self.env.pop(name, None)
        for name in ['OUTPUT_DIR', 'MACOS_SIGN_IDENTITY', 'MACOS_NOTARY_PROFILE', 'MACOS_KEYCHAIN']:
            self.env.pop(name, None)
        self.executable('bin/uname', '#!/bin/sh\ncase "$1" in -s) echo Darwin;; -m) echo arm64;; esac\n')
        self.executable('bin/security', '''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['TEST_RELEASE_ROOT'])
with (root/'events.jsonl').open('a') as f:
    f.write(json.dumps({'command': args[0], 'keys': args[args.index('-s')+1:] if args[0]=='list-keychains' and '-s' in args else []})+'\\n')
if args[0] == 'list-keychains' and '-s' not in args:
    print('    "/Users/test/Library/Keychains/login keychain-db"')
elif args[0] == 'create-keychain': pathlib.Path(args[-1]).touch()
elif args[0] == 'delete-keychain': pathlib.Path(args[-1]).unlink()
elif args[0] == 'find-identity': print('  1) FIXTURE "Developer ID Application: Fixture (FIXTURETEAM)"')
''')
        self.executable('bin/xcrun', '''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['TEST_RELEASE_ROOT'])
with (root/'events.jsonl').open('a') as f:
    f.write(json.dumps({'command': 'xcrun', 'operation': sys.argv[1:3]})+'\\n')
if sys.argv[1:3] == ['notarytool', 'store-credentials']:
    assert pathlib.Path(sys.argv[sys.argv.index('--keychain')+1]).exists()
    if os.environ.get('TEST_NOTARY_REJECT'): raise SystemExit(27)
''')
        self.executable('bin/codesign', '#!/bin/sh\nexit 0\n')
        self.executable('bin/spctl', '#!/bin/sh\nexit 0\n')
        self.executable('bin/ditto', '#!/bin/sh\nmkdir -p "$4/Apertus Local.app/Contents"\n')
        self.executable('scripts/setup_llamacpp.sh', '''#!/bin/sh
printf 'build %s %s\\n' "$1" "$2" >> "$TEST_RELEASE_ROOT/build.log"
''')
        self.executable('scripts/package_release.sh', '''#!/bin/sh
if [ "${TEST_PACKAGE_FAIL:-}" = 1 ]; then exit 9; fi
mkdir -p "$OUTPUT_DIR"
touch "$OUTPUT_DIR/apertus-local-$2-macos-arm64.zip"
touch "$OUTPUT_DIR/apertus-local-$2-macos-arm64.zip.sha256"
printf '%s\\n' "${3:-unsigned}" > "$TEST_RELEASE_ROOT/package.log"
''')

    def executable(self, name, content):
        path = self.root/name
        path.write_text(content)
        path.chmod(0o755)

    def run_release(self, *args, credentials=False, **env):
        environment = dict(self.env)
        if credentials:
            environment.update(CREDENTIALS)
        environment.update(env)
        signing = ['--sign'] if credentials else []
        result = subprocess.run([BASH, str(self.root/'scripts/release_macos.sh'), '--version',
                                 'v0.1.0-preview.2', *signing, *args], env=environment,
                                text=True, capture_output=True, timeout=20)
        for name in ['MACOS_CERTIFICATE_PASSWORD', 'APPLE_APP_PASSWORD']:
            self.assertNotIn(CREDENTIALS[name], result.stdout + result.stderr)
        return result

    def events(self):
        return [json.loads(line) for line in (self.root/'events.jsonl').read_text().splitlines()]

    def assert_credentials_cleaned(self):
        self.assertEqual(list((self.root/'tmp').iterdir()), [])
        events = self.events()
        self.assertEqual(events[-1]['command'], 'delete-keychain')
        self.assertEqual(events[-2]['keys'], ['/Users/test/Library/Keychains/login keychain-db'])

    def test_missing_credentials_stop_before_build_or_keychain(self):
        result = self.run_release('--sign')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing release credential MACOS_CERTIFICATE_P12_BASE64', result.stderr)
        self.assertFalse((self.root/'events.jsonl').exists())
        self.assertFalse((self.root/'build.log').exists())
        self.assertEqual(list((self.root/'tmp').iterdir()), [])

    def test_unsigned_candidate_needs_no_credentials_and_preserves_existing_output(self):
        checked = self.run_release('--check')
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertFalse((self.root/'build.log').exists())
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root/'events.jsonl').exists())
        archive = self.root/'dist/release/apertus-local-v0.1.0-preview.2-macos-arm64.zip'
        archive.write_text('previous artifact')
        again = self.run_release('--unsigned')
        self.assertNotEqual(again.returncode, 0)
        self.assertEqual(archive.read_text(), 'previous artifact')

    def test_notary_credential_rejection_cleans_up_before_build(self):
        result = self.run_release(credentials=True, TEST_NOTARY_REJECT='1')
        self.assertEqual(result.returncode, 27, result.stdout + result.stderr)
        self.assertFalse((self.root/'build.log').exists())
        self.assert_credentials_cleaned()

    def test_success_and_package_failure_restore_previous_keychains(self):
        result = self.run_release(credentials=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root/'package.log').read_text(), '--sign\n')
        self.assertEqual((self.root/'build.log').read_text().splitlines(),
                         ['build --cpu --portable', 'build --metal --portable'])
        self.assert_credentials_cleaned()
        result = self.run_release(credentials=True, TEST_PACKAGE_FAIL='1',
                                  OUTPUT_DIR=str(self.root/'other output'))
        self.assertEqual(result.returncode, 9, result.stdout + result.stderr)
        self.assert_credentials_cleaned()


class NotarizationTests(unittest.TestCase):
    def test_rejected_submission_never_staples_even_when_tool_exits_zero(self):
        with tempfile.TemporaryDirectory(prefix='apertus rejected notary ') as directory:
            root = Path(directory)
            app = root/'Apertus Local.app'
            payload = app/'Contents/Resources/apertus-local'
            (payload/'runtime/cpu/bin').mkdir(parents=True)
            (payload/'release.json').write_text('{}')
            tools = root/'bin'
            tools.mkdir()
            for name in ['uname', 'codesign', 'ditto', 'spctl', 'xcrun']:
                path = tools/name
                path.write_text({
                    'uname': '#!/bin/sh\necho Darwin\n',
                    'codesign': '#!/bin/sh\nexit 0\n',
                    'ditto': '#!/bin/sh\nexit 0\n',
                    'spctl': '#!/bin/sh\ntouch "$TEST_STAPLED"\n',
                    'xcrun': '''#!/bin/sh
if [ "$1 $2" = 'notarytool submit' ]; then
  printf '{"status":"Invalid","id":"fixture"}\\n'
else
  touch "$TEST_STAPLED"
fi
''',
                }[name])
                path.chmod(0o755)
            env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'],
                       MACOS_SIGN_IDENTITY='Developer ID Application: Fixture',
                       MACOS_NOTARY_PROFILE='fixture', TEST_STAPLED=str(root/'stapled'))
            result = subprocess.run([BASH, str(ROOT/'scripts/sign_macos.sh'), str(app)],
                                    env=env, text=True, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Apple did not accept', result.stderr)
            self.assertFalse((root/'stapled').exists())


if __name__ == '__main__':
    unittest.main()
