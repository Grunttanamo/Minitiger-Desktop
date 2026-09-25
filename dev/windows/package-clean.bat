@echo off
REM Build clean, private/local Minitiger Desktop distribution packages.
REM This script NEVER uploads artifacts to GitHub or creates a GitHub Release.

setlocal
call "%~dp0common.bat"

echo.
echo ============================================================
echo   Minitiger Desktop - Clean Local Distribution Build
echo ============================================================
echo.
echo This will create:
echo   - Windows Installer EXE
echo   - Portable ZIP
echo.
echo No personal profiles, settings, browser storage, cache or logs
echo are copied into the packages.
echo Nothing will be uploaded to GitHub.
echo.

set "MINITIGER_DISTRIBUTION=1"

call "%~dp0build.bat"
if errorlevel 1 (
    echo ERROR: Distribution build failed.
    exit /b 1
)

call "%~dp0bundle.bat"
if errorlevel 1 (
    echo ERROR: Distribution packaging failed.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-clean-finalize.ps1"
if errorlevel 1 (
    echo ERROR: Distribution validation/finalization failed.
    exit /b 1
)

echo.
echo Finished. Files are in:
echo   %PROJECT_ROOT%\dist
echo.
endlocal
