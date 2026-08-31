<#
.SYNOPSIS  Pester 5 unit tests for the WP14 staging-lock work: the Part A
           helpers (SR-075 / LLR-080) — owner record writer and reader, the
           pure classifier, the compiled identity-guarded heartbeat — and the
           Part B wiring into the backup run (TC-185, TC-196, TC-201, TC-202).
#>

BeforeAll {
    # $PSScriptRoot here is tests\Unit; repo root is two levels up.
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    $script:Floor = 1800

    # A Read-StagingOwnerRecord-shaped result, built without touching a disk so
    # the classifier tests stay pure (LLR-080: the matrix is unit-testable with
    # no filesystem).
    function New-ReadResult {
        param(
            [string]$State,
            [double]$AgeSeconds = 0,
            [object]$Record = $null,
            [switch]$NoMtime
        )
        [pscustomobject]@{
            State        = $State
            Record       = $Record
            LastWriteUtc = $(if ($NoMtime) { $null } else { [datetime]::UtcNow.AddSeconds(-$AgeSeconds) })
            AgeSeconds   = $(if ($NoMtime) { $null } else { $AgeSeconds })
            Error        = $null
        }
    }

    function New-OwnerPayload {
        param([int]$SchemaVersion = 1, [string]$RunId = ([guid]::NewGuid().ToString()), $StaleAfterSeconds = 1800)
        [pscustomobject]@{
            SchemaVersion            = $SchemaVersion
            Kind                     = 'backup'
            RunId                    = $RunId
            SetName                  = 'library'
            Host                     = 'homehub'
            ContainerId              = ''
            BootId                   = ''
            Pid                      = 1
            StartedUtc               = '2026-08-30T14:34:02Z'
            HeartbeatIntervalSeconds = 60
            StaleAfterSeconds        = $StaleAfterSeconds
        }
    }

    function New-StagingDir {
        $dir = Join-Path $TestDrive ('stage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $dir | Out-Null
        return $dir
    }

    # --- Part B fixtures (TC-185, TC-196, TC-202) ---------------------------

    function Invoke-PipelineBlockingOperation {
        <#
        .SYNOPSIS
            Occupies the pipeline thread inside ONE long .NET call, the way
            hashing a 100 GB file does in production.
        .DESCRIPTION
            A PowerShell LOOP is NOT equivalent and must not be substituted:
            PowerShell drains queued engine events between statements, so a
            loop lets a Register-ObjectEvent handler run and would make the
            TC-185 negative control silently pass. A single blocking call has
            no statement boundary to drain at — which is exactly the condition
            SR-075 says the beat must survive.
        #>
        param([int]$Milliseconds)
        [System.Threading.Thread]::Sleep($Milliseconds)
    }

    function New-BackupSetFixture {
        # A minimal one-set environment driven through Invoke-BackupSet
        # in-process: the entry point re-imports the module, which would tear
        # down the mocks TC-196 needs.
        param([string]$Name)
        $root = Join-Path $TestDrive $Name
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [pscustomobject]@{
            Root = $root; Src = $src; Bkp = $bkp; Chg = $chg
            Set  = [pscustomobject]@{
                Name = $Name; SourcePath = $src; SourceStatePath = ''; BackupPath = $bkp
                ChangePath = $chg; HashRecalcFreq = 'A'; CompressEnabled = $false
                AllowEmptySource = $false; BrowseView = 'off'; ViewPath = ''
            }
        }
    }

    function Invoke-FixtureBackup {
        param([object]$Fixture, [datetime]$When)
        $ok = $true
        Invoke-BackupSet -Set $Fixture.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
            -OverallSuccess ([ref]$ok) -LogPaths (New-Object System.Collections.Generic.List[string]) `
            -BackupTime $When
        return $ok
    }

    function Get-RootedHeartbeatCount {
        # The engine roots every live heartbeat; Stop-StagingHeartbeat unroots
        # it. An empty list therefore means the Part B finally ran.
        InModuleScope FileBackup.Engine {
            if ($null -eq $script:StagingHeartbeats) { 0 } else { $script:StagingHeartbeats.Count }
        }
    }

    function Set-EngineHeartbeatInterval {
        # The production cadence is 60 s (SR-075); the suite shortens it so a
        # test can observe several beats without minutes of sleeping.
        param([double]$Seconds)
        InModuleScope FileBackup.Engine -Parameters @{ S = $Seconds } {
            $script:StagingHeartbeatIntervalSeconds = $S
        }
    }
}

Describe 'Get-StagingLockState — evidence completeness (TC-200, SR-017, SR-075, LLR-080)' {

    It 'classifies a hidden entry as content (TC-200, SR-075, LLR-080)' {
        $v = Get-StagingLockState -Entries @('RUN.inprogress', 'hidden.dat') -OwnerRecord (New-ReadResult -State 'Parsed' -Record (New-OwnerPayload))
        $v.State | Should -Be 'HoldsContent'
        $v.Reclaimable | Should -BeFalse
        $v.Token | Should -Be '[SR-075/content-refused]'
    }

    It 'classifies system and dot-named entries as content (TC-200, SR-075, LLR-080)' {
        foreach ($name in @('system.sys', '.dotfile', '.hidden-dir', 'desktop.ini')) {
            $v = Get-StagingLockState -Entries @([pscustomobject]@{ Name = $name })
            $v.State | Should -Be 'HoldsContent' -Because "'$name' is content like any other entry"
        }
    }

    It 'treats a case-differing marker name as content, fail-closed (TC-200, SR-075, LLR-080)' {
        # On Linux 'run.inprogress' is a DIFFERENT file; refusing is the safe side.
        (Get-StagingLockState -Entries @('run.inprogress')).State | Should -Be 'HoldsContent'
    }

    It 'classifies an enumeration failure as Indeterminate and refuses (TC-200, SR-075, LLR-080)' {
        $v = Get-StagingLockState -EnumerationFailed
        $v.State | Should -Be 'Indeterminate'
        $v.Reclaimable | Should -BeFalse
        $v.Reason | Should -Be 'EnumerationFailed'
        $v.Token | Should -Be '[SR-075/content-refused]'
    }

    It 'refuses a reparse-point Temp with the content refusal (TC-200, SR-017, LLR-080)' {
        # Even when the folder looks empty: moving or deleting through a symlink
        # acts on a tree this guard never classified.
        $v = Get-StagingLockState -Entries @() -DirectoryLastWriteUtc ([datetime]::UtcNow.AddDays(-30)) -IsReparsePoint
        $v.State | Should -Be 'HoldsContent'
        $v.Reason | Should -Be 'ReparsePoint'
        $v.Reclaimable | Should -BeFalse
        $v.Token | Should -Be '[SR-075/content-refused]'
    }

    It 'refuses a PRUNE.inprogress of any age (TC-200, SR-046, SR-075, LLR-080)' {
        $v = Get-StagingLockState -Entries @('PRUNE.inprogress')
        $v.State | Should -Be 'PruneHeld'
        $v.Reclaimable | Should -BeFalse
        $v.Token | Should -Be '[SR-075/prune-held]'
    }

    It 'prefers the prune verdict when both markers are present (TC-200, SR-046, LLR-080)' {
        (Get-StagingLockState -Entries @('RUN.inprogress', 'PRUNE.inprogress')).State | Should -Be 'PruneHeld'
    }
}

Describe 'Get-StagingLockState — the empty branches (SR-075, LLR-080)' {

    It 'reclaims an empty Temp whose own mtime is stale (SR-017, SR-075, LLR-080)' {
        $v = Get-StagingLockState -Entries @() -DirectoryLastWriteUtc ([datetime]::UtcNow.AddSeconds(-($script:Floor + 5)))
        $v.State | Should -Be 'Empty'
        $v.Reclaimable | Should -BeTrue
    }

    It 'refuses an empty Temp whose own mtime is fresh — the create-to-marker window (SR-075, LLR-080)' {
        $v = Get-StagingLockState -Entries @() -DirectoryLastWriteUtc ([datetime]::UtcNow.AddSeconds(-10))
        $v.State | Should -Be 'EmptyFresh'
        $v.Reclaimable | Should -BeFalse
        $v.Token | Should -Be '[SR-075/owner-live]'
    }

    It 'is Indeterminate when the directory mtime is unknown (SR-075, LLR-080)' {
        $v = Get-StagingLockState -Entries @()
        $v.State | Should -Be 'Indeterminate'
        $v.Reclaimable | Should -BeFalse
    }
}

Describe 'Get-StagingLockState — marker liveness and the 1800 s floor (TC-199, SR-075, LLR-080)' {

    It 'calls a parsed, stale marker OwnerStale (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Parsed' -AgeSeconds ($script:Floor + 60) -Record (New-OwnerPayload)
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.State | Should -Be 'OwnerStale'
        $v.Reclaimable | Should -BeTrue
    }

    It 'calls a parsed, fresh marker OwnerLive (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Parsed' -AgeSeconds 30 -Record (New-OwnerPayload)
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.State | Should -Be 'OwnerLive'
        $v.Reclaimable | Should -BeFalse
        $v.Token | Should -Be '[SR-075/owner-live]'
    }

    It 'honours a record threshold that LENGTHENS beyond the floor (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Parsed' -AgeSeconds ($script:Floor + 60) -Record (New-OwnerPayload -StaleAfterSeconds 7200)
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.State | Should -Be 'OwnerLive'
        $v.StaleAfterSeconds | Should -Be 7200
    }

    It 'refuses to let a record threshold SHORTEN below the 1800 s floor (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Parsed' -AgeSeconds 300 -Record (New-OwnerPayload -StaleAfterSeconds 60)
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.StaleAfterSeconds | Should -Be $script:Floor
        $v.State | Should -Be 'OwnerLive'
    }

    It 'falls back to mtime with the floor for a ParseInvalid marker — stale (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'ParseInvalid' -AgeSeconds ($script:Floor + 1)
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.State | Should -Be 'OwnerStale'
        $v.Reclaimable | Should -BeTrue
        $v.StaleAfterSeconds | Should -Be $script:Floor
    }

    It 'falls back to mtime with the floor for a ParseInvalid marker — fresh (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'ParseInvalid' -AgeSeconds 5
        (Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r).State | Should -Be 'OwnerLive'
    }

    It 'is Indeterminate — and refuses — for an Unreadable marker (TC-199, SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Unreadable' -NoMtime
        $v = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r
        $v.State | Should -Be 'Indeterminate'
        $v.Reason | Should -Be 'MarkerUnreadable'
        $v.Reclaimable | Should -BeFalse
    }

    It 'is Indeterminate when the marker was never read (SR-075, LLR-080)' {
        (Get-StagingLockState -Entries @('RUN.inprogress')).State | Should -Be 'Indeterminate'
    }

    It 'treats a FUTURE-dated marker mtime as fresh (SR-075, LLR-080)' {
        $r = New-ReadResult -State 'Parsed' -AgeSeconds (-3600) -Record (New-OwnerPayload)
        (Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $r).State | Should -Be 'OwnerLive'
    }
}

Describe 'Write-StagingOwnerRecord (SR-075, LLR-080)' {

    It 'publishes RUN.inprogress with the schema-1 payload and leaves no temp file (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'

        $rec.MarkerPath | Should -Be (Join-Path $dir 'RUN.inprogress')
        Test-Path -LiteralPath $rec.MarkerPath | Should -BeTrue
        $rec.SchemaVersion | Should -Be 1
        $rec.Kind | Should -Be 'backup'
        $rec.SetName | Should -Be 'library'
        $rec.HeartbeatIntervalSeconds | Should -Be 60
        $rec.StaleAfterSeconds | Should -Be 1800
        [guid]::Parse($rec.RunId) | Should -Not -BeNullOrEmpty
        # The publish is a rename of a temp name INSIDE Temp; nothing may remain.
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 1
    }

    It 'mints a FRESH RunId per acquisition (SR-075, LLR-080)' {
        $a = Write-StagingOwnerRecord -StagingFolder (New-StagingDir) -SetName 'library'
        $b = Write-StagingOwnerRecord -StagingFolder (New-StagingDir) -SetName 'library'
        $a.RunId | Should -Not -Be $b.RunId
    }

    It 'THROWS a recognizable lock-lost error when RUN.inprogress already exists (SR-075, LLR-080)' {
        $dir = New-StagingDir
        Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library' -RunId 'aaaaaaaa-0000-0000-0000-000000000001' | Out-Null
        $before = [System.IO.File]::ReadAllText((Join-Path $dir 'RUN.inprogress'))

        { Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library' } |
            Should -Throw -ExpectedMessage 'StagingLockLost*'

        # The loser touches nothing: the winner's record stands and no temp
        # file is left behind.
        [System.IO.File]::ReadAllText((Join-Path $dir 'RUN.inprogress')) | Should -Be $before
        @(Get-ChildItem -LiteralPath $dir -Force).Count | Should -Be 1
    }

    It 'carries the [SR-075/lock-lost] token in the throw (SR-075, LLR-080)' {
        $dir = New-StagingDir
        Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library' | Out-Null
        $msg = $null
        try { Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library' } catch { $msg = $_.Exception.Message }
        $msg | Should -BeLike '*[[]SR-075/lock-lost]*'
    }
}

Describe 'Read-StagingOwnerRecord — the three states (TC-199, SR-075, LLR-080)' {

    It 'returns Parsed with mtime and age for a well-formed record (TC-199, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $read = Read-StagingOwnerRecord -MarkerPath $rec.MarkerPath
        $read.State | Should -Be 'Parsed'
        $read.Record.RunId | Should -Be $rec.RunId
        $read.LastWriteUtc | Should -Not -BeNullOrEmpty
        $read.AgeSeconds | Should -BeLessThan 60
    }

    It 'returns ParseInvalid with mtime fields for a TRUNCATED record (TC-199, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $whole = [System.IO.File]::ReadAllText($rec.MarkerPath)
        [System.IO.File]::WriteAllText($rec.MarkerPath, $whole.Substring(0, [int]($whole.Length / 2)))
        $stale = [datetime]::UtcNow.AddSeconds(-3600)
        [System.IO.File]::SetLastWriteTimeUtc($rec.MarkerPath, $stale)

        $read = Read-StagingOwnerRecord -MarkerPath $rec.MarkerPath
        $read.State | Should -Be 'ParseInvalid'
        $read.LastWriteUtc | Should -Not -BeNullOrEmpty
        $read.AgeSeconds | Should -BeGreaterThan 1800

        # And it is never an error: the classifier reclaims on the mtime alone.
        (Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $read).State | Should -Be 'OwnerStale'
    }

    It 'returns ParseInvalid for an UNKNOWN SchemaVersion, fresh mtime refusing (TC-199, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $marker = Join-Path $dir 'RUN.inprogress'
        [System.IO.File]::WriteAllText($marker, ((New-OwnerPayload -SchemaVersion 99) | ConvertTo-Json))

        $read = Read-StagingOwnerRecord -MarkerPath $marker
        $read.State | Should -Be 'ParseInvalid'
        $read.Error | Should -BeLike '*SchemaVersion*'
        (Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $read).State | Should -Be 'OwnerLive'
    }

    It 'returns ParseInvalid for a record with no RunId (TC-199, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $marker = Join-Path $dir 'RUN.inprogress'
        [System.IO.File]::WriteAllText($marker, '{"SchemaVersion":1,"Kind":"backup"}')
        (Read-StagingOwnerRecord -MarkerPath $marker).State | Should -Be 'ParseInvalid'
    }

    It 'returns Unreadable for a marker held with a deny-read lock (TC-199, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $fs = [System.IO.File]::Open($rec.MarkerPath, [System.IO.FileMode]::Open,
                                     [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $read = Read-StagingOwnerRecord -MarkerPath $rec.MarkerPath
            $read.State | Should -Be 'Unreadable'
            $read.LastWriteUtc | Should -BeNullOrEmpty
            $read.AgeSeconds | Should -BeNullOrEmpty
            # Absence of evidence is not evidence of death.
            (Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $read).State | Should -Be 'Indeterminate'
        } finally {
            $fs.Dispose()
        }
    }

    It 'returns Unreadable — never an exception — for a missing marker (TC-199, SR-075, LLR-080)' {
        $read = Read-StagingOwnerRecord -MarkerPath (Join-Path (New-StagingDir) 'RUN.inprogress')
        $read.State | Should -Be 'Unreadable'
    }
}

Describe 'StagingHeartbeat (SR-075, LLR-080)' {

    It 'advances the marker mtime when the RunId matches (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $old = [datetime]::UtcNow.AddHours(-2)
        [System.IO.File]::SetLastWriteTimeUtc($rec.MarkerPath, $old)

        $hb = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.TouchCount -lt 2 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $hb.TouchCount | Should -BeGreaterThan 1
            $hb.ErrorCount | Should -Be 0
            [System.IO.File]::GetLastWriteTimeUtc($rec.MarkerPath) | Should -BeGreaterThan $old
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'does NOT touch a marker carrying a different RunId (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $marker = Join-Path $dir 'RUN.inprogress'
        [System.IO.File]::WriteAllText($marker, ((New-OwnerPayload -RunId '11111111-1111-1111-1111-111111111111') | ConvertTo-Json))
        $old = [datetime]::UtcNow.AddHours(-2)
        [System.IO.File]::SetLastWriteTimeUtc($marker, $old)

        $hb = Start-StagingHeartbeat -MarkerPath $marker -RunId '22222222-2222-2222-2222-222222222222' -IntervalSeconds 0.1
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.SkippedCount -lt 2 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $hb.SkippedCount | Should -BeGreaterThan 1
            $hb.TouchCount | Should -Be 0
            [System.IO.File]::GetLastWriteTimeUtc($marker) | Should -Be $old
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'skips — never errors — when the marker has been reclaimed away (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            Remove-Item -LiteralPath $rec.MarkerPath -Force
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.SkippedCount -lt 1 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $hb.SkippedCount | Should -BeGreaterThan 0
            $hb.ErrorCount | Should -Be 0
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'records a throwing callback on ErrorCount/LastError and keeps beating (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            $hb.FaultNextBeat = $true
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.ErrorCount -lt 1 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $hb.ErrorCount | Should -Be 1
            $hb.LastError | Should -BeLike '*Injected heartbeat callback fault*'

            # System.Timers.Timer would have swallowed it invisibly; the beat
            # must also survive it.
            $touches = $hb.TouchCount
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.TouchCount -le $touches -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $hb.TouchCount | Should -BeGreaterThan $touches
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'DRAINS on Stop: it waits out an in-flight callback and none lands after (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            $hb.BeatDelayMs = 700
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.InFlight -lt 1 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
            $hb.InFlight | Should -BeGreaterThan 0 -Because 'the test needs a callback actually in flight'

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Stop-StagingHeartbeat $hb
            $sw.Stop()

            $sw.ElapsedMilliseconds | Should -BeGreaterThan 50 -Because 'Stop must wait out the in-flight callback'
            $hb.InFlight | Should -Be 0
            $hb.IsStopped | Should -BeTrue

            $touches = $hb.TouchCount
            Start-Sleep -Milliseconds 500   # several intervals
            $hb.TouchCount | Should -Be $touches -Because 'no touch may land after Stop returns'
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'is idempotent and never throws from a finally path (SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        { Stop-StagingHeartbeat $hb; Stop-StagingHeartbeat $hb; Stop-StagingHeartbeat $hb } | Should -Not -Throw
        { Stop-StagingHeartbeat $null } | Should -Not -Throw
    }

    It 'compiles the callback type once and re-Add-Types nothing on reload (SR-075, LLR-080)' {
        { Initialize-StagingHeartbeatType; Initialize-StagingHeartbeatType } | Should -Not -Throw
        'FileBackup.StagingHeartbeat' -as [type] | Should -Not -BeNullOrEmpty
    }
}

Describe 'The beat survives a blocked pipeline (TC-185, SR-075, LLR-080)' {

    It 'advances the marker mtime, observed from a SEPARATE process, while a long blocking operation occupies the pipeline (TC-185, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb  = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.25
        try {
            # The observer is a CHILD PROCESS on purpose: nothing in this
            # runspace may be what advances the mtime, or the test proves
            # nothing about the production case (SR-075 acceptance).
            $observedMarker = $rec.MarkerPath
            $job = Start-Job -ScriptBlock {
                $seen = New-Object System.Collections.Generic.List[string]
                $deadline = [datetime]::UtcNow.AddSeconds(7)
                while ([datetime]::UtcNow -lt $deadline) {
                    $t = [System.IO.File]::GetLastWriteTimeUtc($using:observedMarker).ToString('o')
                    if (-not $seen.Contains($t)) { $seen.Add($t) }
                    [System.Threading.Thread]::Sleep(50)
                }
                $seen.Count
            }
            Invoke-PipelineBlockingOperation -Milliseconds 5000
            $distinct = [int](Receive-Job -Job $job -Wait -AutoRemoveJob)

            $distinct | Should -BeGreaterThan 2 -Because 'the compiled callback, not the pipeline, drives the beat'
            $hb.TouchCount | Should -BeGreaterThan 4
            $hb.ErrorCount | Should -Be 0
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'NEGATIVE CONTROL: a Register-ObjectEvent handler does NOT advance it under the same block (TC-185, SR-075, LLR-080)' {
        # The fix removed, per the WP13-T4 precedent: the same cadence driven by
        # a PowerShell scriptblock instead of the Add-Type class. The handler is
        # queued to the pipeline the blocking call is holding, so it cannot run
        # - this is the production failure the compiled callback exists for, and
        # the naive test that would have passed is the one that sleeps instead
        # of blocking.
        $dir = New-StagingDir
        $marker = Join-Path $dir 'BROKEN.marker'
        [System.IO.File]::WriteAllText($marker, 'broken-beat')
        $old = [datetime]::UtcNow.AddHours(-2)
        [System.IO.File]::SetLastWriteTimeUtc($marker, $old)

        $timer = New-Object System.Timers.Timer 250
        $timer.AutoReset = $true
        $sub = Register-ObjectEvent -InputObject $timer -EventName Elapsed -MessageData $marker -Action {
            [System.IO.File]::SetLastWriteTimeUtc($Event.MessageData, [datetime]::UtcNow)
        }
        try {
            $timer.Start()
            Invoke-PipelineBlockingOperation -Milliseconds 4000
            [System.IO.File]::GetLastWriteTimeUtc($marker) | Should -Be $old -Because 'the scriptblock handler is queued to the pipeline the blocking call holds'

            # ...and it is not that the harness is broken: once the pipeline is
            # idle the very same handler fires. That is precisely why an inline
            # or scriptblock beat passes a naive test and fails in production.
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            while ([System.IO.File]::GetLastWriteTimeUtc($marker) -eq $old -and [datetime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }
            [System.IO.File]::GetLastWriteTimeUtc($marker) | Should -BeGreaterThan $old
        } finally {
            $timer.Stop()
            Unregister-Event -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
            $timer.Dispose()
        }
    }

    It 'a throwing callback neither kills the run nor silently stops the beat (TC-185, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb  = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.25
        try {
            $hb.FaultNextBeat = $true
            # Fault it WHILE the pipeline is blocked: System.Timers.Timer would
            # swallow the exception invisibly, so a dead beat would otherwise
            # look identical to a healthy one.
            { Invoke-PipelineBlockingOperation -Milliseconds 3000 } | Should -Not -Throw

            $hb.ErrorCount | Should -Be 1
            $hb.LastError | Should -BeLike '*Injected heartbeat callback fault*'
            $hb.IsStopped | Should -BeFalse
            $touches = $hb.TouchCount
            $touches | Should -BeGreaterThan 0 -Because 'the beat continued past the throw'
            Invoke-PipelineBlockingOperation -Milliseconds 1000
            $hb.TouchCount | Should -BeGreaterThan $touches
        } finally { Stop-StagingHeartbeat $hb }
    }
}

Describe 'Every exit stops the heartbeat (TC-196, SR-075, LLR-017, LLR-080)' {
    # TC-073 itself lives in tests/Unit/Coverage.Tests.ps1 ("Move loops
    # aggregate failures (SR-041)") and runs in this same suite; these cases
    # cover the Part B addition, which is the regression risk: the four catch
    # cleanups reach only the EARLY exits, so an exception escaping AFTER
    # staging has gained content used to leave a live timer advertising an
    # abandoned lock as owned. A successor must classify such a lock OwnerStale.

    BeforeEach { Set-EngineHeartbeatInterval -Seconds 0.2 }
    AfterEach  { Set-EngineHeartbeatInterval -Seconds 60 }

    It 'stops and drains the beat when an early catch cleanup fires (TC-196, SR-075, LLR-017)' {
        $fx = New-BackupSetFixture -Name 'tc196-early'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        Mock -ModuleName FileBackup.Engine Update-SourceManifest { throw 'INJECTED: source walk failed' }

        { Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') } |
            Should -Throw -ExpectedMessage '*INJECTED*'

        # The existing catch cleanup still removes the not-yet-valuable Temp...
        Test-Path -LiteralPath (Join-Path $fx.Chg 'Temp') | Should -BeFalse
        # ...and the Part B finally still stopped the timer.
        Get-RootedHeartbeatCount | Should -Be 0
    }

    # One It PER PHASE (-ForEach), not a loop inside one It: a Pester mock lives
    # for the whole It, so a loop would leave the previous phase's mock in place
    # and break the NEXT iteration's setup run.
    It 'stops and drains the beat when <_> throws after staging gains content (TC-196, SR-075, LLR-017, LLR-080)' -ForEach @(
        'Invoke-BackupFileGroup', 'Move-RemovedFilesToStaging', 'Save-SupersededData', 'Complete-ChangeFolder'
    ) {
        $phase = $_
        $fx = New-BackupSetFixture -Name ('tc196-' + $phase)
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'gone.txt'), 'DOOMED')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Out-Null
        # Give run 2 work in every loop: one changed file and one removal.
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Remove-Item -LiteralPath (Join-Path $fx.Src 'gone.txt') -Force

        Mock -ModuleName FileBackup.Engine $phase { throw "INJECTED: $phase failed" }
        { Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') } |
            Should -Throw -ExpectedMessage '*INJECTED*' -Because "the throw from $phase must escape"

        Get-RootedHeartbeatCount | Should -Be 0 -Because "the finally must stop the beat when $phase throws"

        # And the proof on disk: the abandoned lock's marker STOPS being
        # freshened, so a successor sees it age into OwnerStale instead of
        # OwnerLive forever. (Complete-ChangeFolder throws after step 12.9
        # has already removed the marker, so there is nothing to sample.)
        $marker = Join-Path (Join-Path $fx.Chg 'Temp') 'RUN.inprogress'
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            $before = [System.IO.File]::GetLastWriteTimeUtc($marker)
            Start-Sleep -Milliseconds 1200     # six beat intervals
            [System.IO.File]::GetLastWriteTimeUtc($marker) | Should -Be $before -Because "no beat may land after the finally ran ($phase)"
        }
    }
}

Describe 'A late callback cannot freshen a successor (TC-201, SR-075, LLR-080)' {

    It 'holds a callback in flight across Stop while a successor publishes, and does NOT freshen it (TC-201, SR-075, LLR-080)' {
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb  = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            # Park a callback inside the beat (the delay lands BEFORE it reads
            # the marker), then reclaim the lock underneath it.
            $hb.BeatDelayMs = 1500
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.InFlight -lt 1 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
            $hb.InFlight | Should -BeGreaterThan 0 -Because 'the test needs a callback actually in flight'

            # The successor: a DIFFERENT RunId at the same path.
            [System.IO.File]::Delete($rec.MarkerPath)
            $successor = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
            $successor.RunId | Should -Not -Be $rec.RunId
            $successorMtime = [System.IO.File]::GetLastWriteTimeUtc($successor.MarkerPath)

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            Stop-StagingHeartbeat $hb
            $sw.Stop()
            $sw.ElapsedMilliseconds | Should -BeGreaterThan 50 -Because 'Stop must DRAIN the in-flight callback'
            $hb.InFlight | Should -Be 0

            [System.IO.File]::GetLastWriteTimeUtc($successor.MarkerPath) | Should -Be $successorMtime -Because 'the identity guard rejects a marker that is not this beat''s own'
            Start-Sleep -Milliseconds 400
            [System.IO.File]::GetLastWriteTimeUtc($successor.MarkerPath) | Should -Be $successorMtime

            { Stop-StagingHeartbeat $hb; Stop-StagingHeartbeat $hb } | Should -Not -Throw
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'NEGATIVE CONTROL: with the identity discriminator gone the same held callback DOES freshen it (TC-201, SR-075, LLR-080)' {
        # The guard cannot be deleted from the compiled class without editing
        # shipped code, so the control neutralizes its DISCRIMINATOR instead:
        # the successor republishes under the SAME RunId, which is exactly what
        # the callback would see if it did not compare identities at all. The
        # touch then lands on a record this beat no longer owns - the race
        # TC-201 exists to close. (The drain is measured in the positive case
        # above: Stop provably waits the callback out.)
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        $hb  = Start-StagingHeartbeat -MarkerPath $rec.MarkerPath -RunId $rec.RunId -IntervalSeconds 0.1
        try {
            $hb.BeatDelayMs = 1500
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            while ($hb.InFlight -lt 1 -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
            $hb.InFlight | Should -BeGreaterThan 0

            [System.IO.File]::Delete($rec.MarkerPath)
            $successor = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library' -RunId $rec.RunId
            $successorMtime = [datetime]::UtcNow.AddHours(-2)
            [System.IO.File]::SetLastWriteTimeUtc($successor.MarkerPath, $successorMtime)

            Stop-StagingHeartbeat $hb
            [System.IO.File]::GetLastWriteTimeUtc($successor.MarkerPath) | Should -BeGreaterThan $successorMtime -Because 'without a mismatching identity the late callback freshens the successor'
        } finally { Stop-StagingHeartbeat $hb }
    }
}

Describe 'No RUN.inprogress ever reaches a snapshot (TC-202, SR-075, SR-046, LLR-017)' {

    It 'leaves no marker on the first-run, changed and no-op paths, and the snapshot prunes cleanly (TC-202, SR-075, SR-046, LLR-017)' {
        $fx = New-BackupSetFixture -Name 'tc202'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')

        # 1. First run: Complete-ChangeFolder DISCARDS Temp (no prior state).
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Chg 'Temp') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $fx.Chg -Recurse -Force -File |
            Where-Object Name -eq 'RUN.inprogress') | Should -BeNullOrEmpty

        # 2. Changed run: Temp is RENAMED WHOLESALE into Snapshot_*.
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') | Should -BeTrue
        $snap = @(Get-ChildItem -LiteralPath $fx.Chg -Directory | Where-Object Name -match '^Snapshot_')
        $snap.Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $snap[0].FullName -Recurse -Force -File |
            Where-Object Name -eq 'RUN.inprogress') |
            Should -BeNullOrEmpty -Because 'the marker is stopped, drained and deleted immediately before finalize'

        # 3. No-op run: manifest unchanged, Temp discarded again.
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-03-03 00:00:03') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Chg 'Temp') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $fx.Chg -Recurse -Force -File |
            Where-Object Name -eq 'RUN.inprogress') | Should -BeNullOrEmpty

        # 4. ...and that snapshot prunes WITHOUT an unreferenced-data refusal.
        $pruned = @(Remove-BackupSnapshot -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Name $snap[0].Name)
        $pruned[0].Status | Should -Be 'Pruned'
        $pruned[0].Code | Should -Be 0
    }

    It 'NEGATIVE CONTROL: a marker left in a snapshot IS refused as unreferenced data (TC-202, SR-046, SR-075)' {
        # RUN.inprogress is deliberately NOT in Test-IsInfrastructureFile's
        # root-level list, so left in place it counts as a data file the
        # snapshot's own manifest does not name - SR-046's rail then refuses
        # that snapshot forever. This is why step 12.9 deletes the leaf.
        $fx = New-BackupSetFixture -Name 'tc202-neg'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') | Should -BeTrue

        $snap = @(Get-ChildItem -LiteralPath $fx.Chg -Directory | Where-Object Name -match '^Snapshot_')[0]
        [System.IO.File]::WriteAllText((Join-Path $snap.FullName 'RUN.inprogress'), '{"SchemaVersion":1}')

        $refused = @(Remove-BackupSnapshot -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Name $snap.Name)
        $refused[0].Status | Should -Be 'Refused'
        @($refused[0].Refusals | Where-Object Kind -eq 'unreferenced-data') |
            Should -Not -BeNullOrEmpty -Because 'a surviving marker is unexplained bytes to prune'
    }
}
