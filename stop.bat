@echo off
setlocal enabledelayedexpansion

title GLPI Ticket Management System - Stop Server
cls

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "PORT=8080"

echo ===============================================================================
echo                GLPI TICKET MANAGEMENT SYSTEM - STOP SERVER
echo ===============================================================================
echo.

set "STOPPED=0"

:: -----------------------------------------------------------------------------
:: 1. Stop by PID file
:: -----------------------------------------------------------------------------
if exist ".server.pid" (
    set /p SERVER_PID=<".server.pid"
    if defined SERVER_PID (
        echo [*] Found server PID: !SERVER_PID!
        taskkill /F /PID !SERVER_PID! >nul 2>nul
        if !errorlevel! equ 0 (
            echo [+] Stopped process with PID !SERVER_PID!.
            set "STOPPED=1"
        )
    )
    del /f /q ".server.pid" >nul 2>nul
)

:: -----------------------------------------------------------------------------
:: 2. Find and terminate any remaining process listening on port 8080
:: -----------------------------------------------------------------------------
echo [*] Checking for active processes on port %PORT%...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$port = %PORT%; $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue; if ($conns) { foreach ($c in $conns) { $pidVal = $c.OwningProcess; if ($pidVal -gt 0) { $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue; if ($p) { Write-Host ('[*] Stopping process on port ' + $port + ': ' + $p.ProcessName + ' (PID: ' + $pidVal + ')...'); Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue; Write-Host ('[+] Process ' + $pidVal + ' terminated.') } } } } else { Write-Host ('[+] No active process found on port ' + $port + '.') }"

:: Clean up temporary locks if needed
if exist "files\_lock\*.lock" (
    del /f /q "files\_lock\*.lock" >nul 2>nul
)

:: Terminate any running ngrok node helper
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*start-ngrok.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('[+] Stopped ngrok tunnel process (PID: ' + $_.ProcessId + ')') }"


echo.
echo ===============================================================================
echo                     GLPI APPLICATION SERVER IS STOPPED
echo ===============================================================================
echo.
echo You can start the server again anytime by running:
echo     start.bat
echo.
pause
