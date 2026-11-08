const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('hf-space/app.js', 'utf8');
async function render(config, agent = 'Linux', userAgentData) {
  const elements = new Map();
  function element(name) {
    if (!elements.has(name)) elements.set(name, {value:'macos-arm64', hidden:false, attrs:{},
      classList:{toggle(){}}, setAttribute(k,v){this.attrs[k]=v;}, removeAttribute(k){delete this[k];},
      addEventListener(){}, replaceChildren(child){this.child=child;}});
    return elements.get(name);
  }
  vm.runInNewContext(code, {URL, navigator:{userAgent:agent,userAgentData},
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
test('Mac preview explains first-open approval and exposes its installation guide',async()=>{
  const page=await render(config,'Macintosh');
  assert.equal(page.get('#mac-guide').hidden,false);
  assert.match(page.get('#open-instructions').textContent,/Open Anyway/);
  assert.match(page.get('#platform-note').textContent,/No Apple Developer membership/);
  const linux=await render(config,'Linux');
  assert.equal(linux.get('#mac-guide').hidden,true);
  const guide=fs.readFileSync('hf-space/macos-first-start.html','utf8');
  assert.match(guide,/Privacy &amp; Security/);
  assert.match(guide,/Open Anyway/);
});
test('Windows downloads use the Windows label and first-start guide',async()=>{
  const ready=structuredClone(config);
  ready.platforms['windows-x86_64']={available:true,url:'https://example.org/windows.zip',checksum_url:'https://example.org/windows.sha256',minimum_os:'Windows 10 or later'};
  const page=await render(ready,'Windows NT 10.0');
  assert.equal(page.get('#download').href,'https://example.org/windows.zip');
  assert.match(page.get('#download').textContent,/Download for Windows/);
  assert.match(page.get('#platform-note').textContent,/Windows 10 or later/);
  assert.match(page.get('#open-instructions').textContent,/Start.cmd/);
  assert.equal(page.get('#windows-guide').hidden,false);
  assert.equal(page.get('#mac-guide').hidden,true);
});
test('Windows ARM detection chooses the native archive when the browser reports it',async()=>{
  const ready=structuredClone(config);
  ready.platforms['windows-arm64']={available:true,url:'https://example.org/arm64.zip',checksum_url:'https://example.org/arm64.sha256'};
  const page=await render(ready,'Windows NT 10.0',{getHighEntropyValues:async()=>({architecture:'arm',bitness:'64'})});
  assert.equal(page.get('#platform').value,'windows-arm64');
  assert.equal(page.get('#download').href,'https://example.org/arm64.zip');
});
