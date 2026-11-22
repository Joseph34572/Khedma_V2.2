@echo off
rem NetLab one-time setup. Double-click this file.
rem Each step that changes your system asks first.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Setup-NetLab.ps1"
