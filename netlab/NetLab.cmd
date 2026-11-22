@echo off
rem NetLab menu: deploy labs, consoles (PuTTY), capture (Wireshark), tests, RAM report.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\NetLab-Menu.ps1"
