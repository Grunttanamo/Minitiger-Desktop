param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$buildDir = Join-Path $repoRoot 'build'
$distDir = Join-Path $repoRoot 'dist'
$version = (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()

$installerName = "Minitiger-Desktop-$version-windows-x64-Installer.exe"
$portableName = "Minitiger-Desktop-$version-windows-x64-Portable.zip"

$installerSource = Join-Path $buildDir $installerName
$portableSource = Join-Path $buildDir $portableName

if (-not (Test-Path $installerSource)) {
    throw "Installer not found: $installerSource"
}

if (-not (Test-Path $portableSource)) {
    throw "Portable ZIP not found: $portableSource"
}

if (Test-Path $distDir) {
    Remove-Item $distDir -Recurse -Force
}

New-Item -ItemType Directory -Path $distDir | Out-Null

$installerDest = Join-Path $distDir $installerName
$portableDest = Join-Path $distDir $portableName

Copy-Item $installerSource $installerDest
Copy-Item $portableSource $portableDest

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($portableDest)

try {
    $entries = @($archive.Entries | ForEach-Object {
        $_.FullName.Replace('\', '/')
    })

    $required = @(
        'Minitiger Desktop.exe',
        'portable',
        'README-Minitiger.txt'
    )

    foreach ($requiredEntry in $required) {
        if ($entries -notcontains $requiredEntry) {
            throw "Portable validation failed: missing '$requiredEntry'."
        }
    }

    $forbiddenPatterns = @(
        '^data/',
        '^cache/',
        '^profiles/',
        '^logs/',
        '(^|/)profiles\.json$',
        '(^|/)jellyfin-desktop\.conf$',
        '(^|/)storage\.json$',
        '(^|/)Local Storage/',
        '(^|/)LocalStorage/',
        '(^|/)IndexedDB/',
        '(^|/)GPUCache/',
        '(^|/)Code Cache/',
        '(^|/)Cookies($|/)',
        '(^|/)History($|/)',
        '(^|/)\.git/',
        '(^|/)node_modules/'
    )

    $forbidden = foreach ($entry in $entries) {
        foreach ($pattern in $forbiddenPatterns) {
            if ($entry -match $pattern) {
                $entry
                break
            }
        }
    }

    if ($forbidden) {
        $message = 'Portable validation failed: private/runtime files found:' +
            [Environment]::NewLine +
            (($forbidden | Sort-Object -Unique) -join [Environment]::NewLine)
        throw $message
    }
}
finally {
    $archive.Dispose()
}

$hashLines = foreach ($file in @($installerDest, $portableDest)) {
    $hash = Get-FileHash -Algorithm SHA256 $file
    "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($file))"
}

$hashLines | Set-Content -Encoding ascii (Join-Path $distDir 'SHA256SUMS.txt')

$commit = 'unknown'
try {
    $commitValue = & git -C $repoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $commitValue) {
        $commit = $commitValue.Trim()
    }
} catch {
}

@(
    'Minitiger Desktop local distribution build'
    "Version: $version"
    'Architecture: windows-x64'
    "Commit: $commit"
    'Update checker: disabled'
    'Personal settings included: no'
    'GitHub release/upload performed: no'
) | Set-Content -Encoding utf8 (Join-Path $distDir 'BUILD-INFO.txt')

Write-Host ''
Write-Host 'Clean Minitiger distribution is ready:' -ForegroundColor Green
Write-Host "  Installer: $installerDest"
Write-Host "  Portable:  $portableDest"
Write-Host "  SHA256:    $(Join-Path $distDir 'SHA256SUMS.txt')"
Write-Host ''
Write-Host 'Portable archive privacy validation: OK' -ForegroundColor Green
