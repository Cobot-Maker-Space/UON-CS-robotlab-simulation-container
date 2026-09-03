@echo off
rem Runs every preflight check and prints a report, without starting anything.
rem This is the first thing to try when a student says "it does not work".
title ROS Simulator - Check
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" doctor
echo.
pause
