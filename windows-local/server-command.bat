@echo off
setlocal
set "TEMP=%~dp0tmp"
set "TMP=%TEMP%"
set "COMMAND=%~1"
if not defined COMMAND set /p "COMMAND=Console command: "
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\control.ps1" -Action command -CommandText "%COMMAND%"
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
