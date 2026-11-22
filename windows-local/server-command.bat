@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0scripts\read-console-command.ps1"
if errorlevel 1 pause
