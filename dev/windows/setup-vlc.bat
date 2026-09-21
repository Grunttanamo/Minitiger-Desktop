@echo off
REM Minitiger Desktop - experimental libVLC dependency installer
REM Downloads a private VLC runtime plus the matching public headers.
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

if not defined VCVARS (
    echo ERROR: Visual Studio 2022 C++ Build Tools were not found.
    echo Run setup.bat first and make sure the VCTools workload is installed.
    exit /b 1
)

if exist "!VLC_DIR!\libvlc.dll" if exist "!VLC_DIR!\libvlccore.dll" if exist "!VLC_DIR!\plugins" if exist "!VLC_DIR!\include\vlc\libvlc.h" if exist "!VLC_DIR!\lib\libvlc.lib" (
    echo libVLC !VLC_VERSION! already prepared at:
    echo   !VLC_DIR!
    exit /b 0
)

if not exist "!DEPS_DIR!" mkdir "!DEPS_DIR!"
if exist "!VLC_DIR!" rmdir /s /q "!VLC_DIR!"
if exist "!DEPS_DIR!\vlc_runtime_tmp" rmdir /s /q "!DEPS_DIR!\vlc_runtime_tmp"
if exist "!DEPS_DIR!\vlc_source_tmp" rmdir /s /q "!DEPS_DIR!\vlc_source_tmp"

set "VLC_RUNTIME_ARCHIVE=!DEPS_DIR!\vlc-!VLC_VERSION!-win64.zip"
set "VLC_SOURCE_ARCHIVE=!DEPS_DIR!\vlc-!VLC_VERSION!.tar.xz"
set "VLC_RUNTIME_URL=https://download.videolan.org/pub/videolan/vlc/!VLC_VERSION!/win64/vlc-!VLC_VERSION!-win64.zip"
set "VLC_SOURCE_URL=https://download.videolan.org/pub/videolan/vlc/!VLC_VERSION!/vlc-!VLC_VERSION!.tar.xz"

del /q "!VLC_RUNTIME_ARCHIVE!" 2>nul
del /q "!VLC_SOURCE_ARCHIVE!" 2>nul

echo [VLC 1/4] Downloading VLC !VLC_VERSION! Windows runtime...
curl -L --fail "!VLC_RUNTIME_URL!" -o "!VLC_RUNTIME_ARCHIVE!"
if errorlevel 1 (
    echo ERROR: Failed to download VLC Windows runtime.
    exit /b 1
)

echo [VLC 2/4] Extracting VLC runtime...
"!SEVENZIP!" x "!VLC_RUNTIME_ARCHIVE!" -o"!DEPS_DIR!\vlc_runtime_tmp" -y >nul
if errorlevel 1 (
    echo ERROR: Failed to extract VLC runtime archive.
    exit /b 1
)

set "VLC_RUNTIME_SRC=!DEPS_DIR!\vlc_runtime_tmp\vlc-!VLC_VERSION!"
if not exist "!VLC_RUNTIME_SRC!\libvlc.dll" (
    for /d %%D in ("!DEPS_DIR!\vlc_runtime_tmp\*") do (
        if exist "%%~fD\libvlc.dll" set "VLC_RUNTIME_SRC=%%~fD"
    )
)

if not exist "!VLC_RUNTIME_SRC!\libvlc.dll" (
    echo ERROR: libvlc.dll not found in the official Windows archive.
    exit /b 1
)
if not exist "!VLC_RUNTIME_SRC!\libvlccore.dll" (
    echo ERROR: libvlccore.dll not found in the official Windows archive.
    exit /b 1
)
if not exist "!VLC_RUNTIME_SRC!\plugins" (
    echo ERROR: VLC plugins directory not found in the official Windows archive.
    exit /b 1
)

mkdir "!VLC_DIR!"
xcopy /e /i /y "!VLC_RUNTIME_SRC!\*" "!VLC_DIR!\" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy VLC runtime files.
    exit /b 1
)

echo [VLC 3/4] Downloading matching VLC source headers...
curl -L --fail "!VLC_SOURCE_URL!" -o "!VLC_SOURCE_ARCHIVE!"
if errorlevel 1 (
    echo ERROR: Failed to download VLC source archive.
    exit /b 1
)

mkdir "!DEPS_DIR!\vlc_source_tmp"
"!SEVENZIP!" x "!VLC_SOURCE_ARCHIVE!" -o"!DEPS_DIR!\vlc_source_tmp" -y >nul
if errorlevel 1 (
    echo ERROR: Failed to unpack VLC source .xz archive.
    exit /b 1
)

set "VLC_SOURCE_TAR=!DEPS_DIR!\vlc_source_tmp\vlc-!VLC_VERSION!.tar"
if not exist "!VLC_SOURCE_TAR!" (
    for %%F in ("!DEPS_DIR!\vlc_source_tmp\*.tar") do set "VLC_SOURCE_TAR=%%~fF"
)
if not exist "!VLC_SOURCE_TAR!" (
    echo ERROR: VLC source TAR was not produced after extracting the .xz archive.
    exit /b 1
)

"!SEVENZIP!" x "!VLC_SOURCE_TAR!" -o"!DEPS_DIR!\vlc_source_tmp\src" -y >nul
if errorlevel 1 (
    echo ERROR: Failed to extract VLC source TAR.
    exit /b 1
)

set "VLC_SOURCE_SRC=!DEPS_DIR!\vlc_source_tmp\src\vlc-!VLC_VERSION!"
if not exist "!VLC_SOURCE_SRC!\include\vlc\libvlc.h" (
    for /d %%D in ("!DEPS_DIR!\vlc_source_tmp\src\*") do (
        if exist "%%~fD\include\vlc\libvlc.h" set "VLC_SOURCE_SRC=%%~fD"
    )
)
if not exist "!VLC_SOURCE_SRC!\include\vlc\libvlc.h" (
    echo ERROR: libVLC public headers were not found in the VLC source archive.
    exit /b 1
)

mkdir "!VLC_DIR!\include" 2>nul
xcopy /e /i /y "!VLC_SOURCE_SRC!\include\vlc" "!VLC_DIR!\include\vlc\" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy libVLC headers.
    exit /b 1
)

echo [VLC 4/4] Generating MSVC libvlc import library...
mkdir "!VLC_DIR!\lib" 2>nul

call "!VCVARS!" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Failed to initialize Visual Studio build environment.
    exit /b 1
)

echo LIBRARY libvlc.dll > "!VLC_DIR!\lib\libvlc.def"
echo EXPORTS >> "!VLC_DIR!\lib\libvlc.def"
for /f "skip=19 tokens=4" %%a in ('dumpbin /exports "!VLC_DIR!\libvlc.dll"') do (
    if not "%%a"=="" echo %%a >> "!VLC_DIR!\lib\libvlc.def"
)

lib /def:"!VLC_DIR!\lib\libvlc.def" /out:"!VLC_DIR!\lib\libvlc.lib" /MACHINE:X64
if errorlevel 1 (
    echo ERROR: Failed to create libvlc.lib.
    exit /b 1
)

if not exist "!VLC_DIR!\lib\libvlc.lib" (
    echo ERROR: libvlc.lib was not created.
    exit /b 1
)

rmdir /s /q "!DEPS_DIR!\vlc_runtime_tmp"
rmdir /s /q "!DEPS_DIR!\vlc_source_tmp"
del /q "!VLC_RUNTIME_ARCHIVE!"
del /q "!VLC_SOURCE_ARCHIVE!"

echo.
echo libVLC !VLC_VERSION! prepared successfully:
echo   Runtime: !VLC_DIR!
echo   Headers: !VLC_DIR!\include
echo   Library: !VLC_DIR!\lib\libvlc.lib
echo.
echo Phase 1 note: MPV is still the active player. This only prepares libVLC for the native backend.
endlocal
