<#
.SYNOPSIS
    LEGACY single-file test harness — SUPERSEDED by the tests/ suite.

.NOTES
    Replaced by tests/Run-All.ps1 (modular Subst/VHDX/RealUSB backends, G1-G8
    suites, Pester unit tests, JUnit output). This file predates the module split
    and the System.IO.Hashing switch, references the old function names, and is
    NOT run by CI or RunAllTests.bat. Kept for reference only; add new coverage in
    tests/, not here. See AGENTS.md.

    Original description: comprehensive test suite for FileBackup.ps1 including:
    - Mirror mode (PreserveFolderTree)
    - Content-addressed mode (Hash+Size naming)
    - Compression mode
    - Duplicate detection
    - Moves, renames, modifications, removals
    - Redundant datapath removal across change folders
    - Reconstruction validation
    - Hash-based recovery fallback
    - Decompression in reconstruction
    - Various hash recalc frequencies
    - Edge cases (empty source, special chars, etc.)
#>

param(
    [string]$BackupScriptPath = ".\FileBackup.ps1"
)

$ErrorActionPreference = 'Stop'

# Drive mappings
$DriveSrc = 'X'
$DriveBkp = 'Y'
$DriveChg = 'Z'
$DriveRecon = 'W'

$TestPhysRoot = Join-Path $env:TEMP "BackupTest_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
$SrcPhys = Join-Path $TestPhysRoot 'Source'
$BkpPhys = Join-Path $TestPhysRoot 'Backup'
$ChgPhys = Join-Path $TestPhysRoot 'Changes'
$ReconPhys = Join-Path $TestPhysRoot 'Recon'

# Test results
$TestResults = New-Object System.Collections.Generic.List[object]

# ============================================================
#  Utility Functions
# ============================================================

function Mount-TestDrives {
    New-Item -ItemType Directory -Force -Path $SrcPhys, $BkpPhys, $ChgPhys, $ReconPhys | Out-Null
    cmd /c "subst ${DriveSrc}: `"$SrcPhys`""
    cmd /c "subst ${DriveBkp}: `"$BkpPhys`""
    cmd /c "subst ${DriveChg}: `"$ChgPhys`""
    cmd /c "subst ${DriveRecon}: `"$ReconPhys`""
    Write-Host "Mounted test drives: ${DriveSrc}:\ ${DriveBkp}:\ ${DriveChg}:\ ${DriveRecon}:\"
}

function Dismount-TestDrives {
    cmd /c "subst ${DriveSrc}: /d 2>nul"
    cmd /c "subst ${DriveBkp}: /d 2>nul"
    cmd /c "subst ${DriveChg}: /d 2>nul"
    cmd /c "subst ${DriveRecon}: /d 2>nul"
    Write-Host "Dismounted test drives"
}

function Assert-DrivesAvailable {
    foreach ($letter in @($DriveSrc, $DriveBkp, $DriveChg, $DriveRecon)) {
        if (Test-Path "${letter}:\") {
            throw "Drive ${letter}: is already in use. Cannot proceed with tests."
        }
    }
}

function New-TestFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Content | Out-File -LiteralPath $Path -Encoding UTF8
}

function Reset-TestFolders {
    Remove-Item -LiteralPath $SrcPhys, $BkpPhys, $ChgPhys, $ReconPhys -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $SrcPhys, $BkpPhys, $ChgPhys, $ReconPhys -Force | Out-Null
}

function Write-Header($msg) {
    Write-Host ""
    Write-Host "===============================" -ForegroundColor Cyan
    Write-Host $msg -ForegroundColor Cyan
    Write-Host "===============================" -ForegroundColor Cyan
}

function Write-Config {
    param(
        [string]$ConfigPath,
        [string]$SrcPath,
        [string]$BkpPath,
        [string]$ChgPath,
        [bool]$Compress,
        [bool]$CA,
        [string]$HashRecalcFreq = 'A'
    )

    $secrets = [pscustomobject]@{
        ToEmail = 'test@example.com'
        FromEmail = 'backup@test.local'
        SmtpServer = 'smtp.example.com'
        SmtpPort = 587
        Credential = $null
    }

    $set = [pscustomobject]@{
        Name = 'TestSet'
        SourcePath = $SrcPath
        BackupPath = $BkpPath
        ChangePath = $ChgPath
        HashRecalcFreq = $HashRecalcFreq
        CompressEnabled = $Compress
        PreserveFolderTree = -not $CA
    }

    @{
        Secrets = $secrets
        BackupSets = @($set)
    } | Export-Clixml -LiteralPath $ConfigPath
}

function Add-TestResult {
    param(
        [string]$Suite,
        [string]$Group,
        [string]$TestName,
        [string]$Status,  # 'PASS', 'FAIL', 'SKIP'
        [string]$Detail
    )
    $TestResults.Add([pscustomobject]@{
        Suite = $Suite
        Group = $Group
        TestName = $TestName
        Status = $Status
        Detail = $Detail
        Timestamp = (Get-Date -Format 'O')
    })
}

function Assert-True {
    param(
        [string]$Suite,
        [string]$Group,
        [string]$TestName,
        [scriptblock]$Condition
    )
    try {
        $result = & $Condition
        if ($result) {
            Add-TestResult $Suite $Group $TestName 'PASS' ''
            Write-Host "  [OK] $TestName" -ForegroundColor Green
        } else {
            Add-TestResult $Suite $Group $TestName 'FAIL' 'Condition returned false'
            Write-Host "  [FAIL] $TestName (condition false)" -ForegroundColor Red
        }
    } catch {
        Add-TestResult $Suite $Group $TestName 'FAIL' $_.Exception.Message
        Write-Host "  [FAIL] $TestName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-ManifestRow {
    param(
        [string]$Suite,
        [string]$Group,
        [string]$TestName,
        [string]$ManifestPath,
        [string]$RelativePath,
        [bool]$ShouldExist
    )
    try {
        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            Add-TestResult $Suite $Group $TestName 'FAIL' "Manifest not found at $ManifestPath"
            Write-Host "  [FAIL] $TestName (manifest missing)" -ForegroundColor Red
            return
        }
        $db = Import-Csv -LiteralPath $ManifestPath
        $row = $db | Where-Object RelativePath -eq $RelativePath
        $exists = $null -ne $row
        if ($exists -eq $ShouldExist) {
            Add-TestResult $Suite $Group $TestName 'PASS' ''
            Write-Host "  [OK] $TestName" -ForegroundColor Green
        } else {
            $msg = if ($ShouldExist) { "Row not found: $RelativePath" } else { "Row should not exist: $RelativePath" }
            Add-TestResult $Suite $Group $TestName 'FAIL' $msg
            Write-Host "  [FAIL] $TestName ($msg)" -ForegroundColor Red
        }
    } catch {
        Add-TestResult $Suite $Group $TestName 'FAIL' $_.Exception.Message
        Write-Host "  [FAIL] $TestName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================
#  Test Suite Functions
# ============================================================

function Test-BasicOps {
    param([string]$Suite, [string]$ConfigPath)

    Write-Host ""
    Write-Host "Testing BasicOps..." -ForegroundColor Yellow

    # Run 1 - Initial backup
    Write-Host "  Backup #1: Creating initial files"
    New-TestFile "${DriveSrc}:\file1.txt" "Hello world"
    New-TestFile "${DriveSrc}:\folderA\file2.txt" "Another file"
    New-TestFile "${DriveSrc}:\dup1.txt" "Duplicate data"
    New-TestFile "${DriveSrc}:\dup2.txt" "Duplicate data"

    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'BasicOps' 'InitialBackup_file1_exists' "${DriveBkp}:\MANIFEST.csv" 'file1.txt' $true
    Assert-ManifestRow $Suite 'BasicOps' 'InitialBackup_file2_exists' "${DriveBkp}:\MANIFEST.csv" 'folderA\file2.txt' $true

    # Run 2 - Renames and moves
    Write-Host "  Backup #2: Testing rename and move"
    Rename-Item "${DriveSrc}:\file1.txt" -NewName 'file1_renamed.txt'
    if (Test-Path "${DriveSrc}:\folderA") {
        Move-Item "${DriveSrc}:\folderA\file2.txt" "${DriveSrc}:\folderB\file2_moved.txt"
    }
    New-TestFile "${DriveSrc}:\dup1.txt" "Duplicate data modified"
    Remove-Item "${DriveSrc}:\dup2.txt"

    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'BasicOps' 'Rename_reflected' "${DriveBkp}:\MANIFEST.csv" 'file1_renamed.txt' $true
    Assert-ManifestRow $Suite 'BasicOps' 'OldName_absent' "${DriveBkp}:\MANIFEST.csv" 'file1.txt' $false
    Assert-ManifestRow $Suite 'BasicOps' 'Remove_absent' "${DriveBkp}:\MANIFEST.csv" 'dup2.txt' $false

    # Run 3 - Re-add
    Write-Host "  Backup #3: Re-adding removed file"
    New-TestFile "${DriveSrc}:\dup2.txt" "Duplicate data"

    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'BasicOps' 'Readd_present' "${DriveBkp}:\MANIFEST.csv" 'dup2.txt' $true
}

function Test-Reconstruction {
    param([string]$Suite, [string]$ConfigPath)

    Write-Host ""
    Write-Host "Testing Reconstruction..." -ForegroundColor Yellow

    # Set up a few files and run backup
    Write-Host "  Creating source files"
    New-TestFile "${DriveSrc}:\test_recon.txt" "Reconstruction test content"
    New-TestFile "${DriveSrc}:\subdir\nested.txt" "Nested file"

    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    # Run reconstruction from backup root
    Write-Host "  Reconstructing from backup root"
    $reconScript = "${DriveBkp}:\RECONSTRUCT.ps1"
    if (Test-Path -LiteralPath $reconScript) {
        & $reconScript -TargetRoot "${DriveRecon}:\" 2>&1 | Out-Null

        Assert-True $Suite 'Reconstruction' 'ReconFrom_BackupRoot_fileExists' {
            Test-Path "${DriveRecon}:\test_recon.txt" -PathType Leaf
        }
        Assert-True $Suite 'Reconstruction' 'ReconFrom_BackupRoot_nestedExists' {
            Test-Path "${DriveRecon}:\subdir\nested.txt" -PathType Leaf
        }
    } else {
        Write-Host "  ⚠ RECONSTRUCT.ps1 not found; skipping reconstruction test" -ForegroundColor Yellow
        Add-TestResult $Suite 'Reconstruction' 'ReconScript_missing' 'SKIP' 'RECONSTRUCT.ps1 not found'
    }
}

function Test-EdgeCases {
    param([string]$Suite, [string]$ConfigPath)

    Write-Host ""
    Write-Host "Testing EdgeCases..." -ForegroundColor Yellow

    # Test 1: Empty source
    Write-Host "  Testing empty source"
    Remove-Item "${DriveSrc}:\*" -Recurse -Force -ErrorAction SilentlyContinue

    try {
        & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null
        Add-TestResult $Suite 'EdgeCases' 'EmptySource_completes' 'PASS' ''
        Write-Host "  [OK] Empty source handled gracefully" -ForegroundColor Green
    } catch {
        Add-TestResult $Suite 'EdgeCases' 'EmptySource_completes' 'FAIL' $_.Exception.Message
        Write-Host "  [FAIL] Empty source caused error: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Test 2: Files with spaces
    Write-Host "  Testing files with spaces"
    New-TestFile "${DriveSrc}:\my file with spaces.txt" "File with spaces"
    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'EdgeCases' 'SpacesInFilename' "${DriveBkp}:\MANIFEST.csv" 'my file with spaces.txt' $true

    # Test 3: Deep nesting
    Write-Host "  Testing deep nesting"
    New-TestFile "${DriveSrc}:\a\b\c\d\e\deep.txt" "Deep nested file"
    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'EdgeCases' 'DeepNesting' "${DriveBkp}:\MANIFEST.csv" 'a\b\c\d\e\deep.txt' $true

    # Test 4: Special characters in paths
    Write-Host "  Testing special characters"
    New-TestFile "${DriveSrc}:\folder[1]\file(2).txt" "Special char file"
    & $BackupScriptPath -ConfigPath $ConfigPath 2>&1 | Out-Null

    Assert-ManifestRow $Suite 'EdgeCases' 'SpecialChars' "${DriveBkp}:\MANIFEST.csv" 'folder[1]\file(2).txt' $true
}

function Run-TestSuite {
    param([string]$ModeName, [bool]$Compress, [bool]$CA)

    $header = "TEST SUITE: $ModeName (Compress=$Compress, CA=$($CA))"
    Write-Header $header

    # Reset test folders
    Reset-TestFolders

    # Write config
    $configPath = Join-Path $TestPhysRoot "Config_$ModeName.xml"
    Write-Config -ConfigPath $configPath `
                 -SrcPath "${DriveSrc}:\" `
                 -BkpPath "${DriveBkp}:\" `
                 -ChgPath "${DriveChg}:\" `
                 -Compress:$Compress `
                 -CA:$CA

    # Run test groups
    Test-BasicOps -Suite $ModeName -ConfigPath $configPath
    Test-Reconstruction -Suite $ModeName -ConfigPath $configPath
    Test-EdgeCases -Suite $ModeName -ConfigPath $configPath

    Write-Host ""
}

# ============================================================
#  Main Entry Point
# ============================================================

try {
    Assert-DrivesAvailable

    Write-Header "FILEBACKUP TEST HARNESS"
    Write-Host "Test root: $TestPhysRoot"
    Write-Host ""

    Mount-TestDrives

    # Verify FileBackup.ps1 exists
    $BackupScriptPath = (Resolve-Path -LiteralPath $BackupScriptPath).Path
    Write-Host "Backup script: $BackupScriptPath"

    # Run all test suites
    Run-TestSuite -ModeName "MirrorMode" -Compress:$false -CA:$false
    Run-TestSuite -ModeName "ContentAddressed" -Compress:$false -CA:$true
    Run-TestSuite -ModeName "CompressedCA" -Compress:$true -CA:$true

} finally {
    Dismount-TestDrives
}

# ============================================================
#  Results Summary
# ============================================================

Write-Header "TEST RESULTS"

$csvPath = Join-Path $TestPhysRoot "TestResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$TestResults | Export-Csv -LiteralPath $csvPath -NoTypeInformation
Write-Host "Results exported: $csvPath"

$passed = $TestResults | Where-Object Status -eq 'PASS'
$failed = $TestResults | Where-Object Status -eq 'FAIL'

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Passed: $($passed.Count)" -ForegroundColor Green
Write-Host "  Failed: $($failed.Count)" -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host ""

if ($failed) {
    Write-Host "Failed tests:" -ForegroundColor Red
    $failed | Format-Table Suite, Group, TestName, Detail -AutoSize
}

Write-Host "Test root (for inspection): $TestPhysRoot"
