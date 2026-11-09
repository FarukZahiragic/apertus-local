#!/usr/bin/env node
// Exercise the compiled participant UI, including stale browser preferences.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const [chrome, url, mode = 'multimodal'] = process.argv.slice(2);
if (!chrome || !url || !['text', 'multimodal'].includes(mode)) {
  throw new Error('usage: workshop_ui.mjs CHROME URL [text|multimodal]');
}
const require = createRequire(import.meta.url);
const { chromium } = require(require.resolve('playwright', { paths: [
  path.resolve('vendor/llama.cpp/build-portable/tools/ui/ui-src'),
  path.resolve('vendor/llama.cpp/tools/ui')
] }));
fs.mkdirSync('dist', { recursive: true });
const browser = await chromium.launch({ executablePath: chrome, headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-background-networking'] });
const errors = [];
const staleMcpRequests = [];
try {
  const context = await browser.newContext();
  await context.addInitScript(() => {
    if (window !== window.top || !['http:', 'https:'].includes(location.protocol)) return;
    localStorage.setItem('LlamaUi.reasoningEffortDefault', 'high');
    localStorage.setItem('LlamaUi.config', JSON.stringify({
      max_tokens: 8, sendOnEnter: true, jsSandboxEnabled: true, symbolicMathEnabled: true,
      mcpServers: [{ id: 'old', name: 'Old configuration', url: 'http://127.0.0.1:9/mcp', enabled: true }]
    }));
    localStorage.setItem('LlamaUi.userOverrides', JSON.stringify(['max_tokens']));
  });
  context.on('request', request => {
    if (request.url().startsWith('http://127.0.0.1:9/')) staleMcpRequests.push(request.url());
  });
  context.on('page', page => page.on('pageerror', error => errors.push(error.message)));
  const page = await context.newPage();
  await page.goto(url);
  await page.locator('.file-upload-button').waitFor();
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  const settings = page.getByRole('dialog');
  for (const name of ['Tools', 'Agentic']) {
    assert.equal(await settings.getByRole('button', { name, exact: true }).count(), 0, name);
  }
  await settings.getByRole('button', { name: 'Developer', exact: true }).click();
  for (const name of ['JavaScript sandbox tool', 'Symbolic math (nerdamer)']) {
    assert.equal(await settings.getByLabel(name, { exact: true }).count(), 0, name);
  }
  await settings.getByRole('button', { name: 'Save settings', exact: true }).click();
  await settings.waitFor({ state: 'hidden' });

  const requestPromise = page.waitForRequest(r => r.method() === 'POST' && r.url().includes('/chat/completions'));
  const responsePromise = page.waitForResponse(r => r.request().method() === 'POST' && r.url().includes('/chat/completions'));
  await page.locator('textarea:visible').fill('Reply only with OK.');
  await page.locator('textarea:visible').press('Enter');
  const request = await requestPromise;
  const payload = request.postDataJSON();
  assert.equal(payload.tools, undefined, 'old tool settings must not add tools');
  assert.equal(payload.thinking_budget_tokens, undefined, 'old effort choice must not add a budget');
  assert.equal(payload.chat_template_kwargs?.enable_thinking, undefined, 'server decides thinking');
  const response = await responsePromise;
  assert.equal(response.status(), 200);
  await response.finished();
  await page.waitForURL(/\/chat\//);
  const conversationURL = page.url();
  await page.reload();
  await page.locator('.file-upload-button').waitFor();
  assert.equal(page.url(), conversationURL, 'existing chat must survive reload');
  await page.getByText('Reply only with OK.', { exact: true }).first().waitFor();
  await page.locator('.file-upload-button').click();
  const menu = page.getByRole('menu');
  await menu.getByRole('menuitem', { name: 'System Message', exact: true }).waitFor();
  assert.match(await menu.innerText(), /Add files/);
  assert.doesNotMatch(await menu.innerText(), /Reasoning|MCP|Tools|Video/);
  await menu.screenshot({ path: `dist/workshop-${mode}-desktop-menu.png` });

  const mobile = await context.newPage();
  await mobile.setViewportSize({ width: 390, height: 844 });
  await mobile.goto(url);
  await mobile.locator('.file-upload-button').click();
  const sheet = mobile.getByRole('dialog');
  await sheet.getByRole('button', { name: 'System Message', exact: true }).waitFor();
  assert.doesNotMatch(await sheet.innerText(), /Reasoning|MCP|Tools|Video/);
  for (const name of ['Images', 'Audio Files']) {
    assert.equal(await sheet.getByRole('button', { name, exact: true }).count(), mode === 'multimodal' ? 1 : 0, name);
  }
  for (const name of ['Text Files', 'PDF Files']) {
    assert.equal(await sheet.getByRole('button', { name, exact: true }).count(), 1, name);
  }
  await sheet.screenshot({ path: `dist/workshop-${mode}-mobile-menu.png` });
  assert.deepEqual(staleMcpRequests, [], 'old MCP settings must not reconnect');
  assert.deepEqual(errors, []);
  fs.writeFileSync(`dist/workshop-ui-${mode}.json`, JSON.stringify({
    status: 'passed', mode, browser: await browser.version(),
    checks: ['desktop/mobile controls', 'stale preferences', 'actual chat request', 'history reload', 'input modalities']
  }, null, 2) + '\n');
  console.log(`Workshop ${mode} UI, stale preferences, chat and history checks passed.`);
} finally {
  await browser.close();
}
