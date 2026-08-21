@echo off
title win11-post-install - Windows 11 IoT LTSC
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0win11-post-install.ps1" %*
if errorlevel 1 (
  echo.
  echo Ocurrio un error. Revisa la consola.
  pause
)
