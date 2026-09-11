#Requires -Version 5.1
<#
.SYNOPSIS
    Report on the RepFlow development environment (Windows).
.DESCRIPTION
    Windows equivalent of scripts/doctor.sh. Exits non-zero when something
    required to build RepFlow is missing.
#>

$ErrorActionPreference = 'Continue'

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$CiqHome    = Join-Path $env:APPDATA 'Garmin\ConnectIQ'
$DevicesDir = Join-Path $CiqHome 'Devices'
$DeveloperKey = if ($env:REPFLOW_DEVELOPER_KEY) { $env:REPFLOW_DEVELOPER_KEY }
                else { Join-Path $env:USERPROFILE '.garmin\repflow\developer_key.der' }

$script:Problems = 0
function Write-Ok    ($m) { Write-Host "[OK]   $m"   -ForegroundColor Green }
function Write-Warn  ($m) { Write-Host "[WARN] $m"   -ForegroundColor Yellow }
function Write-Fail  ($m) { Write-Host "[FAIL] $m"   -ForegroundColor Red; $script:Problems++ }
function Write-Info  ($m) { Write-Host "       $m" }

function Resolve-Sdk {
    if ($env:CIQ_SDK_HOME -and (Test-Path (Join-Path $env:CIQ_SDK_HOME 'bin\monkeyc.bat'))) {
        return $env:CIQ_SDK_HOME
    }
    $cfg = Join-Path $CiqHome 'current-sdk.cfg'
    if (Test-Path $cfg) {
        $sdk = (Get-Content $cfg -Raw).Trim().TrimEnd('/','\')
        if (Test-Path (Join-Path $sdk 'bin\monkeyc.bat')) { return $sdk }
    }
    $sdks = Join-Path $CiqHome 'Sdks'
    if (Test-Path $sdks) {
        $newest = Get-ChildItem $sdks -Directory | Sort-Object Name | Select-Object -Last 1
        if ($newest -and (Test-Path (Join-Path $newest.FullName 'bin\monkeyc.bat'))) {
            return $newest.FullName
        }
    }
    return $null
}

Write-Host "RepFlow environment" -ForegroundColor Cyan
Write-Host ""
Write-Info "OS:    $([System.Environment]::OSVersion.VersionString) ($env:PROCESSOR_ARCHITECTURE)"
Write-Info "Shell: PowerShell $($PSVersionTable.PSVersion)"
Write-Host ""

# --- Java -------------------------------------------------------------
$java = Get-Command java -ErrorAction SilentlyContinue
if ($java) {
    $raw = (& java -version 2>&1 | Select-Object -First 1).ToString()
    if ($raw -match 'version "(\d+)') {
        $major = [int]$Matches[1]
        if ($major -ge 11) { Write-Ok "Java ($raw)" }
        else { Write-Fail "Java is too old, Connect IQ needs 11+: $raw" }
    } else { Write-Warn "Java found but the version could not be parsed: $raw" }
} else {
    Write-Fail "Java not found. Install a JDK 11+ (winget install EclipseAdoptium.Temurin.21.JDK)."
}

# --- SDK --------------------------------------------------------------
$sdk = Resolve-Sdk
if ($sdk) {
    $verFile = Join-Path $sdk 'bin\version.txt'
    $ver = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { '?' }
    Write-Ok "Connect IQ SDK $ver"
    Write-Info $sdk
    $env:PATH = "$(Join-Path $sdk 'bin');$env:PATH"
} else {
    Write-Fail "Connect IQ SDK not found under $CiqHome\Sdks"
    Write-Info "Run scripts\bootstrap-windows.ps1 to install it."
}

foreach ($tool in 'monkeyc','monkeydo','connectiq') {
    if (Get-Command "$tool.bat" -ErrorAction SilentlyContinue) { Write-Ok $tool }
    else { Write-Fail "$tool not on PATH (expected in <SDK>\bin)" }
}

# --- Signing key ------------------------------------------------------
if (Test-Path $DeveloperKey) {
    Write-Ok "developer signing key"
    Write-Info $DeveloperKey
} else {
    Write-Fail "No developer signing key at $DeveloperKey"
    Write-Info "Create one with: scripts\bootstrap-windows.ps1  (see docs\SIGNING.md)"
}

# --- Devices ----------------------------------------------------------
$installed = @()
if (Test-Path $DevicesDir) {
    $installed = Get-ChildItem $DevicesDir -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'compiler.json') } |
        ForEach-Object { $_.Name }
}
if ($installed.Count -gt 0) {
    Write-Ok "device definitions ($($installed.Count) installed)"
    $manifest = Get-Content (Join-Path $RepoRoot 'manifest.xml') -Raw
    $declared = [regex]::Matches($manifest, 'iq:product id="([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
    $buildable = $declared | Where-Object { $installed -contains $_ }
    if ($buildable.Count -gt 0) {
        Write-Ok "required device definitions"
        Write-Info "buildable from manifest.xml: $($buildable -join ' ')"
    } else {
        Write-Fail "None of the products in manifest.xml are installed locally."
        Write-Info "Installed: $($installed -join ' ')"
    }
} else {
    Write-Fail "No device definitions installed in $DevicesDir"
    Write-Info "Open the Connect IQ SDK Manager, sign in with a Garmin account and"
    Write-Info "download the device definitions. See docs\ENVIRONMENT.md."
}

# --- Optional tooling -------------------------------------------------
Write-Host ""
foreach ($tool in 'git','make','just','openssl','code') {
    if (Get-Command $tool -ErrorAction SilentlyContinue) { Write-Ok $tool }
    else { Write-Warn "$tool not found (optional)" }
}

Write-Host ""
if ($script:Problems -eq 0) {
    Write-Host "Environment ready." -ForegroundColor Green
    exit 0
}
Write-Host "$($script:Problems) problem(s) found." -ForegroundColor Red
exit 1
