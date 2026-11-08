#Requires -Version 5.1
# Maintainer build only. Participants use the prebuilt ZIP and Start.cmd.
[CmdletBinding()]
param([ValidateSet('x64','arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $root 'vendor/llama.cpp'
$build = Join-Path $source "build-windows-$Architecture"
$repo = 'https://github.com/MichelRosselli/llama.cpp'
$branch = 'model/apertus-v1.5-refresh-20260914'
$commit = '442b0444168a0f72788b40a16c8289bd1eb217f5'
function Run {
    param([string]$Tool, [string[]]$Values)
    & $Tool @Values
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE" }
}
if (-not (Test-Path (Join-Path $source '.git'))) { Run 'git' @('clone','--filter=blob:none','--no-checkout',$repo,$source) }
Run 'git' @('-C',$source,'fetch','--quiet','origin',$branch)
Run 'git' @('-C',$source,'checkout','--force','--detach',$commit)
Run 'git' @('-C',$source,'reset','--hard',$commit)
foreach ($patch in (Get-ChildItem (Join-Path $root 'patches/*.patch') | Sort-Object Name)) {
    Write-Host "Applying $($patch.Name)"
    Run 'git' @('-C',$source,'apply',$patch.FullName)
}
$arguments = @('-S',$source,'-B',$build,'-DCMAKE_BUILD_TYPE=Release',
    '-DGGML_NATIVE=OFF','-DGGML_BACKEND_DL=ON','-DGGML_CPU_ALL_VARIANTS=ON',
    '-DGGML_OPENMP=OFF','-DGGML_VULKAN=OFF','-DGGML_METAL=OFF','-DGGML_CUDA=OFF',
    '-DLLAMA_OPENSSL=OFF','-DLLAMA_BUILD_TESTS=OFF',
    '-DLLAMA_BUILD_UI=ON','-DLLAMA_USE_PREBUILT_UI=OFF',
    '-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL','-DCMAKE_POLICY_DEFAULT_CMP0091=NEW')
if ($Architecture -eq 'x64') {
    $arguments += @('-G','Visual Studio 17 2022','-A','x64')
} else {
    # Portable ARM variants need Clang, rather than MSVC's host-only ARM probing.
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -property installationPath
    if (-not $installation) { throw 'Visual Studio C++ tools were not found' }
    $developer = Join-Path $installation 'Common7/Tools/VsDevCmd.bat'
    $environment = & $env:ComSpec /d /c ('call "{0}" -no_logo -arch=arm64 -host_arch=arm64 >nul && set' -f $developer)
    if ($LASTEXITCODE -ne 0) { throw 'Could not load the ARM64 compiler environment' }
    foreach ($line in $environment) {
        $equal = $line.IndexOf('=')
        if ($equal -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0,$equal),$line.Substring($equal+1),'Process') }
    }
    $arguments += @('-G','Ninja','-DCMAKE_C_COMPILER=clang','-DCMAKE_CXX_COMPILER=clang++',
        '-DCMAKE_C_COMPILER_TARGET=aarch64-pc-windows-msvc','-DCMAKE_CXX_COMPILER_TARGET=aarch64-pc-windows-msvc')
}
Run 'cmake' $arguments
$jobs = '2'
if ($env:JOBS) { $jobs = $env:JOBS }
Run 'cmake' @('--build',$build,'--config','Release','--parallel',$jobs,'--target','llama-server','llama-bench','llama-cli','ggml')
Write-Host "Portable Windows $Architecture runtime built at $build"
