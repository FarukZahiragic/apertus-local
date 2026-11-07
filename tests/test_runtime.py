"""Verify backend selection through the public serving entry point."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('TEST_BASH', 'bash')


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='apertus runtime ')
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'model.gguf').touch()
        server = self.root / 'bin/llama-server'
        server.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                          'if "--list-devices" in sys.argv:\n'
                          ' print(os.environ.get("TEST_DEVICES", "Available devices:"))\n'
                          'else:\n print(json.dumps(sys.argv[1:]))\n')
        server.chmod(0o755)
        self.env = dict(os.environ, BUILD_DIR=str(self.root), MODEL=str(self.root / 'model.gguf'),
                        THREADS='2', BACKEND='auto')

    def tearDown(self):
        self.temp.cleanup()

    def serve(self, **env):
        return subprocess.run([BASH, str(ROOT / 'scripts/serve.sh')],
                              env=dict(self.env, **env), text=True, capture_output=True)

    def test_cpu_settings_preserve_explicit_overrides(self):
        result = self.serve(CTX='2048', THINKING='1', LOAD_MODE='none')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        for flag, value in [('--threads', '2'), ('--ctx-size', '2048'), ('--n-gpu-layers', '0'), ('--load-mode','none')]:
            self.assertEqual(args[args.index(flag) + 1], value)
        self.assertIn('--offline', args)
        self.assertIn('Runtime:    cpu', result.stdout)

    def test_explicit_metal_requires_real_device(self):
        result = self.serve(BACKEND='metal')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no metal device', result.stderr)

    def test_explicit_metal_selects_offload(self):
        result = self.serve(BACKEND='metal', TEST_DEVICES='MTL0: Apple M2', GPU_LAYERS='8')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(args[args.index('--n-gpu-layers') + 1], '8')

    def test_invalid_runtime_settings_fail_before_start(self):
        for setting in [{'BACKEND': 'unknown'}, {'THREADS': '0'}, {'CTX': '-1'}, {'PORT': '99999'}, {'THINKING': 'yes'}, {'LOAD_MODE':'bad'}, {'BACKEND':'metal','GPU_LAYERS':'0'}]:
            with self.subTest(setting=setting):
                result = self.serve(**setting)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('error:', result.stderr)

    def test_auto_metal_requires_validation_and_available_device(self):
        shims = self.root / 'shims'
        shims.mkdir()
        for name, content in {
            'uname': 'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac',
        }.items():
            path = shims / name
            path.write_text('#!/bin/sh\n'+content+'\n')
            path.chmod(0o755)
        overrides = dict(PATH=str(shims)+os.pathsep+os.environ['PATH'], TEST_DEVICES='MTL0: Apple M2')
        result = self.serve(**overrides, APERTUS_METAL_VALIDATED='0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Runtime:    cpu', result.stdout)
        result = self.serve(**overrides, APERTUS_METAL_VALIDATED='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Runtime:    metal', result.stdout)
        overrides['TEST_DEVICES'] = 'Available devices: (none)'
        result = self.serve(**overrides, APERTUS_METAL_VALIDATED='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('auto mode selected CPU', result.stderr)


if __name__ == '__main__':
    unittest.main()
