@echo off
REM Minitiger Desktop - start with debug logging and follow the active runtime log.

setlocal
call "%~dp0common.bat"
call "%~dp0common.bat" :setup_runtime || exit /b 1

set "APP_EXE=%BUILD_DIR%\src\%EXE_NAME%"

if not exist "%APP_EXE%" (
    echo ERROR: Minitiger Desktop executable was not found:
    echo   %APP_EXE%
    echo.
    echo Run this first:
    echo   dev\windows\build.bat
    exit /b 1
)

echo Starting Minitiger Desktop with debug logging...
start "" "%APP_EXE%" --log-level debug %*

echo Waiting for the Minitiger Desktop runtime log...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0follow-debug-log.ps1"
set "RC=%ERRORLEVEL%"

endlocal & exit /b %RC%
