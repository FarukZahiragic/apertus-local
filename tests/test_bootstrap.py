"""Exercise standalone setup, trusted archives, file reuse and offline entry points."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import threading
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', '/bin/bash')
POWERSHELL = os.environ.get('TEST_POWERSHELL') or shutil.which('pwsh') or shutil.which('powershell.exe')
MODEL = 'apertus-v1.5-8b-Q4_K_M.gguf'


class BootstrapFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="apertus bootstrap's ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.data = self.root / 'local data'
        self.calls = self.root / 'calls'
        self.requests = []
        self.archive_bytes = b''
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                fixture.requests.append(self.headers.get('Range', 'full'))
                start = int(self.headers.get('Range', 'bytes=0-')[6:-1])
                content = fixture.archive_bytes[start:]
                self.send_response(206 if start else 200)
                self.send_header('Content-Length', str(len(content)))
                if start:
                    self.send_header('Content-Range', f'bytes {start}-{len(fixture.archive_bytes)-1}/{len(fixture.archive_bytes)}')
                self.end_headers()
                self.wfile.write(content)

            def log_message(self, *args):
                pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.env = dict(os.environ, APERTUS_INSTALL_DIR=str(self.data),
                        APERTUS_PACKAGE_URL=f'http://127.0.0.1:{self.server.server_port}/runtime',
                        BOOTSTRAP_TEST_CALLS=str(self.calls))
        for key in ('MODEL', 'MODEL_SHA256', 'MODELS_DIR', 'APERTUS_RUNTIME_DIR', 'APERTUS_STATE_DIR'):
            self.env.pop(key, None)

    def publish_archive(self, path):
        self.archive_bytes = path.read_bytes()
        self.env['APERTUS_PACKAGE_SHA256'] = hashlib.sha256(self.archive_bytes).hexdigest()

    def run_command(self, command, **kwargs):
        return subprocess.run(command, env=self.env, cwd=self.root,
                              capture_output=True, text=True, timeout=30, **kwargs)


@unittest.skipUnless(os.name != 'nt' and Path(BASH).exists(), 'requires POSIX Bash')
class PosixBootstrapTests(BootstrapFixture):
    def setUp(self):
        super().setUp()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env['PATH'] = str(self.bin) + os.pathsep + os.environ['PATH']
        self.env['HOME'] = str(self.root / 'home')
        self.stub('uname', 'case "$1" in -s) echo Linux;; -m) echo x86_64;; esac')
        self.stub('git', 'echo "unexpected git" >&2; exit 99')
        self.stub('brew', 'echo "unexpected brew" >&2; exit 99')
        self.stub('cmake', 'echo "unexpected cmake" >&2; exit 99')
        self.payload = self.root / 'payload'
        self.make_payload(self.payload)
        self.make_archive()

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -euo pipefail\n' + body + '\n')
        path.chmod(0o755)

    def make_payload(self, root):
        for directory in ('scripts', 'config', 'runtime/cpu/bin'):
            (root / directory).mkdir(parents=True)
        (root / 'config/model.env').write_text('fixture\n')
        (root / 'scripts/launch.sh').write_text('''#!/bin/bash
set -euo pipefail
printf 'launch:%s|models:%s|model:%s|multimodal:%s\\n' "$*" "$MODELS_DIR" "${MODEL:-}" "$MULTIMODAL" >> "$BOOTSTRAP_TEST_CALLS"
''')
        (root / 'scripts/get_model.sh').write_text('''#!/bin/bash
set -euo pipefail
echo "model:$*|models:$MODELS_DIR" >> "$BOOTSTRAP_TEST_CALLS"
if [[ "${BOOTSTRAP_FAIL_MODEL:-0}" != 0 ]]; then exit 1; fi
mkdir -p "$MODELS_DIR"
''')
        server = root / 'runtime/cpu/bin/llama-server'
        server.write_text('#!/bin/bash\nexit 0\n')
        server.chmod(0o755)

    def make_archive(self, mac=False):
        path = self.root / ('runtime.zip' if mac else 'runtime.tar.gz')
        if mac:
            with zipfile.ZipFile(path, 'w') as archive:
                for file in self.payload.rglob('*'):
                    if file.is_file():
                        info = zipfile.ZipInfo('Apertus Local.app/Contents/Resources/apertus-local/' + str(file.relative_to(self.payload)))
                        info.external_attr = file.stat().st_mode << 16
                        archive.writestr(info, file.read_bytes())
        else:
            with tarfile.open(path, 'w:gz') as archive:
                archive.add(self.payload, arcname='apertus-local-v0.1.0-preview.3-linux-x86_64')
        self.publish_archive(path)

    def run_setup(self, *args, inline=False):
        if inline:
            return self.run_command([BASH, '-c', (ROOT / 'run.sh').read_text(), 'apertus', *args])
        return self.run_command([BASH, str(ROOT / 'run.sh'), *args])

    def test_fresh_inline_setup_and_no_browser_launch(self):
        result = self.run_setup('--no-browser', inline=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests, ['full'])
        self.assertIn('launch:--no-browser', self.calls.read_text())
        self.assertIn('multimodal:0', self.calls.read_text())
        self.assertTrue((self.data / 'start.sh').exists())
        self.assertFalse(list((self.data / 'downloads').glob('*')))

    def test_repeated_setup_reuses_runtime_without_networking(self):
        first = self.run_setup('--prepare-only')
        self.assertEqual(first.returncode, 0, first.stderr)
        self.stub('curl', 'echo "network must not be used" >&2; exit 99')
        second = self.run_setup('--no-browser')
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(self.requests, ['full'])

    def test_offline_start_preserves_quoted_paths_and_arguments(self):
        result = self.run_setup('--prepare-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.stub('curl', 'exit 99')
        result = self.run_command([BASH, str(self.data / 'start.sh'), '--stop'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('launch:--stop|models:' + str(self.data / 'models'), self.calls.read_text())

    def test_package_hash_mismatch_never_runs_payload(self):
        self.env['APERTUS_PACKAGE_SHA256'] = '0' * 64
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum mismatch', result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertFalse(list((self.data / 'downloads').glob('*')))
        self.assertFalse((self.data / '.bootstrap-lock').exists())

    def test_resume_and_completed_partial_recovery(self):
        downloads = self.data / 'downloads'
        downloads.mkdir(parents=True)
        partial = downloads / 'apertus-local-v0.1.0-preview.3-linux-x86_64.tar.gz.part'
        partial.write_bytes(self.archive_bytes[:100])
        result = self.run_setup('--prepare-only')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests, ['bytes=100-'])

    def test_completed_partial_does_not_download_again(self):
        downloads = self.data / 'downloads'
        downloads.mkdir(parents=True)
        (downloads / 'apertus-local-v0.1.0-preview.3-linux-x86_64.tar.gz.part').write_bytes(self.archive_bytes)
        self.stub('curl', 'exit 99')
        result = self.run_setup('--prepare-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests, [])

    def test_explicit_runtime_and_model_require_no_download(self):
        model = self.root / "model's file.gguf"
        model.write_bytes(b'fixture model')
        self.env.update(APERTUS_RUNTIME_DIR=str(self.payload), MODEL=str(model),
                        MODEL_SHA256=hashlib.sha256(model.read_bytes()).hexdigest())
        self.stub('curl', 'exit 99')
        result = self.run_setup('--prepare-only')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_command([BASH, str(self.data / 'start.sh')])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('model:' + str(model), self.calls.read_text())
        self.assertEqual(self.requests, [])

    def test_existing_model_directory_is_reused(self):
        models = self.root / 'models'
        models.mkdir()
        (models / MODEL).write_bytes(b'model')
        result = self.run_setup('--prepare-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('models:' + str(models), self.calls.read_text())

    def test_prepared_checkout_is_detected_without_downloading_runtime(self):
        checkout = Path(self.env['HOME']) / 'apertus-1.5-local'
        self.make_payload(checkout)
        (checkout / 'config/model.env').write_text('APERTUS_MODEL_SHA256=e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c\n')
        self.stub('curl', 'exit 99')
        result = self.run_setup('--no-browser')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests, [])
        self.assertIn('Reusing the local runtime: ' + str(checkout), result.stdout)

    def test_unrecognized_runtime_is_preserved(self):
        runtime = self.data / 'packages/linux-x86_64-v0.1.0-preview.3'
        runtime.mkdir(parents=True)
        sentinel = runtime / 'keep.txt'
        sentinel.write_text('Keep this.')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('nothing was overwritten', result.stderr)
        self.assertEqual(sentinel.read_text(), 'Keep this.')
        self.assertEqual(self.requests, [])

    def test_model_failure_keeps_verified_runtime_for_retry(self):
        self.env['BOOTSTRAP_FAIL_MODEL'] = '1'
        first = self.run_setup('--prepare-only')
        self.assertNotEqual(first.returncode, 0)
        self.env['BOOTSTRAP_FAIL_MODEL'] = '0'
        second = self.run_setup('--prepare-only')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.requests, ['full'])

    def test_unsupported_architecture_exits_before_writing(self):
        self.stub('uname', 'case "$1" in -s) echo Linux;; -m) echo aarch64;; esac')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.data.exists())
        self.assertEqual(self.requests, [])

    def test_mac_extracts_runtime_without_opening_app(self):
        self.stub('uname', 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac')
        self.make_archive(mac=True)
        self.stub('ditto', '''exec python3 - "$3" "$4" <<'PY'
import sys, zipfile, pathlib
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2])
    for item in archive.infolist():
        pathlib.Path(sys.argv[2], item.filename).chmod(item.external_attr >> 16)
PY''')
        self.stub('open', 'echo "app opening must not be used" >&2; exit 99')
        result = self.run_setup('--no-browser')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('launch:--no-browser', self.calls.read_text())
        self.assertFalse(list(self.data.rglob('*.app')))


@unittest.skipUnless(POWERSHELL, 'PowerShell is not installed')
class WindowsBootstrapTests(BootstrapFixture):
    def setUp(self):
        super().setUp()
        self.env.update(OS='Windows_NT', PROCESSOR_ARCHITECTURE='AMD64',
                        LOCALAPPDATA=str(self.root / 'appdata'), USERPROFILE=str(self.root / 'home'))
        self.env.pop('PROCESSOR_ARCHITEW6432', None)
        self.package = self.root / 'runtime.zip'
        module = '''function Invoke-Apertus {
    param([string]$Root, [switch]$GetModel)
    if ($env:MULTIMODAL -ne '0') { throw 'Bootstrap must not fetch optional encoders' }
    [IO.File]::AppendAllText($env:BOOTSTRAP_TEST_CALLS, "model:$env:MODELS_DIR`n")
}
'''
        with zipfile.ZipFile(self.package, 'w') as archive:
            archive.writestr('scripts/windows/Apertus.psm1', module)
            archive.writestr('scripts/windows/launch.ps1', '# fixture\n')
            archive.writestr('runtime/cpu/bin/llama-server.exe', b'fixture')
        self.publish_archive(self.package)

    def run_setup(self, inline=False):
        expression = ('& ([scriptblock]::Create([IO.File]::ReadAllText($env:BOOTSTRAP_SCRIPT))) -PrepareOnly'
                      if inline else '& $env:BOOTSTRAP_SCRIPT -PrepareOnly')
        self.env['BOOTSTRAP_SCRIPT'] = str(ROOT / 'run.ps1')
        return self.run_command([POWERSHELL, '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
                                 "$ErrorActionPreference='Stop'; " + expression])

    def test_fresh_inline_windows_setup(self):
        result = self.run_setup(inline=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests, ['full'])
        self.assertTrue((self.data / 'Start.cmd').exists())
        self.assertTrue((self.data / 'Stop.cmd').exists())
        self.assertIn('model:' + str(self.data / 'models'), self.calls.read_text())
        self.assertIn('Sysnative', (self.data / 'Start.cmd').read_text())
        self.assertIn("$env:MULTIMODAL = '0'", (self.data / 'start.ps1').read_text(encoding='utf-8-sig'))
        self.assertIn("bootstrap''s", (self.data / 'start.ps1').read_text(encoding='utf-8-sig'))

    def test_windows_reuses_verified_runtime(self):
        first = self.run_setup()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        second = self.run_setup()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(self.requests, ['full'])

    def test_windows_bad_hash_never_runs_model_download(self):
        self.env['APERTUS_PACKAGE_SHA256'] = '0' * 64
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('checksum mismatch', result.stderr)
        self.assertFalse(self.calls.exists())

    def test_windows_arm64_uses_native_package(self):
        self.env['PROCESSOR_ARCHITECTURE'] = 'ARM64'
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.data / 'packages/windows-arm64-v0.1.0-preview.4').exists())


if __name__ == '__main__':
    unittest.main()
