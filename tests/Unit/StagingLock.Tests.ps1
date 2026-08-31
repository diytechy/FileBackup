<#
.SYNOPSIS  Pester 5 unit tests for the WP14 Part A staging-lock helpers
           (SR-075 / LLR-080): the owner record writer and reader, the pure
           classifier, and the compiled identity-guarded heartbeat.
#>

BeforeAll {
    # $PSScriptRoot here is tests\Unit; repo root is two levels up.
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
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
