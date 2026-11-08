#Requires -Version 5.1
# Real Windows process/file tests, using a C# HTTP fixture instead of model weights.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $root 'scripts/windows/Apertus.psm1') -Force -DisableNameChecking
function Assert([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message } }
function FreePort {
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    $listener.Start(); $port=$listener.LocalEndpoint.Port; $listener.Stop(); return $port
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('apertus windows test ' + [Guid]::NewGuid().ToString('N'))
$children = @()
$names = @('PORT','MODELS_DIR','APERTUS_STATE_DIR','MODEL','MODEL_SHA256','MODEL_URL','BACKEND','THREADS','CTX','STARTUP_TIMEOUT',
    'APERTUS_FIXTURE_SOURCE','APERTUS_FIXTURE_ARGUMENTS','APERTUS_FIXTURE_CORRUPT','APERTUS_FIXTURE_REQUESTS',
    'APERTUS_FIXTURE_COMPUTE_FAILURE','APERTUS_FIXTURE_START_FAILURE')
$original=@{}
foreach($name in $names) { $original[$name]=[Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name,$null,'Process') }
try {
    foreach($directory in @('scripts/windows','config','runtime/cpu/bin','models','state')) { [IO.Directory]::CreateDirectory((Join-Path $temporary $directory)) | Out-Null }
    Copy-Item (Join-Path $root 'scripts/windows/*') (Join-Path $temporary 'scripts/windows')
    $fixture = Join-Path $temporary 'runtime/cpu/bin/llama-server.exe'
    Add-Type -Path (Join-Path $PSScriptRoot 'windows_fixture.cs') -OutputAssembly $fixture -OutputType ConsoleApplication
    $env:APERTUS_FIXTURE_SOURCE=Join-Path $temporary 'source.gguf'
    [IO.File]::WriteAllBytes($env:APERTUS_FIXTURE_SOURCE,[Text.Encoding]::UTF8.GetBytes(('fixture data 1234567890' * 4096)))
    $hash=Get-ApertusHash $env:APERTUS_FIXTURE_SOURCE
    $bytes=(Get-Item $env:APERTUS_FIXTURE_SOURCE).Length
    $configText="APERTUS_MODEL_FILE=fixture.gguf`nAPERTUS_MODEL_SHA256=$hash`nAPERTUS_MODEL_BYTES=$bytes`nAPERTUS_MODEL_REPO=fixture/model`nAPERTUS_MODEL_REVISION=fixture`n"
    [IO.File]::WriteAllText((Join-Path $temporary 'config/model.env'),$configText)
    $config=Get-ApertusConfig $temporary
    $env:MODELS_DIR=Join-Path $temporary 'models'
    $env:APERTUS_STATE_DIR=Join-Path $temporary 'state'
    $env:APERTUS_FIXTURE_ARGUMENTS=Join-Path $temporary 'arguments.txt'
    $env:APERTUS_FIXTURE_REQUESTS=Join-Path $temporary 'requests.txt'
    $env:APERTUS_FIXTURE_CORRUPT=Join-Path $temporary 'corrupt'
    $env:APERTUS_FIXTURE_COMPUTE_FAILURE=Join-Path $temporary 'compute-failure'
    $env:APERTUS_FIXTURE_START_FAILURE=Join-Path $temporary 'start-failure'
    $downloadPort=FreePort
    $download=Start-Process $fixture -ArgumentList "--port $downloadPort" -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $temporary 'download.stdout') -RedirectStandardError (Join-Path $temporary 'download.stderr')
    $children += $download
    $env:MODEL_URL="http://127.0.0.1:$downloadPort/model"
    $destination=Join-Path $env:MODELS_DIR 'fixture.gguf'
    $source=[IO.File]::ReadAllBytes($env:APERTUS_FIXTURE_SOURCE)
    [IO.File]::WriteAllBytes("$destination.part",$source[0..4095])
    $saved=Save-ApertusModel $config $env:MODELS_DIR
    Assert (Test-ApertusModel $saved $hash) 'Resumed model checksum failed'
    Assert ((Get-Content $env:APERTUS_FIXTURE_REQUESTS -Raw) -match 'bytes=4096-') 'Download did not resume'
    Write-Host 'PASS: ranged download and checksum'
    Remove-Item -LiteralPath $destination
    [IO.File]::WriteAllText($env:APERTUS_FIXTURE_CORRUPT,'corrupt')
    $rejected=$false
    try { Save-ApertusModel $config $env:MODELS_DIR | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Corrupt download was accepted'
    Assert (-not (Test-Path "$destination.part")) 'Corrupt partial file was retained'
    Assert (-not (Test-Path $destination)) 'Corrupt bytes became the model'
    Remove-Item $env:APERTUS_FIXTURE_CORRUPT
    Save-ApertusModel $config $env:MODELS_DIR | Out-Null
    $download.Kill(); $download.WaitForExit()
    Save-ApertusModel $config $env:MODELS_DIR | Out-Null
    Move-Item $destination "$destination.part"
    Save-ApertusModel $config $env:MODELS_DIR | Out-Null
    Write-Host 'PASS: corrupt download rejection, offline reuse and completed-part recovery'
    $env:PORT=[string](FreePort); $env:STARTUP_TIMEOUT='10'; $env:CTX='512'; $env:THREADS='2'
    $launcher=Join-Path $temporary 'scripts/windows/launch.ps1'
    function Launch([string]$Name,[string]$Extra='') {
        $log=Join-Path $temporary "$Name.log"
        $errorLog=Join-Path $temporary "$Name.err"
        $nativeArguments=ConvertTo-ApertusArguments @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-NoBrowser')
        if($Extra) { $nativeArguments += ' ' + $Extra }
        $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $nativeArguments -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError $errorLog
        $null=$process.Handle
        return $process
    }
    $first=Launch 'first'; $children += $first
    $ready=$false
    for($i=0;$i -lt 600;$i++) {
        if(Test-Path (Join-Path $temporary 'first.log')) {
            if((Get-Content (Join-Path $temporary 'first.log') -Raw) -match 'Ready:') { $ready=$true; break }
        }
        if($first.HasExited) { break }
        Start-Sleep -Milliseconds 100
    }
    if(-not $ready) { Get-Content (Join-Path $temporary 'first.err'); Get-Content (Join-Path $temporary 'first.log') }
    Assert $ready 'Launcher did not reach real inference readiness'
    $arguments=[IO.File]::ReadAllLines($env:APERTUS_FIXTURE_ARGUMENTS)
    Assert ($arguments -contains '{"enable_thinking":false}') 'Native JSON argument quoting changed'
    Assert ($arguments -contains $destination) 'Native model path with spaces changed'
    $second=Launch 'second'; $children += $second
    Assert ($second.WaitForExit(30000)) 'Second launcher did not exit'
    Assert ($second.ExitCode -ne 0) 'Two launchers acquired the same port'
    Assert (-not $first.HasExited) 'Second launcher stopped the first server'
    $stop=Launch 'stop' '-Stop'; $children += $stop
    Assert ($stop.WaitForExit(30000)) 'Stop request timed out'
    Assert ($stop.ExitCode -eq 0) 'Owned stop failed'
    Assert ($first.WaitForExit(30000)) 'Owner did not exit after Stop'
    Assert (-not (Test-Path (Join-Path $env:APERTUS_STATE_DIR "port-$env:PORT.lock"))) 'Lock was not released'
    Write-Host 'PASS: native argument quoting, exclusive ownership and owned stop'
    [IO.File]::WriteAllText($env:APERTUS_FIXTURE_COMPUTE_FAILURE,'fail')
    $failure=Launch 'compute'; $children += $failure
    Assert ($failure.WaitForExit(30000)) 'Compute failure did not stop startup'
    Assert ($failure.ExitCode -ne 0) 'Healthy HTTP response hid compute failure'
    Assert ((Get-Content (Join-Path $temporary 'compute.log') -Raw) -notmatch 'Ready:') 'Failed compute was reported ready'
    Remove-Item $env:APERTUS_FIXTURE_COMPUTE_FAILURE
    Write-Host 'PASS: actual inference check rejects an unhealthy backend'
    $occupiedPort=FreePort
    $external=Start-Process $fixture -ArgumentList "--port $occupiedPort" -NoNewWindow -PassThru
    $children += $external
    Start-Sleep -Milliseconds 500
    $env:PORT=[string]$occupiedPort
    $occupied=Launch 'occupied'; $children += $occupied
    Assert ($occupied.WaitForExit(30000)) 'Occupied-port check timed out'
    Assert ($occupied.ExitCode -ne 0) 'Occupied port was accepted'
    Assert (-not $external.HasExited) 'Launcher killed an unrelated server'
    Write-Host 'PASS: occupied port is refused without stopping its owner'
} finally {
    $diagnostics=Join-Path $root 'dist/windows-fixtures'
    foreach($file in @(Get-ChildItem $temporary -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.(log|err|stderr|stdout|txt)$' })) {
        $target=Join-Path $diagnostics $file.FullName.Substring($temporary.Length+1)
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
    foreach($child in $children) {
        $child.Refresh()
        if(-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
    foreach($name in $names) { [Environment]::SetEnvironmentVariable($name,$original[$name],'Process') }
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
