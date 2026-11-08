#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoBrowser, [switch]$Stop, [switch]$Check, [switch]$GetModel)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Apertus.psm1') -Force -DisableNameChecking
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    Invoke-Apertus -Root $root -NoBrowser:$NoBrowser -Stop:$Stop -Check:$Check -GetModel:$GetModel
    exit 0
} catch {
    [Console]::Error.WriteLine('Apertus: ' + $_.Exception.Message)
    exit 1
}
