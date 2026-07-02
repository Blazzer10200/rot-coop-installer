@echo off
REM ============================================================
REM  Realm of Thrones + Co-op  -  Setup & Repair Tool
REM  Double-click this file to run. That's it.
REM ============================================================
title Realm of Thrones Co-op Tool
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\ROT-CoopSetup.ps1"
if errorlevel 1 (
  echo.
  echo  Something went wrong starting the tool.
  echo  Make sure the whole folder was extracted, not run from inside the zip.
  echo.
  pause
)
