<#
.SYNOPSIS
    Idempotent dependency setup for the FileBackup test suite.
    First run: prompts for K4os.Hash.xxHash install (and 7-Zip if missing).
    Subsequent runs: writes a marker file; exits immediately.

.PARAMETER InstallDeps
    Install missing dependencies. In -NonInteractive mode, fail rather than prompt.

.PARAMETER NonInteractive
    No prompts; suitable for CI. Missing K4os = fail. Missing 7-Zip = warn (tests SKIP).
#>
param(
    [switch]$InstallDeps,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$marker = Join-Path $PSScriptRoot '.setup-complete'

function Test-K4os {
    if ('K4os.Hash.xxHash.XXH128' -as [type]) { return $true }
    return [bool](Get-Package -Name 'K4os.Hash.xxHash' -ErrorAction SilentlyContinue)
}

function Install-K4os {
    Write-Host "Installing K4os.Hash.xxHash 1.0.8 ..." -ForegroundColor Cyan
    if (-not (Get-PackageSource -Name nuget.org -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name nuget.org -Location https://www.nuget.org/api/v2 `
            -ProviderName NuGet -Trusted -Force | Out-Null
    }
    Install-Package K4os.Hash.xxHash -RequiredVersion 1.0.8 `
        -Force -Scope CurrentUser -Source nuget.org | Out-Null
}

function Test-SevenZip {
    Test-Path (Join-Path $env:ProgramFiles '7-Zip\7z.exe')
}

Write-Host "FileBackup Test Setup" -ForegroundColor Cyan
Write-Host "====================="

# K4os.Hash.xxHash
if (Test-K4os) {
    Write-Host "[OK]  K4os.Hash.xxHash available"
} else {
    if ($NonInteractive) {
        if ($InstallDeps) {
            Install-K4os
        } else {
            Write-Error "K4os.Hash.xxHash missing and -InstallDeps not set."
            exit 2
        }
    } else {
        $resp = Read-Host "K4os.Hash.xxHash 1.0.8 missing. Install now? (Y/N)"
        if ($resp -match '^[Yy]') { Install-K4os } else {
            Write-Error "Cannot proceed without K4os.Hash.xxHash."
            exit 2
        }
    }
}

# 7-Zip
if (Test-SevenZip) {
    Write-Host "[OK]  7-Zip found at $env:ProgramFiles\7-Zip\7z.exe"
} else {
    Write-Warning "7-Zip not found; compression tests will SKIP. Install from https://www.7-zip.org/ or run 'winget install 7zip.7zip'."
}

# PowerShell version
Write-Host ("[OK]  PowerShell {0}" -f $PSVersionTable.PSVersion)

New-Item -ItemType File -Path $marker -Force | Out-Null
Write-Host "Setup complete." -ForegroundColor Green
