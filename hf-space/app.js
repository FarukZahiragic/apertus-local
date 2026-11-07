'use strict';
const platform = document.querySelector('#platform');
const button = document.querySelector('#download');
const checksum = document.querySelector('#checksum');
const status = document.querySelector('#status');
let configuration;
const platformText = {
  'macos-arm64': ['On a Mac, check About This Mac for an Apple M-series chip.', 'Unzip the download and open Apertus Local.app. Allow Terminal access when asked, and keep the terminal window open.'],
  'linux-x86_64': ['For compatible Intel / AMD Linux laptops. Check the release notes for the supported distribution.', 'Extract the archive, open a terminal in the extracted folder, and run ./Start.sh. Keep the terminal open.'],
  'windows-x86_64': ['Windows packaging and validation are still pending.', 'A Windows launcher will be provided after native Windows validation.']
};
function safeURL(value) {
  try { const parsed = new URL(value); return parsed.protocol === 'https:' ? parsed.href : null; } catch { return null; }
}
function update() {
  const selected = platform.value;
  document.querySelector('#platform-note').textContent = platformText[selected][0];
  document.querySelector('#open-instructions').textContent = platformText[selected][1];
  const release = configuration?.platforms?.[selected];
  const url = safeURL(release?.url);
  const sumURL = safeURL(release?.checksum_url);
  const available = release?.available === true && url && sumURL && safeURL(configuration?.model?.url);
  button.classList.toggle('disabled', !available);
  button.setAttribute('aria-disabled', String(!available));
  button.removeAttribute('href');
  if (available) button.href = url;
  button.textContent = available ? 'Download for ' + (selected.startsWith('macos') ? 'macOS' : 'Linux') + ' ↓' : 'Download not available yet';
  status.textContent = release?.status || 'Release information is temporarily unavailable. See project releases.';
  checksum.hidden = !available;
  if (available) checksum.href = sumURL; else checksum.removeAttribute('href');
}
platform.addEventListener('change', update);
const agent = navigator.userAgent || '';
if (/Windows/i.test(agent)) platform.value = 'windows-x86_64';
else if (/Linux/i.test(agent)) platform.value = 'linux-x86_64';
update();
fetch('config.json', {cache: 'no-cache'}).then(response => {
  if (!response.ok) throw new Error('Release configuration unavailable');
  return response.json();
}).then(config => {
  configuration = config;
  document.querySelector('#version').textContent = config.version || 'Preparing a release';
  const modelURL = safeURL(config.model?.url);
  if (modelURL) {
    const link = document.createElement('a');
    link.href = 'https://huggingface.co/' + config.model.repo;
    link.textContent = 'Model files, provenance and checksum ↗';
    document.querySelector('#model-link').replaceChildren(link);
  }
  update();
}).catch(() => { status.textContent = 'Release information could not be loaded. Use Project & source for help.'; });
