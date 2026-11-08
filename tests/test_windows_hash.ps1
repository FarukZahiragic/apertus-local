#Requires -Version 5.1
# Also runs under PowerShell 7 on Linux; no model or Windows compiler needed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $root 'scripts/windows/Apertus.psm1') -Force -DisableNameChecking
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('apertus hash test ' + [Guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
# Shadow the optional cmdlet in the module's own scope. The original launcher
# fails here; checksum verification must still run and must reject bad bytes.
$module = Get-Module Apertus
& $module { function script:Get-FileHash { throw 'Get-FileHash is unavailable in this regression test' } }
try {
    [IO.Directory]::CreateDirectory($temporary) | Out-Null
    $empty = Join-Path $temporary 'empty.bin'
    [IO.File]::WriteAllBytes($empty, [byte[]]@())
    $emptyHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    Assert ((Get-ApertusHash $empty) -ceq $emptyHash) 'Empty-file SHA-256 does not match its known vector'
    $fileName = 'literal [hash] ' + [char]0x0107 + '.bin'
    $file = Join-Path $temporary $fileName
    [IO.File]::WriteAllBytes($file, [Text.Encoding]::ASCII.GetBytes('abc'))
    $abcHash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    Assert ((Get-ApertusHash $file) -ceq $abcHash) 'Literal-path SHA-256 does not match its known vector'
    Push-Location -LiteralPath $temporary
    try { Assert ((Get-ApertusHash $fileName) -ceq $abcHash) 'Hashing ignored the PowerShell working directory' }
    finally { Pop-Location }
    Assert (Test-ApertusModel $file $abcHash.ToUpperInvariant()) 'Correct model checksum was rejected'
    Assert (-not (Test-ApertusModel $file $emptyHash)) 'Wrong model checksum was accepted'
    Assert (-not (Test-ApertusModel (Join-Path $temporary 'absent') $abcHash)) 'Missing model was accepted'
    $failed = $false
    try { Get-ApertusHash (Join-Path $temporary 'absent') | Out-Null }
    catch { $failed = $_.Exception.Message -like 'SHA-256 verification failed*' }
    Assert $failed 'Unreadable file did not produce a checksum verification error'
    # Windows refuses renames/deletes when a reader is leaked without delete
    # sharing. This also verifies cleanup after the relative-path checks.
    [IO.File]::Move($file, "$file.moved")
    [IO.File]::Delete("$file.moved")
    Write-Host 'PASS: known SHA-256 vectors, literal/relative paths, missing cmdlet, fail-closed validation and file cleanup'
} finally {
    & $module { Remove-Item Function:script:Get-FileHash }
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
