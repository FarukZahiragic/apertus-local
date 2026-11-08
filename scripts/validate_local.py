#!/usr/bin/env python3
# Shared cross-platform functional validator. Participants do not need Python.
import argparse, datetime, gzip, json, os, platform, urllib.parse, urllib.request
from html.parser import HTMLParser
from pathlib import Path
parser = argparse.ArgumentParser(description='Validate local Apertus UI/API inference; does not disable networking.')
parser.add_argument('--repeat', type=int, default=1)
parser.add_argument('--max-tokens', type=int, default=16)
parser.add_argument('--report', default='')
parser.add_argument('--hardware', default=os.environ.get('HARDWARE_LABEL', platform.platform()))
args = parser.parse_args()
repeat, tokens = args.repeat, args.max_tokens
if repeat <= 0 or tokens <= 0 or not 1 <= int(os.environ.get('PORT','8080')) <= 65535:
    parser.error('repeat, max-tokens and PORT must be valid positive integers')
base = 'http://127.0.0.1:' + os.environ.get('PORT','8080')
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
timeout = float(os.environ.get('VALIDATION_TIMEOUT','300'))
def get(path):
    request = urllib.request.Request(base + path, headers={'Accept-Encoding':'gzip'})
    return opener.open(request, timeout=timeout)
def read(response):
    body = response.read()
    return gzip.decompress(body) if response.headers.get('Content-Encoding') == 'gzip' else body
with get('/health') as response:
    assert json.load(response)['status'] == 'ok', 'server not healthy'
with get('/') as response:
    html = read(response).decode()
    assert '<html' in html.lower(), 'missing chat UI'
class Assets(HTMLParser):
    paths = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        path = attrs.get('src') if tag == 'script' else attrs.get('href') if tag == 'link' and attrs.get('rel') == 'stylesheet' else None
        if path:
            self.paths.append(path)
assets = Assets()
assets.feed(html)
for path in assets.paths:
    if path.startswith('data:'):
        continue
    absolute = urllib.parse.urljoin(base + '/', path)
    assert urllib.parse.urlsplit(absolute).netloc == urllib.parse.urlsplit(base).netloc, 'UI loads external asset: ' + path
    request = urllib.request.Request(absolute, headers={'Accept-Encoding':'gzip'})
    with opener.open(request, timeout=timeout) as response:
        assert read(response), 'empty UI asset'
with get('/v1/models') as response:
    model = json.load(response)['data'][0]['id']
def ask(prompt):
    body = dict(model=model, messages=[{'role':'user','content':prompt}], max_tokens=tokens,
                temperature=0, stream=True, stream_options={'include_usage':True}, cache_prompt=True)
    request = urllib.request.Request(base+'/v1/chat/completions', data=json.dumps(body).encode(), headers={'Content-Type':'application/json'})
    text, usage = '', None
    with opener.open(request, timeout=timeout) as response:
        for line in response:
            line = line.decode().strip()
            if not line.startswith('data:') or line == 'data: [DONE]':
                continue
            event = json.loads(line[5:])
            if event.get('error'):
                raise RuntimeError('server inference error: ' + json.dumps(event['error']))
            if event.get('choices'):
                text += event['choices'][0].get('delta',{}).get('content') or ''
            if event.get('usage'):
                usage = event['usage']
    assert text.strip(), 'empty streamed answer'
    assert usage and usage['completion_tokens'] > 0, 'missing final token usage'
    return text.strip()
answer = ask('Document: The workshop takes place in Sarajevo.\nQuestion: Which city hosts the workshop? Answer with only the city name.')
assert 'sarajevo' in answer.lower(), 'document question failed: ' + answer
print('Health, embedded UI assets, streamed usage and document Q&A passed.', flush=True)
for index in range(repeat):
    ask('Say hello in English in a short sentence.')
    print(f'Reliability {index+1}/{repeat} passed', flush=True)
result = {'date':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'hardware':args.hardware,
          'model':model, 'repeat':repeat, 'max_tokens':tokens, 'ui_assets_checked':len(assets.paths),
          'settings':{key:os.environ[key] for key in ['BACKEND','GPU_LAYERS','LOAD_MODE','THREADS','CTX'] if key in os.environ},
          'document_answer':answer, 'network_isolation':'not established by this script', 'status':'passed'}
if args.report:
    path = Path(args.report); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result,indent=2)+'\n')
print('Functional validation passed. Complete the network-disabled hardware rehearsal separately.')
