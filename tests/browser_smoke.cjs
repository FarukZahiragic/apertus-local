#!/usr/bin/env node
// Real-time browser readiness: virtual time can finish before IndexedDB starts.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const [chrome, url, output = 'dist/offline-ui.html'] = process.argv.slice(2);
if (!chrome || !url) throw new Error('usage: browser_smoke.cjs CHROME URL [DOM_FILE]');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'apertus-browser-'));
const browser = spawn(chrome, [
  '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
  '--disable-background-networking', '--no-first-run', '--disable-extensions',
  `--user-data-dir=${profile}`, '--remote-debugging-pipe', 'about:blank'
], { stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'] });
let nextId = 0;
let buffer = '';
let diagnostics = '';
const pending = new Map();
browser.stderr.on('data', chunk => { diagnostics += chunk.toString(); });
browser.stdio[4].on('data', chunk => {
  buffer += chunk.toString();
  let end;
  while ((end = buffer.indexOf('\0')) !== -1) {
    const message = JSON.parse(buffer.slice(0, end));
    buffer = buffer.slice(end + 1);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject, timer } = pending.get(message.id);
      pending.delete(message.id);
      clearTimeout(timer);
      if (message.error) reject(new Error(JSON.stringify(message.error)));
      else resolve(message.result);
    } else if (message.method === 'Runtime.exceptionThrown') {
      diagnostics += JSON.stringify(message) + '\n';
    }
  }
});
function call(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`browser command timed out: ${method}`));
    }, 10000);
    pending.set(id, { resolve, reject, timer });
    browser.stdio[3].write(JSON.stringify({ id, method, params, sessionId }) + '\0');
  });
}
async function main() {
  const { targetId } = await call('Target.createTarget', { url });
  const { sessionId } = await call('Target.attachToTarget', { targetId, flatten: true });
  await call('Runtime.enable', {}, sessionId);
  await call('Runtime.runIfWaitingForDebugger', {}, sessionId);
  await call('Debugger.disable', {}, sessionId);
  const deadline = Date.now() + 30000;
  let loaded = false;
  while (Date.now() < deadline) {
    const { result, exceptionDetails } = await call('Runtime.evaluate', {
      expression: `({html: document.documentElement.outerHTML,
        ready: /apertus/i.test(document.body.innerText) && !!document.querySelector('textarea')})`,
      returnByValue: true
    }, sessionId);
    if (exceptionDetails) diagnostics += JSON.stringify(exceptionDetails) + '\n';
    if (result.value) {
      fs.writeFileSync(output, result.value.html);
      if (result.value.ready) { loaded = true; break; }
    }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  if (!loaded) throw new Error('browser did not render the Apertus chat input and model');
  console.log('Actual browser rendered the Apertus chat input and model.');
}
main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
}).finally(async () => {
  try { await call('Browser.close'); } catch { browser.kill('SIGTERM'); }
  fs.writeFileSync(path.join(path.dirname(output), 'offline-browser.log'), diagnostics);
  fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
});
