@echo off
rem Drag a Cisco IOL / IOL-L2 image file onto this file to import it.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Import-Image.ps1" -Path "%~1"
