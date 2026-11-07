"""Exercise real curl/checksums, interrupted downloads and Darwin detection."""
import hashlib
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')
PAYLOAD = b'GGUF workshop download fixture\n' * 512


class RangeServer(http.server.BaseHTTPRequestHandler):
    requests = 0

    def do_GET(self):
        type(self).requests += 1
        offset = int(self.headers.get('Range', 'bytes=0-')[6:].split('-')[0])
        self.send_response(206 if offset else 200)
        if offset:
            self.send_header('Content-Range', f'bytes {offset}-{len(PAYLOAD)-1}/{len(PAYLOAD)}')
        self.send_header('Content-Length', str(len(PAYLOAD) - offset))
        self.end_headers()
        self.wfile.write(PAYLOAD[offset:])

    def log_message(self, *args):
        pass


class PortabilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), RangeServer)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def download(self, directory, digest=None):
        env = dict(os.environ, MODELS_DIR=str(directory),
                   MODEL_URL=f'http://127.0.0.1:{self.server.server_port}/fixture.gguf',
                   MODEL_SHA256=digest or hashlib.sha256(PAYLOAD).hexdigest(),
                   MODEL_BYTES=str(len(PAYLOAD)))
        return subprocess.run([BASH, str(ROOT / 'scripts/get_model.sh'), 'fixture/repo', 'fixture.gguf'],
                              env=env, capture_output=True, text=True)

    def test_resume_verify_and_offline_reuse(self):
        with tempfile.TemporaryDirectory(prefix='apertus download ') as directory:
            directory = Path(directory)
            (directory / 'fixture.gguf.part').write_bytes(PAYLOAD[:137])
            result = self.download(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((directory / 'fixture.gguf').read_bytes(), PAYLOAD)
            self.assertFalse((directory / 'fixture.gguf.part').exists())
            count = RangeServer.requests
            result = self.download(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(RangeServer.requests, count, 'cached model must not contact server')

    def test_corrupt_download_never_becomes_model(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.download(directory, '0' * 64)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('checksum mismatch', result.stderr)
            self.assertFalse((Path(directory) / 'fixture.gguf').exists())
            self.assertFalse((Path(directory) / 'fixture.gguf.download-lock').exists())

    def test_darwin_hardware_without_proc_or_nproc(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = {
                'uname': 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac',
                'sysctl': 'case "$2" in hw.perflevel0.physicalcpu) echo 4;; hw.memsize) echo 17179869184;; machdep.cpu.brand_string) echo "Apple M2";; *) exit 1;; esac',
                'sw_vers': 'echo 14.0',
            }
            for name, script in commands.items():
                path = Path(directory) / name
                path.write_text('#!/bin/sh\n' + script + '\n')
                path.chmod(0o755)
            result = subprocess.run([BASH, str(ROOT / 'scripts/platform.sh')],
                                    env=dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH']),
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Mac: Apple M2, 16 GB', result.stdout)
            self.assertIn('Suggested CPU threads: 4', result.stdout)


if __name__ == '__main__':
    unittest.main()
