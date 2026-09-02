@echo off
setlocal enabledelayedexpansion

title GLPI Ticket Management System - Server
cls

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "HOST=127.0.0.1"
set "PORT=8080"
set "URL=http://%HOST%:%PORT%"

echo ===============================================================================
echo                GLPI TICKET MANAGEMENT SYSTEM - START SERVER
echo ===============================================================================
echo.

:: -----------------------------------------------------------------------------
:: 1. Locate PHP
:: -----------------------------------------------------------------------------
set "PHP_CMD="

where php >nul 2>nul
if !errorlevel! equ 0 (
    set "PHP_CMD=php"
    goto :php_ready
)

set "WINGET_PHP_DIR=%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP.8.4_Microsoft.Winget.Source_8wekyb3d8bbwe"
if exist "%WINGET_PHP_DIR%\php.exe" (
    set "PHP_CMD=%WINGET_PHP_DIR%\php.exe"
    set "PATH=%WINGET_PHP_DIR%;!PATH!"
    goto :php_ready
)

for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP*") do (
    if exist "%%D\php.exe" (
        set "PHP_CMD=%%D\php.exe"
        set "PATH=%%D;!PATH!"
        goto :php_ready
    )
)

if exist "C:\tools\php\php.exe" (
    set "PHP_CMD=C:\tools\php\php.exe"
    set "PATH=C:\tools\php;!PATH!"
    goto :php_ready
)

if exist "C:\xampp\php\php.exe" (
    set "PHP_CMD=C:\xampp\php\php.exe"
    set "PATH=C:\xampp\php;!PATH!"
    goto :php_ready
)

echo [ERROR] PHP executable was not found.
echo Please run setup.bat first to install PHP and dependencies.
pause
:php_ready

:: Ensure OPENSSL_CONF is configured for Windows
if not defined OPENSSL_CONF (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP*") do (
        if exist "%%D\extras\ssl\openssl.cnf" set "OPENSSL_CONF=%%D\extras\ssl\openssl.cnf"
    )
    if not defined OPENSSL_CONF (
        if exist "C:\tools\php\extras\ssl\openssl.cnf" set "OPENSSL_CONF=C:\tools\php\extras\ssl\openssl.cnf"
    )
    if not defined OPENSSL_CONF (
        if exist "C:\xampp\php\extras\ssl\openssl.cnf" set "OPENSSL_CONF=C:\xampp\php\extras\ssl\openssl.cnf"
    )
)

:: -----------------------------------------------------------------------------
:: 2. Check dependencies
:: -----------------------------------------------------------------------------
if not exist "vendor\autoload.php" (
    echo [!] Dependencies are not installed.
    echo [*] Running setup.bat...
    call setup.bat
)

:: -----------------------------------------------------------------------------
:: 3. Check and Start MySQL Service (if installed)
:: -----------------------------------------------------------------------------
echo [*] Checking MySQL / MariaDB database service...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$services = Get-Service -Name '*mysql*', '*mariadb*' -ErrorAction SilentlyContinue; if ($services) { foreach ($svc in $services) { if ($svc.Status -ne 'Running') { Write-Host ('[*] Starting database service: ' + $svc.DisplayName + '...'); Start-Service -Name $svc.Name -ErrorAction SilentlyContinue } else { Write-Host ('[+] Database service is running: ' + $svc.DisplayName) } } } else { Write-Host '[i] No local MySQL/MariaDB Windows service detected.' }"

:: -----------------------------------------------------------------------------
:: 4. Check if Port is already active
:: -----------------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if !errorlevel! equ 0 (
    echo.
    echo [WARNING] A process is already listening on port %PORT%.
    echo Opening application at %URL%...
    start "" "%URL%"
    echo.
    echo To stop the existing server, run: stop.bat
    echo.
    pause
    exit /b 0
)

:: Ensure log directory exists
if not exist "files\_log" mkdir "files\_log"

:: -----------------------------------------------------------------------------
:: 5. Launch PHP Built-in Server in Background
:: -----------------------------------------------------------------------------
echo [*] Launching GLPI web server on %URL%...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$phpPath = '%PHP_CMD%'; $phpExe = if (Test-Path $phpPath -PathType Leaf) { $phpPath } else { (Get-Command $phpPath).Source }; $root = '%SCRIPT_DIR%'.TrimEnd('\'); $stdout = Join-Path $root 'files\_log\server.log'; $stderr = Join-Path $root 'files\_log\server-err.log'; $proc = Start-Process -FilePath $phpExe -ArgumentList '-S', '%HOST%:%PORT%', '-t', 'public', 'public/index.php' -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru; if ($proc) { Set-Content -Path (Join-Path $root '.server.pid') -Value $proc.Id -Encoding ASCII; Write-Host ('[+] Server process started with PID: ' + $proc.Id) } else { Write-Host '[ERROR] Failed to start PHP server.'; exit 1 }"

:: Wait 2 seconds for server initialization
ping -n 3 127.0.0.1 >nul

:: Verify server is responding
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-NetTCPConnection -LocalPort %PORT% -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if !errorlevel! equ 0 (
    echo [+] Server is actively listening on %URL%
) else (
    echo [!] Server starting...
)

:: -----------------------------------------------------------------------------
:: 6. Open Browser and Display Dashboard Info
:: -----------------------------------------------------------------------------
start "" "%URL%"

echo.
echo ===============================================================================
echo                     GLPI APPLICATION SERVER IS RUNNING
echo ===============================================================================
echo.
echo   URL:           %URL%
echo   Document Root: %SCRIPT_DIR%public
echo   Server Logs:   %SCRIPT_DIR%files\_log\server-err.log
echo   App Logs:      %SCRIPT_DIR%files\_log\php-errors.log
echo.
echo -------------------------------------------------------------------------------
echo   Default Credentials (after database initialization):
echo     * Super-Admin:     Username: glpi        / Password: glpi
echo     * Technician:      Username: tech        / Password: tech
echo     * Normal User:     Username: normal      / Password: normal
echo     * Self-Service:    Username: post-only   / Password: postonly
echo.
echo   Useful Console Commands:
echo     * Requirement check:  php bin/console system:check_requirements
echo     * Database status:    php bin/console database:is_up_to_date
echo     * Clear cache:        php bin/console cache:clear
echo     * Help / All tools:   php bin/console list
echo -------------------------------------------------------------------------------
echo.
echo   To STOP the server at any time, run:
echo       stop.bat
echo.
echo ===============================================================================
echo [Server running in background. You may close this window or keep it open.]
echo.
pause
