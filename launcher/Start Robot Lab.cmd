@echo off
rem Double-click target for students. All the logic is in robotlab.ps1.
rem
rem -ExecutionPolicy Bypass applies to this one PowerShell process only. It changes nothing
rem system-wide and needs no admin rights, which is what makes this work on a locked-down
rem lab account.
title Robot Lab
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" start
if errorlevel 1 (
    echo.
    pause
)
