#!/usr/bin/env python3
"""Check first launch and cached restart through the one-command entry point."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--install-dir', required=True)
parser.add_argument('--port', type=int, default=18089)
parser.add_argument('--timeout', type=int, default=900)
args = parser.parse_args()
data = Path(args.install_dir).resolve()
windows = os.name == 'nt'
shell = shutil.which('powershell.exe') if windows else '/bin/bash'
env = dict(os.environ, APERTUS_INSTALL_DIR=str(data), PORT=str(args.port),
           CTX='512', THREADS='2', BACKEND='cpu')
env.pop('BUILD_DIR', None)
env.pop('MODEL', None)
env.pop('MODEL_SHA256', None)
env.pop('APERTUS_RUNTIME_DIR', None)
env.pop('APERTUS_PACKAGE_URL', None)
env.pop('APERTUS_PACKAGE_SHA256', None)
output = ROOT / 'dist'
output.mkdir(exist_ok=True)
process = None
handle = None


def command(first=False, stop=False):
    if windows:
        script = ROOT / 'run.ps1' if first else data / 'start.ps1'
        return [shell, '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', str(script), '-Stop' if stop else '-NoBrowser']
    script = ROOT / 'run.sh' if first else data / 'start.sh'
    return [shell, str(script), '--stop' if stop else '--no-browser']


def stop_owned():
    global process, handle
    if process is not None:
        result = subprocess.run(command(stop=True), env=env, cwd=ROOT,
                                capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise RuntimeError('Cached stop failed: ' + result.stdout + result.stderr)
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=10)
            raise RuntimeError('Bootstrap did not exit after owned stop')
        if process.returncode:
            raise RuntimeError(f'Bootstrap exited with code {process.returncode}')
        process = None
    if handle:
        handle.close()
        handle = None


try:
    for first in (True, False):
        label = 'first-start' if first else 'cached-restart'
        log = output / f'bootstrap-{label}.log'
        handle = log.open('w')
        process = subprocess.Popen(command(first=first), env=env, cwd=ROOT,
                                   stdout=handle, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            text = log.read_text(errors='replace')
            if 'Ready: http://127.0.0.1:' in text:
                break
            if process.poll() is not None:
                raise RuntimeError(f'{label} exited early:\n{text[-8000:]}')
            time.sleep(1)
        else:
            raise RuntimeError(f'{label} timed out:\n{log.read_text(errors="replace")[-8000:]}')
        report = output / f'bootstrap-{label}.json'
        subprocess.run([sys.executable, str(ROOT / 'scripts/validate_local.py'),
                        '--max-tokens', '8', '--report', str(report)],
                       env=env, cwd=ROOT, check=True, timeout=300)
        stop_owned()
    print('One-command setup, actual model/UI/API, owned stop and cached restart passed.', flush=True)
finally:
    if process is not None:
        try:
            stop_owned()
        except Exception:
            process.terminate()
            process.wait(timeout=10)
            if handle:
                handle.close()
