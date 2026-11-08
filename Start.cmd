@echo off
setlocal
set "APERTUS_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "APERTUS_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%APERTUS_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\launch.ps1" %*
set "APERTUS_EXIT=%ERRORLEVEL%"
if not "%APERTUS_EXIT%"=="0" pause
exit /b %APERTUS_EXIT%
