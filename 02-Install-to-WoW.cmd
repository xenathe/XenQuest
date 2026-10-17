@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\Install-Dev.ps1" %*
echo.
pause
