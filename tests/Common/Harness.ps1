<#
.SYNOPSIS
    Shared test harness: result collection, assertions, file generators, config writer.
.NOTES
    Dot-sourced by Run-All.ps1. Exposes:
        $script:TestResults  (List[object])
        Add-TestResult, Assert-True, Assert-FilesByteEqual, Assert-ManifestRow
        New-TestFile, New-RandomBinaryFile, New-HugeSparseFile
        Write-TestConfig
        Invoke-Backup, Invoke-Reconstruct
        Get-ManifestRow
#>

if (-not (Get-Variable -Name TestResults -Scope Script -ErrorAction SilentlyContinue)) {
    $script:TestResults = New-Object System.Collections.Generic.List[object]
}

function Add-TestResult {
    param(
        [string]$Suite, [string]$Group, [string]$ScenarioId, [string]$TestName,
        [ValidateSet('PASS','FAIL','SKIP')][string]$Status,
        [string]$Detail = '',
        [hashtable]$Extras = @{}
    )
    $row = [ordered]@{
        Suite        = $Suite
        Group        = $Group
        ScenarioId   = $ScenarioId
        TestName     = $TestName
        Status       = $Status
        Detail       = $Detail
        Timestamp    = (Get-Date -Format 'O')
    }
    foreach ($k in $Extras.Keys) { $row[$k] = $Extras[$k] }
    $script:TestResults.Add([pscustomobject]$row)
    $color = switch ($Status) { 'PASS' {'Green'} 'FAIL' {'Red'} 'SKIP' {'Yellow'} }
    Write-Host ("  [{0}] {1}/{2}/{3} {4}" -f $Status, $Suite, $Group, $ScenarioId, $TestName) -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
}

function Assert-True {
    param(
        [string]$Suite, [string]$Group, [string]$ScenarioId, [string]$TestName,
        [scriptblock]$Condition
    )
    try {
        $ok = & $Condition
        if ($ok) { Add-TestResult $Suite $Group $ScenarioId $TestName 'PASS' '' }
        else     { Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' 'Condition returned false' }
    } catch {
        Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' $_.Exception.Message
    }
}

function Assert-FilesByteEqual {
    param(
        [string]$Suite, [string]$Group, [string]$ScenarioId, [string]$TestName,
        [string]$Expected, [string]$Actual
    )
    try {
        if (-not (Test-Path -LiteralPath $Expected)) {
            Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' "Expected missing: $Expected"; return
        }
        if (-not (Test-Path -LiteralPath $Actual)) {
            Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' "Actual missing: $Actual"; return
        }
        $h1 = (Get-FileHash -LiteralPath $Expected -Algorithm SHA256).Hash
        $h2 = (Get-FileHash -LiteralPath $Actual   -Algorithm SHA256).Hash
        if ($h1 -eq $h2) { Add-TestResult $Suite $Group $ScenarioId $TestName 'PASS' '' }
        else             { Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' "Hash mismatch: $h1 vs $h2" }
    } catch {
        Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' $_.Exception.Message
    }
}

function Get-ManifestRow {
    param([string]$ManifestPath, [string]$RelativePath)
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $null }
    Import-Csv -LiteralPath $ManifestPath | Where-Object { $_.RelativePath -eq $RelativePath } | Select-Object -First 1
}

function Assert-ManifestRow {
    param(
        [string]$Suite, [string]$Group, [string]$ScenarioId, [string]$TestName,
        [string]$ManifestPath, [string]$RelativePath, [bool]$ShouldExist
    )
    try {
        if (-not (Test-Path -LiteralPath $ManifestPath)) {
            Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' "Manifest missing: $ManifestPath"; return
        }
        $row = Get-ManifestRow -ManifestPath $ManifestPath -RelativePath $RelativePath
        $exists = $null -ne $row
        if ($exists -eq $ShouldExist) {
            Add-TestResult $Suite $Group $ScenarioId $TestName 'PASS' ''
        } else {
            $msg = if ($ShouldExist) { "Missing row: $RelativePath" } else { "Unexpected row: $RelativePath" }
            Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' $msg
        }
    } catch {
        Add-TestResult $Suite $Group $ScenarioId $TestName 'FAIL' $_.Exception.Message
    }
}

function New-TestFile {
    param([string]$Path, [string]$Content = '')
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function New-RandomBinaryFile {
    param([string]$Path, [int]$SizeBytes)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $SizeBytes
    $rng.GetBytes($bytes)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function New-HugeSparseFile {
    param([string]$Path, [long]$SizeBytes)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $fs = [System.IO.File]::Create($Path)
    try { $fs.SetLength($SizeBytes) } finally { $fs.Dispose() }
}

function Write-TestConfig {
    param(
        [string]$ConfigPath, [string]$SrcPath, [string]$BkpPath, [string]$ChgPath,
        [bool]$Compress, [bool]$ContentAddressed, [string]$HashRecalcFreq = 'A',
        [string]$Name = 'TestSet'
    )
    $secrets = [pscustomobject]@{
        ToEmail    = 'test@example.com'
        FromEmail  = 'backup@test.local'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $null
    }
    $set = [pscustomobject]@{
        Name               = $Name
        SourcePath         = $SrcPath
        BackupPath         = $BkpPath
        ChangePath         = $ChgPath
        HashRecalcFreq     = $HashRecalcFreq
        CompressEnabled    = $Compress
        PreserveFolderTree = -not $ContentAddressed
    }
    @{ Secrets = $secrets; BackupSets = @($set) } | Export-Clixml -LiteralPath $ConfigPath
}

function Invoke-Backup {
    param([string]$BackupScriptPath, [string]$ConfigPath, [switch]$SuppressMail)
    # NOTE: FileBackup.ps1 currently calls Send-MailMessage at the end.
    # In test mode we wrap with try/catch and ignore mail failures so tests can run offline.
    $oldErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $BackupScriptPath -ConfigPath $ConfigPath *>&1 | Tee-Object -Variable bkOut | Out-Null
        return $bkOut
    } finally {
        $ErrorActionPreference = $oldErr
    }
}

function Invoke-Reconstruct {
    param([string]$ReconstructScript, [string]$TargetRoot)
    if (-not (Test-Path -LiteralPath $ReconstructScript)) {
        throw "Reconstruct script not found: $ReconstructScript"
    }
    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    }
    & $ReconstructScript -TargetRoot $TargetRoot *>&1 | Out-Null
}
