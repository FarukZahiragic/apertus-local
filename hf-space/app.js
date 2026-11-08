'use strict';
const platform = document.querySelector('#platform');
const button = document.querySelector('#download');
const checksum = document.querySelector('#checksum');
const status = document.querySelector('#status');
let configuration;
let selectedByUser = false;
const platformText = {
  'macos-arm64': ['Apple M-series chip. No Apple Developer membership needed.', 'Open Terminal and paste the command above. It starts the server directly, without the app wrapper. Keep the terminal open and save the printed start.sh command for later.'],
  'linux-x86_64': ['For compatible Intel / AMD Linux laptops. Check the release notes for the supported distribution.', 'Open a terminal and paste the command above. It prepares local chat and prints a start.sh command for later, including offline. Keep the terminal open.'],
  'windows-x86_64': ['64-bit Windows on Intel / AMD processors.', 'Open PowerShell and paste the command above. It prepares local chat and leaves Start.cmd and Stop.cmd for later, including offline. Keep its window open.'],
  'windows-arm64': ['64-bit Windows on ARM / Snapdragon processors.', 'Open PowerShell and paste the command above. It selects the native runtime and leaves Start.cmd and Stop.cmd for later, including offline. Keep its window open.']
};
function safeURL(value) {
  try { const parsed = new URL(value); return parsed.protocol === 'https:' ? parsed.href : null; } catch { return null; }
}
function update() {
  const selected = platform.value;
  const windows = selected.startsWith('windows');
  const script = windows ? 'run.ps1' : 'run.sh';
  const scriptURL = 'https://raw.githubusercontent.com/FarukZahiragic/apertus-local/main/' + script;
  const command = windows ? '& ([scriptblock]::Create((irm ' + scriptURL + ')))' : 'bash -c "$(curl -fsSL ' + scriptURL + ')"';
  document.querySelector('#start-command').value = command;
  document.querySelector('#copy-command').textContent = 'Copy command';
  document.querySelector('#shell-label').textContent = windows ? 'Paste into PowerShell' : 'Paste into Terminal';
  document.querySelector('#command-source').href = 'https://github.com/FarukZahiragic/apertus-local/blob/main/' + script;
  const release = configuration?.platforms?.[selected];
  document.querySelector('#version').textContent = release?.version || configuration?.version || 'Preparing a release';
  document.querySelector('#platform-note').textContent = platformText[selected][0] + (release?.minimum_os ? ' Requires ' + release.minimum_os + '.' : ' See release notes for minimum system requirements.');
  document.querySelector('#open-instructions').textContent = platformText[selected][1];
  document.querySelector('#mac-guide').hidden = selected !== 'macos-arm64';
  document.querySelector('#windows-guide').hidden = !selected.startsWith('windows');
  const url = safeURL(release?.url);
  const sumURL = safeURL(release?.checksum_url);
  const encoders = configuration?.encoders;
  const encodersReady = safeURL(encoders?.url) && /^[a-fA-F0-9]{64}$/.test(encoders?.sha256 || '')
    && Number.isSafeInteger(encoders?.bytes) && encoders.bytes > 0;
  const available = release?.available === true && url && sumURL && safeURL(configuration?.model?.url) && encodersReady;
  document.querySelector('#command-panel').hidden = !available;
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
document.querySelector('#copy-command').addEventListener('click', async () => {
  const input = document.querySelector('#start-command');
  const copy = document.querySelector('#copy-command');
  try {
    await navigator.clipboard.writeText(input.value);
    copy.textContent = 'Copied';
  } catch {
    input.focus(); input.select();
    copy.textContent = 'Select and copy the command';
  }
});
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
