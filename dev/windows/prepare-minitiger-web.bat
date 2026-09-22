@echo off
REM Minitiger Desktop - prepare the bundled Minitiger Web frontend
REM Desktop-only frontend source: Grunttanamo/Minitiger-Desktop-Web, branch minitiger-desktop-v12.1.

setlocal EnableDelayedExpansion
call "%~dp0common.bat"

where git.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: git.exe is not available on PATH.
    exit /b 1
)

where node.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js is not available on PATH.
    echo Run dev\windows\setup.bat, then open a NEW PowerShell window.
    exit /b 1
)

where npm.cmd >nul 2>&1
if errorlevel 1 (
    echo ERROR: npm.cmd is not available on PATH.
    echo Run dev\windows\setup.bat, then open a NEW PowerShell window.
    exit /b 1
)

for /f "delims=" %%V in ('node -p "Number(process.versions.node.split('.')[0])"') do set "NODE_MAJOR=%%V"
if !NODE_MAJOR! LSS 24 (
    echo ERROR: Minitiger Web requires Node.js 24 or newer. Found:
    node --version
    echo Run dev\windows\setup.bat to install/update Node.js LTS.
    exit /b 1
)

if not exist "%DEPS_DIR%" mkdir "%DEPS_DIR%"

if not exist "%MINITIGER_WEB_SOURCE_DIR%\.git" (
    echo.
    echo [Minitiger Web] Cloning authoritative frontend...
    git clone --branch "%MINITIGER_WEB_BRANCH%" --single-branch "%MINITIGER_WEB_REPO%" "%MINITIGER_WEB_SOURCE_DIR%"
    if errorlevel 1 (
        echo ERROR: Failed to clone Minitiger Web.
        exit /b 1
    )
)

pushd "%MINITIGER_WEB_SOURCE_DIR%"

REM Existing build caches may still point at the public Sidecar/Web repository.
REM Always bind this Desktop checkout to the dedicated Desktop-Web source.
git remote set-url origin "%MINITIGER_WEB_REPO%"
if errorlevel 1 (
    popd
    echo ERROR: Failed to configure Minitiger Desktop Web origin.
    exit /b 1
)

echo.
echo [Minitiger Web] Syncing %MINITIGER_WEB_BRANCH%...
git fetch origin "%MINITIGER_WEB_BRANCH%"
if errorlevel 1 (
    popd
    echo ERROR: Failed to fetch Minitiger Web.
    exit /b 1
)

git checkout -B "%MINITIGER_WEB_BRANCH%" "origin/%MINITIGER_WEB_BRANCH%"
if errorlevel 1 (
    popd
    echo ERROR: Failed to checkout Minitiger Web branch.
    exit /b 1
)

for /f "delims=" %%C in ('git rev-parse HEAD') do set "MINITIGER_WEB_COMMIT=%%C"

set "BUILT_COMMIT="
if exist ".minitiger-desktop-built-commit" (
    set /p BUILT_COMMIT=<".minitiger-desktop-built-commit"
)

if exist "dist\index.html" if /i "!BUILT_COMMIT!"=="!MINITIGER_WEB_COMMIT!" (
    echo [Minitiger Web] Production bundle already matches !MINITIGER_WEB_COMMIT!.
    popd
    exit /b 0
)

echo [Minitiger Web] Installing npm dependencies...
call npm.cmd ci
if errorlevel 1 (
    popd
    echo ERROR: npm ci failed for Minitiger Web.
    exit /b 1
)

echo [Minitiger Web] Building production frontend...
call npm.cmd run build:production
if errorlevel 1 (
    popd
    echo ERROR: Minitiger Web production build failed.
    exit /b 1
)

if not exist "dist\index.html" (
    popd
    echo ERROR: Minitiger Web build completed without dist\index.html.
    exit /b 1
)

if not exist "dist\config.json" (
    popd
    echo ERROR: Minitiger Web build completed without dist\config.json.
    exit /b 1
)

> ".minitiger-desktop-built-commit" echo !MINITIGER_WEB_COMMIT!

echo [Minitiger Web] Bundle ready:
echo   Source: %MINITIGER_WEB_REPO%
echo   Branch: %MINITIGER_WEB_BRANCH%
echo   Commit: !MINITIGER_WEB_COMMIT!
echo   Dist:   %MINITIGER_WEB_DIST_DIR%

popd
endlocal
