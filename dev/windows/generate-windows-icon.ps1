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

$source = [System.Drawing.Image]::FromFile($SourcePng)

try {
    $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
    $frames = New-Object System.Collections.Generic.List[object]

    foreach ($size in $sizes) {
        $bitmap = [System.Drawing.Bitmap]::new(
            $size,
            $size,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )

        try {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

            try {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.CompositingMode =
                    [System.Drawing.Drawing2D.CompositingMode]::SourceOver
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

                $width = [Math]::Max(
                    1,
                    [int][Math]::Round($source.Width * $scale)
                )
                $height = [Math]::Max(
                    1,
                    [int][Math]::Round($source.Height * $scale)
                )
                $x = [int](($size - $width) / 2)
                $y = [int](($size - $height) / 2)

                $graphics.DrawImage(
                    $source,
                    $x,
                    $y,
                    $width,
                    $height
                )
            }
            finally {
                $graphics.Dispose()
            }

            # Store every icon image as PNG inside the ICO container. Windows,
            # Resource Compiler and current Inno Setup all support PNG-backed
            # ICO frames and preserve alpha much better than GetHicon().
            $stream = [System.IO.MemoryStream]::new()
            try {
                $bitmap.Save(
                    $stream,
                    [System.Drawing.Imaging.ImageFormat]::Png
                )
                $frames.Add([PSCustomObject]@{
                    Size = $size
                    Data = $stream.ToArray()
                })
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $bitmap.Dispose()
        }
    }

    $outputDirectory = Split-Path -Parent $OutputIco
    if ($outputDirectory) {
        [System.IO.Directory]::CreateDirectory(
            $outputDirectory
        ) | Out-Null
    }

    $file = [System.IO.File]::Open(
        $OutputIco,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )

    try {
        $writer = [System.IO.BinaryWriter]::new($file)

        try {
            # ICONDIR
            $writer.Write([UInt16]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]$frames.Count)

            $offset = 6 + (16 * $frames.Count)

            # ICONDIRENTRY records.
            foreach ($frame in $frames) {
                $sizeByte = if ($frame.Size -ge 256) {
                    [byte]0
                } else {
                    [byte]$frame.Size
                }

                $writer.Write($sizeByte)
                $writer.Write($sizeByte)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([UInt16]1)
                $writer.Write([UInt16]32)
                $writer.Write([UInt32]$frame.Data.Length)
                $writer.Write([UInt32]$offset)

                $offset += $frame.Data.Length
            }

            foreach ($frame in $frames) {
                $writer.Write(
                    [byte[]]$frame.Data
                )
            }
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $file.Dispose()
    }
}
finally {
    $source.Dispose()
}

if (-not (Test-Path -LiteralPath $OutputIco)) {
    throw "Windows icon was not created: $OutputIco"
}

$iconFile = Get-Item -LiteralPath $OutputIco

if ($iconFile.Length -lt 1000) {
    throw "Generated Windows icon looks invalid: $OutputIco"
}

# Confirm Windows itself can parse the generated multi-frame icon.
$probe = [System.Drawing.Icon]::new($OutputIco)
try {
    if ($probe.Width -lt 1 -or $probe.Height -lt 1) {
        throw "Generated Windows icon could not be parsed."
    }
}
finally {
    $probe.Dispose()
}

Write-Host "[Minitiger] Multi-resolution Windows icon generated: $OutputIco"
Write-Host "[Minitiger] Icon sizes: $($sizes -join ', ')"
