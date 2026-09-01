<#
.SYNOPSIS  G8 - Real-volume-only scenarios.
.NOTES     Skipped under Subst / VHDX backends.

           G8.3-G8.5 are TC-194 (WP14 §5, §8 row 7): the SR-075 stale-staging
           reclaim exercised against an ACTUAL exFAT-formatted volume, because
           the plan's Q1 asks whether Directory.Move of a directory within its
           own parent is reliable on the deployment stacks. .NET promises no
           rename atomicity and permits in-use failures, so the supported-
           provider list is defined from this evidence rather than assumed.
#>

function Get-G8TreeHash {
    <#
    .SYNOPSIS
        SHA-256 of every byte under a folder, as "<relative path>=<hash>" lines.
    .DESCRIPTION
        The TC-194 refusal arms assert HASHES, not presence: a refusal that
        quietly rewrote a marker would sail through a Test-Path check.
    #>
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return '<missing>' }
    $lines = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object { "$($_.FullName)=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })
    return ($lines -join "`n")
}

function New-G8AbandonedTemp {
    <#
    .SYNOPSIS
        The on-disk state an externally killed run leaves behind, built on the
        real volume: ChangePath\Temp holding ONLY its own RUN.inprogress, with
        the marker's and the directory's mtime aged past the staleness
        threshold. Mirrors tests\Unit\StagingLock.Tests.ps1's New-AbandonedTemp.
    .DESCRIPTION
        The record is written by the module's own writer (never hand-rolled
        JSON) so the classifier sees a genuine, parseable owner record. The
        ageing uses [IO.File]/[IO.Directory]::SetLastWriteTimeUtc: exFAT stores
        timestamps at 2-second granularity, which a 3-hour age is far outside.
        exFAT also carries no ACLs, so nothing here depends on them.
    .OUTPUTS
        [pscustomobject] Path, MarkerPath, RunId.
    #>
    param([string]$ChgPath, [double]$MarkerAgeSeconds = 10800, [string]$SetName = 'TestSet')
    $temp = Join-Path $ChgPath 'Temp'
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $rec = Write-StagingOwnerRecord -StagingFolder $temp -SetName $SetName
    [System.IO.File]::SetLastWriteTimeUtc($rec.MarkerPath, [datetime]::UtcNow.AddSeconds(-$MarkerAgeSeconds))
    [System.IO.Directory]::SetLastWriteTimeUtc($temp, [datetime]::UtcNow.AddSeconds(-$MarkerAgeSeconds))
    [pscustomobject]@{ Path = $temp; MarkerPath = $rec.MarkerPath; RunId = $rec.RunId }
}

function Remove-G8StagingRemnant {
    <#
    .SYNOPSIS
        Clears Temp and any Temp.stale-* left on the real change volume, so the
        next arm (or the next mode's G8.2 backup) does not meet a lock.
    #>
    param([string]$ChgPath)
    foreach ($d in @(Get-ChildItem -LiteralPath $ChgPath -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'Temp' -or $_.Name -like 'Temp.stale-*' })) {
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-G8ConfirmationSample {
    <#
    .SYNOPSIS
        Compresses (or restores) the engine's confirmation-sample base for the
        IN-PROCESS arms. Production waits ~90 s before believing a lock is
        abandoned; the sample is still really taken and really compared.
    .DESCRIPTION
        Run-All.ps1 is not Pester, so there is no InModuleScope here: the module
        object itself is the session state to run in. Only the arms that call
        Initialize-StagingFolder directly are affected — G8.3 drives
        FileBackup.ps1, which re-imports the modules with -Force and therefore
        resets this to the production 90 s.
    #>
    param([double]$Seconds)
    $m = Get-Module FileBackup.Engine
    if (-not $m) { throw 'FileBackup.Engine is not loaded in the harness process.' }
    & $m { param($s) $script:StagingConfirmationSampleSeconds = $s } $Seconds
}

function Set-G8StagingHook {
    <#
    .SYNOPSIS
        Installs (or clears, with $null) one of the engine's named SR-075 test
        seams. Every seam is $null in production; only the suite assigns one.
    #>
    param([string]$Name, [AllowNull()][scriptblock]$Hook)
    $m = Get-Module FileBackup.Engine
    if (-not $m) { throw 'FileBackup.Engine is not loaded in the harness process.' }
    & $m { param($n, $h) Set-Variable -Name $n -Value $h -Scope Script } $Name $Hook
}

function New-G8StagingLogger {
    <#
    .SYNOPSIS
        A set-logger scriptblock for the in-process arms that both collects the
        lines and appends them to a real file on the change volume, so the
        SR-075 refusal evidence is quotable from the exFAT disk itself.
    .OUTPUTS
        [pscustomobject] Log (scriptblock), Path, Lines.
    #>
    param([string]$Path)
    $lines = New-Object System.Collections.Generic.List[string]
    $log = {
        param($Message, $Level = 'INFO')
        $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'O'), $Level, $Message
        $lines.Add($line)
        [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine)
    }.GetNewClosure()
    [pscustomobject]@{ Log = $log; Path = $Path; Lines = $lines }
}

function Invoke-G8 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G8-RealVolume'

    if ($Env.Backend -ne 'RealUSB') {
        Add-TestResult $suite $group 'G8.0' 'BackendNotRealUSB' 'SKIP' "Current backend: $($Env.Backend)"
        return
    }

    $cfg = Join-Path $env:TEMP 'cfg-g8.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress

    # G8.1 capacity sanity. (The original one-liner ended in
    # `Measure-Object | ForEach-Object Count -eq 0`, which binds 'Count' as a
    # METHOD name on the always-emitted GenericMeasureInfo and threw — so this
    # arm could never pass under the only backend that runs it. TC-194 is the
    # first run to actually exercise G8, which is how it surfaced.)
    Assert-True $suite $group 'G8.1' 'VolumesPresent_andLabeled' {
        $missing = @(@($Env.SrcPath, $Env.BkpPath, $Env.ChgPath, $Env.ReconPath) |
            Where-Object { -not (Test-Path -LiteralPath $_) })
        $missing.Count -eq 0
    }

    # G8.2 single-pass backup on real disks
    New-TestFile (Join-Path $Env.SrcPath 'real.txt') 'real-volume content'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G8.2' 'RealBackup_rowPresent' (Join-Path $Env.BkpPath 'MANIFEST.csv') 'real.txt' $true

    Invoke-G8StaleStagingReclaim -Env $Env -BackupScript $BackupScript -Suite $suite -Group $group -Compress $Compress
    Invoke-G8AmbiguousMoveRefusal -Env $Env -Suite $suite -Group $group
}

function Invoke-G8StaleStagingReclaim {
    <#
    .SYNOPSIS
        G8.3 (TC-194): a stale marker-only Temp reclaimed END TO END on a real
        exFAT volume, through the ordinary FileBackup.ps1 entry point.
    .DESCRIPTION
        The entry point re-imports both modules with -Force, so the engine's
        confirmation-sample seam cannot reach it: this arm runs at the
        PRODUCTION 90 s sample and really waits it out. That is the point —
        nothing about the decision is compressed for the exFAT evidence.
    #>
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Suite, [string]$Group, [bool]$Compress)

    Reset-TestEnvironment $Env
    $cfg = Join-Path $env:TEMP 'cfg-g8-reclaim.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress
    New-TestFile (Join-Path $Env.SrcPath 'reclaim.txt') 'stale-temp reclaim on exFAT'

    $dead = New-G8AbandonedTemp -ChgPath $Env.ChgPath
    $started = Get-Date
    Invoke-Backup -Suite $Suite -Group $Group -ScenarioId 'G8.3' -Label 'exFAT reclaim' -ExpectSuccess `
        -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $exit = $script:LastBackupExitCode

    $logPath = Join-Path $Env.ChgPath 'backup.log'
    $log = if (Test-Path -LiteralPath $logPath -PathType Leaf) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    $aside = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Temp.stale-*' })
    $successor = [regex]::Match($log, 'owner record published \(RunId=([0-9a-fA-F-]+)')

    Add-TestResult $Suite $Group 'G8.3' 'ExfatStaleTempReclaimedEndToEnd_TC-194' `
        $(if ($exit -eq 0) { 'PASS' } else { 'FAIL' }) `
        "backup exit $exit after a real $elapsed s run (production 90 s confirmation sample, uncompressed)"

    Assert-ManifestRow $Suite $Group 'G8.3' 'ExfatReclaim_manifestRowPresent_TC-194' `
        (Join-Path $Env.BkpPath 'MANIFEST.csv') 'reclaim.txt' $true

    foreach ($pattern in @('\[SR-075/reclaimed\]',
                           'confirming with a second sample',
                           'Moved the abandoned staging folder aside',
                           'held only its own owner record and has been removed')) {
        Assert-True $Suite $Group 'G8.3' "ExfatReclaimLog_$($pattern -replace '[^\w]', '')_TC-194" `
            { $log -match $pattern }.GetNewClosure()
    }

    Assert-True $Suite $Group 'G8.3' 'ExfatReclaim_asideFolderGone_TC-194' `
        { $aside.Count -eq 0 }.GetNewClosure()
    Assert-True $Suite $Group 'G8.3' 'ExfatReclaim_TempDiscardedByCompleteChangeFolder_TC-194' `
        { -not (Test-Path -LiteralPath (Join-Path $Env.ChgPath 'Temp')) }.GetNewClosure()
    Assert-True $Suite $Group 'G8.3' 'ExfatReclaim_successorRunIdDiffersFromDead_TC-194' `
        { $successor.Success -and $successor.Groups[1].Value -ne $dead.RunId }.GetNewClosure()

    if ($exit -ne 0 -or $aside.Count -gt 0) { Save-FailureArtifact -Env $Env -Tag "G8.3-$Suite" }
    Remove-G8StagingRemnant -ChgPath $Env.ChgPath
}

function Invoke-G8AmbiguousMoveRefusal {
    <#
    .SYNOPSIS
        G8.4 / G8.5 (TC-194): the two ways the reclaim's Directory.Move can go
        wrong on a real exFAT volume, both of which must REFUSE with both paths
        untouched and no writer started — never a fallback to delete (Q1).
    .DESCRIPTION
        G8.4 is the §11 R-3 interleaving from the TC-191 unit test, replayed on
        the exFAT disk: reclaimer A completes its whole reclaim while reclaimer
        B is parked before its move, so B's move takes a LIVE directory.
        G8.5 is a REAL ambiguous move failure rather than an interleaving: an
        open FileShare.Read handle on the marker inside a genuinely abandoned
        Temp makes Windows fail the directory rename outright.

        Both arms drive Initialize-StagingFolder in the harness process, which
        is where the engine's test seams live; the confirmation sample is
        compressed and restored in a finally.
    #>
    param([pscustomobject]$Env, [string]$Suite, [string]$Group)

    Remove-G8StagingRemnant -ChgPath $Env.ChgPath
    $stagingLogPath = Join-Path $Env.ChgPath 'staging-reclaim.log'
    Remove-Item -LiteralPath $stagingLogPath -Force -ErrorAction SilentlyContinue

    # ---------- G8.4: the R-3 interleaving (a LIVE directory is moved) ----------
    $state = @{ Fired = $false; A = $null; HashAfterA = $null }
    $logger = New-G8StagingLogger -Path $stagingLogPath
    try {
        Set-G8ConfirmationSample -Seconds 0.3
        New-G8AbandonedTemp -ChgPath $Env.ChgPath | Out-Null
        $chg = $Env.ChgPath

        $hook = {
            param($folder)
            if ($state.Fired) { return }
            $state.Fired = $true
            # A completes its ENTIRE reclaim - move aside, recreate Temp, publish
            # its own owner record - while B is parked before its move. (The
            # nested call re-enters this seam; the flag makes it a no-op.)
            $state.A = Initialize-StagingFolder -ChgPath (Split-Path -Parent $folder) -Log $logger.Log `
                          -SetName 'G8.4-A' -ConfirmationSampleSeconds 0.3
            $state.HashAfterA = Get-G8TreeHash -Root (Join-Path $chg 'Temp')
        }.GetNewClosure()
        Set-G8StagingHook -Name 'StagingReclaimTestHook_BeforeMove' -Hook $hook

        $msg = $null
        try {
            Initialize-StagingFolder -ChgPath $Env.ChgPath -Log $logger.Log -SetName 'G8.4-B' `
                -ConfirmationSampleSeconds 0.3 | Out-Null
        } catch { $msg = $_.Exception.Message }
        Set-G8StagingHook -Name 'StagingReclaimTestHook_BeforeMove' -Hook $null

        $marker = Join-Path (Join-Path $Env.ChgPath 'Temp') 'RUN.inprogress'
        $hashAfterB = Get-G8TreeHash -Root (Join-Path $Env.ChgPath 'Temp')
        $entries = @(Get-ChildItem -LiteralPath (Join-Path $Env.ChgPath 'Temp') -Force -ErrorAction SilentlyContinue)
        $aside = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Temp.stale-*' })
        $ownerRunId = if (Test-Path -LiteralPath $marker -PathType Leaf) {
            (Read-StagingOwnerRecord -MarkerPath $marker).Record.RunId
        } else { $null }

        Add-TestResult $Suite $Group 'G8.4' 'ExfatLiveDirectoryMoved_seamRanAToCompletion_TC-194' `
            $(if ($state.Fired -and $state.A) { 'PASS' } else { 'FAIL' }) "A RunId=$($state.A.RunId)"
        Assert-True $Suite $Group 'G8.4' 'ExfatAmbiguousMove_refusedOwnerLive_TC-194' `
            { $msg -and $msg -match '\[SR-075/owner-live\]' }.GetNewClosure()
        Assert-True $Suite $Group 'G8.4' 'ExfatAmbiguousMove_AsLockStandsAtOriginalPath_TC-194' `
            { $state.A -and $ownerRunId -eq $state.A.RunId }.GetNewClosure()
        Assert-True $Suite $Group 'G8.4' 'ExfatAmbiguousMove_noAsideFolderLeft_TC-194' `
            { $aside.Count -eq 0 }.GetNewClosure()
        Assert-True $Suite $Group 'G8.4' 'ExfatAmbiguousMove_bothPathsByteUntouched_TC-194' `
            { $state.HashAfterA -and $hashAfterB -eq $state.HashAfterA }.GetNewClosure()
        Assert-True $Suite $Group 'G8.4' 'ExfatAmbiguousMove_BstartedNoWriter_TC-194' `
            { $entries.Count -eq 1 -and $entries[0].Name -ceq 'RUN.inprogress' }.GetNewClosure()
    } catch {
        Add-TestResult $Suite $Group 'G8.4' 'ExfatAmbiguousMoveArmCrashed_TC-194' 'FAIL' $_.Exception.Message
    } finally {
        Set-G8StagingHook -Name 'StagingReclaimTestHook_BeforeMove' -Hook $null
        if ($state.A) { Stop-StagingHeartbeat $state.A.Heartbeat }
        Set-G8ConfirmationSample -Seconds 90
        Remove-G8StagingRemnant -ChgPath $Env.ChgPath
    }

    # ---------- G8.5: a REAL ambiguous Directory.Move failure ----------
    $handle = $null
    try {
        Set-G8ConfirmationSample -Seconds 0.3
        $dead = New-G8AbandonedTemp -ChgPath $Env.ChgPath
        $before = Get-G8TreeHash -Root $dead.Path
        # FileShare.Read keeps the marker READABLE - the folder must still
        # classify as provably abandoned - while denying the rename, which
        # Windows fails with "Access to the path ... is denied".
        $handle = [System.IO.File]::Open($dead.MarkerPath, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)

        $msg = $null
        try {
            Initialize-StagingFolder -ChgPath $Env.ChgPath -Log $logger.Log -SetName 'G8.5' `
                -ConfirmationSampleSeconds 0.3 | Out-Null
        } catch { $msg = $_.Exception.Message }
        $handle.Dispose(); $handle = $null

        $after = Get-G8TreeHash -Root $dead.Path
        $entries = @(Get-ChildItem -LiteralPath $dead.Path -Force -ErrorAction SilentlyContinue)
        $aside = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Temp.stale-*' })
        $logText = ($logger.Lines -join "`n")

        Assert-True $Suite $Group 'G8.5' 'ExfatRealMoveFailure_refusedNotDeleted_TC-194' `
            { $msg -and $msg -match '\[SR-075/content-refused\]' }.GetNewClosure()
        Assert-True $Suite $Group 'G8.5' 'ExfatRealMoveFailure_logNamesTheMoveFailure_TC-194' `
            { $logText -match 'moving it aside to .+ FAILED' -and $logText -match 'both paths are left exactly as they were' }.GetNewClosure()
        Assert-True $Suite $Group 'G8.5' 'ExfatRealMoveFailure_TempStandsByteIdentical_TC-194' `
            { (Test-Path -LiteralPath $dead.Path) -and $after -eq $before }.GetNewClosure()
        Assert-True $Suite $Group 'G8.5' 'ExfatRealMoveFailure_noAsideCreated_TC-194' `
            { $aside.Count -eq 0 }.GetNewClosure()
        Assert-True $Suite $Group 'G8.5' 'ExfatRealMoveFailure_noWriterStarted_TC-194' `
            { $entries.Count -eq 1 -and $entries[0].Name -ceq 'RUN.inprogress' }.GetNewClosure()
    } catch {
        Add-TestResult $Suite $Group 'G8.5' 'ExfatRealMoveFailureArmCrashed_TC-194' 'FAIL' $_.Exception.Message
    } finally {
        if ($handle) { $handle.Dispose() }
        Set-G8ConfirmationSample -Seconds 90
        Set-G8StagingHook -Name 'StagingReclaimTestHook_BeforeMove' -Hook $null
        Remove-G8StagingRemnant -ChgPath $Env.ChgPath
    }
}
