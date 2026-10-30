# Minitiger Desktop private updater.
#
# Started detached by SystemComponent::applyMinitigerUpdate() (see
# src/system/MinitigerUpdater.cpp) after the release signature was verified.
# Runs on the Windows PowerShell 5.1 that ships with Windows and shows a
# small progress window, so nobody restarts Minitiger in the middle of an
# update. While it runs, minitiger-update.lock keeps new Minitiger instances
# from starting.
#
# With -Demo (or "demo": true in the parameters) it only plays the window
# animation and touches nothing.
param(
    [string]$ParamsFile,
    [switch]$Demo
)

$ErrorActionPreference = 'Stop'

$p = $null
if ($ParamsFile) {
    $p = Get-Content -LiteralPath $ParamsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.demo) { $Demo = $true }
}
if (-not $p -and -not $Demo) { throw 'Missing -ParamsFile.' }

$maxAttempts = 3

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()
# Windows PowerShell 5.1 may not offer TLS 1.2 by default.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-UpdateLog([string]$message) {
    if ($Demo -or -not $p.logPath) { return }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try { Add-Content -LiteralPath $p.logPath -Value "[$timestamp] $message" -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------- window ---

$accent = [System.Drawing.Color]::FromArgb(255, 156, 37)
$background = [System.Drawing.Color]::FromArgb(16, 16, 20)
$track = [System.Drawing.Color]::FromArgb(42, 42, 51)
$muted = [System.Drawing.Color]::FromArgb(160, 160, 172)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Minitiger Desktop – Update'
$form.ClientSize = New-Object System.Drawing.Size(480, 196)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.BackColor = $background
$form.ForeColor = [System.Drawing.Color]::White
$form.TopMost = $true
$form.ShowInTaskbar = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$appIcon = $null
if ($p -and $p.appExe -and (Test-Path -LiteralPath $p.appExe)) {
    try { $appIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($p.appExe) } catch { }
}
if ($appIcon) { $form.Icon = $appIcon }
# The large logo next to the title; written next to this script by the client.
$logo = $null
$logoPath = Join-Path $PSScriptRoot 'minitiger-updater-logo.png'
if (Test-Path -LiteralPath $logoPath) {
    try { $logo = [System.Drawing.Image]::FromFile($logoPath) } catch { }
}

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(24, 26)
$picture.Size = New-Object System.Drawing.Size(48, 48)
$picture.SizeMode = 'Zoom'
if ($logo) { $picture.Image = $logo } elseif ($appIcon) { $picture.Image = $appIcon.ToBitmap() }
$form.Controls.Add($picture)

$title = New-Object System.Windows.Forms.Label
$title.Location = New-Object System.Drawing.Point(88, 22)
$title.Size = New-Object System.Drawing.Size(370, 28)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$title.Text = 'Minitiger wird aktualisiert'
$form.Controls.Add($title)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Location = New-Object System.Drawing.Point(90, 52)
$versionLabel.Size = New-Object System.Drawing.Size(370, 20)
$versionLabel.ForeColor = $muted
if ($p -and $p.targetVersion) {
    $versionLabel.Text = "Version $($p.targetVersion) · Build $($p.targetBuild)"
} else {
    $versionLabel.Text = 'Vorschau des Update-Fensters'
}
$form.Controls.Add($versionLabel)

$stepLabel = New-Object System.Windows.Forms.Label
$stepLabel.Location = New-Object System.Drawing.Point(24, 94)
$stepLabel.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($stepLabel)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Location = New-Object System.Drawing.Point(300, 94)
$detailLabel.Size = New-Object System.Drawing.Size(156, 20)
$detailLabel.TextAlign = 'TopRight'
$detailLabel.ForeColor = $muted
$form.Controls.Add($detailLabel)

$trackPanel = New-Object System.Windows.Forms.Panel
$trackPanel.Location = New-Object System.Drawing.Point(24, 120)
$trackPanel.Size = New-Object System.Drawing.Size(432, 8)
$trackPanel.BackColor = $track
$form.Controls.Add($trackPanel)

$fillPanel = New-Object System.Windows.Forms.Panel
$fillPanel.Location = New-Object System.Drawing.Point(0, 0)
$fillPanel.Size = New-Object System.Drawing.Size(0, 8)
$fillPanel.BackColor = $accent
$trackPanel.Controls.Add($fillPanel)

$hint = New-Object System.Windows.Forms.Label
$hint.Location = New-Object System.Drawing.Point(24, 144)
$hint.Size = New-Object System.Drawing.Size(432, 40)
$hint.ForeColor = $muted
$hint.Text = 'Bitte Minitiger jetzt nicht neu starten – es öffnet sich nach dem Update von selbst.'
$form.Controls.Add($hint)

$script:allowClose = $false
$form.add_FormClosing({
    param($sender, $e)
    if (-not $script:allowClose) { $e.Cancel = $true }
})

# Indeterminate steps (installer, hash check) show a moving segment.
$script:indeterminate = $false
$script:marqueeOffset = 0
$marquee = New-Object System.Windows.Forms.Timer
$marquee.Interval = 30
$marquee.add_Tick({
    if (-not $script:indeterminate) { return }
    $width = [int]($trackPanel.Width * 0.28)
    $script:marqueeOffset = ($script:marqueeOffset + 7) % ($trackPanel.Width + $width)
    $fillPanel.Width = $width
    $fillPanel.Left = $script:marqueeOffset - $width
})
$marquee.Start()

function Update-Window { [System.Windows.Forms.Application]::DoEvents() }

function Set-Step([string]$text) {
    $stepLabel.Text = $text
    Write-UpdateLog $text
    Update-Window
}

function Set-Progress($fraction, [string]$detail = '') {
    if ($null -eq $fraction) {
        $script:indeterminate = $true
    } else {
        $script:indeterminate = $false
        $fraction = [Math]::Max(0, [Math]::Min(1, [double]$fraction))
        $fillPanel.Left = 0
        $fillPanel.Width = [int]($trackPanel.Width * $fraction)
    }
    $detailLabel.Text = $detail
    Update-Window
}

function Wait-Window([int]$milliseconds) {
    $until = (Get-Date).AddMilliseconds($milliseconds)
    while ((Get-Date) -lt $until) {
        Update-Window
        Start-Sleep -Milliseconds 30
    }
}

function Format-MB([double]$bytes) {
    return ('{0:N1} MB' -f ($bytes / 1MB))
}

$form.Show()
$form.Activate()
Update-Window

# ----------------------------------------------------------------- steps ---

function Invoke-Download {
    Set-Step 'Update wird heruntergeladen …'
    if ($Demo) {
        $total = 84MB
        for ($i = 0; $i -le 100; $i += 2) {
            Set-Progress ($i / 100) ('{0} % · {1} / {2}' -f $i, (Format-MB ($total * $i / 100)), (Format-MB $total))
            Wait-Window 70
        }
        return
    }

    if (Test-Path -LiteralPath $p.packagePath) { Remove-Item -LiteralPath $p.packagePath -Force }
    $request = [System.Net.HttpWebRequest]::Create([string]$p.url)
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 60000
    $response = $request.GetResponse()
    try {
        $total = $response.ContentLength
        $source = $response.GetResponseStream()
        $output = [System.IO.File]::Create($p.packagePath)
        try {
            $buffer = New-Object byte[] (256KB)
            $done = 0
            $lastUpdate = [DateTime]::MinValue
            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $output.Write($buffer, 0, $read)
                $done += $read
                if (((Get-Date) - $lastUpdate).TotalMilliseconds -ge 100) {
                    $lastUpdate = Get-Date
                    if ($total -gt 0) {
                        Set-Progress ($done / $total) ('{0} % · {1} / {2}' -f [int](100 * $done / $total), (Format-MB $done), (Format-MB $total))
                    } else {
                        Set-Progress $null (Format-MB $done)
                    }
                }
            }
        } finally {
            $output.Dispose()
            $source.Dispose()
        }
    } finally {
        $response.Dispose()
    }
    Set-Progress 1 (Format-MB $done)
}

function Invoke-Verify {
    Set-Step 'Update wird geprüft …'
    if ($Demo) {
        for ($i = 0; $i -le 100; $i += 5) { Set-Progress ($i / 100) "$i %"; Wait-Window 40 }
        return
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($p.packagePath)
    try {
        $buffer = New-Object byte[] (1MB)
        $total = [Math]::Max(1, $stream.Length)
        $done = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha.TransformBlock($buffer, 0, $read, $null, 0)
            $done += $read
            Set-Progress ($done / $total) ('{0} %' -f [int](100 * $done / $total))
        }
        [void]$sha.TransformFinalBlock($buffer, 0, 0)
        $actualHash = -join ($sha.Hash | ForEach-Object { $_.ToString('x2') })
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
    if ($actualHash -ne ([string]$p.expectedHash).ToLowerInvariant()) {
        throw "SHA-256 stimmt nicht (erwartet $($p.expectedHash), erhalten $actualHash)."
    }
    Write-UpdateLog 'Download and SHA-256 validation completed.'
}

function Wait-ForMinitigerExit([switch]$Quiet) {
    if (-not $Quiet) {
        Set-Step 'Minitiger wird beendet …'
        Set-Progress $null
    }
    if ($Demo) { Wait-Window 900; return }
    $deadline = (Get-Date).AddSeconds(60)
    while (Get-Process -Id ([int]$p.targetPid) -ErrorAction SilentlyContinue) {
        if ((Get-Date) -gt $deadline) {
            Write-UpdateLog 'Minitiger did not exit in time; stopping it.'
            Stop-Process -Id ([int]$p.targetPid) -Force -ErrorAction SilentlyContinue
            Wait-Window 1000
            break
        }
        Wait-Window 150
    }
}

function Install-Portable {
    Set-Step 'Update wird entpackt …'
    if (Test-Path -LiteralPath $p.stagePath) { Remove-Item -LiteralPath $p.stagePath -Recurse -Force }
    New-Item -ItemType Directory -Path $p.stagePath | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead($p.packagePath)
    try {
        $entries = @($archive.Entries)
        $stageRoot = [System.IO.Path]::GetFullPath($p.stagePath).TrimEnd('\') + '\'
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $entry = $entries[$i]
            $target = [System.IO.Path]::GetFullPath((Join-Path $p.stagePath $entry.FullName))
            if (-not $target.StartsWith($stageRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Ungültiger Pfad im Update-Archiv: $($entry.FullName)"
            }
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            } else {
                New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            if ($i % 10 -eq 0) { Set-Progress (($i + 1) / $entries.Count) ('{0} / {1} Dateien' -f ($i + 1), $entries.Count) }
        }
    } finally {
        $archive.Dispose()
    }

    $stagedExe = Join-Path $p.stagePath 'Minitiger Desktop.exe'
    if (-not (Test-Path -LiteralPath $stagedExe)) { throw 'Das Update-Archiv enthält keine Minitiger Desktop.exe.' }

    Set-Step 'Update wird installiert …'
    $items = @(Get-ChildItem -LiteralPath $p.stagePath -Force | Where-Object { $_.Name -notin @('data', 'cache') })
    for ($i = 0; $i -lt $items.Count; $i++) {
        Copy-Item -LiteralPath $items[$i].FullName -Destination $p.appDir -Recurse -Force
        Set-Progress (($i + 1) / $items.Count) ''
    }
}

function Install-Installer {
    Set-Step 'Update wird installiert …'
    Set-Progress $null
    $installer = Start-Process -FilePath $p.packagePath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS') -PassThru
    while (-not $installer.HasExited) { Wait-Window 150 }
    if ($installer.ExitCode -ne 0) { throw "Der Installer meldet Fehlercode $($installer.ExitCode)." }
}

function Register-Failure {
    # "build attempts": the client only gives up on a build after
    # $maxAttempts failed attempts (see MinitigerUpdater::failedBuild()).
    $attempts = 1
    if (Test-Path -LiteralPath $p.failureMarker) {
        $previous = ((Get-Content -LiteralPath $p.failureMarker -Raw) -split '\s+') | Where-Object { $_ }
        if ($previous.Count -ge 1 -and [int]$previous[0] -eq [int]$p.targetBuild) {
            $attempts = 1
            if ($previous.Count -ge 2) { $attempts = [int]$previous[1] + 1 } else { $attempts = 2 }
        }
    }
    Set-Content -LiteralPath $p.failureMarker -Value "$($p.targetBuild) $attempts" -Encoding ASCII
    return $attempts
}

function Start-Minitiger {
    if ($Demo) { return }
    # Release the lock first: the new instance refuses to start while it exists.
    Remove-Item -LiteralPath $p.lockPath -Force -ErrorAction SilentlyContinue
    if ($p.appExe -and (Test-Path -LiteralPath $p.appExe)) { Start-Process -FilePath $p.appExe }
}

# ------------------------------------------------------------------ main ---

if (-not $Demo) {
    Set-Content -LiteralPath $p.lockPath -Value "$PID`n$((Get-Date).ToUniversalTime().ToString('o'))" -Encoding ASCII
    Write-UpdateLog "Starting update to $($p.targetVersion) build $($p.targetBuild) ($($p.packageType))."
}

try {
    Invoke-Download
    Invoke-Verify
    Wait-ForMinitigerExit
    if ($Demo) {
        Set-Step 'Update wird installiert …'
        Set-Progress $null
        Wait-Window 2500
    } elseif ($p.packageType -eq 'portable') {
        Install-Portable
    } else {
        Install-Installer
    }

    if (-not $Demo -and (Test-Path -LiteralPath $p.failureMarker)) { Remove-Item -LiteralPath $p.failureMarker -Force }
    $title.Text = 'Update abgeschlossen'
    Set-Step 'Minitiger wird gestartet …'
    Set-Progress 1 '100 %'
    $hint.Text = ''
    Write-UpdateLog 'Update applied successfully; restarting Minitiger Desktop.'
    Start-Minitiger
    Wait-Window 1500
} catch {
    $message = $_.Exception.Message
    Write-UpdateLog "Update failed: $message"
    $attempts = 1
    if (-not $Demo) { $attempts = Register-Failure }
    $marquee.Stop()
    $title.Text = 'Update fehlgeschlagen'
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255, 120, 120)
    $stepLabel.Text = $message
    $stepLabel.Size = New-Object System.Drawing.Size(432, 20)
    $detailLabel.Text = ''
    $fillPanel.Width = 0
    if ($attempts -lt $maxAttempts) {
        $hint.Text = "Minitiger startet gleich wieder. Das Update wird beim nächsten Start erneut versucht (Versuch $attempts von $maxAttempts)."
    } else {
        $hint.Text = "Das Update ist $maxAttempts-mal fehlgeschlagen und wird bis zur nächsten Version nicht mehr automatisch versucht. Details: minitiger-update.log"
    }
    Update-Window
    Wait-ForMinitigerExit -Quiet
    Start-Minitiger
    Wait-Window 6000
} finally {
    if (-not $Demo) {
        Remove-Item -LiteralPath $p.lockPath -Force -ErrorAction SilentlyContinue
        if ($p.stagePath -and (Test-Path -LiteralPath $p.stagePath)) { Remove-Item -LiteralPath $p.stagePath -Recurse -Force -ErrorAction SilentlyContinue }
        if ($p.packagePath -and (Test-Path -LiteralPath $p.packagePath)) { Remove-Item -LiteralPath $p.packagePath -Force -ErrorAction SilentlyContinue }
        if ($ParamsFile) { Remove-Item -LiteralPath $ParamsFile -Force -ErrorAction SilentlyContinue }
    }
    $script:allowClose = $true
    $marquee.Stop()
    $form.Close()
}
