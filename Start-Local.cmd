@echo off
rem SPDX-License-Identifier: Apache-2.0
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows-local.ps1" -Action Start
if errorlevel 1 echo Setup did not finish. Keep the error message for troubleshooting.
pause
