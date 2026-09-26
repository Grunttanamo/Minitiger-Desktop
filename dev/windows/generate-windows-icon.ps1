param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [string]$OutputIco
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourcePng)) {
    throw "Minitiger icon source not found: $SourcePng"
}

Add-Type -AssemblyName System.Drawing

if (-not ('Minitiger.Win32.IconHandle' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace Minitiger.Win32
{
    public static class IconHandle
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }
}
"@
}

$source = [System.Drawing.Image]::FromFile($SourcePng)

try {
    $size = 256
    $bitmap = New-Object System.Drawing.Bitmap(
        $size,
        $size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingQuality =
                [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode =
                [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode =
                [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $scale = [Math]::Min(
                $size / [double]$source.Width,
                $size / [double]$source.Height
            )

            $width = [Math]::Max(1, [int][Math]::Round($source.Width * $scale))
            $height = [Math]::Max(1, [int][Math]::Round($source.Height * $scale))
            $x = [int](($size - $width) / 2)
            $y = [int](($size - $height) / 2)

            $graphics.DrawImage($source, $x, $y, $width, $height)
        }
        finally {
            $graphics.Dispose()
        }

        $handle = $bitmap.GetHicon()

        if ($handle -eq [IntPtr]::Zero) {
            throw 'Failed to create Windows icon handle.'
        }

        try {
            $icon = [System.Drawing.Icon]::FromHandle($handle)

            try {
                $outputDirectory = Split-Path -Parent $OutputIco

                if ($outputDirectory) {
                    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
                }

                $stream = [System.IO.File]::Open(
                    $OutputIco,
                    [System.IO.FileMode]::Create,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None
                )

                try {
                    $icon.Save($stream)
                }
                finally {
                    $stream.Dispose()
                }
            }
            finally {
                $icon.Dispose()
            }
        }
        finally {
            [void][Minitiger.Win32.IconHandle]::DestroyIcon($handle)
        }
    }
    finally {
        $bitmap.Dispose()
    }
}
finally {
    $source.Dispose()
}

if (-not (Test-Path -LiteralPath $OutputIco)) {
    throw "Windows icon was not created: $OutputIco"
}

$iconFile = Get-Item -LiteralPath $OutputIco

if ($iconFile.Length -lt 100) {
    throw "Generated Windows icon looks invalid: $OutputIco"
}

Write-Host "[Minitiger] Windows icon generated: $OutputIco"
