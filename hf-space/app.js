'use strict';
const platform = document.querySelector('#platform');
const button = document.querySelector('#download');
const checksum = document.querySelector('#checksum');
const status = document.querySelector('#status');
let configuration;
let selectedByUser = false;
const platformText = {
  'macos-arm64': ['Apple M-series chip. No Apple Developer membership needed.', 'Unzip and open Apertus Local.app. If macOS blocks this unsigned preview, use System Settings → Privacy & Security → Open Anyway. Allow Terminal access when asked and keep its window open.'],
  'linux-x86_64': ['For compatible Intel / AMD Linux laptops. Check the release notes for the supported distribution.', 'Extract the archive, open a terminal in the extracted folder, and run ./Start.sh. Keep the terminal open.'],
  'windows-x86_64': ['64-bit Windows on Intel / AMD processors.', 'Extract the whole ZIP, then double-click Start.cmd. It gets the model once and opens local chat. Keep its window open; Ctrl+C or Stop.cmd stops the model.'],
  'windows-arm64': ['64-bit Windows on ARM / Snapdragon processors.', 'Extract the whole ZIP, then double-click Start.cmd. It gets the model once and opens local chat. Keep its window open; Ctrl+C or Stop.cmd stops the model.']
};
function safeURL(value) {
  try { const parsed = new URL(value); return parsed.protocol === 'https:' ? parsed.href : null; } catch { return null; }
}
function update() {
  const selected = platform.value;
  const release = configuration?.platforms?.[selected];
  document.querySelector('#version').textContent = release?.version || configuration?.version || 'Preparing a release';
  document.querySelector('#platform-note').textContent = platformText[selected][0] + (release?.minimum_os ? ' Requires ' + release.minimum_os + '.' : ' See release notes for minimum system requirements.');
  document.querySelector('#open-instructions').textContent = platformText[selected][1];
  document.querySelector('#mac-guide').hidden = selected !== 'macos-arm64';
  document.querySelector('#windows-guide').hidden = !selected.startsWith('windows');
  const url = safeURL(release?.url);
  const sumURL = safeURL(release?.checksum_url);
  const available = release?.available === true && url && sumURL && safeURL(configuration?.model?.url);
  button.classList.toggle('disabled', !available);
  button.setAttribute('aria-disabled', String(!available));
  button.removeAttribute('href');
  if (available) button.href = url;
  button.textContent = available ? 'Download for ' + (selected.startsWith('macos') ? 'macOS' : selected.startsWith('windows') ? 'Windows' : 'Linux') + ' ↓' : 'Download not available yet';
  status.textContent = release?.status || 'Release information is temporarily unavailable. See project releases.';
  checksum.hidden = !available;
  if (available) checksum.href = sumURL; else checksum.removeAttribute('href');
}
platform.addEventListener('change', () => { selectedByUser = true; update(); });
const agent = navigator.userAgent || '';
if (/Windows/i.test(agent)) platform.value = 'windows-x86_64';
else if (/Linux/i.test(agent)) platform.value = 'linux-x86_64';
if (/Windows/i.test(agent) && navigator.userAgentData?.getHighEntropyValues) {
  navigator.userAgentData.getHighEntropyValues(['architecture', 'bitness']).then(info => {
    if (!selectedByUser && info.architecture === 'arm') { platform.value = 'windows-arm64'; update(); }
  }).catch(() => {});
}
update();
fetch('config.json', {cache: 'no-cache'}).then(response => {
  if (!response.ok) throw new Error('Release configuration unavailable');
  return response.json();
}).then(config => {
  configuration = config;
  const modelURL = safeURL(config.model?.url);
  if (modelURL) {
    const link = document.createElement('a');
    link.href = 'https://huggingface.co/' + config.model.repo;
    link.textContent = 'Model files, provenance and checksum ↗';
    document.querySelector('#model-link').replaceChildren(link);
  }
  update();
}).catch(() => { status.textContent = 'Release information could not be loaded. Use Project & source for help.'; });
