@echo off
REM Minitiger Desktop / Jellyfin Desktop - Common Windows variables
REM Sourced by other scripts

set QT_VERSION=6.10.1

REM Pinned to a currently published shinchiro mpv-winbuild-cmake release.
REM The previous upstream 20260223 tag no longer exists.
set MPV_RELEASE=20260921
set MPV_VERSION=20260921-git-e76a35ec95

set VLC_VERSION=3.0.23

REM Minitiger Web is the authoritative frontend source for the desktop bundle.
set MINITIGER_WEB_REPO=https://github.com/Grunttanamo/Minitiger-Desktop-Web.git
set MINITIGER_WEB_BRANCH=minitiger-desktop-v12.1

set SCRIPT_DIR=%~dp0
for %%i in ("%SCRIPT_DIR%\..\..") do set "PROJECT_ROOT=%%~fi"
set DEPS_DIR=%SCRIPT_DIR%deps
set VLC_DIR=%DEPS_DIR%\vlc-%VLC_VERSION%
set MINITIGER_WEB_SOURCE_DIR=%DEPS_DIR%\minitiger-web-src
set MINITIGER_WEB_DIST_DIR=%MINITIGER_WEB_SOURCE_DIR%\dist
set BUILD_DIR=%PROJECT_ROOT%\build
set EXE_NAME=Jellyfin Desktop.exe

REM === Find Visual Studio ===
set VCVARS=
set "VS_BT=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
set "VS_CM=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
set "VS_PR=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
set "VS_EN=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
set "VS_BT86=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

if exist "%VS_BT%" set "VCVARS=%VS_BT%"
if not defined VCVARS if exist "%VS_CM%" set "VCVARS=%VS_CM%"
if not defined VCVARS if exist "%VS_PR%" set "VCVARS=%VS_PR%"
if not defined VCVARS if exist "%VS_EN%" set "VCVARS=%VS_EN%"
if not defined VCVARS if exist "%VS_BT86%" set "VCVARS=%VS_BT86%"

if "%~1"=="" goto :eof
goto %~1

REM === Setup runtime PATH for DLLs ===
REM Call with: call "%~dp0common.bat" :setup_runtime
:setup_runtime
if not exist "%BUILD_DIR%" (
    echo ERROR: Build not found. Run build.bat first
    exit /b 1
)
set "PATH=%DEPS_DIR%\mpv;%PATH%"
if exist "%VLC_DIR%\libvlc.dll" set "PATH=%VLC_DIR%;%PATH%"
if exist "%VLC_DIR%\plugins" set "VLC_PLUGIN_PATH=%VLC_DIR%\plugins"
set "PATH=%DEPS_DIR%\qt\%QT_VERSION%\msvc2022_64\bin;%PATH%"
goto :eof
