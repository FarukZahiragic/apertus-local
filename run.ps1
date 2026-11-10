#Requires -Version 5.1
# One-command Windows participant setup using the published native runtime.
[CmdletBinding()]
param([switch]$PrepareOnly, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ($env:OS -ne 'Windows_NT') { throw 'Use run.ps1 on Windows, or run.sh on macOS/Linux.' }
# Choose a native package and its fixed checksum; no build tools are installed.
$architecture = $env:PROCESSOR_ARCHITEW6432
if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
switch ($architecture) {
    'AMD64' { $platform = 'windows-x86_64'; $digest = '04a4534aff2f00dedb1cc0349331d253bef6f8d8472e5e4ddcc756e2b37824e6' }
    'ARM64' { $platform = 'windows-arm64'; $digest = 'ed9c2ac8524a0d07abd9b19c10665ee42c0090373ba9ea5b31b2fd9f00d280d3' }
    default { throw 'Apertus requires 64-bit Windows on Intel/AMD or ARM/Snapdragon.' }
}
$version = 'v0.2.0-preview.2'
if (-not $env:MULTIMODAL) { $env:MULTIMODAL = '1' }
if ($env:MULTIMODAL -notin @('0','1')) { throw 'MULTIMODAL must be 0 or 1' }
$archive = "apertus-local-$version-$platform.zip"
$url = "https://github.com/FarukZahiragic/apertus-local/releases/download/$version/$archive"
if ($env:APERTUS_PACKAGE_URL -or $env:APERTUS_PACKAGE_SHA256) {
    if (-not $env:APERTUS_PACKAGE_URL -or $env:APERTUS_PACKAGE_SHA256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'A package URL override requires APERTUS_PACKAGE_SHA256 as well.' }
    $url = $env:APERTUS_PACKAGE_URL; $digest = $env:APERTUS_PACKAGE_SHA256.ToLowerInvariant()
}
$uri = [Uri]$url
if ($uri.Scheme -ne 'https' -and -not ($uri.Scheme -eq 'http' -and $uri.IsLoopback)) { throw 'Package downloads require HTTPS (HTTP loopback is allowed for tests).' }
if ($env:MODEL -and -not [IO.File]::Exists($env:MODEL)) { throw "MODEL does not exist: $env:MODEL" }
if ($env:MODEL) { $env:MODEL = [IO.Path]::GetFullPath($env:MODEL) }
# Keep new files in the user's data folder; reuse a prepared runtime when found.
$data = Join-Path $env:LOCALAPPDATA 'Apertus Local'
if ($env:APERTUS_INSTALL_DIR) { $data = [IO.Path]::GetFullPath($env:APERTUS_INSTALL_DIR) }
[IO.Directory]::CreateDirectory($data) | Out-Null
if (-not $env:APERTUS_RUNTIME_DIR) {
    foreach ($candidate in @([string]$PWD, (Join-Path $env:USERPROFILE 'apertus-1.5-local'))) {
        $config = Join-Path $candidate 'config/model.env'
        $server = Join-Path $candidate 'runtime/cpu/bin/llama-server.exe'
        $buildArch = 'x64'
        if ($platform -eq 'windows-arm64') { $buildArch = 'arm64' }
        $built = Join-Path $candidate "vendor/llama.cpp/build-windows-$buildArch/bin"
        $hasServer = [IO.File]::Exists($server) -or [IO.File]::Exists((Join-Path $built 'llama-server.exe')) -or [IO.File]::Exists((Join-Path $built 'Release/llama-server.exe'))
        $hasEncoders = $env:MULTIMODAL -eq '0' -or [IO.File]::Exists((Join-Path $candidate 'config/multimodal.env'))
        $hasParticipantUI = $false
        if ([IO.File]::Exists($server)) {
            try {
                $manifest = [IO.File]::ReadAllText((Join-Path $candidate 'release.json')) | ConvertFrom-Json
                $hasParticipantUI = $manifest.patches.PSObject.Properties.Name -contains '0006-apertus-workshop-ui.patch'
            } catch { $hasParticipantUI = $false }
        } else {
            $cache = Join-Path $candidate "vendor/llama.cpp/build-windows-$buildArch/CMakeCache.txt"
            if ([IO.File]::Exists($cache)) {
                $text = [IO.File]::ReadAllText($cache)
                $hasParticipantUI = $text -match '(?m)^LLAMA_BUILD_UI:BOOL=ON\r?$' -and $text -match '(?m)^LLAMA_USE_PREBUILT_UI:BOOL=OFF\r?$'
            }
        }
        if ($hasServer -and $hasParticipantUI -and $hasEncoders -and [IO.File]::Exists($config) -and [IO.File]::Exists((Join-Path $candidate 'scripts/windows/launch.ps1'))) {
            if ([IO.File]::ReadAllText($config) -match '(?m)^APERTUS_MODEL_SHA256=e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c\r?$') { $env:APERTUS_RUNTIME_DIR = $candidate; break }
        }
    }
}
$runtime = Join-Path $data "packages/$platform-$version"
if ($env:APERTUS_RUNTIME_DIR) { $runtime = [IO.Path]::GetFullPath($env:APERTUS_RUNTIME_DIR) }
function Get-BootstrapHash {
    param([string]$Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Test-BootstrapRuntime {
    if ($env:MULTIMODAL -eq '1' -and -not [IO.File]::Exists((Join-Path $runtime 'config/multimodal.env'))) { return $false }
    if (-not [IO.File]::Exists((Join-Path $runtime 'scripts/windows/Apertus.psm1'))) { return $false }
    if (-not [IO.File]::Exists((Join-Path $runtime 'scripts/windows/launch.ps1'))) { return $false }
    if ($env:APERTUS_RUNTIME_DIR) { return $true }
    $marker = Join-Path $runtime '.bootstrap-sha256'
    return ([IO.File]::Exists($marker) -and [IO.File]::ReadAllText($marker).Trim() -eq $digest)
}
Write-Host 'Apertus Local - one-command setup'
Write-Host "Local files: $data"
Write-Host 'Model files total 6.1 GiB (5.3 GiB in text-only mode). A missing native runtime downloads once.'
# Verify the downloaded archive before extracting it into the data folder.
if (-not (Test-BootstrapRuntime)) {
    if ($env:APERTUS_RUNTIME_DIR) { throw 'APERTUS_RUNTIME_DIR is not an Apertus Windows runtime folder.' }
    if (Test-Path -LiteralPath $runtime) { throw "Unrecognized runtime at $runtime; nothing was overwritten." }
    $lockPath = Join-Path $data '.bootstrap-lock'
    try { $lock = New-Object IO.FileStream($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Another setup is running; close it and retry.' }
    $stage = $null
    try {
        $downloads = Join-Path $data 'downloads'
        [IO.Directory]::CreateDirectory($downloads) | Out-Null
        $partial = Join-Path $downloads ($archive + '.part')
        if (-not [IO.File]::Exists($partial) -or (Get-BootstrapHash $partial) -ne $digest) {
            Write-Host "Downloading the native $platform runtime."
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $client = New-Object Net.WebClient
            try { $client.DownloadFile($uri, $partial) } finally { $client.Dispose() }
        }
        if ((Get-BootstrapHash $partial) -ne $digest) {
            [IO.File]::Delete($partial)
            throw 'Runtime checksum mismatch; incorrect download removed.'
        }
        $stage = Join-Path $data ('.install-' + [Guid]::NewGuid().ToString('N'))
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($partial, $stage)
        if (-not [IO.File]::Exists((Join-Path $stage 'scripts/windows/launch.ps1')) -or -not [IO.File]::Exists((Join-Path $stage 'runtime/cpu/bin/llama-server.exe'))) { throw 'Runtime archive is missing its launcher or server.' }
        [IO.File]::WriteAllText((Join-Path $stage '.bootstrap-sha256'), $digest)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $runtime)) | Out-Null
        [IO.Directory]::Move($stage, $runtime)
        $stage = $null
        [IO.File]::Delete($partial)
    } finally {
        if ($stage -and [IO.Directory]::Exists($stage)) { [IO.Directory]::Delete($stage, $true) }
        $lock.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
} else { Write-Host "Reusing the local runtime: $runtime" }
# Reuse existing weights where possible; otherwise download into this install.
$models = Join-Path $data 'models'
if ($env:MODELS_DIR) { $models = [IO.Path]::GetFullPath($env:MODELS_DIR) }
if (-not $env:MODEL -and -not $env:MODELS_DIR) {
    foreach ($candidate in @((Join-Path $PWD 'models'), (Join-Path $env:USERPROFILE 'apertus-1.5-local/models'))) {
        if ([IO.File]::Exists((Join-Path $candidate 'apertus-v1.5-8b-Q4_K_M.gguf'))) { $models = [IO.Path]::GetFullPath($candidate); break }
    }
}
$env:MODELS_DIR = $models
if ($env:MMPROJ) {
    if (-not [IO.File]::Exists($env:MMPROJ)) { throw "Encoder does not exist: $env:MMPROJ" }
    $env:MMPROJ = [IO.Path]::GetFullPath($env:MMPROJ)
}
if (-not $env:APERTUS_STATE_DIR) { $env:APERTUS_STATE_DIR = Join-Path $data 'state' }
if ($env:MODEL -and -not $env:MODEL_SHA256) { $env:MODEL_SHA256 = 'e8ddf308abe64441725dcdbfc32e7c89f2b52b94e90f24c30236694f0a90eb8c' }
function Quote-BootstrapLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}
# Save small offline launchers with the selected paths and mode. They delegate
# to the packaged launch.ps1; model execution stays in the shared runtime.
$start = Join-Path $data 'start.ps1'
$lines = @('$ErrorActionPreference = ''Stop''', ('if (-not $env:MULTIMODAL) {{ $env:MULTIMODAL = ''{0}'' }}' -f $env:MULTIMODAL))
foreach ($name in @('MODELS_DIR', 'APERTUS_STATE_DIR', 'MODEL', 'MODEL_SHA256', 'MMPROJ', 'MMPROJ_SHA256')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($value) { $lines += ('if (-not $env:{0}) {{ $env:{0} = {1} }}' -f $name, (Quote-BootstrapLiteral $value)) }
}
$lines += '& ' + (Quote-BootstrapLiteral (Join-Path $runtime 'scripts/windows/launch.ps1')) + ' @args'
[IO.File]::WriteAllLines($start, $lines, (New-Object Text.UTF8Encoding($true)))
$cmd = @('@echo off', 'setlocal',
    'set "APERTUS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"',
    'if defined PROCESSOR_ARCHITEW6432 if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "APERTUS_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"',
    '"%APERTUS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*', 'exit /b %ERRORLEVEL%')
[IO.File]::WriteAllLines((Join-Path $data 'Start.cmd'), $cmd, [Text.Encoding]::ASCII)
[IO.File]::WriteAllLines((Join-Path $data 'Stop.cmd'), @('@echo off', 'call "%~dp0Start.cmd" -Stop'), [Text.Encoding]::ASCII)
Write-Host "Next time, including offline: open $(Join-Path $data 'Start.cmd')"
# Preparation only downloads/verifies files; normal setup starts local chat.
if ($PrepareOnly) {
    # Loading the module as an in-memory script also works when setup was pasted
    # into a shell that does not permit executing downloaded .ps1 files directly.
    $module = New-Module -ScriptBlock ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $runtime 'scripts/windows/Apertus.psm1'))))
    Import-Module $module -Force -DisableNameChecking
    if ($env:MODEL) {
        if ((Get-BootstrapHash $env:MODEL) -ne $env:MODEL_SHA256) { throw 'MODEL_SHA256 mismatch.' }
    } else {
        $config = Get-ApertusConfig $runtime
        Save-ApertusModel $config $models | Out-Null
    }
    if ($env:MULTIMODAL -eq '1') {
        $config = Get-ApertusConfig $runtime 'multimodal.env'
        if ($env:MMPROJ) {
            $hash = $config.APERTUS_MODEL_SHA256
            if ($env:MMPROJ_SHA256) { $hash = $env:MMPROJ_SHA256 }
            if ((Get-BootstrapHash $env:MMPROJ) -ne $hash) { throw 'MMPROJ_SHA256 mismatch.' }
        } else {
            $encoderUrl = $config.APERTUS_MODEL_URL
            if ($env:MMPROJ_URL) { $encoderUrl = $env:MMPROJ_URL }
            Save-ApertusModel $config $models -Url $encoderUrl | Out-Null
        }
    }
    Write-Host 'Preparation complete. Open Start.cmd in the folder above to chat.'
} else {
    $launchArgs = @()
    if ($NoBrowser) { $launchArgs += '-NoBrowser' }
    & (Join-Path $data 'Start.cmd') @launchArgs
    if ($LASTEXITCODE -ne 0) { throw "Apertus exited with code $LASTEXITCODE" }
}
