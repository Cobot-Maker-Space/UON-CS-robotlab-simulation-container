@echo off
rem Clears the compiled workspace cache so the next start re-seeds it from the image.
rem Needed after IT publishes a new image, because a Docker named volume is only ever seeded
rem when it is first created.
rem
rem Asks for confirmation. Leaves the student's source code alone.
title ROS Simulator - Reset
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0robotlab.ps1" reset
echo.
pause
