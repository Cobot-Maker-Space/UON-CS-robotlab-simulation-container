@echo off
rem Shuts down the containers. Does not touch the student's code or their build cache.
title ROS Simulator - Stop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" stop
echo.
pause
