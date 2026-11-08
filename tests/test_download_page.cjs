const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('hf-space/app.js', 'utf8');
const html = fs.readFileSync('hf-space/index.html', 'utf8');
const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map(match => '#' + match[1]));
const config = JSON.parse(fs.readFileSync('hf-space/config.json', 'utf8'));
const targets = Object.keys(config.platforms);
async function render(config, agent = 'Linux', options = {}) {
  const elements = new Map();
  function element(name) {
    assert.ok(ids.has(name), 'Element must exist in the page: ' + name);
    if (!elements.has(name)) elements.set(name, {
      value: name === '#platform' ? 'macos-linux' : '', hidden: false, attrs: {}, handlers: {},
      classList: {toggle() {}}, setAttribute(k,v) {this.attrs[k] = v;},
      removeAttribute(k) {delete this[k]; delete this.attrs[k];},
      addEventListener(event, handler) {this.handlers[event] = handler;},
      focus() {this.focused = true;}, select() {this.selected = true;}
    });
    return elements.get(name);
  }
  vm.runInNewContext(code, {URL, navigator: {userAgent: agent, clipboard: options.clipboard},
    document: {querySelector: element},
    fetch: async () => {
      if (options.fail) throw new Error('offline');
      return {ok: true, json: async () => config};
    }});
  await new Promise(resolve => setImmediate(resolve));
  elements.choose = value => {
    element('#platform').value = value;
    element('#platform').handlers.change();
  };
  return elements;
}
test('the main selector has only macOS / Linux and Windows', () => {
  assert.deepEqual([...html.matchAll(/<option value="([^"]+)">([^<]+)<\/option>/g)]
    .map(match => [match[1], match[2]]), [['macos-linux', 'macOS / Linux'], ['windows', 'Windows']]);
});
test('Mac and Linux share the Terminal command, and Windows uses PowerShell', async () => {
  const mac = await render(config, 'Macintosh');
  const linux = await render(config, 'Linux');
  const windows = await render(config, 'Windows NT 10.0');
  assert.equal(mac.get('#start-command').value, linux.get('#start-command').value);
  assert.match(mac.get('#start-command').value, /bash -c.*\/main\/run\.sh/);
  assert.equal(windows.get('#platform').value, 'windows');
  assert.match(windows.get('#start-command').value, /scriptblock.*\/main\/run\.ps1/);
  assert.match(windows.get('#shell-label').textContent, /PowerShell/);
});
test('switching OS updates the command, copy feedback and visible archive choices', async () => {
  const page = await render(config);
  page.get('#copy-command').textContent = 'Copied';
  page.choose('windows');
  assert.equal(page.get('#copy-command').textContent, 'Copy command');
  for (const target of targets) {
    assert.equal(page.get('#archive-' + target).hidden, !target.startsWith('windows'));
  }
  assert.match(page.get('#command-source').href, /run\.ps1$/);
  page.choose('macos-linux');
  assert.match(page.get('#shell-label').textContent, /Terminal/);
  for (const target of targets) {
    assert.equal(page.get('#archive-' + target).hidden, target.startsWith('windows'));
  }
});
test('all four native archives keep their own URL, checksum, requirements and version', async () => {
  const mixed = structuredClone(config);
  mixed.platforms['macos-arm64'].version = 'earlier-preview';
  const page = await render(mixed);
  for (const target of targets) {
    const release = mixed.platforms[target];
    assert.equal(page.get('#download-' + target).href, release.url);
    assert.equal(page.get('#checksum-' + target).href, release.checksum_url);
    assert.ok(page.get('#requirements-' + target).textContent.includes(release.minimum_os));
    assert.ok(page.get('#requirements-' + target).textContent.includes(release.version));
  }
  assert.equal(page.get('#version').textContent, config.version);
});
test('unreleased groups have no active command or archive links', async () => {
  const unreleased = structuredClone(config);
  for (const release of Object.values(unreleased.platforms)) release.available = false;
  for (const agent of ['Linux', 'Macintosh', 'Windows']) {
    const page = await render(unreleased, agent);
    assert.equal(page.get('#command-panel').hidden, true);
    for (const target of targets) {
      assert.equal(page.get('#download-' + target).attrs['aria-disabled'], 'true');
      assert.equal(page.get('#download-' + target).href, undefined);
      assert.equal(page.get('#checksum-' + target).hidden, true);
    }
  }
});
test('an unavailable package does not hide another ready package in the same group', async () => {
  const partial = structuredClone(config);
  partial.platforms['windows-x86_64'].available = false;
  const page = await render(partial, 'Windows');
  assert.equal(page.get('#download-windows-x86_64').href, undefined);
  assert.equal(page.get('#download-windows-arm64').href, config.platforms['windows-arm64'].url);
  assert.equal(page.get('#command-panel').hidden, false);
});
test('downloads require HTTPS package and checksum URLs and verified model metadata', async () => {
  for (const change of [{url: 'javascript:alert(1)'}, {checksum_url: null}]) {
    const broken = structuredClone(config);
    Object.assign(broken.platforms['linux-x86_64'], change);
    const page = await render(broken);
    assert.equal(page.get('#download-linux-x86_64').href, undefined);
  }
  for (const key of ['model', 'encoders']) {
    for (const change of [{url: null}, {url: 'javascript:alert(1)'}, {sha256: 'bad'}, {bytes: 0}]) {
      const broken = structuredClone(config);
      Object.assign(broken[key], change);
      const page = await render(broken);
      assert.equal(page.get('#command-panel').hidden, true);
      for (const target of targets) assert.equal(page.get('#download-' + target).href, undefined);
    }
  }
});
test('an archive becoming unavailable clears its previous links', async () => {
  const changing = structuredClone(config);
  const page = await render(changing);
  changing.platforms['linux-x86_64'].available = false;
  page.choose('macos-linux');
  assert.equal(page.get('#download-linux-x86_64').href, undefined);
  assert.equal(page.get('#checksum-linux-x86_64').href, undefined);
});
test('configuration failure leaves links disabled and keeps the error after changing OS', async () => {
  const page = await render(config, 'Linux', {fail: true});
  page.choose('windows');
  assert.match(page.get('#status').textContent, /could not be loaded/);
  assert.equal(page.get('#command-panel').hidden, true);
  for (const target of targets) assert.equal(page.get('#download-' + target).href, undefined);
});
test('copying puts the displayed command on the clipboard and announces success', async () => {
  let copied;
  const page = await render(config, 'Windows', {clipboard: {writeText: async value => {copied = value;}}});
  await page.get('#copy-command').handlers.click();
  assert.equal(copied, page.get('#start-command').value);
  assert.equal(page.get('#copy-command').textContent, 'Copied');
  assert.match(page.get('#copy-status').textContent, /PowerShell/);
});
test('blocked clipboard selects the command for manual copying', async () => {
  const page = await render(config);
  await page.get('#copy-command').handlers.click();
  assert.equal(page.get('#start-command').selected, true);
  assert.equal(page.get('#start-command').focused, true);
  assert.match(page.get('#copy-status').textContent, /selected/);
});
test('changing OS while copying cannot label a different command as copied', async () => {
  let resolveCopy;
  const page = await render(config, 'Linux', {clipboard: {writeText: () => new Promise(resolve => {resolveCopy = resolve;})}});
  const copying = page.get('#copy-command').handlers.click();
  page.choose('windows');
  resolveCopy();
  await copying;
  assert.equal(page.get('#copy-command').textContent, 'Copy command');
  assert.equal(page.get('#copy-status').textContent, '');
});
