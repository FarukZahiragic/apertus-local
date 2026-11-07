"""Check standalone Mac setup without installing tools or downloading weights."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')
GIT = shutil.which('git')


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='apertus setup ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root/'bin'
        self.bin.mkdir()
        # The only delivered file lives outside the project, in a path with spaces.
        self.script = self.root/'sent setup.sh'
        shutil.copy2(ROOT/'setup.sh', self.script)
        self.install = self.root/'installed project'
        self.calls = self.root/'calls'
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        APERTUS_INSTALL_DIR=str(self.install),
                        APERTUS_SETUP_LOG=str(self.root/'setup.log'),
                        SETUP_TEST_CALLS=str(self.calls), BACKEND='cpu')
        self.stub('uname', 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac')
        self.stub('sysctl', 'echo 17179869184')
        self.stub('xcrun', 'echo /fixture/AppleTools')
        self.stub('cmake', 'exit 0')

    def stub(self, name, body):
        file = self.bin/name
        file.write_text('#!/bin/bash\nset -euo pipefail\n'+body+'\n')
        file.chmod(0o755)

    def fixture(self, directory):
        scripts = directory/'scripts'
        scripts.mkdir(parents=True)
        for name in ['platform.sh', 'setup_llamacpp.sh', 'get_model.sh']:
            (scripts/name).write_text('#!/bin/bash\nset -euo pipefail\n'
                                     'printf "%s|%s|%s\\n" "$PWD" "${0##*/}" "$*" >> "$SETUP_TEST_CALLS"\n')
        (directory/'Start.command').write_text('#!/bin/bash\nset -euo pipefail\n'
                                              'echo "started:$BACKEND" >> "$SETUP_TEST_CALLS"\n')
        subprocess.run([GIT, 'init', '-q', str(directory)], check=True)
        subprocess.run([GIT, '-C', str(directory), 'remote', 'add', 'origin',
                        'https://github.com/FarukZahiragic/apertus-local'], check=True)
        subprocess.run([GIT, '-C', str(directory), '-c', 'user.name=Test',
                        '-c', 'user.email=test@example.invalid', 'commit', '-q',
                        '--allow-empty', '-m', 'Fixture'], check=True)

    def run_setup(self, *args):
        return subprocess.run([BASH, str(self.script), *args], env=self.env,
                              capture_output=True, text=True, timeout=20)

    def test_standalone_clone_and_default_cpu_start(self):
        template = self.root/'template'
        self.fixture(template)
        self.env['SETUP_TEST_TEMPLATE'] = str(template)
        self.env['SETUP_TEST_REAL_GIT'] = GIT
        self.stub('git', '''if [[ "$1" == clone ]]; then
  [[ "$2 $3 $4" == '--branch feat/macos-setup --single-branch' ]]
  [[ "$5" == https://github.com/FarukZahiragic/apertus-local ]]
  cp -R "$SETUP_TEST_TEMPLATE" "$6"
else
  exec "$SETUP_TEST_REAL_GIT" "$@"
fi''')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        calls = self.calls.read_text()
        self.assertIn(str(self.install)+'|setup_llamacpp.sh|--cpu', calls)
        self.assertIn(str(self.install)+'|setup_llamacpp.sh|--metal', calls)
        self.assertIn('|get_model.sh|--apertus', calls)
        self.assertIn('started:cpu', calls)
        self.assertTrue((self.root/'setup.log').exists())

    def test_existing_checkout_keeps_edits_and_can_prepare_without_start(self):
        self.fixture(self.install)
        edited = self.install/'notes.txt'
        edited.write_text('Keep my local work.\n')
        before = subprocess.check_output([GIT, '-C', str(self.install), 'status', '--porcelain'])
        result = self.run_setup('--no-start')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(edited.read_text(), 'Keep my local work.\n')
        self.assertEqual(subprocess.check_output([GIT, '-C', str(self.install), 'status', '--porcelain']), before)
        self.assertNotIn('started:', self.calls.read_text())

    def test_unrelated_existing_folder_is_preserved(self):
        self.install.mkdir()
        sentinel = self.install/'important.txt'
        sentinel.write_text('Keep this.\n')
        result = self.run_setup('--no-start')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('nothing was overwritten', result.stdout+result.stderr)
        self.assertEqual(sentinel.read_text(), 'Keep this.\n')
        self.assertFalse(self.calls.exists())

    def test_unsupported_platform_exits_before_installing(self):
        self.stub('uname', 'case "$1" in -s) echo Linux;; -m) echo x86_64;; esac')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Apple Silicon Mac', result.stderr)
        self.assertFalse(self.install.exists())
        self.assertFalse((self.root/'setup.log').exists())

    def test_missing_apple_tools_do_not_wait_without_a_terminal(self):
        self.stub('xcrun', 'exit 1')
        self.stub('xcode-select', 'echo apple-install-requested >> "$SETUP_TEST_CALLS"')
        result = self.run_setup('--no-start')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('run this file again in Terminal', result.stdout+result.stderr)
        self.assertEqual(self.calls.read_text(), 'apple-install-requested\n')
        self.assertFalse(self.install.exists())


if __name__ == '__main__':
    unittest.main()
