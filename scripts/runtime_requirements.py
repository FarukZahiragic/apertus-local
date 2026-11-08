#!/usr/bin/env python3
"""Record real binary compatibility floors instead of a build-host OS label."""
import argparse
import json
from pathlib import Path
import re
import struct
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('root', type=Path)
parser.add_argument('--max-macos-minimum')
args = parser.parse_args()
versions = {'GLIBC': [], 'GLIBCXX': [], 'CXXABI': []}
mac_versions = []
architectures = set()
count = 0

def version(value):
    return tuple(map(int, value.split('.')))

def mach(data):
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = magic[-1] == 0xBF
        for index in range(struct.unpack_from('>I', data, 4)[0]):
            item = struct.unpack_from('>IIQQII' if wide else '>5I', data, 8+index*(32 if wide else 20))
            mach(data[item[2]:item[2]+item[3]])
        return
    assert magic == b'\xcf\xfa\xed\xfe'
    header = struct.unpack_from('<8I', data)
    architectures.add({0x100000C: 'arm64', 0x1000007: 'x86_64'}.get(header[1], hex(header[1])))
    position = 32
    for _ in range(header[4]):
        command, size = struct.unpack_from('<II', data, position)
        if command in (0x32, 0x24):
            value = struct.unpack_from('<I', data, position+(12 if command == 0x32 else 8))[0]
            mac_versions.append((value >> 16, (value >> 8) & 255, value & 255))
        position += size

seen = set()
for path in args.root.rglob('*'):
    if not path.is_file() or path.resolve() in seen:
        continue
    seen.add(path.resolve())
    with path.open('rb') as source:
        magic = source.read(4)
    if magic == b'\x7fELF':
        count += 1
        machine = struct.unpack_from('<H', path.read_bytes(), 18)[0]
        architectures.add({62:'x86_64', 183:'arm64'}.get(machine, f'elf:{machine}'))
        symbols = subprocess.check_output(['objdump', '-T', str(path)], text=True)
        for line in symbols.splitlines():
            if '*UND*' in line:
                for kind, value in re.findall(r'\b(GLIBCXX|GLIBC|CXXABI)_([0-9.]+)\b', line):
                    versions[kind].append(version(value))
    elif magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        count += 1
        mach(path.read_bytes())
assert count, 'No native binaries found'
result = {'architectures': sorted(architectures), 'checked_binaries': count}
if mac_versions:
    minimum = max(mac_versions)
    if args.max_macos_minimum:
        maximum = version(args.max_macos_minimum)
        maximum += (0,) * (3-len(maximum))
        assert minimum <= maximum, f'A binary needs macOS {minimum}, above intended target {maximum}'
    result.update(system='macos', minimum_macos='.'.join(map(str, minimum)))
else:
    result.update(system='linux', **{
        {'GLIBC':'minimum_glibc', 'GLIBCXX':'minimum_glibcxx', 'CXXABI':'minimum_cxxabi'}[kind]: '.'.join(map(str, max(values)))
        for kind, values in versions.items() if values
    })
print(json.dumps(result, indent=2))
