@echo off
REM Minitiger Desktop - Windows bundling script
REM Run build.bat first

setlocal enabledelayedexpansion
call "%~dp0common.bat"

REM === Check build exists ===
if not exist "%BUILD_DIR%\src\%EXE_NAME%" (
    echo ERROR: Build not found. Run build.bat first
    exit /b 1
)

REM === Check Visual Studio ===
if not defined VCVARS (
    echo ERROR: vcvars64.bat not found
    exit /b 1
)
echo Using: %VCVARS%

REM === Initialize VS environment ===
call "%VCVARS%"
if errorlevel 1 (
    echo ERROR: Failed to initialize VS environment
    exit /b 1
)

REM === Add tools to PATH ===
set "PATH=%PATH%;%LocalAppData%\Programs\Inno Setup 6"
set "PATH=%PATH%;C:\Program Files\Git\cmd"

cd /d "%BUILD_DIR%"

REM === Always package from a clean staging area ===
REM This prevents stale binaries, portable data/cache, profiles or settings from
REM ever leaking into a distributable package.
if exist "%BUILD_DIR%\output" rmdir /s /q "%BUILD_DIR%\output"
if exist "%BUILD_DIR%\portable" rmdir /s /q "%BUILD_DIR%\portable"
del /q "%BUILD_DIR%\Minitiger-Desktop-*-Installer.exe" 2>nul
del /q "%BUILD_DIR%\Minitiger-Desktop-*-Portable.zip" 2>nul
del /q "%BUILD_DIR%\JellyfinDesktop-*.exe" 2>nul
del /q "%BUILD_DIR%\JellyfinDesktop-*.zip" 2>nul

REM === Package ===
echo Creating clean Minitiger installer and portable ZIP...
ninja windows_all
if errorlevel 1 (
    echo ERROR: Package creation failed
    exit /b 1
)

echo.
echo Bundle complete!
echo Installer: %BUILD_DIR%\Minitiger-Desktop-*-Installer.exe
echo Portable:  %BUILD_DIR%\Minitiger-Desktop-*-Portable.zip
endlocal
