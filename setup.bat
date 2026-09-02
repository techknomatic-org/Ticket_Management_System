@echo off
setlocal enabledelayedexpansion

title GLPI Ticket Management System - Setup
cls
echo ===============================================================================
echo                GLPI TICKET MANAGEMENT SYSTEM - SETUP SCRIPT
echo ===============================================================================
echo.

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

:: -----------------------------------------------------------------------------
:: 1. Auto-detect or Configure PHP
:: -----------------------------------------------------------------------------
echo [*] Step 1/6: Checking PHP environment...

set "PHP_CMD="

:: Check if php is already in PATH
where php >nul 2>nul
if %errorlevel% equ 0 (
    set "PHP_CMD=php"
    goto :php_found
)

:: Search common PHP paths
set "WINGET_PHP_DIR=%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP.8.4_Microsoft.Winget.Source_8wekyb3d8bbwe"
if exist "%WINGET_PHP_DIR%\php.exe" (
    set "PHP_CMD=%WINGET_PHP_DIR%\php.exe"
    set "PATH=%WINGET_PHP_DIR%;!PATH!"
    goto :php_found
)

for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP*") do (
    if exist "%%D\php.exe" (
        set "PHP_CMD=%%D\php.exe"
        set "PATH=%%D;!PATH!"
        goto :php_found
    )
)

if exist "C:\tools\php\php.exe" (
    set "PHP_CMD=C:\tools\php\php.exe"
    set "PATH=C:\tools\php;!PATH!"
    goto :php_found
)

if exist "C:\xampp\php\php.exe" (
    set "PHP_CMD=C:\xampp\php\php.exe"
    set "PATH=C:\xampp\php;!PATH!"
    goto :php_found
)

:: PHP Not found - attempt to install via winget
echo [-] PHP not found in PATH or standard directories.
echo [*] Attempting to install PHP 8.4 via winget...
winget install PHP.PHP.8.4 --accept-package-agreements --accept-source-agreements --silent
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP*") do (
    if exist "%%D\php.exe" (
        set "PHP_CMD=%%D\php.exe"
        set "PATH=%%D;!PATH!"
        goto :php_found
    )
)

echo [ERROR] PHP is required but could not be installed automatically.
echo Please install PHP 8.2+ from https://windows.php.net/download/ and run setup.bat again.
pause
exit /b 1

:php_found
echo [+] PHP located: %PHP_CMD%
"%PHP_CMD%" -v | findstr /r "^PHP [0-9]"
echo.

:: Ensure OPENSSL_CONF is configured for Windows
if not defined OPENSSL_CONF (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\PHP.PHP*") do (
        if exist "%%D\extras\ssl\openssl.cnf" (
            set "OPENSSL_CONF=%%D\extras\ssl\openssl.cnf"
            powershell -NoProfile -ExecutionPolicy Bypass -Command "[System.Environment]::SetEnvironmentVariable('OPENSSL_CONF', '%%D\extras\ssl\openssl.cnf', 'User')" >nul 2>nul
        )
    )
)

:: -----------------------------------------------------------------------------
:: 2. Ensure php.ini with required extensions is configured
:: -----------------------------------------------------------------------------
echo [*] Step 2/6: Configuring PHP extensions and php.ini...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$phpPath = '%PHP_CMD%'; $phpDir = if (Test-Path $phpPath -PathType Leaf) { Split-Path $phpPath } else { (Get-Command $phpPath).Source | Split-Path }; $iniTarget = Join-Path $phpDir 'php.ini'; if (-not (Test-Path $iniTarget)) { Write-Host ('Creating configured php.ini at: ' + $iniTarget); $iniContent = @('[PHP]', 'engine = On', 'short_open_tag = Off', 'precision = 14', 'output_buffering = 4096', 'zlib.output_compression = Off', 'implicit_flush = Off', 'serialize_precision = -1', 'zend.enable_gc = On', 'expose_php = Off', 'max_execution_time = 300', 'max_input_time = 300', 'memory_limit = 512M', 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT', 'display_errors = On', 'display_startup_errors = On', 'log_errors = On', 'log_errors_max_len = 1024', 'variables_order = \"GPCS\"', 'request_order = \"GP\"', 'register_argc_argv = Off', 'auto_globals_jit = On', 'post_max_size = 100M', 'default_mimetype = \"text/html\"', 'default_charset = \"UTF-8\"', 'file_uploads = On', 'upload_max_filesize = 100M', 'max_file_uploads = 20', 'allow_url_fopen = On', 'allow_url_include = Off', 'default_socket_timeout = 60', 'extension_dir = \"ext\"', 'extension=bz2', 'extension=curl', 'extension=fileinfo', 'extension=gd', 'extension=gettext', 'extension=intl', 'extension=ldap', 'extension=mbstring', 'extension=exif', 'extension=mysqli', 'extension=openssl', 'extension=pdo_mysql', 'extension=pdo_sqlite', 'extension=shmop', 'extension=soap', 'extension=sockets', 'extension=sodium', 'extension=sqlite3', 'extension=tidy', 'extension=xsl', 'extension=zip', '[Date]', 'date.timezone = UTC', '[Session]', 'session.save_handler = files', 'session.use_strict_mode = 0', 'session.use_cookies = 1', 'session.use_only_cookies = 1', 'session.name = PHPSESSID', 'session.auto_start = 0', 'session.cookie_httponly = 1', '[opcache]', 'opcache.enable=1', 'opcache.enable_cli=1') -join \"`r`n\"; Set-Content -Path $iniTarget -Value $iniContent -Encoding UTF8 } else { Write-Host ('php.ini exists at: ' + $iniTarget) }"
echo [+] PHP configuration verified.
echo.

:: -----------------------------------------------------------------------------
:: 3. Check / Install Composer
:: -----------------------------------------------------------------------------
echo [*] Step 3/6: Checking Composer...
set "COMPOSER_CMD="

where composer >nul 2>nul
if %errorlevel% equ 0 (
    set "COMPOSER_CMD=composer"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$phpPath = '%PHP_CMD%'; $phpDir = if (Test-Path $phpPath -PathType Leaf) { Split-Path $phpPath } else { (Get-Command $phpPath).Source | Split-Path }; $phar = Join-Path $phpDir 'composer.phar'; if (-not (Test-Path $phar)) { Write-Host 'Downloading composer.phar...'; Invoke-WebRequest -Uri 'https://getcomposer.org/composer.phar' -OutFile $phar -UseBasicParsing }; $bat = Join-Path $phpDir 'composer.bat'; if (-not (Test-Path $bat)) { Set-Content -Path $bat -Value \"@echo off`r`n`\"%~dp0php.exe`\" `\"%~dp0composer.phar`\" %*\" -Encoding ASCII }"
    set "COMPOSER_CMD=composer"
)

echo [*] Installing Composer PHP dependencies...
call %COMPOSER_CMD% install --ansi --no-interaction --no-progress

:: Apply vendor patches if needed
if exist "tools\patches\guzzlehttp-guzzle-restrict-http-methods.patch" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$gitBash = 'C:\Users\' + $env:USERNAME + '\AppData\Local\Programs\Git\bin\bash.exe'; if (Test-Path $gitBash) { & $gitBash -c 'patch --dry-run -R --fuzz=0 -f -p1 -d vendor/guzzlehttp/guzzle/ < tools/patches/guzzlehttp-guzzle-restrict-http-methods.patch &>/dev/null || patch --fuzz=0 -f -p1 -d vendor/guzzlehttp/guzzle/ < tools/patches/guzzlehttp-guzzle-restrict-http-methods.patch' 2>`$null; & $gitBash -c 'patch --dry-run -R --fuzz=0 -f -p1 -d vendor/laminas/laminas-mail/ < tools/patches/laminas-laminas-mail-invalid-header-ignore.patch &>/dev/null || patch --fuzz=0 -f -p1 -d vendor/laminas/laminas-mail/ < tools/patches/laminas-laminas-mail-invalid-header-ignore.patch' 2>`$null; & $gitBash -c 'patch --dry-run -R --fuzz=0 -f -p1 -d vendor/wapmorgan/unified-archive/ < tools/patches/wapmorgan-unified-archive-php-8.5-compat.patch &>/dev/null || patch --fuzz=0 -f -p1 -d vendor/wapmorgan/unified-archive/ < tools/patches/wapmorgan-unified-archive-php-8.5-compat.patch' 2>`$null }"
)

:: Write .composer.hash and generate hardware JSONs
"%PHP_CMD%" -r "if(file_exists('composer.lock')){file_put_contents('.composer.hash', sha1_file('composer.lock'));}"
if exist "vendor\bin\build_hw_jsons" (
    "%PHP_CMD%" vendor\bin\build_hw_jsons >nul 2>nul
)

echo [+] Composer dependencies installed successfully.
echo.

:: -----------------------------------------------------------------------------
:: 4. Check Node.js and Install NPM Packages
:: -----------------------------------------------------------------------------
echo [*] Step 4/6: Checking Node.js and NPM dependencies...

where node >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Node.js is not installed or not in PATH.
    echo Please install Node.js (>= 20.9) from https://nodejs.org/
    pause
    exit /b 1
)

where npm >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] NPM is not installed or not in PATH.
    pause
    exit /b 1
)

echo [+] Node version:
node -v
echo [+] NPM version:
npm -v

echo [*] Installing NPM packages...
call npm install --no-save
"%PHP_CMD%" -r "if(file_exists('package-lock.json')){file_put_contents('.package.hash', sha1_file('package-lock.json'));}"

echo [*] Applying NPM patches...
call npx patch-package --patch-dir tools/patches/npm >nul 2>nul

echo [+] NPM packages installed successfully.
echo.

:: -----------------------------------------------------------------------------
:: 5. Build Frontend Assets & Compile Locales
:: -----------------------------------------------------------------------------
echo [*] Step 5/6: Building Webpack bundles and compiling locales...

echo [*] Compiling Webpack vendor pack...
call npm run build:pack

echo [*] Compiling Vue components...
call npm run build:vue

echo [*] Generating illustration translations...
call "%PHP_CMD%" bin\console tools:generate_illustration_translations --allow-superuser

echo [*] Compiling MO translation files...
set "GETTEXT_BIN=%LOCALAPPDATA%\Programs\gettext-iconv\bin"
if exist "%GETTEXT_BIN%\msgfmt.exe" (
    set "PATH=%GETTEXT_BIN%;!PATH!"
)
call "%PHP_CMD%" bin\console tools:locales:compile --allow-superuser

echo [+] Assets and locales compiled successfully.
echo.

:: -----------------------------------------------------------------------------
:: 6. Create Directories & Verify Requirements
:: -----------------------------------------------------------------------------
echo [*] Step 6/6: Verifying data directories and system requirements...

if not exist "config" mkdir "config"
if not exist "files\_cache" mkdir "files\_cache"
if not exist "files\_cron" mkdir "files\_cron"
if not exist "files\_dumps" mkdir "files\_dumps"
if not exist "files\_graphs" mkdir "files\_graphs"
if not exist "files\_inventories" mkdir "files\_inventories"
if not exist "files\_locales" mkdir "files\_locales"
if not exist "files\_lock" mkdir "files\_lock"
if not exist "files\_log" mkdir "files\_log"
if not exist "files\_pictures" mkdir "files\_pictures"
if not exist "files\_plugins" mkdir "files\_plugins"
if not exist "files\_rss" mkdir "files\_rss"
if not exist "files\_sessions" mkdir "files\_sessions"
if not exist "files\_themes" mkdir "files\_themes"
if not exist "files\_tmp" mkdir "files\_tmp"
if not exist "files\_uploads" mkdir "files\_uploads"
if not exist "marketplace" mkdir "marketplace"

echo [*] Running GLPI system requirement diagnostics...
call "%PHP_CMD%" bin\console system:check_requirements

echo.
echo ===============================================================================
echo                      GLPI SETUP COMPLETED SUCCESSFULLY!
echo ===============================================================================
echo.
echo You can now start the application by running:
echo     start.bat
echo.
echo Or stop the server anytime with:
echo     stop.bat
echo.
pause
