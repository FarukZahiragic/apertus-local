#!/usr/bin/env python3
"""Real image, image-follow-up and audio checks against an already running server."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import struct
import time
import urllib.request
import zlib


def square_png(color, size=2048):
    """A large input exercises runtime resizing, without an imaging dependency."""
    white = b'\xff\xff\xff'
    edge = size//8
    blank = b'\0' + white*size
    colored = b'\0' + white*edge + bytes(color)*(size-2*edge) + white*edge
    pixels = blank*edge + colored*(size-2*edge) + blank*edge

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:'+os.environ.get('PORT', '8080'))
    parser.add_argument('--report', type=Path, default=Path('dist/validation-multimodal.json'))
    args = parser.parse_args()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    report = {'status': 'failed', 'checks': [], 'hardware': os.environ.get('HARDWARE_LABEL', 'local machine')}

    def chat(messages, expected, name, max_tokens=32):
        payload = {'messages': messages, 'max_tokens': max_tokens, 'temperature': 0, 'cache_prompt': True}
        request = urllib.request.Request(args.url+'/v1/chat/completions', data=json.dumps(payload).encode(),
                                         headers={'Content-Type': 'application/json'})
        start = time.monotonic()
        with opener.open(request, timeout=600) as response:
            result = json.load(response)
        message = result['choices'][0]['message']
        answer = message.get('content', '')
        assert all(re.search(r'\b'+re.escape(word)+r'\b', answer.lower()) for word in expected), (name, answer)
        # Two 2048-square photos should each be resized to 256 image codes,
        # plus row/frame/prompt tokens. Without patch 0005 this exceeds 1000.
        if name.startswith('image-'):
            assert result['usage']['prompt_tokens'] < 650, ('Image budget ignored', result['usage'])
        report['checks'].append({'name': name, 'answer': answer, 'elapsed_s': time.monotonic()-start,
                                  'usage': result.get('usage'), 'timings': result.get('timings')})
        print(name+': '+answer, flush=True)
        return message

    try:
        with opener.open(args.url+'/props', timeout=10) as response:
            report['modalities'] = json.load(response)['modalities']
        assert report['modalities']['vision'] and report['modalities']['audio'], report['modalities']
        for color, rgb in [('red', (255,0,0)), ('blue', (0,0,255))]:
            image = base64.b64encode(square_png(rgb)).decode()
            messages = [{'role': 'user', 'content': [
                {'type': 'text', 'text': 'What color is the square? Answer in one word.'},
                {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,'+image}}]}]
            message = chat(messages, [color], 'image-'+color)
            if color == 'blue':
                chat(messages+[message, {'role': 'user', 'content': 'What shape was it? Answer in one word.'}],
                     ['square'], 'image-follow-up')
        audio = base64.b64encode((Path(__file__).resolve().parents[1]/'tests/fixtures/speech.wav').read_bytes()).decode()
        chat([{'role': 'user', 'content': [
            {'type': 'text', 'text': 'Transcribe the spoken words in this audio.'},
            {'type': 'input_audio', 'input_audio': {'data': audio, 'format': 'wav'}}]}],
             ['new', 'york', 'times', '1969'], 'audio-transcription', max_tokens=96)
        report['status'] = 'passed'
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
