#Requires -Version 5.1
# Actual model check from a relocated archive. Hosted VM, not laptop performance.
param([string]$Archive, [ValidateSet('x64','arm64')][string]$Architecture='x64')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage=Join-Path ([IO.Path]::GetTempPath()) ('apertus delivered package ' + [Guid]::NewGuid().ToString('N'))
$launcher=$null
$rule='Apertus-CI-offline-' + [Guid]::NewGuid().ToString('N')
$firewall=$false
try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $stage
    $env:PORT='18087'; $env:CTX='512'; $env:THREADS='2'; $env:BACKEND='cpu'
    $env:GPU_LAYERS='0'; $env:LOAD_MODE='auto'
    $env:MODELS_DIR=Join-Path $root 'models'
    $env:APERTUS_STATE_DIR=Join-Path $root '.apertus-state/windows'
    Import-Module (Join-Path $stage 'scripts/windows/Apertus.psm1') -Force -DisableNameChecking
    $hardware=Get-ApertusHardware
    $env:HARDWARE_LABEL='GitHub-hosted Windows VM (NOT laptop): ' + $hardware.Label
    $env:MODEL=Join-Path $env:MODELS_DIR 'apertus-v1.5-8b-Q4_K_M.gguf'
    $env:MODEL_SHA256=(Get-ApertusConfig $stage).APERTUS_MODEL_SHA256
    $server=Join-Path $stage 'runtime/cpu/bin/llama-server.exe'
    python (Join-Path $PSScriptRoot 'check_windows_binary.py') (Split-Path -Parent $server) $Architecture
    if($LASTEXITCODE -ne 0) { throw 'Binary compatibility check failed' }
    New-NetFirewallRule -DisplayName $rule -Direction Outbound -Program $server -Action Block -Profile Any | Out-Null
    $firewall=$true
    $stdout=Join-Path $root 'dist/windows-launcher.log'
    $stderr=Join-Path $root 'dist/windows-launcher.err'
    $arguments=ConvertTo-ApertusArguments @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $stage 'scripts/windows/launch.ps1'),'-NoBrowser')
    $launcher=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null=$launcher.Handle
    $ready=$false
    for($i=0;$i -lt 300;$i++) {
        if((Test-Path $stdout) -and (Get-Content $stdout -Raw) -match 'Ready:') { $ready=$true; break }
        if($launcher.HasExited) { Get-Content $stdout; Get-Content $stderr; throw 'Packaged launcher exited before readiness' }
        Start-Sleep -Seconds 1
    }
    if(-not $ready) { throw 'Packaged Windows startup timed out' }
    python (Join-Path $root 'scripts/validate_local.py') --repeat 3 --max-tokens 16 --report (Join-Path $root 'dist/validation-windows.json')
    if($LASTEXITCODE -ne 0) { throw 'Actual Windows inference validation failed' }
    $report=Get-Content (Join-Path $root 'dist/validation-windows.json') -Raw | ConvertFrom-Json
    $report.network_isolation='Outbound Windows Firewall block on the owned llama-server process; loopback API remains available'
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'dist/validation-windows.json') -Encoding UTF8
    & (Join-Path $stage 'scripts/windows/launch.ps1') -Stop
    if($LASTEXITCODE -ne 0) { throw 'Packaged Windows stop failed' }
    if(-not $launcher.WaitForExit(10000)) { throw 'Packaged launcher did not stop' }
    if($launcher.ExitCode -ne 0) { throw 'Packaged launcher reported a failure' }
    Write-Host 'Delivered Windows CPU inference, UI assets, streaming and owned stop passed with server outbound networking blocked.'
} finally {
    if($launcher) { $launcher.Refresh(); if(-not $launcher.HasExited) { $launcher.Kill(); $launcher.WaitForExit() }; $launcher.Dispose() }
    if($firewall) { Get-NetFirewallRule -DisplayName $rule | Remove-NetFirewallRule }
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
