<#
.SYNOPSIS
    Shared test harness: result collection, assertions, file generators, config writer.
.NOTES
    Dot-sourced by Run-All.ps1. Exposes:
        $script:TestResults  (List[object])
        Add-TestResult, Assert-True, Assert-FilesByteEqual, Assert-ManifestRow
        New-TestFile, New-RandomBinaryFile, New-HugeSparseFile
        Write-TestConfig
        Invoke-Backup, Invoke-Reconstruct, Save-FailureArtifact
        Get-ManifestRow
        $script:LastBackupExitCode, $script:ArtifactRoot (set by Run-All.ps1)
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
        [bool]$Compress, [string]$HashRecalcFreq = 'A',
        [string]$Name = 'TestSet', [string]$BrowseView = ''
    )
    $secrets = [pscustomobject]@{
        ToEmail    = 'test@example.com'
        FromEmail  = 'backup@test.local'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $null
    }
    $set = [ordered]@{
        Name               = $Name
        SourcePath         = $SrcPath
        BackupPath         = $BkpPath
        ChangePath         = $ChgPath
        HashRecalcFreq     = $HashRecalcFreq
        CompressEnabled    = $Compress
    }
    if ($BrowseView) { $set['BrowseView'] = $BrowseView }
    @{ Secrets = $secrets; BackupSets = @([pscustomobject]$set) } | Export-Clixml -LiteralPath $ConfigPath
}

# Set by Invoke-Backup: the exit code of the most recent backup run, so a caller
# (or a post-mortem) can tell a failed FIXTURE run from a failed assertion.
$script:LastBackupExitCode = 0

function Invoke-Backup {
    <#
    .SYNOPSIS
        Runs FileBackup.ps1 and returns its output, recording the exit code.
    .DESCRIPTION
        WP11 Part A. This used to run the entry point and never look at
        $LASTEXITCODE, so a fixture backup could FAIL and the suite would carry
        on building assertions over a store that was missing a snapshot, a row
        or a stored object. Every observed instance of the 2026-08-26 Full-tier
        intermittent surfaced that way: an opaque 'Condition returned false' in
        G9 prune, several steps downstream of whatever actually went wrong.

        It still does not throw - many suites drive failing backups on purpose
        (G4's legacy refusal, the capacity refusals) - but a non-zero exit is now
        always ANNOUNCED, so any later opaque failure is preceded by its cause.
        Fixture builders pass -ExpectSuccess to turn an unexpected non-zero into
        a recorded FAIL that names the run rather than its consequences.
    .PARAMETER ExpectSuccess
        This call builds a fixture later assertions depend on; a non-zero exit is
        recorded as a FAIL naming the exit code and the tail of the run output.
    #>
    param(
        [string]$BackupScriptPath, [string]$ConfigPath, [switch]$SuppressMail,
        [Nullable[datetime]]$BackupTime,
        [switch]$ExpectSuccess,
        # Identify the failing run in the results row when -ExpectSuccess is set.
        [string]$Suite = '?', [string]$Group = '?', [string]$ScenarioId = 'fixture',
        [string]$Label = 'backup run'
    )
    # NOTE: FileBackup.ps1 currently calls Send-MailMessage at the end.
    # In test mode we wrap with try/catch and ignore mail failures so tests can run offline.
    $oldErr = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $extra = @{}
    if ($BackupTime) { $extra['BackupTime'] = [datetime]$BackupTime }   # deterministic snapshot dating (SR-005)
    try {
        $global:LASTEXITCODE = 0
        & $BackupScriptPath -ConfigPath $ConfigPath -NoMail @extra *>&1 | Tee-Object -Variable bkOut | Out-Null
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $script:LastBackupExitCode = $code
        if ($code -ne 0) {
            # ALWAYS visible, expected or not: the cause must appear above the
            # consequence in the transcript.
            Write-Host ("         [backup exit $code] $Label ($ConfigPath)") -ForegroundColor DarkYellow
        }
        if ($ExpectSuccess -and $code -ne 0) {
            $tail = (@($bkOut) | Select-Object -Last 6 | ForEach-Object { "$_" }) -join ' | '
            Add-TestResult $Suite $Group $ScenarioId "FixtureBackupFailed_$Label" 'FAIL' `
                "the fixture backup exited $code; every later assertion in this section is built on an incomplete store. Tail: $tail"
        }
        return $bkOut
    } finally {
        $ErrorActionPreference = $oldErr
    }
}

function Save-FailureArtifact {
    <#
    .SYNOPSIS
        Copies a section's logs and pool manifests into the run's artifact
        directory so a failure survives the next Reset-TestEnvironment.
    .DESCRIPTION
        WP11 Part A. The suites share ONE environment root and reset it between
        sections, so by the time a run finishes there is nothing left to examine
        - which is why three separate investigations of the 2026-08-26
        intermittent had to reason from the assertion name alone.
    .PARAMETER Env
        The test environment whose BkpPath/ChgPath should be preserved.
    .PARAMETER Tag
        Short name for the subdirectory, e.g. 'G9-prune-Plain'.
    #>
    param([pscustomobject]$Env, [string]$Tag)
    if (-not $script:ArtifactRoot) { return }
    $dest = Join-Path $script:ArtifactRoot ("failure-" + ($Tag -replace '[^\w\-]', '_'))
    try {
        New-Item -ItemType Directory -Path $dest -Force -ErrorAction Stop | Out-Null
        foreach ($log in @((Join-Path $Env.ChgPath 'backup.log'))) {
            if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination $dest -Force -ErrorAction SilentlyContinue }
        }
        foreach ($folder in @($Env.BkpPath) + @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue |
                                                Where-Object { $_.Name -like 'Snapshot_*' -or $_.Name -like 'Pruning_*' -or $_.Name -eq 'Temp' } |
                                                ForEach-Object { $_.FullName })) {
            $m = Join-Path $folder 'MANIFEST.csv'
            if (Test-Path -LiteralPath $m) {
                $name = ([IO.Path]::GetFileName($folder)) + '-MANIFEST.csv'
                Copy-Item -LiteralPath $m -Destination (Join-Path $dest $name) -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "         [artifacts] preserved under $dest" -ForegroundColor DarkGray
    } catch {
        Write-Host "         [artifacts] could not preserve: $($_.Exception.Message)" -ForegroundColor DarkGray
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
