@echo off
REM ============================================================
REM  Realm of Thrones + Co-op  -  Setup & Repair Tool
REM  Double-click this file to run. That's it.
REM ============================================================
title Realm of Thrones Co-op Tool
cd /d "%~dp0"
echo.
echo   Starting the Realm of Thrones Co-op Tool...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\ROT-CoopSetup.ps1"
if errorlevel 1 (
  echo.
  echo  ------------------------------------------------------------
  echo   The tool could not start. This is usually one of two things:
  echo.
  echo    1. The folder wasn't fully extracted. Right-click the ZIP,
  echo       choose "Extract All", and run Start.bat from the extracted
  echo       folder (not from inside the ZIP preview).
  echo.
  echo    2. Windows blocked the script. Right-click Start.bat and
  echo       choose "Run as administrator", or unblock it in Properties.
  echo  ------------------------------------------------------------
  echo.
  pause
)
