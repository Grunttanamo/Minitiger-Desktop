@echo off
REM Minitiger Desktop - Windows build script
REM Run setup.bat and setup-vlc.bat first.

setlocal enabledelayedexpansion
call "%~dp0common.bat"

REM === Ensure git submodules are present ===
if not exist "%PROJECT_ROOT%\external\mpvqt\src\mpvabstractitem.cpp" (
    echo Preparing git submodules...
    pushd "%PROJECT_ROOT%"
    git submodule update --init --recursive
    if errorlevel 1 (
        popd
        echo ERROR: Failed to initialize git submodules.
        exit /b 1
    )
    popd
)

REM === Check dependencies ===
if not exist "%DEPS_DIR%\mpv\libmpv-2.dll" (
    echo ERROR: libmpv not found. Run dev\windows\setup.bat first.
    exit /b 1
)
if not exist "%DEPS_DIR%\vcruntime\*.dll" (
    echo ERROR: VC runtime DLLs not found. Run dev\windows\setup.bat first.
    exit /b 1
)

if not exist "%VLC_DIR%\libvlc.dll" (
    echo ERROR: libVLC runtime not found. Run dev\windows\setup-vlc.bat first.
    exit /b 1
)
if not exist "%VLC_DIR%\include\vlc\libvlc.h" (
    echo ERROR: libVLC headers not found. Run dev\windows\setup-vlc.bat first.
    exit /b 1
)
if not exist "%VLC_DIR%\lib\libvlc.lib" (
    echo ERROR: libVLC import library not found. Run dev\windows\setup-vlc.bat first.
    exit /b 1
)

REM === Find Qt ===
set QTROOT_WIN=%DEPS_DIR%\qt\%QT_VERSION%\msvc2022_64
set "QTROOT=%QTROOT_WIN:\=/%"
if not exist "%QTROOT_WIN%" (
    echo ERROR: Qt not found at %QTROOT_WIN%
    echo Run dev\windows\setup.bat first.
    exit /b 1
)
echo Using Qt: %QTROOT%

REM === Check Visual Studio ===
if not defined VCVARS (
    echo ERROR: vcvars64.bat not found.
    echo Make sure Visual Studio 2022 C++ Build Tools are installed.
    exit /b 1
)
echo Using: %VCVARS%

REM === Initialize VS environment ===
call "%VCVARS%"
if errorlevel 1 (
    echo ERROR: Failed to initialize VS environment.
    exit /b 1
)

REM CMake/Ninja installed by winget may require a new shell before they become
REM visible on PATH. Fail with a useful message instead of a confusing error.
where cmake.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: cmake.exe is not on PATH.
    echo Close PowerShell, open a NEW PowerShell window, return to the repo, and run build.bat again.
    exit /b 1
)
where ninja.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: ninja.exe is not on PATH.
    echo Close PowerShell, open a NEW PowerShell window, return to the repo, and run build.bat again.
    exit /b 1
)

REM === Setup build directory ===
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

REM === Generate mpv import library if needed ===
if not exist "%DEPS_DIR%\mpv\libmpv-2.dll.lib" (
    echo Generating mpv import library...
    echo LIBRARY libmpv-2.dll > "%DEPS_DIR%\mpv\mpv.def"
    echo EXPORTS >> "%DEPS_DIR%\mpv\mpv.def"
    for /f "skip=19 tokens=4" %%a in ('dumpbin /exports "%DEPS_DIR%\mpv\libmpv-2.dll"') do (
        if not "%%a"=="" echo %%a >> "%DEPS_DIR%\mpv\mpv.def"
    )
    lib /def:"%DEPS_DIR%\mpv\mpv.def" /out:"%DEPS_DIR%\mpv\libmpv-2.dll.lib" /MACHINE:X64
    if errorlevel 1 (
        echo ERROR: Failed to create mpv import library.
        exit /b 1
    )
)

REM === Configure ===
set "DEPS_CMAKE=%DEPS_DIR:\=/%"
set "VLC_CMAKE=%VLC_DIR:\=/%"

echo Configuring...
cmake -GNinja ^
    -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
    -DCMAKE_INSTALL_PREFIX=output ^
    -DQTROOT=%QTROOT% ^
    -DMPV_INCLUDE_DIR="%DEPS_CMAKE%/mpv/include" ^
    -DMPV_LIBRARY="%DEPS_CMAKE%/mpv/libmpv-2.dll.lib" ^
    -DENABLE_VLC=ON ^
    -DVLC_INCLUDE_DIR="%VLC_CMAKE%/include" ^
    -DVLC_LIBRARY="%VLC_CMAKE%/lib/libvlc.lib" ^
    -DVLC_RUNTIME_DIR="%VLC_CMAKE%" ^
    -DCHECK_FOR_UPDATES=ON ^
    -DUSE_STATIC_MPVQT=ON ^
    "%PROJECT_ROOT%"
if errorlevel 1 (
    echo ERROR: CMake configuration failed.
    exit /b 1
)

REM === Build ===
echo Building...
ninja
if errorlevel 1 (
    echo ERROR: Build failed.
    exit /b 1
)

echo.
echo Build complete!
echo Executable: %BUILD_DIR%\src\%EXE_NAME%
endlocal
