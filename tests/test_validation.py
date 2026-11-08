"""Check gzip UI validation and explicit streamed compute-error reporting."""
import gzip
import http.server
import json
import os
from pathlib import Path
import socketserver
import subprocess
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')


class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            body = b'{"status":"ok"}'
        elif self.path == '/v1/models':
            body = b'{"data":[{"id":"fixture"}]}'
        elif self.path == '/':
            body = gzip.compress(b'<html><script src="/client.js"></script></html>')
        else:
            body = b'console.log("local asset");'
        self.send_response(200)
        if self.path == '/': self.send_header('Content-Encoding','gzip')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length','0')))
        if self.server.compute_error:
            events = [{'error':{'message':'Compute error','code':500}}]
        else:
            events = [{'choices':[{'delta':{'content':'Sarajevo'}}]}, {'usage':{'completion_tokens':1}}]
        body = ''.join('data: '+json.dumps(event)+'\n\n' for event in events).encode()+b'data: [DONE]\n\n'
        self.send_response(200)
        self.send_header('Content-Type','text/event-stream')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self,*args): pass


class ValidationTests(unittest.TestCase):
    def check(self,compute_error):
        server = Server(('127.0.0.1',0),Handler)
        server.compute_error = compute_error
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            return subprocess.run([BASH,str(ROOT/'scripts/validate_local.sh'),'--repeat','1'],
                                  env=dict(os.environ,PORT=str(server.server_port)),
                                  text=True,capture_output=True,timeout=10)
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_gzip_ui_and_streamed_usage(self):
        result = self.check(False)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('Functional validation passed',result.stdout)

    def test_streamed_error_keeps_actual_compute_failure(self):
        result = self.check(True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Compute error',result.stderr)
        self.assertNotIn('empty streamed answer',result.stderr)


if __name__ == '__main__': unittest.main()
