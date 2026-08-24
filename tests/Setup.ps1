<#
.SYNOPSIS
    Idempotent dependency setup for the FileBackup test suite (PowerShell 7+).

.DESCRIPTION
    Ensures the runtime + test dependencies are present:
        * System.IO.Hashing   (NuGet)  - xxHash128 hashing. REQUIRED.
        * 7-Zip               (winget) - compression tests. Optional (tests SKIP).
        * Pester 5            (PSGallery) - unit suite. Optional unless -InstallTestTools.
        * PSScriptAnalyzer    (PSGallery) - lint. Optional unless -InstallTestTools.

.PARAMETER InstallDeps
    Install missing dependencies. In -NonInteractive mode, fail rather than prompt.

.PARAMETER InstallTestTools
    Also install Pester 5 and PSScriptAnalyzer (for the unit + lint jobs).

.PARAMETER NonInteractive
    No prompts; suitable for CI. Missing System.IO.Hashing = fail. Missing 7-Zip = warn.
#>
param(
    [switch]$InstallDeps,
    [switch]$InstallTestTools,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$marker = Join-Path $PSScriptRoot '.setup-complete'

$HashPackage = 'System.IO.Hashing'
$HashVersion = '8.0.0'

function Test-HashPackage {
    if ('System.IO.Hashing.XxHash128' -as [type]) { return $true }
    return [bool](Get-Package -Name $HashPackage -ErrorAction SilentlyContinue)
}

function Install-HashPackage {
    Write-Host "Installing $HashPackage $HashVersion ..." -ForegroundColor Cyan
    if (-not (Get-PackageSource -Name nuget.org -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name nuget.org -Location https://api.nuget.org/v3/index.json `
            -ProviderName NuGet -Trusted -Force | Out-Null
    }
    Install-Package $HashPackage -RequiredVersion $HashVersion `
        -Force -Scope CurrentUser -Source nuget.org | Out-Null
}

function Test-SevenZip { Test-Path (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }

Write-Host "FileBackup Test Setup (PowerShell $($PSVersionTable.PSVersion))" -ForegroundColor Cyan
Write-Host "============================================"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "FileBackup requires PowerShell 7+. Detected $($PSVersionTable.PSVersion). Run under 'pwsh'."
}

# System.IO.Hashing
if (Test-HashPackage) {
    Write-Host "[OK]  $HashPackage available"
} else {
    if ($NonInteractive) {
        if ($InstallDeps) { Install-HashPackage }
        else { Write-Error "$HashPackage missing and -InstallDeps not set."; exit 2 }
    } else {
        $resp = Read-Host "$HashPackage $HashVersion missing. Install now? (Y/N)"
        if ($resp -match '^[Yy]') { Install-HashPackage }
        else { Write-Error "Cannot proceed without $HashPackage."; exit 2 }
    }
}

# 7-Zip
if (Test-SevenZip) {
    Write-Host "[OK]  7-Zip found at $env:ProgramFiles\7-Zip\7z.exe"
} else {
    Write-Warning "7-Zip not found; compression tests will SKIP. Install via 'winget install 7zip.7zip'."
}

# Optional test tooling
if ($InstallTestTools) {
    if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.0'))) {
        Write-Host "Installing Pester 5 ..." -ForegroundColor Cyan
        Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
    } else { Write-Host "[OK]  Pester 5+ available" }

    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Write-Host "Installing PSScriptAnalyzer ..." -ForegroundColor Cyan
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
    } else { Write-Host "[OK]  PSScriptAnalyzer available" }
}

New-Item -ItemType File -Path $marker -Force | Out-Null
Write-Host "Setup complete." -ForegroundColor Green
