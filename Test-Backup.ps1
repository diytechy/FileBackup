<#
.SYNOPSIS
    Basic tests for Backup.ps1 and Reconstruct.ps1.

.DESCRIPTION
    - Creates a temporary root under $env:TEMP\BackupTest.
    - Sets up:
        * Source with duplicates and unique files.
        * Backup and change folders.
    - Runs Backup.ps1 once.
    - Modifies files (rename/move/change/delete).
    - Runs Backup.ps1 again.
    - Runs reconstruction and performs simple assertions.
#>

param(
    [string]$BackupScriptPath = ".\Backup.ps1"
)

$ErrorActionPreference = 'Stop'

$root = Join-Path $env:TEMP "BackupTest_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
$src  = Join-Path $root 'Source'
$bkp  = Join-Path $root 'Backup'
$chg  = Join-Path $root 'Changes'

New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null

Write-Host "Test root: $root"

# Create initial files
"Hello world"     | Out-File -LiteralPath (Join-Path $src 'file1.txt') -Encoding UTF8
"Duplicate data"  | Out-File -LiteralPath (Join-Path $src 'dup1.txt')  -Encoding UTF8
"Duplicate data"  | Out-File -LiteralPath (Join-Path $src 'dup2.txt')  -Encoding UTF8

# Create config
$configPath = Join-Path $root 'BackupConfig.xml'
$secrets = [pscustomobject]@{
    ToEmail     = 'test@example.com'
    FromEmail   = 'backup@test.local'
    SmtpServer  = 'smtp.example.com'
    SmtpPort    = 587
    Credential  = $null
}
$set = [pscustomobject]@{
    Name             = 'TestSet'
    SourcePath       = $src
    BackupPath       = $bkp
    ChangePath       = $chg
    HashRecalcFreq   = 'A'
    CompressEnabled  = $false
    PreserveFolderTree = $true
}
@{
    Secrets    = $secrets
    BackupSets = @($set)
} | Export-Clixml -LiteralPath $configPath

Write-Host "Running first backup..."
& $BackupScriptPath -ConfigPath $configPath

# Simulate changes
Rename-Item -LiteralPath (Join-Path $src 'file1.txt') -NewName 'file1_renamed.txt'
"Modified content" | Out-File -LiteralPath (Join-Path $src 'dup1.txt') -Encoding UTF8
Remove-Item -LiteralPath (Join-Path $src 'dup2.txt')

Write-Host "Running second backup..."
& $BackupScriptPath -ConfigPath $configPath

# Basic assertions
$backupManifestPath = Join-Path $bkp 'MANIFEST.csv'
if (-not (Test-Path -LiteralPath $backupManifestPath)) {
    throw "Backup manifest not found after second backup."
}

$db = Import-Csv -LiteralPath $backupManifestPath
if (-not ($db | Where-Object { $_.RelativePath -eq 'file1_renamed.txt' })) {
    throw "Renamed file is not present in backup manifest."
}
if ($db | Where-Object { $_.RelativePath -eq 'dup2.txt' }) {
    throw "Removed file still present in backup manifest."
}

Write-Host "Basic manifest checks passed."

# Test reconstruction
$reconTarget = Join-Path $root 'Reconstructed'
$reconScript = Join-Path $bkp 'RECONSTRUCT.ps1'
if (-not (Test-Path -LiteralPath $reconScript -PathType Leaf)) {
    throw "Reconstruct script not found in backup root."
}

& $reconScript -TargetRoot $reconTarget

if (-not (Test-Path -LiteralPath (Join-Path $reconTarget 'file1_renamed.txt'))) {
    throw "Reconstructed folder does not contain renamed file."
}
if (Test-Path -LiteralPath (Join-Path $reconTarget 'dup2.txt')) {
    throw "Reconstructed folder incorrectly contains removed file."
}

Write-Host "Reconstruction checks passed."
Write-Host "Test root (inspect manually if desired): $root"