@echo off
rem Read-only check of this PC for NetLab (changes nothing).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Check-Environment.ps1"
pause
