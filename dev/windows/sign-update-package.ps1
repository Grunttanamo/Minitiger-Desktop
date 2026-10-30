# Signs one private update package for the Minitiger Desktop updater and
# prints the base64 signature. The signature is checked against
# bundle/update-signing-public-key.txt before it is returned, so a wrong or
# mismatched MINITIGER_UPDATE_SIGNING_KEY fails the workflow instead of
# publishing packages the clients would reject.
#
# The signed message must match minitigerUpdateSignedMessage() in
# src/system/SystemComponent.cpp.
param(
    [Parameter(Mandatory = $true)][ValidateSet('installer', 'portable')][string]$PackageType,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][int]$Build,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$Sha256
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
    # Annotations stay readable even where the full job log is not.
    Write-Host "::error title=Update signing::$message"
    exit 1
}

try {
    if (-not $env:MINITIGER_UPDATE_SIGNING_KEY) {
        Fail 'MINITIGER_UPDATE_SIGNING_KEY secret is missing or empty; refusing to publish unsigned update packages.'
    }

    $message = [System.Text.Encoding]::UTF8.GetBytes(
        "minitiger-desktop-update/v1`n$PackageType`n$($Version.Trim())`n$Build`n$Sha256")

    $signingKey = [System.Security.Cryptography.ECDsa]::Create()
    try {
        $signingKey.ImportFromPem($env:MINITIGER_UPDATE_SIGNING_KEY)
    } catch {
        Fail "MINITIGER_UPDATE_SIGNING_KEY is not a readable PEM private key: $($_.Exception.Message)"
    }
    if ($signingKey.KeySize -ne 256) {
        Fail "MINITIGER_UPDATE_SIGNING_KEY must be an ECDSA P-256 key (got $($signingKey.KeySize) bits)."
    }

    $signature = $signingKey.SignData(
        $message,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)

    $publicKeyFile = Join-Path $PSScriptRoot '..\..\bundle\update-signing-public-key.txt'
    $publicKeyRaw = [Convert]::FromBase64String((Get-Content $publicKeyFile -Raw).Trim())
    if ($publicKeyRaw.Length -ne 64) {
        Fail 'bundle/update-signing-public-key.txt must hold the 64-byte P-256 point (X || Y).'
    }

    $point = New-Object System.Security.Cryptography.ECPoint
    $point.X = [byte[]]$publicKeyRaw[0..31]
    $point.Y = [byte[]]$publicKeyRaw[32..63]
    $parameters = New-Object System.Security.Cryptography.ECParameters
    $parameters.Curve = [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256
    $parameters.Q = $point
    $verifier = [System.Security.Cryptography.ECDsa]::Create($parameters)

    $valid = $verifier.VerifyData(
        $message,
        $signature,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.DSASignatureFormat]::IeeeP1363FixedFieldConcatenation)
    if (-not $valid) {
        Fail 'MINITIGER_UPDATE_SIGNING_KEY does not belong to bundle/update-signing-public-key.txt.'
    }

    [Convert]::ToBase64String($signature)
} catch {
    Fail "Signing failed: $($_.Exception.Message)"
}
