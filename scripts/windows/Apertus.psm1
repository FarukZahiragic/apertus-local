# Native Windows runtime helpers; compatible with Windows PowerShell 5.1 and PS 7.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-ApertusConfig {
    param([Parameter(Mandatory=$true)][string]$Root)
    $config = @{}
    foreach ($line in [IO.File]::ReadAllLines((Join-Path $Root 'config/model.env'))) {
        if ($line -match '^(APERTUS_MODEL_[A-Z0-9_]+)=(.*)$') {
            $name = $Matches[1]; $value = $Matches[2].Trim('"')
            if ($value -match '^\$\{([A-Z0-9_]+):-([^}]+)\}$') {
                $override = [Environment]::GetEnvironmentVariable($Matches[1])
                $value = $Matches[2]
                if ($override) { $value = $override }
            }
            $config[$name] = $value
        }
    }
    foreach ($name in @('FILE','SHA256','BYTES','REPO','REVISION')) {
        if (-not $config.ContainsKey("APERTUS_MODEL_$name")) { throw "Missing APERTUS_MODEL_$name in model.env" }
    }
    if ($config.APERTUS_MODEL_SHA256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid model SHA-256' }
    if ($config.APERTUS_MODEL_FILE -match '[/\\]' -or $config.APERTUS_MODEL_FILE.StartsWith('.')) { throw 'Invalid model filename' }
    if ($config.APERTUS_MODEL_BYTES -notmatch '^[1-9][0-9]*$') { throw 'Invalid model byte count' }
    return $config
}

function Get-ApertusHash {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ApertusModel {
    param([string]$Path, [string]$Hash)
    return ((Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-ApertusHash $Path) -eq $Hash.ToLowerInvariant())
}

function Save-ApertusModel {
    param([hashtable]$Config, [string]$Directory, [string]$Url = $env:MODEL_URL)
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $destination = Join-Path $Directory $Config.APERTUS_MODEL_FILE
    $hash = $Config.APERTUS_MODEL_SHA256
    if (Test-ApertusModel $destination $hash) { Write-Host "Model present and verified: $destination"; return $destination }
    $lockPath = "$destination.download-lock"
    try { $lock = New-Object IO.FileStream($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw "A model download already owns $lockPath. Close that download and retry." }
    try {
        if (Test-ApertusModel $destination $hash) { return $destination }
        $partial = "$destination.part"
        if (-not (Test-ApertusModel $partial $hash)) {
            $total = [long]$Config.APERTUS_MODEL_BYTES
            if (-not $Url) { $Url = "https://huggingface.co/$($Config.APERTUS_MODEL_REPO)/resolve/$($Config.APERTUS_MODEL_REVISION)/$($Config.APERTUS_MODEL_FILE)" }
            $uri = [Uri]$Url
            if ($uri.Scheme -ne 'https' -and -not ($uri.Scheme -eq 'http' -and $uri.IsLoopback)) { throw 'Model downloads require HTTPS (HTTP loopback is allowed for tests)' }
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $offset = 0L
                if (Test-Path -LiteralPath $partial) { $offset = (Get-Item -LiteralPath $partial).Length }
                if ($offset -ge $total) { Remove-Item -LiteralPath $partial -Force; $offset = 0L }
                $driveRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Directory))
                if ($driveRoot -match '^[A-Za-z]:\\$') {
                    $drive = New-Object IO.DriveInfo($driveRoot)
                    if ($drive.AvailableFreeSpace -lt ($total - $offset + 100MB)) { throw 'Insufficient free disk space for the model and a 100 MiB reserve' }
                }
                Write-Host ('Downloading model, {0:N1} / {1:N1} GiB; interrupt and restart to resume.' -f ($offset / 1GB), ($total / 1GB))
                $response = $null; $inputStream = $null; $outputStream = $null
                try {
                    $request = [Net.HttpWebRequest]::Create($uri)
                    $request.Timeout = 30000; $request.ReadWriteTimeout = 30000
                    if ($env:HF_TOKEN) { $request.Headers['Authorization'] = 'Bearer ' + $env:HF_TOKEN }
                    if ($offset -gt 0) { $request.AddRange($offset) }
                    $response = $request.GetResponse()
                    if ([int]$response.StatusCode -eq 206) {
                        if ($response.Headers['Content-Range'] -notmatch "^bytes $offset-") { throw 'Server returned an unexpected resume offset' }
                    } elseif ([int]$response.StatusCode -eq 200) { $offset = 0L }
                    else { throw "Unexpected model HTTP status $([int]$response.StatusCode)" }
                    $outputStream = New-Object IO.FileStream($partial, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::Read)
                    $outputStream.SetLength($offset); $outputStream.Position = $offset
                    $inputStream = $response.GetResponseStream()
                    # Keep the large transfer in .NET rather than interpreting
                    # one PowerShell loop per TLS record (especially slow on ARM).
                    $copy = $inputStream.CopyToAsync($outputStream, 1MB)
                    $progress = [Diagnostics.Stopwatch]::StartNew()
                    while (-not $copy.IsCompleted) {
                        if ($progress.Elapsed.TotalSeconds -ge 3) {
                            $written = (Get-Item -LiteralPath $partial).Length
                            Write-Host ('Model: {0:N1} / {1:N1} GiB' -f ($written / 1GB), ($total / 1GB))
                            $progress.Restart()
                        }
                        Start-Sleep -Milliseconds 250
                    }
                    [void]$copy.GetAwaiter().GetResult()
                    $outputStream.Flush()
                    if ($outputStream.Length -ne $total) { throw 'Model download ended before the expected byte count' }
                    break
                } catch {
                    if ($attempt -eq 3) { throw }
                    Write-Host "Download interrupted; retrying ($attempt/3). Partial bytes are retained for the final checksum check."
                    Start-Sleep -Seconds (2 * $attempt)
                } finally {
                    if ($inputStream) { $inputStream.Dispose() }
                    if ($outputStream) { $outputStream.Dispose() }
                    if ($response) { $response.Dispose() }
                }
            }
            Write-Host 'Verifying model SHA-256.'
            if (-not (Test-ApertusModel $partial $hash)) {
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
                throw 'Model checksum mismatch; incorrect download removed. Restart to download again.'
            }
        } else { Write-Host 'Recovering a completed, verified partial download without networking.' }
        # Only a verified file becomes the installed model. A completed .part
        # can be recovered offline if the process stops before the rename.
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        [IO.File]::Move($partial, $destination)
        return $destination
    } finally {
        $lock.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ApertusArchitecture {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { return 'x86_64' }
        'ARM64' { return 'arm64' }
        default { throw 'Apertus requires 64-bit Windows; download the archive matching your processor architecture.' }
    }
}

function Get-ApertusHardware {
    $cores = [Environment]::ProcessorCount; $memory = 0L
    $name = $env:PROCESSOR_IDENTIFIER
    try {
        $cpus = @(Get-CimInstance Win32_Processor)
        $physical = [int](($cpus | Measure-Object -Property NumberOfCores -Sum).Sum)
        if ($physical -gt 0) { $cores = $physical }
        $name = $cpus[0].Name.Trim()
        $memory = [long](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    } catch { Write-Host 'Hardware inventory unavailable; using the OS processor count. THREADS can override it.' }
    return @{ Threads = $cores; Memory = $memory; Label = ('Windows: {0}; {1} CPU cores; {2:N0} GB detected RAM; {3}' -f $name, $cores, ($memory / 1GB), (Get-ApertusArchitecture)) }
}

function Read-ApertusLog {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $reader = New-Object IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function ConvertTo-ApertusArguments {
    param([string[]]$Values)
    # Win32 command-line quoting, including JSON quotes and trailing backslashes.
    $quoted = foreach ($value in $Values) {
        $escaped = [regex]::Replace($value, '(\\*)"', '$1$1\"')
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        '"' + $escaped + '"'
    }
    return ($quoted -join ' ')
}

function Invoke-ApertusLocalRequest {
    param([int]$Port, [string]$Path, [string]$Body = '', [int]$Timeout = 2000)
    $request = [Net.HttpWebRequest]::Create("http://127.0.0.1:$Port$Path")
    $request.Proxy = $null
    $request.Timeout = $Timeout; $request.ReadWriteTimeout = $Timeout
    if ($Body) {
        $request.Method = 'POST'; $request.ContentType = 'application/json'
        $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    $response = $request.GetResponse()
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
}

function Invoke-Apertus {
    param([string]$Root, [switch]$NoBrowser, [switch]$Stop, [switch]$Check, [switch]$GetModel)
    if ($env:OS -ne 'Windows_NT') { throw 'Use the native Windows package on Windows, or Start.sh/Start.command on Linux/macOS.' }
    $port = 8080
    if ($env:PORT) {
        if ($env:PORT -notmatch '^[1-9][0-9]*$') { throw 'PORT must be a positive integer' }
        $port = [int]$env:PORT
    }
    if ($port -gt 65535) { throw 'PORT must be at most 65535' }
    $dataRoot = Join-Path $env:LOCALAPPDATA 'Apertus Local'
    $state = Join-Path $dataRoot 'state'
    if ($env:APERTUS_STATE_DIR) { $state = $env:APERTUS_STATE_DIR }
    $lockPath = Join-Path $state "port-$port.lock"
    $stopPath = Join-Path $state "port-$port.stop"
    if ($Stop) {
        if (-not (Test-Path -LiteralPath $lockPath)) { Write-Host "Apertus is not running on port $port."; return }
        [IO.File]::WriteAllText($stopPath, 'stop')
        for ($i=0; $i -lt 30; $i++) {
            if (-not (Test-Path -LiteralPath $lockPath)) { Write-Host 'Apertus stopped.'; return }
            Start-Sleep -Seconds 1
        }
        throw "Launcher did not respond. Close its Terminal window and retry. State: $state"
    }
    $config = Get-ApertusConfig $Root
    $models = Join-Path $dataRoot 'models'
    if ($env:MODELS_DIR) { $models = $env:MODELS_DIR }
    if ($GetModel) { Save-ApertusModel $config $models | Out-Null; return }
    if ($env:BACKEND -and $env:BACKEND -notin @('auto','cpu')) { throw 'The Windows preview uses CPU. Set BACKEND=cpu or remove the backend override.' }
    $hardware = Get-ApertusHardware
    $threads = $hardware.Threads
    if ($env:THREADS) {
        if ($env:THREADS -notmatch '^[1-9][0-9]*$') { throw 'THREADS must be a positive integer' }
        $threads = [int]$env:THREADS
    }
    $context = 4096
    if ($env:CTX) {
        if ($env:CTX -notmatch '^[1-9][0-9]*$') { throw 'CTX must be a positive integer' }
        $context = [int]$env:CTX
    }
    $timeout = 300
    if ($env:STARTUP_TIMEOUT) {
        if ($env:STARTUP_TIMEOUT -notmatch '^[1-9][0-9]*$') { throw 'STARTUP_TIMEOUT must be a positive integer' }
        $timeout = [int]$env:STARTUP_TIMEOUT
    }
    $build = Join-Path $Root 'runtime/cpu'
    if ($env:BUILD_DIR) { $build = $env:BUILD_DIR }
    elseif (-not (Test-Path (Join-Path $build 'bin/llama-server.exe'))) {
        $architecture = 'x64'
        if ((Get-ApertusArchitecture) -eq 'arm64') { $architecture = 'arm64' }
        $build = Join-Path $Root "vendor/llama.cpp/build-windows-$architecture"
    }
    $serverPath = Join-Path $build 'bin/llama-server.exe'
    if (Test-Path (Join-Path $build 'bin/Release/llama-server.exe')) { $serverPath = Join-Path $build 'bin/Release/llama-server.exe' }
    if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) { throw 'Runtime missing. Extract the complete Windows ZIP before opening Start.cmd.' }
    $manifestPath = Join-Path $Root 'release.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.platform -ne ('windows-' + (Get-ApertusArchitecture))) { throw 'This archive is for another processor architecture. Download the matching Windows archive.' }
    }
    Write-Host "Hardware: $($hardware.Label)"
    Write-Host "Selected: CPU, $threads threads, $context-token context"
    if ($hardware.Memory -gt 0 -and $hardware.Memory -lt 15000000000) { Write-Host 'Memory note: 16 GB RAM is recommended; close other applications if memory is tight.' }
    if ($Check) { Write-Host "Runtime: $serverPath"; Write-Host "Model folder: $models"; return }
    [IO.Directory]::CreateDirectory($state) | Out-Null
    try { $lock = New-Object IO.FileStream($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw "Another Apertus launcher owns port $port. Open Stop.cmd or use another PORT." }
    $server = $null
    try {
        Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
        if ($env:MODEL) {
            $model = $env:MODEL
            if (-not (Test-Path -LiteralPath $model -PathType Leaf)) { throw "Model not found: $model" }
            if ($env:MODEL_SHA256) {
                if (-not (Test-ApertusModel $model $env:MODEL_SHA256)) { throw 'MODEL_SHA256 mismatch' }
            } else { Write-Host 'Developer MODEL override: checksum not specified.' }
        } else { $model = Save-ApertusModel $config $models }
        $client = New-Object Net.Sockets.TcpClient
        $occupied = $false
        try {
            $connection = $client.ConnectAsync('127.0.0.1', $port)
            if ($connection.Wait(500)) { $occupied = $client.Connected }
        } catch { } finally { $client.Dispose() }
        if ($occupied) { throw "Port $port already serves another application; change PORT or stop that application." }
        $stdout = Join-Path $state "server-$port-cpu.stdout.log"
        $stderr = Join-Path $state "server-$port-cpu.stderr.log"
        $loadMode = 'auto'
        if ($env:LOAD_MODE) { $loadMode = $env:LOAD_MODE }
        if ($loadMode -notin @('auto','none','mmap','mlock','mmap+mlock','dio')) { throw 'Invalid LOAD_MODE' }
        $thinking = 'false'
        if ($env:THINKING -eq '1') { $thinking = 'true' }
        elseif ($env:THINKING -and $env:THINKING -ne '0') { throw 'THINKING must be 0 or 1' }
        $arguments = @('--model',$model,'--alias',[IO.Path]::GetFileNameWithoutExtension($model),
            '--host','127.0.0.1','--port',"$port",'--threads',"$threads",'--ctx-size',"$context",
            '--parallel','1','--n-gpu-layers','0','--load-mode',$loadMode,'--jinja',
            '--chat-template-kwargs',('{"enable_thinking":' + $thinking + '}'),'--offline')
        Write-Host "Loading Apertus; startup logs: $stderr"
        $server = Start-Process -FilePath $serverPath -ArgumentList (ConvertTo-ApertusArguments $arguments) `
            -WorkingDirectory (Split-Path -Parent $serverPath) -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr -NoNewWindow -PassThru
        $null = $server.Handle
        $deadline = [DateTime]::UtcNow.AddSeconds($timeout)
        $ready = $false
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $stopPath) { return }
            $server.Refresh()
            if ($server.HasExited) { break }
            $logs = (Read-ApertusLog $stderr) + (Read-ApertusLog $stdout)
            if ($logs -match "listening on .*:$port") {
                try {
                    $health = Invoke-ApertusLocalRequest $port '/health' | ConvertFrom-Json
                    if ($health.status -eq 'ok') { $ready = $true; break }
                } catch { }
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) {
            if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Tail 20 | ForEach-Object { Write-Host $_ } }
            $exitDetail = 'startup timeout'
            if ($server.HasExited) { $exitDetail = 'exit code ' + $server.ExitCode }
            throw "Model startup failed ($exitDetail). Check $stderr, or close other applications and retry."
        }
        $probe = Invoke-ApertusLocalRequest $port '/completion' '{"prompt":"Hello","n_predict":1,"temperature":0,"cache_prompt":false}' ([Math]::Min($timeout,30) * 1000)
        [IO.File]::WriteAllText((Join-Path $state "check-$port-cpu.json"), $probe)
        Write-Host "Ready: http://127.0.0.1:$port/"
        Write-Host 'Keep this window open. Press Ctrl+C or open Stop.cmd to stop Apertus.'
        if (-not $NoBrowser) {
            try { Start-Process "http://127.0.0.1:$port/" }
            catch { Write-Host "Open http://127.0.0.1:$port/ in your browser." }
        }
        while (-not $server.HasExited) {
            if (Test-Path -LiteralPath $stopPath) { return }
            Start-Sleep -Milliseconds 500
            $server.Refresh()
        }
        if ($server.ExitCode -ne 0) { throw "Server exited unexpectedly. Check $stderr" }
    } finally {
        if ($server) {
            $server.Refresh()
            if (-not $server.HasExited) { $server.Kill(); $server.WaitForExit() }
            $server.Dispose()
        }
        $lock.Dispose()
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-ApertusConfig, Get-ApertusHash, Test-ApertusModel, Save-ApertusModel, Get-ApertusArchitecture, Get-ApertusHardware, ConvertTo-ApertusArguments, Invoke-ApertusLocalRequest, Invoke-Apertus
