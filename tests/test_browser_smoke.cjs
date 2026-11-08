const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('browser cleanup waits for the owned process to finish profile writes', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'apertus browser cleanup '));
  try {
    const fake = path.join(root, 'fake chrome');
    fs.writeFileSync(fake, `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const profile = process.argv.find(a => a.startsWith('--user-data-dir=')).split('=').slice(1).join('=');
fs.writeFileSync(process.env.TEST_PROFILE_FILE, profile);
let buffer = '';
fs.createReadStream(null, {fd: 3}).on('data', chunk => {
  buffer += chunk.toString();
  let end;
  while ((end = buffer.indexOf('\\0')) !== -1) {
    const message = JSON.parse(buffer.slice(0, end));
    buffer = buffer.slice(end+1);
    let result = {};
    if (message.method === 'Target.createTarget') result = {targetId:'fixture'};
    if (message.method === 'Target.attachToTarget') result = {sessionId:'fixture'};
    if (message.method === 'Runtime.evaluate') result = {result:{value:{html:'<textarea>Apertus</textarea>',ready:true}}};
    fs.writeSync(4, JSON.stringify({id:message.id,result})+'\\0');
    if (message.method === 'Browser.close') {
      // Real Chrome may still flush profile data after acknowledging close.
      setTimeout(() => {
        fs.mkdirSync(path.join(profile,'Default'), {recursive:true});
        fs.writeFileSync(path.join(profile,'Default','late-write'), 'flushed');
        fs.writeFileSync(process.env.TEST_EXIT_FILE, 'done');
        process.exit(0);
      }, 500);
    }
  }
});
`);
    fs.chmodSync(fake, 0o755);
    const result = spawnSync(process.execPath, ['tests/browser_smoke.cjs', fake,
      'http://127.0.0.1:8080/', path.join(root,'ui.html')], {
      encoding:'utf8', timeout:15000,
      env:{...process.env, TEST_PROFILE_FILE:path.join(root,'profile'), TEST_EXIT_FILE:path.join(root,'exited')}
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(fs.readFileSync(path.join(root,'exited'),'utf8'), 'done');
    assert.equal(fs.existsSync(fs.readFileSync(path.join(root,'profile'),'utf8')), false);
    assert.match(fs.readFileSync(path.join(root,'ui.html'),'utf8'), /Apertus/);
  } finally {
    fs.rmSync(root, {recursive:true,force:true});
  }
});
