@echo off
setlocal
set "TEMP=%~dp0tmp"
set "TMP=%TEMP%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\control.ps1" -Action status
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
