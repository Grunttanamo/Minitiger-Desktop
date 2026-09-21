@echo off
REM Minitiger Desktop - Windows dependency installer
REM Based on Jellyfin Desktop's development setup, with Minitiger fixes.

setlocal EnableDelayedExpansion
call "%~dp0common.bat"

set "SEVENZIP=C:\Program Files\7-Zip\7z.exe"

if not exist "!DEPS_DIR!" mkdir "!DEPS_DIR!"

echo [1/14] Installing CMake...
winget install --id Kitware.CMake --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: CMake may already be installed or winget may have returned a non-zero update code.

echo [2/14] Installing Ninja...
winget install --id Ninja-build.Ninja --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: Ninja may already be installed or winget may have returned a non-zero update code.

echo [3/14] Installing 7-Zip...
winget install --id 7zip.7zip --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: 7-Zip may already be installed or winget may have returned a non-zero update code.

if not exist "!SEVENZIP!" (
    for /f "delims=" %%i in ('where 7z.exe 2^>nul') do (
        set "SEVENZIP=%%i"
        goto :found7zip
    )
)
:found7zip
if not exist "!SEVENZIP!" (
    echo ERROR: 7-Zip could not be located after installation.
    echo Open a new terminal and re-run this script.
    exit /b 1
)

echo [4/14] Installing aqtinstall...
winget install --id miurahr.aqtinstall --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: aqtinstall may already be installed or winget may have returned a non-zero update code.

REM winget can update PATH only for new shells. Locate aqt explicitly so this
REM first setup run can continue without requiring a terminal restart.
set "AQT_EXE="
for /f "delims=" %%i in ('where aqt.exe 2^>nul') do (
    set "AQT_EXE=%%i"
    goto :foundaqt
)
:foundaqt
if not defined AQT_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\aqt.exe" set "AQT_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\aqt.exe"
if not defined AQT_EXE (
    for /f "delims=" %%i in ('dir /b /s "%LOCALAPPDATA%\Microsoft\WinGet\Packages\aqt.exe" 2^>nul') do (
        set "AQT_EXE=%%i"
        goto :foundaqtfallback
    )
)
:foundaqtfallback
if not defined AQT_EXE (
    echo ERROR: aqtinstall was installed, but aqt.exe is not visible yet.
    echo Close PowerShell, open a new PowerShell window, and run setup.bat again.
    exit /b 1
)

echo [5/14] Installing Visual Studio 2022 Build Tools...
winget install --id Microsoft.VisualStudio.2022.BuildTools ^
  --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" ^
  --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: Build Tools may already be installed; checking the existing installation.

REM Re-read common.bat so VCVARS is detected after a first-time installation.
call "%~dp0common.bat"
if not defined VCVARS (
    echo ERROR: Visual Studio 2022 C++ Build Tools could not be located.
    echo Open Visual Studio Installer and make sure "Desktop development with C++" / VCTools is installed.
    exit /b 1
)

echo [6/14] MSVC provides dumpbin/lib; separate MinGW install is not required.

echo [7/14] Installing Inno Setup...
winget install --id JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 echo Warning: Inno Setup may already be installed or winget may have returned a non-zero update code.

echo [8/14] Installing Qt !QT_VERSION!...
if not exist "!DEPS_DIR!\qt\!QT_VERSION!\msvc2022_64" (
    pushd "!DEPS_DIR!"
    "!AQT_EXE!" install-qt windows desktop !QT_VERSION! win64_msvc2022_64 -m qtwebengine qtwebchannel qtpositioning -O "qt"
    if errorlevel 1 (
        popd
        echo ERROR: Qt installation failed.
        exit /b 1
    )
    popd
) else (
    echo Qt already installed, skipping
)

echo [9/14] Downloading libmpv AVX2...
if not exist "!DEPS_DIR!\mpv\libmpv-2.dll" (
    if exist "!DEPS_DIR!\mpv" rmdir /s /q "!DEPS_DIR!\mpv"
    if exist "!DEPS_DIR!\mpv_tmp" rmdir /s /q "!DEPS_DIR!\mpv_tmp"
    del /q "!DEPS_DIR!\mpv.7z" 2>nul

    set "MPV_URL=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/!MPV_RELEASE!/mpv-dev-x86_64-v3-!MPV_VERSION!.7z"
    echo Downloading !MPV_URL!
    curl -L --fail "!MPV_URL!" -o "!DEPS_DIR!\mpv.7z"
    if errorlevel 1 (
        echo ERROR: Failed to download libmpv AVX2.
        exit /b 1
    )

    "!SEVENZIP!" x "!DEPS_DIR!\mpv.7z" -o"!DEPS_DIR!\mpv_tmp" -y >nul
    if errorlevel 1 (
        echo ERROR: Failed to extract libmpv archive.
        exit /b 1
    )

    set "MPV_SRC=!DEPS_DIR!\mpv_tmp"
    if not exist "!MPV_SRC!\libmpv-2.dll" (
        for /d %%D in ("!DEPS_DIR!\mpv_tmp\*") do (
            if exist "%%~fD\libmpv-2.dll" set "MPV_SRC=%%~fD"
        )
    )
    if not exist "!MPV_SRC!\libmpv-2.dll" (
        echo ERROR: libmpv-2.dll was not found after extraction.
        exit /b 1
    )

    mkdir "!DEPS_DIR!\mpv"
    if exist "!MPV_SRC!\include" xcopy /e /i /y "!MPV_SRC!\include" "!DEPS_DIR!\mpv\include\" >nul
    copy /y "!MPV_SRC!\libmpv-2.dll" "!DEPS_DIR!\mpv\" >nul
    if exist "!MPV_SRC!\libmpv.dll.a" copy /y "!MPV_SRC!\libmpv.dll.a" "!DEPS_DIR!\mpv\" >nul
    if exist "!MPV_SRC!\libmpv-2.dll.lib" copy /y "!MPV_SRC!\libmpv-2.dll.lib" "!DEPS_DIR!\mpv\" >nul

    rmdir /s /q "!DEPS_DIR!\mpv_tmp"
    del /q "!DEPS_DIR!\mpv.7z"
    echo libmpv extracted to !DEPS_DIR!\mpv
) else (
    echo libmpv already installed, skipping
)

echo [10/14] Downloading libmpv fallback (non-AVX2)...
if not exist "!DEPS_DIR!\mpv-fallback\libmpv-2.dll" (
    if exist "!DEPS_DIR!\mpv-fallback" rmdir /s /q "!DEPS_DIR!\mpv-fallback"
    if exist "!DEPS_DIR!\mpv-fallback-tmp" rmdir /s /q "!DEPS_DIR!\mpv-fallback-tmp"
    del /q "!DEPS_DIR!\mpv-fallback.7z" 2>nul

    set "MPV_FALLBACK_URL=https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/!MPV_RELEASE!/mpv-dev-x86_64-!MPV_VERSION!.7z"
    echo Downloading !MPV_FALLBACK_URL!
    curl -L --fail "!MPV_FALLBACK_URL!" -o "!DEPS_DIR!\mpv-fallback.7z"
    if errorlevel 1 (
        echo ERROR: Failed to download libmpv fallback.
        exit /b 1
    )

    "!SEVENZIP!" x "!DEPS_DIR!\mpv-fallback.7z" -o"!DEPS_DIR!\mpv-fallback-tmp" -y >nul
    if errorlevel 1 (
        echo ERROR: Failed to extract libmpv fallback archive.
        exit /b 1
    )

    set "MPV_FALLBACK_SRC=!DEPS_DIR!\mpv-fallback-tmp"
    if not exist "!MPV_FALLBACK_SRC!\libmpv-2.dll" (
        for /d %%D in ("!DEPS_DIR!\mpv-fallback-tmp\*") do (
            if exist "%%~fD\libmpv-2.dll" set "MPV_FALLBACK_SRC=%%~fD"
        )
    )
    if not exist "!MPV_FALLBACK_SRC!\libmpv-2.dll" (
        echo ERROR: fallback libmpv-2.dll was not found after extraction.
        exit /b 1
    )

    mkdir "!DEPS_DIR!\mpv-fallback"
    copy /y "!MPV_FALLBACK_SRC!\libmpv-2.dll" "!DEPS_DIR!\mpv-fallback\" >nul
    rmdir /s /q "!DEPS_DIR!\mpv-fallback-tmp"
    del /q "!DEPS_DIR!\mpv-fallback.7z"
    echo libmpv fallback extracted to !DEPS_DIR!\mpv-fallback
) else (
    echo libmpv fallback already installed, skipping
)

echo [11/14] Downloading VCRedist and WiX tools...
if not exist "!DEPS_DIR!\vc_redist.x64.exe" (
    curl -L --fail -o "!DEPS_DIR!\vc_redist.x64.exe" https://aka.ms/vs/17/release/vc_redist.x64.exe
    if errorlevel 1 (
        echo ERROR: Failed to download vc_redist.x64.exe.
        exit /b 1
    )
)

if not exist "!DEPS_DIR!\wix\dark.exe" (
    if exist "!DEPS_DIR!\wix" rmdir /s /q "!DEPS_DIR!\wix"
    del /q "!DEPS_DIR!\wix.zip" 2>nul
    curl -L --fail -o "!DEPS_DIR!\wix.zip" https://github.com/wixtoolset/wix3/releases/download/wix3111rtm/wix311-binaries.zip
    if errorlevel 1 (
        echo ERROR: Failed to download WiX tools.
        exit /b 1
    )
    mkdir "!DEPS_DIR!\wix"
    "!SEVENZIP!" x -y "!DEPS_DIR!\wix.zip" -o"!DEPS_DIR!\wix" >nul
    if errorlevel 1 (
        echo ERROR: Failed to extract WiX tools.
        exit /b 1
    )
    del /q "!DEPS_DIR!\wix.zip"
)

echo [12/14] Extracting VC runtime DLLs...
if not exist "!DEPS_DIR!\vcruntime\*.dll" (
    if exist "!DEPS_DIR!\vcruntime" rmdir /s /q "!DEPS_DIR!\vcruntime"
    if exist "!DEPS_DIR!\vcredist_tmp" rmdir /s /q "!DEPS_DIR!\vcredist_tmp"
    mkdir "!DEPS_DIR!\vcruntime"

    "!DEPS_DIR!\wix\dark.exe" -nologo "!DEPS_DIR!\vc_redist.x64.exe" -x "!DEPS_DIR!\vcredist_tmp"
    if errorlevel 1 (
        echo ERROR: dark.exe failed to unpack the Visual C++ redistributable.
        exit /b 1
    )

    expand.exe -F:* "!DEPS_DIR!\vcredist_tmp\AttachedContainer\packages\vcRuntimeMinimum_amd64\cab1.cab" "!DEPS_DIR!\vcruntime"
    if errorlevel 1 exit /b 1
    expand.exe -F:* "!DEPS_DIR!\vcredist_tmp\AttachedContainer\packages\vcRuntimeAdditional_amd64\cab1.cab" "!DEPS_DIR!\vcruntime"
    if errorlevel 1 exit /b 1

    for %%f in ("!DEPS_DIR!\vcruntime\*_amd64") do (
        set "name=%%~nf"
        ren "%%f" "!name:_amd64=!.dll"
    )
    rd /s /q "!DEPS_DIR!\vcredist_tmp"
    echo VC runtime DLLs extracted to !DEPS_DIR!\vcruntime
)

echo [13/14] Generating mpv import library...
if not exist "!DEPS_DIR!\mpv\libmpv-2.dll.lib" (
    call "!VCVARS!" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Failed to initialize Visual Studio build environment.
        exit /b 1
    )

    echo LIBRARY libmpv-2.dll > "!DEPS_DIR!\mpv\mpv.def"
    echo EXPORTS >> "!DEPS_DIR!\mpv\mpv.def"
    for /f "skip=19 tokens=4" %%a in ('dumpbin /exports "!DEPS_DIR!\mpv\libmpv-2.dll"') do (
        if not "%%a"=="" echo %%a >> "!DEPS_DIR!\mpv\mpv.def"
    )
    lib /def:"!DEPS_DIR!\mpv\mpv.def" /out:"!DEPS_DIR!\mpv\libmpv-2.dll.lib" /MACHINE:X64
    if errorlevel 1 (
        echo ERROR: Failed to create mpv import library.
        exit /b 1
    )
)

echo [14/14] Generating CMakePresets.json...
powershell -NoProfile -Command "(Get-Content '!SCRIPT_DIR!..\CMakePresets.json.in' -Raw) -replace '@QT_VERSION@','!QT_VERSION!' -replace '@BREW_PREFIX@','' | Set-Content '!PROJECT_ROOT!\CMakePresets.json' -NoNewline"
if errorlevel 1 (
    echo ERROR: Failed to generate CMakePresets.json.
    exit /b 1
)

echo.
echo Setup complete.
echo IMPORTANT: If CMake/Ninja were installed during this run, open a NEW PowerShell window before building.
endlocal
