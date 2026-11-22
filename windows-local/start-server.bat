@echo off
setlocal
set "TEMP=%~dp0tmp"
set "TMP=%TEMP%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\control.ps1" -Action start
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
