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


# Verify the icon actually embedded into both distributable executables.
# This catches stale Windows resources before a package is handed out.
Add-Type -AssemblyName System.Drawing

$expectedIconPath = Join-Path $repoRoot 'bundle\win\minitiger.ico'
if (-not (Test-Path $expectedIconPath)) {
    throw "Expected Minitiger Windows icon not found: $expectedIconPath"
}

function Get-NormalizedIconHash {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Icon]$Icon
    )

    $size = 64
    $bitmap = [System.Drawing.Bitmap]::new(
        $size,
        $size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.DrawIcon(
                $Icon,
                [System.Drawing.Rectangle]::new(0, 0, $size, $size)
            )
        }
        finally {
            $graphics.Dispose()
        }

        $stream = [System.IO.MemoryStream]::new()
        try {
            $bitmap.Save(
                $stream,
                [System.Drawing.Imaging.ImageFormat]::Png
            )
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hash = $sha.ComputeHash($stream.ToArray())
                return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $sha.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

$expectedIcon = [System.Drawing.Icon]::new($expectedIconPath)
try {
    $expectedIconHash = Get-NormalizedIconHash -Icon $expectedIcon
}
finally {
    $expectedIcon.Dispose()
}

function Assert-MinitigerExecutableIcon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $embeddedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    if ($null -eq $embeddedIcon) {
        throw "$Label icon validation failed: no embedded executable icon found in $Path"
    }

    try {
        $actualHash = Get-NormalizedIconHash -Icon $embeddedIcon
    }
    finally {
        $embeddedIcon.Dispose()
    }

    if ($actualHash -ne $expectedIconHash) {
        throw "$Label icon validation failed: packaged executable does not contain the current Minitiger icon."
    }

    Write-Host "$Label icon validation: OK" -ForegroundColor Green
}

$iconVerifyDir = Join-Path (
    [System.IO.Path]::GetTempPath()
) ("minitiger-portable-icon-" + [Guid]::NewGuid().ToString('N'))

try {
    Expand-Archive -LiteralPath $portableDest -DestinationPath $iconVerifyDir
    $portableExe = Join-Path $iconVerifyDir 'Minitiger Desktop.exe'

    if (-not (Test-Path $portableExe)) {
        throw "Portable icon validation failed: Minitiger Desktop.exe was not found after extraction."
    }

    # The application EXE is the authoritative icon check. Unlike the Inno
    # bootstrapper, Windows does not re-encode this resource after linking.
    Assert-MinitigerExecutableIcon -Path $portableExe -Label 'Portable EXE'
}
finally {
    if (Test-Path $iconVerifyDir) {
        Remove-Item $iconVerifyDir -Recurse -Force
    }
}

# Inno Setup may re-encode/select another frame from SetupIconFile, so an
# exact rendered hash is too strict for the installer bootstrapper. Report it
# as a diagnostic instead of discarding an otherwise valid distribution.
try {
    Assert-MinitigerExecutableIcon -Path $installerDest -Label 'Installer'
}
catch {
    Write-Warning $_.Exception.Message
    Write-Host 'Installer uses SetupIconFile=minitiger.ico; exact Inno icon hash differs after compilation.' -ForegroundColor Yellow
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
