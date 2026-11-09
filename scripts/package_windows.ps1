#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version,
      [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
      [string]$BuildDirectory = '', [string]$OutputDirectory = '', [string]$RuntimeDirectory = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Invalid release version' }
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $root "vendor/llama.cpp/build-windows-$Architecture" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$cache = Get-Content -LiteralPath (Join-Path $BuildDirectory 'CMakeCache.txt') -Raw
foreach ($required in @('GGML_NATIVE:BOOL=OFF','GGML_BACKEND_DL:BOOL=ON','GGML_CPU_ALL_VARIANTS:BOOL=ON',
    'LLAMA_BUILD_UI:BOOL=ON','LLAMA_USE_PREBUILT_UI:BOOL=OFF',
    'GGML_OPENMP:BOOL=OFF','CMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL')) {
    if ($cache -notmatch ('(?m)^' + [regex]::Escape($required) + '\r?$')) { throw "Nonportable Windows build: missing $required" }
}
$bin = Join-Path $BuildDirectory 'bin/Release'
if (-not (Test-Path -LiteralPath $bin)) { $bin = Join-Path $BuildDirectory 'bin' }
$platform = 'windows-x86_64'
if ($Architecture -eq 'arm64') { $platform = 'windows-arm64' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$archive = Join-Path $OutputDirectory "apertus-local-$Version-$platform.zip"
if (Test-Path -LiteralPath $archive) { throw 'Archive already exists; select another version or output directory' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('apertus-package-' + [Guid]::NewGuid().ToString('N'))
try {
    foreach ($directory in @('scripts/windows','config','runtime/cpu/bin','licenses')) {
        [IO.Directory]::CreateDirectory((Join-Path $stage $directory)) | Out-Null
    }
    foreach ($file in @('Start.cmd','Start-Text.cmd','Stop.cmd')) { Copy-Item (Join-Path $root $file) $stage }
    Copy-Item (Join-Path $root 'scripts/windows/*') (Join-Path $stage 'scripts/windows')
    Copy-Item (Join-Path $root 'config/model.env') (Join-Path $stage 'config')
    Copy-Item (Join-Path $root 'config/multimodal.env') (Join-Path $stage 'config')
    Copy-Item (Join-Path $root 'packaging/WINDOWS_FIRST_START.txt') (Join-Path $stage 'README.txt')
    Copy-Item (Join-Path $root 'packaging/MODEL_CARD.md') $stage
    Copy-Item (Join-Path $root 'packaging/APERTUS-LICENSE.txt') (Join-Path $stage 'licenses')
    Copy-Item (Join-Path $root 'vendor/llama.cpp/LICENSE') (Join-Path $stage 'licenses/llama.cpp-LICENSE')
    $vendor = Join-Path $root 'vendor/llama.cpp'
    foreach ($folder in @('licenses','vendor','tools/ui')) {
        foreach ($file in @(Get-ChildItem (Join-Path $vendor $folder) -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)' })) {
            $relative = $file.FullName.Substring($vendor.Length+1)
            $target = Join-Path (Join-Path $stage 'licenses') $relative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    $runtime = Join-Path $stage 'runtime/cpu/bin'
    foreach ($name in @('llama-server.exe','llama-bench.exe','llama-cli.exe')) {
        Copy-Item -LiteralPath (Join-Path $bin $name) -Destination $runtime
    }
    foreach ($library in @(Get-ChildItem (Join-Path $bin '*.dll'))) { Copy-Item -LiteralPath $library.FullName -Destination $runtime }
    # ggml_fopen returns FILE* across engine DLL boundaries. Those DLLs must
    # share one CRT; statically linking a separate CRT into each is unsafe.
    # App-local deployment needs no participant runtime installer or admin rights.
    if (-not $RuntimeDirectory) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $installation = & $vswhere -latest -products '*' -property installationPath
        $candidates = @(Get-ChildItem (Join-Path $installation "VC/Redist/MSVC/*/$Architecture/Microsoft.VC*.CRT") -Directory)
        $RuntimeDirectory = ($candidates | Sort-Object FullName -Descending | Select-Object -First 1).FullName
    }
    if (-not $RuntimeDirectory -or -not (Test-Path $RuntimeDirectory)) { throw 'Visual C++ redistributable directory was not found' }
    $expectedMachine = 0x8664
    if ($Architecture -eq 'arm64') { $expectedMachine = 0xAA64 }
    foreach ($library in @(Get-ChildItem (Join-Path $RuntimeDirectory '*.dll'))) {
        # Microsoft's ARM64 redistributable directory also contains an x64
        # exception helper. Copy only DLLs for this native engine architecture.
        $bytes = [IO.File]::ReadAllBytes($library.FullName)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        if ($machine -eq $expectedMachine) { Copy-Item -LiteralPath $library.FullName -Destination $runtime }
    }
    foreach ($required in @('vcruntime140.dll', 'msvcp140.dll')) {
        if (-not (Test-Path (Join-Path $runtime $required))) { throw "Missing native CRT DLL: $required" }
    }
    Copy-Item (Join-Path $root 'packaging/MSVC-REDIST-NOTICE.txt') (Join-Path $stage 'licenses')
    if (@(Get-ChildItem (Join-Path $runtime 'ggml-cpu*.dll')).Count -eq 0) { throw 'Missing dynamically dispatched CPU backend DLLs' }
    $files = @{}
    foreach ($file in (Get-ChildItem $stage -Recurse -File)) {
        $relative = $file.FullName.Substring($stage.Length+1).Replace('\','/')
        $files[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $patches = @{}
    foreach ($file in (Get-ChildItem (Join-Path $root 'patches/*.patch'))) {
        $patches[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sourceCommit = & git -C $root rev-parse HEAD
    $llamaCommit = & git -C $vendor rev-parse HEAD
    $manifest = @{ version=$Version; platform=$platform; source_commit=$sourceCommit; llama_commit=$llamaCommit;
        minimum_windows='10'; minimum_powershell='5.1'; cpu_dispatch=$true; msvc_runtime='app-local'; signing='unsigned';
        patches=$patches; files=$files }
    [IO.File]::WriteAllText((Join-Path $stage 'release.json'), ($manifest | ConvertTo-Json -Depth 5))
    & (Join-Path $runtime 'llama-server.exe') --version
    if ($LASTEXITCODE -ne 0) { throw 'Relocated runtime failed; package dependencies are incomplete' }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$archive.sha256", "$digest  $([IO.Path]::GetFileName($archive))`n")
    Write-Host "Package: $archive"
    Write-Host "Checksum: $archive.sha256"
} finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
