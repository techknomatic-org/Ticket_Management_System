@echo off
setlocal enabledelayedexpansion

title GLPI - Start Ngrok Tunnel
cls

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo ===============================================================================
echo                GLPI TICKET MANAGEMENT SYSTEM - NGROK TUNNEL
echo ===============================================================================
echo.
echo [*] Starting persistent Ngrok tunnel to port 8080...
echo.

node tools/start-ngrok.js

pause
