param(
    [int]$TimeoutSeconds = 20
)

$roots = @(
    (Join-Path $env:LOCALAPPDATA 'Minitiger Desktop'),
    (Join-Path $env:APPDATA 'Minitiger Desktop')
) | Where-Object { Test-Path $_ }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$log = $null

do {
    $candidates = foreach ($root in $roots) {
        Get-ChildItem -Path $root -Recurse -File -Filter 'Minitiger Desktop.log' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Directory -and $_.Directory.Name -eq 'logs'
            }
    }

    $log = $candidates |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $log) {
        Start-Sleep -Milliseconds 200
    }
} while (-not $log -and (Get-Date) -lt $deadline)

if (-not $log) {
    Write-Host 'ERROR: Could not locate the Minitiger Desktop runtime log in a logs folder.' -ForegroundColor Red
    exit 1
}

Write-Host ('Following log: ' + $log.FullName) -ForegroundColor Cyan
Write-Host 'Press Ctrl+C to stop following the log; the app can stay open.' -ForegroundColor DarkGray

Get-Content -LiteralPath $log.FullName -Wait -Tail 200
