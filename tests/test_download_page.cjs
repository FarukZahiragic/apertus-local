const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('hf-space/app.js', 'utf8');
async function render(config, agent = 'Linux') {
  const elements = new Map();
  function element(name) {
    if (!elements.has(name)) elements.set(name, {value:'macos-arm64', hidden:false, attrs:{},
      classList:{toggle(){}}, setAttribute(k,v){this.attrs[k]=v;}, removeAttribute(k){delete this[k];},
      addEventListener(){}, replaceChildren(child){this.child=child;}});
    return elements.get(name);
  }
  vm.runInNewContext(code, {URL, navigator:{userAgent:agent},
    document:{querySelector:element, createElement:()=>({})},
    fetch:async()=>({ok:true,json:async()=>config})});
  await new Promise(resolve=>setImmediate(resolve));
  return elements;
}
const config = JSON.parse(fs.readFileSync('hf-space/config.json','utf8'));
test('unreleased platforms have no active download links', async()=>{
  const unreleased = structuredClone(config);
  for (const release of Object.values(unreleased.platforms)) release.available = false;
  for (const agent of ['Linux','Macintosh','Windows']) {
    const page = await render(unreleased, agent);
    assert.equal(page.get('#download').attrs['aria-disabled'], 'true');
    assert.equal(page.get('#download').href, undefined);
  }
});
test('download requires package, checksum and published model', async()=>{
  const ready = structuredClone(config);
  ready.model.url='https://huggingface.co/example/model/resolve/pin/model.gguf';
  ready.platforms['linux-x86_64']={available:true,url:'https://example.org/app.tar.gz',checksum_url:'https://example.org/app.sha256'};
  let page=await render(ready);
  assert.equal(page.get('#download').href,'https://example.org/app.tar.gz');
  ready.platforms['linux-x86_64'].checksum_url=null;
  page=await render(ready);
  assert.equal(page.get('#download').href,undefined);
});
test('download links reject non-HTTPS schemes',async()=>{
  const unsafe=structuredClone(config);
  unsafe.model.url='https://example.org/model.gguf';
  unsafe.platforms['linux-x86_64']={available:true,url:'javascript:alert(1)',checksum_url:'https://example.org/app.sha256'};
  const page=await render(unsafe);
  assert.equal(page.get('#download').href,undefined);
});
