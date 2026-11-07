"""Check launcher readiness, exclusive ownership and shutdown with a local server."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='apertus launcher ')
        self.root = Path(self.temp.name)
        (self.root/'bin').mkdir()
        (self.root/'model.gguf').touch()
        server = self.root/'bin/llama-server'
        server.write_text('''#!/usr/bin/env python3
import http.server, os, socketserver, sys
if '--list-devices' in sys.argv:
    print('MTL0: Apple M2')
    raise SystemExit(0)
if os.environ.get('TEST_START_FAILURE') in ('1', os.environ.get('BACKEND')):
    print('intentional startup failure', flush=True)
    raise SystemExit(7)
port = int(sys.argv[sys.argv.index('--port') + 1])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        failure = os.environ.get('TEST_COMPUTE_FAILURE') == os.environ.get('BACKEND')
        self.send_response(500 if failure else 200)
        self.end_headers()
        self.wfile.write(b'{"error":"Compute error"}' if failure else b'{"content":"Hello"}')
    def log_message(self, *args): pass
class Server(http.server.HTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]
server = Server(('127.0.0.1', port), Handler)
print(f'listening on http://127.0.0.1:{port}', flush=True)
server.serve_forever()
''')
        server.chmod(0o755)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            self.port = sock.getsockname()[1]
        self.env = dict(os.environ, BACKEND='cpu', BUILD_DIR=str(self.root),
                        MODEL=str(self.root/'model.gguf'), THREADS='1', PORT=str(self.port),
                        APERTUS_STATE_DIR=str(self.root/'state'), STARTUP_TIMEOUT='30')
        self.process = None

    def tearDown(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=8)
        self.temp.cleanup()

    def exercise_start_stop(self):
        output = self.root/'launcher.log'
        with output.open('w') as log:
            self.process = subprocess.Popen([BASH, str(ROOT/'scripts/launch.sh'), '--no-browser'],
                                            env=self.env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 45
            while 'Ready:' not in output.read_text() and time.monotonic() < deadline:
                if self.process.poll() is not None:
                    self.fail(output.read_text())
                time.sleep(.05)
            self.assertIn('Ready:', output.read_text())
            duplicate = subprocess.run([BASH, str(ROOT/'scripts/launch.sh'), '--no-browser'],
                                       env=self.env, capture_output=True, text=True, timeout=5)
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn('another launcher', duplicate.stderr)
            stop = subprocess.run([BASH, str(ROOT/'scripts/launch.sh'), '--stop'],
                                  env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(stop.returncode, 0, stop.stderr)
            self.assertEqual(self.process.wait(timeout=5), 0)
            self.assertFalse((self.root/f'state/port-{self.port}').exists())
            with socket.socket() as sock:
                self.assertNotEqual(sock.connect_ex(('127.0.0.1', self.port)), 0)
        return output.read_text()

    def test_ready_then_stop_releases_owned_server(self):
        self.exercise_start_stop()

    def test_auto_metal_start_failure_retries_cpu(self):
        self.exercise_auto_retry('TEST_START_FAILURE')

    def test_auto_metal_compute_failure_retries_cpu(self):
        self.exercise_auto_retry('TEST_COMPUTE_FAILURE')

    def exercise_auto_retry(self, failure):
        shims = self.root/'shims'
        shims.mkdir()
        for name, code in {
            'uname': 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac',
            'sysctl': 'case "$2" in hw.memsize) echo 17179869184;; machdep.cpu.brand_string) echo "Apple M2";; *) echo 4;; esac',
            'sw_vers': 'echo 14.0',
        }.items():
            path = shims/name
            path.write_text('#!/bin/sh\n'+code+'\n')
            path.chmod(0o755)
        for backend in ['build','build-metal']:
            destination = self.root/backend/'bin'
            destination.mkdir(parents=True)
            (destination/'llama-server').symlink_to(self.root/'bin/llama-server')
        self.env.pop('BUILD_DIR')
        self.env.update(BACKEND='auto', LLAMA_CPP_DIR=str(self.root), APERTUS_METAL_VALIDATED='1',
                        PATH=str(shims)+os.pathsep+os.environ['PATH'])
        self.env[failure] = 'metal'
        log = self.exercise_start_stop()
        self.assertIn('Selected: metal', log)
        self.assertIn('retrying on CPU', log)

    def test_startup_failure_preserves_log_and_releases_lock(self):
        result = subprocess.run([BASH, str(ROOT/'scripts/launch.sh'), '--no-browser'],
                                env=dict(self.env, TEST_START_FAILURE='1'),
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('intentional startup failure', result.stderr)
        self.assertFalse((self.root/f'state/port-{self.port}').exists())
        self.assertTrue((self.root/f'state/server-{self.port}-cpu.log').exists())


if __name__ == '__main__':
    unittest.main()
