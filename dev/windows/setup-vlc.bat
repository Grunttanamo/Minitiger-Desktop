@echo off
REM Minitiger Desktop - experimental libVLC dependency installer
REM Installs a private libVLC SDK/runtime below dev\windows\deps.
REM This does NOT install VLC system-wide.

setlocal EnableDelayedExpansion
call "%~dp0common.bat"

set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"
if not exist "!SEVENZIP!" (
    for /f "delims=" %%i in ('where 7z.exe 2^>nul') do (
        set "SEVENZIP=%%i"
        goto :found7zip
    )
)
:found7zip

if not exist "!SEVENZIP!" (
    echo ERROR: 7-Zip was not found. Run setup.bat first.
    exit /b 1
)

if exist "!VLC_DIR!\libvlc.dll" if exist "!VLC_DIR!\sdk\lib\libvlc.lib" if exist "!VLC_DIR!\sdk\include\vlc\libvlc.h" if exist "!VLC_DIR!\plugins" (
    echo libVLC !VLC_VERSION! already installed at:
    echo   !VLC_DIR!
    exit /b 0
)

if not exist "!DEPS_DIR!" mkdir "!DEPS_DIR!"
if exist "!VLC_DIR!" rmdir /s /q "!VLC_DIR!"
if exist "!DEPS_DIR!\vlc_tmp" rmdir /s /q "!DEPS_DIR!\vlc_tmp"

set "VLC_ARCHIVE=!DEPS_DIR!\vlc-!VLC_VERSION!-win64.zip"
set "VLC_URL=https://download.videolan.org/pub/videolan/vlc/!VLC_VERSION!/win64/vlc-!VLC_VERSION!-win64.zip"

echo Downloading libVLC !VLC_VERSION!...
curl -L --fail "!VLC_URL!" -o "!VLC_ARCHIVE!"
if errorlevel 1 (
    echo ERROR: Failed to download VLC !VLC_VERSION!.
    exit /b 1
)

echo Extracting libVLC...
"!SEVENZIP!" x "!VLC_ARCHIVE!" -o"!DEPS_DIR!\vlc_tmp" -y >nul
if errorlevel 1 (
    echo ERROR: Failed to extract VLC archive.
    exit /b 1
)

set "VLC_SRC=!DEPS_DIR!\vlc_tmp\vlc-!VLC_VERSION!"
if not exist "!VLC_SRC!\libvlc.dll" (
    for /d %%D in ("!DEPS_DIR!\vlc_tmp\*") do (
        if exist "%%~fD\libvlc.dll" set "VLC_SRC=%%~fD"
    )
)

if not exist "!VLC_SRC!\libvlc.dll" (
    echo ERROR: libvlc.dll not found in extracted archive.
    exit /b 1
)
if not exist "!VLC_SRC!\libvlccore.dll" (
    echo ERROR: libvlccore.dll not found in extracted archive.
    exit /b 1
)
if not exist "!VLC_SRC!\sdk\include\vlc\libvlc.h" (
    echo ERROR: libVLC SDK headers not found in extracted archive.
    exit /b 1
)
if not exist "!VLC_SRC!\sdk\lib\libvlc.lib" (
    echo ERROR: libVLC MSVC import library not found in extracted archive.
    exit /b 1
)
if not exist "!VLC_SRC!\plugins" (
    echo ERROR: VLC plugins directory not found in extracted archive.
    exit /b 1
)

mkdir "!VLC_DIR!"
xcopy /e /i /y "!VLC_SRC!\*" "!VLC_DIR!\" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy libVLC files into the dependency directory.
    exit /b 1
)

rmdir /s /q "!DEPS_DIR!\vlc_tmp"
del /q "!VLC_ARCHIVE!"

echo.
echo libVLC !VLC_VERSION! installed successfully:
echo   !VLC_DIR!
echo.
echo Phase 1 note: VLC is now available to the native build,
echo but MPV remains the active playback backend until the VLC surface is implemented.
endlocal
