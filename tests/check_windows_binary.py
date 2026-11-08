"""Check architecture and avoid a hidden Visual C++/OpenMP installer dependency."""
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
expected = {'x64': 0x8664, 'arm64': 0xAA64}[sys.argv[2]]
files = [*root.glob('*.exe'), *root.glob('*.dll')]
available = {path.name.lower() for path in files}
assert files, 'No Windows runtime files'
for path in files:
    data = path.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    assert data[pe:pe+4] == b'PE\0\0', path
    machine, sections = struct.unpack_from('<HH', data, pe+4)
    assert machine == expected, f'Wrong architecture: {path}'
    optional_size = struct.unpack_from('<H', data, pe+20)[0]
    optional = pe+24
    assert struct.unpack_from('<H', data, optional)[0] == 0x20B
    imports = struct.unpack_from('<I', data, optional+120)[0]
    def offset(rva):
        for index in range(sections):
            section = optional+optional_size+index*40
            virtual_size, start, size, position = struct.unpack_from('<IIII', data, section+8)
            if start <= rva < start+max(size, virtual_size):
                return position+rva-start
        raise AssertionError(f'Unknown PE address {rva}: {path}')
    dependencies = []
    if imports:
        entry = offset(imports)
        while any(data[entry:entry+20]):
            name = offset(struct.unpack_from('<I', data, entry+12)[0])
            dependencies.append(data[name:data.index(b'\0', name)].decode().lower())
            entry += 20
    for name in dependencies:
        if name.startswith(('vcruntime', 'msvcp', 'libomp', 'libiomp', 'ggml', 'llama', 'common')):
            assert name in available, f'Missing app-local runtime DLL: {path}: {name}'
    print(path.name + ': ' + ', '.join(dependencies))
print(f'{len(files)} Windows runtime files passed architecture/dependency checks.')
