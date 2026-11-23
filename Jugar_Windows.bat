@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0run_windows.ps1" %*
if errorlevel 1 pause
