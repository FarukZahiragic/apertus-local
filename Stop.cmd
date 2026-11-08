@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\launch.ps1" -Stop
set "APERTUS_EXIT=%ERRORLEVEL%"
if not "%APERTUS_EXIT%"=="0" pause
exit /b %APERTUS_EXIT%
