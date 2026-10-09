@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Analyze Gaming.ps1"
if errorlevel 1 pause
