#Requires -Version 5.1
<#
.SYNOPSIS
    Set up a RepFlow development environment on Windows.
.DESCRIPTION
    Installs what is missing (JDK, Connect IQ SDK, SDK Manager, VS Code and the
    Monkey C extension) and creates a developer signing key outside the repo.
    Device definitions still require a signed-in SDK Manager — see the message
    printed at the end.
#>

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CiqHome  = Join-Path $env:APPDATA 'Garmin\ConnectIQ'
$KeyPath  = if ($env:REPFLOW_DEVELOPER_KEY) { $env:REPFLOW_DEVELOPER_KEY }
            else { Join-Path $env:USERPROFILE '.garmin\repflow\developer_key.der' }

function Write-Ok   ($m) { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Info ($m) { Write-Host "       $m" }
function Write-Warn ($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    throw "winget is required. Install 'App Installer' from the Microsoft Store and re-run."
}

# --- Java -------------------------------------------------------------
$needJava = $true
$java = Get-Command java -ErrorAction SilentlyContinue
if ($java) {
    $raw = (& java -version 2>&1 | Select-Object -First 1).ToString()
    if ($raw -match 'version "(\d+)' -and [int]$Matches[1] -ge 11) { $needJava = $false }
}
if ($needJava) {
    Write-Info "Installing a JDK (Connect IQ requires Java 11+)..."
    winget install --id EclipseAdoptium.Temurin.21.JDK --silent --accept-package-agreements --accept-source-agreements
}
Write-Ok "Java"

# --- Connect IQ SDK ---------------------------------------------------
function Resolve-Sdk {
    $cfg = Join-Path $CiqHome 'current-sdk.cfg'
    if (Test-Path $cfg) {
        $sdk = (Get-Content $cfg -Raw).Trim().TrimEnd('/','\')
        if (Test-Path (Join-Path $sdk 'bin\monkeyc.bat')) { return $sdk }
    }
    $sdks = Join-Path $CiqHome 'Sdks'
    if (Test-Path $sdks) {
        $newest = Get-ChildItem $sdks -Directory | Sort-Object Name | Select-Object -Last 1
        if ($newest -and (Test-Path (Join-Path $newest.FullName 'bin\monkeyc.bat'))) { return $newest.FullName }
    }
    return $null
}

$sdk = Resolve-Sdk
if ($sdk) {
    Write-Ok "Connect IQ SDK already installed"
    Write-Info $sdk
} else {
    $feed = 'https://developer.garmin.com/downloads/connect-iq/sdks'
    Write-Info "Fetching the Connect IQ SDK catalogue from Garmin..."
    $catalogue = Invoke-RestMethod -Uri "$feed/sdks.json"
    $latest = $catalogue[-1]
    Write-Info "Downloading Connect IQ SDK $($latest.version)..."
    $tmp = Join-Path $env:TEMP "ciq-sdk-$($latest.version).zip"
    Invoke-WebRequest -Uri "$feed/$($latest.windows)" -OutFile $tmp
    $dest = Join-Path $CiqHome "Sdks\connectiq-sdk-win-$($latest.version)"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -Path $tmp -DestinationPath $dest -Force
    Remove-Item $tmp -Force
    New-Item -ItemType Directory -Force -Path $CiqHome | Out-Null
    Set-Content -Path (Join-Path $CiqHome 'current-sdk.cfg') -Value "$dest/" -NoNewline
    Write-Ok "Connect IQ SDK $($latest.version) installed at $dest"
    $sdk = $dest
}

# --- SDK Manager / VS Code -------------------------------------------
Write-Info "The Connect IQ SDK Manager is needed to download device definitions."
Write-Info "Download it from https://developer.garmin.com/connect-iq/sdk/ if you do not have it."

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Info "Installing VS Code..."
    winget install --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements
}
if (Get-Command code -ErrorAction SilentlyContinue) {
    $exts = & code --list-extensions 2>$null
    if ($exts -notcontains 'garmin.monkey-c') {
        Write-Info "Installing the Garmin Monkey C VS Code extension..."
        & code --install-extension garmin.monkey-c | Out-Null
    }
    Write-Ok "Monkey C VS Code extension"
}

# --- Developer signing key -------------------------------------------
if (Test-Path $KeyPath) {
    Write-Ok "Developer key already exists — leaving it untouched."
    Write-Info $KeyPath
    Write-Info "NEVER regenerate this key once RepFlow is published. See docs\SIGNING.md."
} else {
    $keyDir = Split-Path -Parent $KeyPath
    New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        $pem = [System.IO.Path]::ChangeExtension($KeyPath, '.pem')
        & openssl genrsa -out $pem 4096
        & openssl pkcs8 -topk8 -inform PEM -outform DER -in $pem -out $KeyPath -nocrypt
        Write-Ok "Developer key created at $KeyPath"
    } else {
        # No openssl: fall back to .NET, which can emit PKCS#8 DER directly.
        $rsa = [System.Security.Cryptography.RSA]::Create(4096)
        [System.IO.File]::WriteAllBytes($KeyPath, $rsa.ExportPkcs8PrivateKey())
        Write-Ok "Developer key created at $KeyPath (via .NET RSA)"
    }
    Write-Warn "Back this key up now. Losing it means you can never ship an update"
    Write-Warn "to a published RepFlow listing."
}

# --- Device definitions ----------------------------------------------
$devicesDir = Join-Path $CiqHome 'Devices'
$count = 0
if (Test-Path $devicesDir) {
    $count = (Get-ChildItem $devicesDir -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'compiler.json') }).Count
}
Write-Host ""
if ($count -eq 0) {
    Write-Warn "No device definitions installed — RepFlow cannot be compiled without them."
    Write-Host ""
    Write-Host "MANUAL STEP (requires your Garmin account):" -ForegroundColor Cyan
    Write-Info "1. Open the Connect IQ SDK Manager"
    Write-Info "2. Sign in with your Garmin developer account and accept the SDK licence"
    Write-Info "3. Open the 'Devices' tab and download the devices you target"
    Write-Info "   (at minimum: fenix6pro, fenix847mm, fenix8pro47mm)"
    Write-Info "4. Re-run scripts\doctor.ps1"
} else {
    Write-Ok "Device definitions: $count installed"
}

Write-Host ""
& (Join-Path $PSScriptRoot 'doctor.ps1')
