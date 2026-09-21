@echo off
REM Minitiger Desktop - Run built executable
REM Run build.bat first

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

REM === Run ===
"%APP_EXE%" %*
set EXIT_CODE=%ERRORLEVEL%

endlocal & exit /b %EXIT_CODE%
