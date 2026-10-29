@echo off
rem Launches the WinFixKit GUI without a console window.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-FixKit.ps1"
