'use strict';
const platform = document.querySelector('#platform');
const status = document.querySelector('#status');
const copy = document.querySelector('#copy-command');
const copyStatus = document.querySelector('#copy-status');
const targets = ['macos-arm64', 'linux-x86_64', 'windows-x86_64', 'windows-arm64'];
const labels = {
  'macos-arm64': 'Apple Silicon Mac',
  'linux-x86_64': 'Linux · Intel / AMD',
  'windows-x86_64': 'Windows · Intel / AMD',
  'windows-arm64': 'Windows · ARM / Snapdragon'
};
let configuration;
let loadFailed = false;
let selection = 0;
// Keep the copied command and its source link on the same reviewed setup version.
const bootstrapRevision = '7be7121b402832d72bbe8ab04328214e8bd4f02a';

function safeURL(value) {
  try { const parsed = new URL(value); return parsed.protocol === 'https:' ? parsed.href : null; } catch { return null; }
}
function artifactReady(artifact) {
  return Boolean(safeURL(artifact?.url) && /^[a-fA-F0-9]{64}$/.test(artifact?.sha256 || '')
    && Number.isSafeInteger(artifact?.bytes) && artifact.bytes > 0);
}
function releaseReady(release) {
  return Boolean(release?.available === true && safeURL(release.url) && safeURL(release.checksum_url));
}
function update() {
  selection++;
  const windows = platform.value === 'windows';
  const script = windows ? 'run.ps1' : 'run.sh';
  const scriptURL = 'https://raw.githubusercontent.com/FarukZahiragic/apertus-local/' + bootstrapRevision + '/' + script;
  const command = windows ? '& ([scriptblock]::Create((irm ' + scriptURL + ')))' : 'bash -c "$(curl -fsSL ' + scriptURL + ')"';
  document.querySelector('#start-command').value = command;
  copy.textContent = 'Copy command';
  copyStatus.textContent = '';
  document.querySelector('#shell-label').textContent = windows ? 'Paste into PowerShell' : 'Paste into Terminal';
  document.querySelector('#command-source').href = 'https://github.com/FarukZahiragic/apertus-local/blob/' + bootstrapRevision + '/' + script;
  document.querySelector('#version').textContent = configuration?.version || 'Loading release…';
  document.querySelector('#platform-note').textContent = windows
    ? 'For Intel/AMD and ARM PCs. Setup detects your processor automatically.'
    : 'For Apple Silicon Macs and Intel/AMD Linux. Setup selects the right download.';

  const modelsReady = artifactReady(configuration?.model) && artifactReady(configuration?.encoders);
  // The command chooses the native package itself; architecture choices belong
  // only to manual downloads. Keep unavailable or unverified files unlinked.
  let groupReady = false;
  for (const target of targets) {
    const belongsToGroup = target.startsWith('windows') === windows;
    const release = configuration?.platforms?.[target];
    const available = modelsReady && releaseReady(release);
    const button = document.querySelector('#download-' + target);
    const checksum = document.querySelector('#checksum-' + target);
    document.querySelector('#archive-' + target).hidden = !belongsToGroup;
    button.classList.toggle('disabled', !available);
    button.setAttribute('aria-disabled', String(!available));
    button.removeAttribute('href');
    checksum.removeAttribute('href');
    checksum.hidden = !available;
    button.textContent = labels[target] + (available ? ' ↓' : ' · unavailable');
    if (available) {
      button.href = safeURL(release.url);
      checksum.href = safeURL(release.checksum_url);
    }
    document.querySelector('#requirements-' + target).textContent = [release?.minimum_os, release?.version].filter(Boolean).join(' · ');
    if (belongsToGroup && available) groupReady = true;
  }
  document.querySelector('#command-panel').hidden = !groupReady;
  status.textContent = loadFailed ? 'Release information could not be loaded. Use Setup help or try refreshing.'
    : !configuration ? 'Loading release information…'
    : !groupReady ? 'Setup is temporarily unavailable for this selection. See Setup help for alternatives.' : '';
}
platform.addEventListener('change', update);
copy.addEventListener('click', async () => {
  const input = document.querySelector('#start-command');
  const currentSelection = selection;
  const command = input.value;
  try {
    await navigator.clipboard.writeText(command);
    if (currentSelection !== selection) return;
    copy.textContent = 'Copied';
    copyStatus.textContent = 'Command copied. Paste it into ' + (platform.value === 'windows' ? 'PowerShell.' : 'Terminal.');
  } catch {
    if (currentSelection !== selection) return;
    input.focus(); input.select();
    copy.textContent = 'Select and copy the command';
    copyStatus.textContent = 'Automatic copying is unavailable. The command is selected for you to copy.';
  }
});
if (/Windows/i.test(navigator.userAgent || '')) platform.value = 'windows';
update();
fetch('config.json', {cache: 'no-cache'}).then(response => {
  if (!response.ok) throw new Error('Release configuration unavailable');
  return response.json();
}).then(config => {
  configuration = config;
  update();
}).catch(() => { loadFailed = true; update(); });
