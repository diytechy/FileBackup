<#
.SYNOPSIS
    Comprehensive test suite for FileBackup.ps1 including:
    - Mirror mode
    - Content-addressed mode
    - Compression mode
    - Duplicate detection
    - Moves, renames, modifications, removals
    - Redundant datapath removal across change folders
    - Reconstruction validation
#>

param(
    [string]$BackupScriptPath = ".\FileBackup.ps1"
)

$ErrorActionPreference = 'Stop'

function New-TestFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -LiteralPath $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Content | Out-File -LiteralPath $Path -Encoding UTF8
}

function Write-Header($msg) {
    Write-Host ""
    Write-Host "==============================="
    Write-Host $msg
    Write-Host "==============================="
}

# ============================================================
#  TEST ROOT
# ============================================================

$root = Join-Path $env:TEMP "BackupTest_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
$src  = Join-Path $root 'Source'
$bkp  = Join-Path $root 'Backup'
$chg  = Join-Path $root 'Changes'

New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null

Write-Host "Test root: $root"

# ============================================================
#  CONFIG GENERATOR
# ============================================================

function Write-Config {
    param(
        [string]$ConfigPath,
        [bool]$Compress,
        [bool]$CA
    )

    $secrets = [pscustomobject]@{
        ToEmail     = 'test@example.com'
        FromEmail   = 'backup@test.local'
        SmtpServer  = 'smtp.example.com'
        SmtpPort    = 587
        Credential  = $null
    }

    $set = [pscustomobject]@{
        Name               = 'TestSet'
        SourcePath         = $src
        BackupPath         = $bkp
        ChangePath         = $chg
        HashRecalcFreq     = 'A'
        CompressEnabled    = $Compress
        PreserveFolderTree = -not $CA
    }

    @{
        Secrets    = $secrets
        BackupSets = @($set)
    } | Export-Clixml -LiteralPath $ConfigPath
}

# ============================================================
#  TEST SUITE
# ============================================================

function Run-TestSuite {
    param(
        [string]$ModeName,
        [bool]$Compress,
        [bool]$CA
    )

    Write-Header "RUNNING TEST SUITE: $ModeName"

    # Reset folders
    Remove-Item -LiteralPath $src,$bkp,$chg -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $src,$bkp,$chg -Force | Out-Null

    $configPath = Join-Path $root "BackupConfig_$ModeName.xml"
    Write-Config -ConfigPath $configPath -Compress:$Compress -CA:$CA

    # -------------------------
    # RUN 1 — Initial files
    # -------------------------
    Write-Header "$ModeName — Backup #1"

    New-TestFile (Join-Path $src 'file1.txt') "Hello world"
    New-TestFile (Join-Path $src 'folderA\file2.txt') "Another file"

    # Duplicates
    New-TestFile (Join-Path $src 'dup1.txt') "Duplicate data"
    New-TestFile (Join-Path $src 'dup2.txt') "Duplicate data"
    New-TestFile (Join-Path $src 'nested\dup3.txt') "Duplicate data"

    & $BackupScriptPath -ConfigPath $configPath

    $db1 = Import-Csv (Join-Path $bkp 'MANIFEST.csv')
    if (-not ($db1 | Where-Object RelativePath -eq 'file1.txt')) {
        throw "$ModeName: file1.txt missing after run 1"
    }

    # -------------------------
    # RUN 2 — Moves, renames, modifications, removals
    # -------------------------
    Write-Header "$ModeName — Backup #2"

    Rename-Item (Join-Path $src 'file1.txt') -NewName 'file1_renamed.txt'

    Move-Item (Join-Path $src 'folderA\file2.txt') (Join-Path $src 'folderB\file2_moved.txt')

    New-TestFile (Join-Path $src 'dup1.txt') "Duplicate data modified"

    Remove-Item (Join-Path $src 'dup2.txt')

    & $BackupScriptPath -ConfigPath $configPath

    $db2 = Import-Csv (Join-Path $bkp 'MANIFEST.csv')

    if (-not ($db2 | Where-Object RelativePath -eq 'file1_renamed.txt')) {
        throw "$ModeName: rename not reflected in manifest"
    }
    if ($db2 | Where-Object RelativePath -eq 'file1.txt') {
        throw "$ModeName: old file1.txt still present"
    }

    # -------------------------
    # RUN 3 — Re-add duplicates
    # -------------------------
    Write-Header "$ModeName — Backup #3"

    New-TestFile (Join-Path $src 'dup2.txt') "Duplicate data"
    New-TestFile (Join-Path $src 'dup4.txt') "Duplicate data modified"

    & $BackupScriptPath -ConfigPath $configPath

    $db3 = Import-Csv (Join-Path $bkp 'MANIFEST.csv')

    if (-not ($db3 | Where-Object RelativePath -eq 'dup2.txt')) {
        throw "$ModeName: re-added dup2.txt missing"
    }
    if (-not ($db3 | Where-Object RelativePath -eq 'dup4.txt')) {
        throw "$ModeName: dup4.txt missing"
    }

    # -------------------------
    # TARGETED TEST — REDUNDANT DATAPATH REMOVAL
    # -------------------------
    Write-Header "$ModeName — Redundant Datapath Removal Test"

    # Force creation of redundant datapaths:
    # 1. Modify a file
    # 2. Run backup (creates change folder)
    # 3. Modify same file back to original content
    # 4. Run backup again (creates another change folder)
    # Now two change folders contain datapaths for same hash/size.

    New-TestFile (Join-Path $src 'redundant.txt') "Original content"
    & $BackupScriptPath -ConfigPath $configPath

    New-TestFile (Join-Path $src 'redundant.txt') "Modified content"
    & $BackupScriptPath -ConfigPath $configPath

    New-TestFile (Join-Path $src 'redundant.txt') "Original content"
    & $BackupScriptPath -ConfigPath $configPath

    # After sanitization, only the newest datapath (or backup datapath) should remain.
    $changeDirs = Get-ChildItem -LiteralPath $chg -Directory |
                  Where-Object { $_.Name -like 'Pre_*_Changes' } |
                  Sort-Object Name

    $allDataPaths = @()
    foreach ($dir in $changeDirs) {
        $manifest = Import-Csv (Join-Path $dir.FullName 'MANIFEST.csv')
        foreach ($row in $manifest) {
            if ($row.RelativePath -eq 'redundant.txt' -and $row.DataPath) {
                $full = Join-Path $dir.FullName $row.DataPath
                if (Test-Path $full) {
                    $allDataPaths += $full
                }
            }
        }
    }

    if ($allDataPaths.Count -gt 1) {
        throw "$ModeName: redundant datapaths were NOT removed correctly"
    }

    Write-Host "$ModeName: redundant datapath removal PASSED"

    # -------------------------
    # FINAL RECONSTRUCTION TEST
    # -------------------------
    Write-Header "$ModeName — Reconstruction Test"

    $reconTarget = Join-Path $root "Reconstructed_$ModeName"
    $reconScript = Join-Path $bkp 'RECONSTRUCT.ps1'

    & $reconScript -TargetRoot $reconTarget

    if (-not (Test-Path (Join-Path $reconTarget 'file1_renamed.txt'))) {
        throw "$ModeName: reconstruction missing file1_renamed.txt"
    }

    Write-Host "$ModeName reconstruction PASSED"
}

# ============================================================
#  RUN ALL MODES
# ============================================================

Run-TestSuite -ModeName "MirrorMode" -Compress:$false -CA:$false
Run-TestSuite -ModeName "ContentAddressed" -Compress:$false -CA:$true
Run-TestSuite -ModeName "CompressedCA" -Compress:$true -CA:$true

Write-Header "ALL TEST SUITES PASSED"
Write-Host "Test root: $root"