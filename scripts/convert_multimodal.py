#!/usr/bin/env python3
"""Convert only the pinned source's encoders; never download the language shards.

Developer tool. Run in an environment with llama.cpp's conversion requirements
and huggingface_hub. Participant archives do not include or need Python.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from huggingface_hub import hf_hub_download

ROOT = Path(__file__).resolve().parents[1]
REPO = 'swiss-ai/Apertus-v1.5-8B'
REVISION = '0be762a6a58dad2a3b3f71b2e0f46d34339fa836'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, default=ROOT/'dist/multimodal-source')
    parser.add_argument('--outfile', type=Path, default=ROOT/'models/apertus-v1.5-8b-mmproj-F32.gguf')
    args = parser.parse_args()
    args.source_dir.mkdir(parents=True, exist_ok=True)
    args.outfile.parent.mkdir(parents=True, exist_ok=True)

    def download(name):
        # Use the authenticated HF cache; no tokens are written into this project.
        return Path(hf_hub_download(REPO, name, revision=REVISION))

    original = json.loads(download('model.safetensors.index.json').read_text())
    shards = {file for name, file in original['weight_map'].items()
              if name.startswith(('model.vision_tokenizer.', 'model.audio_tokenizer.encoder.'))
              or name == 'model.audio_tokenizer.quantizer.codebook.embed'}
    if len(shards) != 2:
        raise RuntimeError('Pinned encoder shard layout changed; inspect before converting')
    import shutil
    for name in ['config.json', 'processor_config.json', *sorted(shards)]:
        shutil.copyfile(download(name), args.source_dir/name)
    (args.source_dir/'original-model.safetensors.index.json').write_text(json.dumps(original, indent=2))
    # Index all tensors physically in these shards, including unused audio decoder
    # tensors. The converter filters them later and verifies shard completeness.
    reduced = {'metadata': {'total_size': sum((args.source_dir/f).stat().st_size for f in shards)},
               'weight_map': {n: f for n, f in original['weight_map'].items() if f in shards}}
    (args.source_dir/'model.safetensors.index.json').write_text(json.dumps(reduced, indent=2))
    subprocess.run([sys.executable, str(ROOT/'vendor/llama.cpp/convert_hf_to_gguf.py'),
                    str(args.source_dir), '--mmproj', '--outtype', 'f32',
                    '--model-name', 'Apertus-v1.5-8B', '--outfile', str(args.outfile)], check=True)
    digest = hashlib.sha256()
    with args.outfile.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024), b''):
            digest.update(chunk)
    print(json.dumps({'source': REPO, 'revision': REVISION, 'file': str(args.outfile),
                      'bytes': args.outfile.stat().st_size, 'sha256': digest.hexdigest()}, indent=2))


if __name__ == '__main__':
    main()
