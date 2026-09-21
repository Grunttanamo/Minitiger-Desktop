@echo off
REM Minitiger Desktop - start with debug logging and follow the active log file.

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

echo Waiting for the Minitiger Desktop log file...
timeout /t 1 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$roots = @((Join-Path $env:LOCALAPPDATA 'Minitiger Desktop'), (Join-Path $env:APPDATA 'Minitiger Desktop'));" ^
  "$log = $null;" ^
  "for ($i = 0; $i -lt 100 -and -not $log; $i++) {" ^
  "  $log = $roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1;" ^
  "  if (-not $log) { Start-Sleep -Milliseconds 200 }" ^
  "};" ^
  "if (-not $log) { Write-Host 'ERROR: Could not locate a Minitiger Desktop log under LocalAppData/AppData.' -ForegroundColor Red; exit 1 };" ^
  "Write-Host ('Following log: ' + $log.FullName) -ForegroundColor Cyan;" ^
  "Write-Host 'Press Ctrl+C to stop following the log; the app can stay open.' -ForegroundColor DarkGray;" ^
  "Get-Content -LiteralPath $log.FullName -Wait -Tail 200"

endlocal
