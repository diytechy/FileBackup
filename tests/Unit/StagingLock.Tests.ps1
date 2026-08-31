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

    # --- Part C fixtures (TC-186..TC-193, TC-197, TC-198, TC-203, TC-204) ----

    $script:RepoRoot = $repo

    function Set-EngineConfirmationSample {
        # Production waits one heartbeat interval plus margin (~90 s) before it
        # believes a lock is abandoned. Compressing it is the ONLY thing the
        # suite changes about the decision: the sample is still really taken and
        # really compared.
        param([double]$Seconds)
        InModuleScope FileBackup.Engine -Parameters @{ S = $Seconds } {
            $script:StagingConfirmationSampleSeconds = $S
        }
    }

    function Set-EngineStagingHook {
        # Installs one of the engine's named SR-075 seams. Every seam is $null in
        # production; only this helper ever assigns one.
        param([Parameter(Mandatory)][string]$Name, [AllowNull()][scriptblock]$Hook)
        InModuleScope FileBackup.Engine -Parameters @{ N = $Name; H = $Hook } {
            Set-Variable -Name $N -Value $H -Scope Script
        }
    }

    function Clear-EngineStagingHooks {
        foreach ($name in @(
                'StagingTestHook_AfterCreateBeforePublish',
                'StagingReclaimTestHook_BeforeMove',
                'StagingReclaimTestHook_BeforeAsideDelete',
                'StagingFenceTestHook')) {
            Set-EngineStagingHook -Name $name -Hook $null
        }
    }

    function New-AbandonedTemp {
        <#
        .SYNOPSIS
            Builds the on-disk state an externally killed run leaves behind: a
            Temp under ChangePath holding (usually) only its RUN.inprogress,
            with the marker's mtime aged past the staleness threshold.
        #>
        param(
            [Parameter(Mandatory)][string]$ChgPath,
            [double]$MarkerAgeSeconds = 10800,
            [switch]$NoMarker,
            [string]$MarkerName = 'RUN.inprogress',
            [string]$RunId,
            [AllowNull()][Nullable[double]]$DirectoryAgeSeconds
        )
        $temp = Join-Path $ChgPath 'Temp'
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        if (-not $NoMarker) {
            $markerPath = Join-Path $temp $MarkerName
            if ($MarkerName -eq 'RUN.inprogress') {
                $writeArgs = @{ StagingFolder = $temp; SetName = 'library' }
                if ($RunId) { $writeArgs['RunId'] = $RunId }
                $rec = Write-StagingOwnerRecord @writeArgs
                $markerPath = $rec.MarkerPath
            } else {
                [System.IO.File]::WriteAllText($markerPath, '{"SchemaVersion":1,"Kind":"prune"}')
            }
            [System.IO.File]::SetLastWriteTimeUtc($markerPath, [datetime]::UtcNow.AddSeconds(-$MarkerAgeSeconds))
        }
        if ($null -ne $DirectoryAgeSeconds) {
            [System.IO.Directory]::SetLastWriteTimeUtc($temp, [datetime]::UtcNow.AddSeconds(-([double]$DirectoryAgeSeconds)))
        }
        return $temp
    }

    function Get-TreeHashMap {
        # SHA-256 of every file under the given roots. TC-187/TC-188 assert
        # HASHES, not presence: a refusal that quietly rewrote a byte would pass
        # a presence check. backup.log is excluded because a refused run is
        # REQUIRED to write its refusal there.
        param([string[]]$Roots)
        $map = [ordered]@{}
        foreach ($root in $Roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName)) {
                if ($file.Name -eq 'backup.log') { continue }
                $map[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            }
        }
        return $map
    }

    function Format-TreeHashMap {
        param($Map)
        return (($Map.Keys | ForEach-Object { "$_=$($Map[$_])" }) -join "`n")
    }

    function Get-FixtureTreeHash {
        param([object]$Fixture)
        return (Format-TreeHashMap (Get-TreeHashMap -Roots @($Fixture.Chg, $Fixture.Bkp, $Fixture.Src)))
    }

    function Get-SetLog {
        param([object]$Fixture)
        $path = Join-Path $Fixture.Chg 'backup.log'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
        return (Get-Content -LiteralPath $path -Raw)
    }

    function Get-AsideFolder {
        param([string]$ChgPath)
        return @(Get-ChildItem -LiteralPath $ChgPath -Directory -Force |
            Where-Object { $_.Name -like 'Temp.stale-*' })
    }

    function Get-SnapshotFolder {
        param([string]$ChgPath)
        return @(Get-ChildItem -LiteralPath $ChgPath -Directory -Force |
            Where-Object { $_.Name -match '^Snapshot_' })
    }

    function New-ForeignMarkerJson {
        param([string]$RunId)
        return ('{"SchemaVersion":1,"Kind":"backup","RunId":"' + $RunId + '","SetName":"successor","Host":"other",' +
                '"ContainerId":"","BootId":"","Pid":4242,"StartedUtc":"2026-08-31T00:00:00Z",' +
                '"HeartbeatIntervalSeconds":60,"StaleAfterSeconds":1800}')
    }
}

AfterAll {
    Clear-EngineStagingHooks
    Set-EngineConfirmationSample -Seconds 90
    Set-EngineHeartbeatInterval -Seconds 60
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

# =========================================================================
# Part C — the reclaim protocol (SR-017 amended, SR-075 §2.4) and the RunId
# fence (§2.5). Every case here drives the REAL Invoke-BackupSet: the whole
# point of WP14 is what a second run does to a store a first run abandoned.
# =========================================================================

Describe 'Reclaiming a provably abandoned staging lock (TC-186, SR-017, SR-075, LLR-017)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'reclaims a stale marker-only Temp, completes the run, and the aside folder is GONE (TC-186, SR-017, SR-075, LLR-017)' {
        # The observed HomeHub defect end to end: a run killed from outside left
        # Temp holding only its RUN.inprogress, and every later run failed in
        # about a second, for roughly 18 hours.
        $fx = New-BackupSetFixture -Name 'tc186'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        $temp = New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 10800
        $deadRunId = (Read-StagingOwnerRecord -MarkerPath (Join-Path $temp 'RUN.inprogress')).Record.RunId

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
            Should -BeTrue -Because 'an interrupted run must not be a permanent interrupt'

        $log = Get-SetLog $fx
        $log | Should -Match '\[SR-075/reclaimed\]'
        $log | Should -Match 'confirming with a second sample'
        $log | Should -Match 'Moved the abandoned staging folder aside'
        $log | Should -Match 'held only its own owner record and has been removed'

        # The aside folder is gone: marker leaf deleted BY NAME, directory
        # deleted NON-RECURSIVELY.
        Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
        # ...and the successor really owned the lock it took (a different RunId).
        $log | Should -Match 'owner record published \(RunId='
        $log | Should -Not -Match ('RunId=' + [regex]::Escape($deadRunId))
        # First run: Complete-ChangeFolder discards Temp, so nothing survives.
        Test-Path -LiteralPath (Join-Path $fx.Chg 'Temp') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Bkp 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
    }
}

Describe 'A LIVE owner is never stomped (TC-187, TC-203, SR-017, SR-075, LLR-017)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'refuses a fresh marker-only Temp with [SR-075/owner-live], moves nothing, and leaves the tree byte-identical (TC-187, SR-017, SR-075, LLR-017)' {
        $fx = New-BackupSetFixture -Name 'tc187'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        $temp = New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 0
        # A GENUINELY live owner: the real compiled heartbeat, really beating.
        $marker = Join-Path $temp 'RUN.inprogress'
        $rec = Read-StagingOwnerRecord -MarkerPath $marker
        $hb = Start-StagingHeartbeat -MarkerPath $marker -RunId $rec.Record.RunId -IntervalSeconds 0.1
        try {
            $before = Get-FixtureTreeHash $fx

            Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
                Should -BeFalse -Because 'stomping a live run is the failure reclaim-by-age alone could not survive'

            $log = Get-SetLog $fx
            $log | Should -Match '\[SR-075/owner-live\]'
            # The refusal stops hedging: it names the owner, the start time and
            # the seconds since the last heartbeat.
            $log | Should -Match 'is ALIVE'
            $log | Should -Match ([regex]::Escape("$([Environment]::MachineName)/pid $PID"))
            $log | Should -Match 'last heartbeat was'
            $log | Should -Not -Match 'may have failed or still be running'

            Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
            Get-SnapshotFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
            Get-FixtureTreeHash $fx | Should -Be $before
        } finally { Stop-StagingHeartbeat $hb }
    }

    It 'refuses an owner whose clock is BEHIND the reader beyond the threshold, because the sample sees the mtime move (TC-203, SR-075, LLR-017)' {
        # The dangerous skew direction: a live, continuously beating owner whose
        # stamps all land far in the reader's past looks INSTANTLY stale to an
        # age test. The confirmation sample is clock-free, so it sees the mtime
        # MOVE and refuses anyway.
        $fx = New-BackupSetFixture -Name 'tc203'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        $temp = New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 10800
        $marker = Join-Path $temp 'RUN.inprogress'

        # The skewed beater runs in a CHILD PROCESS: nothing in this runspace
        # may be what advances the mtime. Every stamp it writes is ~3 h in the
        # reader's past, and each is later than the last.
        $beater = Start-Job -ScriptBlock {
            $base = [datetime]::UtcNow.AddHours(-3)
            for ($i = 0; $i -lt 200; $i++) {
                try { [System.IO.File]::SetLastWriteTimeUtc($using:marker, $base.AddSeconds($i)) }
                catch { Write-Debug $_.Exception.Message }
                [System.Threading.Thread]::Sleep(150)
            }
        }
        try {
            Start-Sleep -Milliseconds 1500

            # NEGATIVE CONTROL, taken live: age ALONE says this lock is
            # reclaimable. Without the confirmation sample the run below would
            # have stomped a beating owner.
            $read = Read-StagingOwnerRecord -MarkerPath $marker
            $ageOnly = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $read
            $ageOnly.State | Should -Be 'OwnerStale'
            $ageOnly.Reclaimable | Should -BeTrue -Because 'age alone would have reclaimed a LIVE owner - this is the fix being removed'

            Set-EngineConfirmationSample -Seconds 1.5
            $before = Get-FixtureTreeHash $fx

            Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
                Should -BeFalse -Because 'no clock configuration may cause a live owner to be stomped'

            $log = Get-SetLog $fx
            $log | Should -Match '\[SR-075/owner-live\]'
            $log | Should -Match 'CHANGED during the confirmation sample'
            Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
            Get-FixtureTreeHash $fx | Should -Be $before
        } finally {
            Stop-Job -Job $beater -ErrorAction SilentlyContinue
            Remove-Job -Job $beater -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'A Temp holding anything is refused, unchanged from before (TC-188, TC-190, SR-017, SR-046, SR-075, LLR-017)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'refuses a STALE marker plus data files and leaves every byte hash-identical (TC-188, SR-017, SR-075, LLR-017)' {
        # Invariant I-1. A README that once said "remove the leftover Temp and
        # re-run" permanently destroyed the only physical copy of
        # snapshot-demanded bytes; the age of the marker changes nothing here.
        $fx = New-BackupSetFixture -Name 'tc188'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        $temp = New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 10800
        [System.IO.File]::WriteAllText((Join-Path $temp 'evicted.dat'), 'THE ONLY PHYSICAL COPY')
        $hidden = Join-Path $temp '.hidden.dat'
        [System.IO.File]::WriteAllText($hidden, 'HIDDEN BUT STILL THE ONLY COPY')
        (Get-Item -LiteralPath $hidden -Force).Attributes = [System.IO.FileAttributes]::Hidden

        $before = Get-FixtureTreeHash $fx

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeFalse

        $log = Get-SetLog $fx
        $log | Should -Match '\[SR-075/content-refused\]'
        $log | Should -Match 'A run refuses because Temp exists \(stale Temp folder error\)'
        Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
        Get-SnapshotFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
        Test-Path -LiteralPath $temp | Should -BeTrue
        Get-FixtureTreeHash $fx | Should -Be $before -Because 'every byte, hashed - not merely present'
    }

    It 'refuses a PRUNE.inprogress of ANY age with [SR-075/prune-held] (TC-190, SR-017, SR-046, SR-075, LLR-017)' -ForEach @(0, 10800) {
        $age = $_
        $fx = New-BackupSetFixture -Name ('tc190-' + $age)
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        New-AbandonedTemp -ChgPath $fx.Chg -MarkerName 'PRUNE.inprogress' -MarkerAgeSeconds $age | Out-Null

        $before = Get-FixtureTreeHash $fx
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
            Should -BeFalse -Because "a prune marker aged $age s still holds the lock (WP14 does not own prune)"

        (Get-SetLog $fx) | Should -Match '\[SR-075/prune-held\]'
        Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
        Get-FixtureTreeHash $fx | Should -Be $before
    }

    It 'leaves prunes own staging-busy rail untouched (TC-190, SR-046, SR-075, LLR-017)' {
        # I-3, from the other side: the backup path learning to RECOGNISE the
        # prune marker must not have changed what prune itself does with Temp.
        $fx = New-BackupSetFixture -Name 'tc190-prune'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') | Should -BeTrue
        $snap = (Get-SnapshotFolder -ChgPath $fx.Chg)[0]

        New-Item -ItemType Directory -Path (Join-Path $fx.Chg 'Temp') | Out-Null
        $refused = @(Remove-BackupSnapshot -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Name $snap.Name)
        $refused[0].Status | Should -Be 'Refused'
        @($refused[0].Refusals | Where-Object Kind -eq 'staging-busy') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Resurrection between the classification and the move (TC-189, SR-075, LLR-017, LLR-080)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'keeps the aside folder, skips the deletes, prints the recovery, and CONTINUES the run (TC-189, SR-075, LLR-017, LLR-080)' {
        # 2.4 step 5's first window. The classification is never trusted through
        # the move: a frozen owner can resume and write in between.
        $fx = New-BackupSetFixture -Name 'tc189'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 10800 | Out-Null

        $payload = 'RESURRECTED OWNER BYTES'
        $hook = {
            param($folder)
            [System.IO.File]::WriteAllText((Join-Path $folder 'resurrected-1.dat'), $payload)
            [System.IO.File]::WriteAllText((Join-Path $folder 'resurrected-2.dat'), $payload)
        }.GetNewClosure()
        Set-EngineStagingHook -Name 'StagingReclaimTestHook_BeforeMove' -Hook $hook

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
            Should -BeTrue -Because 'the reclaim already succeeded; the aside folder is evidence, not a failure'

        $aside = Get-AsideFolder -ChgPath $fx.Chg
        $aside.Count | Should -Be 1 -Because 'the move-aside is the READMEs own prescribed safe action'
        foreach ($leaf in @('resurrected-1.dat', 'resurrected-2.dat')) {
            $p = Join-Path $aside[0].FullName $leaf
            Test-Path -LiteralPath $p -PathType Leaf | Should -BeTrue
            [System.IO.File]::ReadAllText($p) | Should -Be $payload -Because 'the bytes are intact, not merely present'
        }
        Test-Path -LiteralPath (Join-Path $aside[0].FullName 'RUN.inprogress') -PathType Leaf |
            Should -BeTrue -Because 'the deletes were SKIPPED entirely'

        $log = Get-SetLog $fx
        $log | Should -Match 'is being KEPT'
        $log | Should -Match 'entry\(ies\) that appeared after the classification'
        $log | Should -Match 'A run refuses because Temp exists \(stale Temp folder error\)'
        $log | Should -Match '----- Backup set .* completed -----'
    }

    It 'NEGATIVE CONTROL: trusting the classification through the move DELETES the injected bytes (TC-189, SR-075, LLR-017)' {
        # The fix removed, WP13-T4 style: an in-test replica of step 4 WITHOUT
        # the re-enumeration - "we classified it as marker-only, so sweep it".
        # That is the first draft's protocol, and it destroys the very bytes
        # TC-189 exists to protect.
        $aside = Join-Path $TestDrive ('tc189-neg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $aside | Out-Null
        Write-StagingOwnerRecord -StagingFolder $aside -SetName 'library' | Out-Null
        $victim = Join-Path $aside 'resurrected-1.dat'
        [System.IO.File]::WriteAllText($victim, 'RESURRECTED OWNER BYTES')

        # No re-enumeration, and a RECURSIVE delete: exactly what the plan bans.
        Remove-Item -LiteralPath $aside -Recurse -Force
        Test-Path -LiteralPath $victim | Should -BeFalse -Because 'without step 4 the resurrected owners only copy is gone'

        # ...whereas the shipped step 4, given the same folder, keeps it.
        New-Item -ItemType Directory -Path $aside | Out-Null
        Write-StagingOwnerRecord -StagingFolder $aside -SetName 'library' | Out-Null
        [System.IO.File]::WriteAllText($victim, 'RESURRECTED OWNER BYTES')
        InModuleScope FileBackup.Engine -Parameters @{ P = $aside } {
            Clear-ReclaimedStagingFolder -AsidePath $P -Log { param($m, $l) } | Should -BeFalse
        }
        Test-Path -LiteralPath $victim -PathType Leaf | Should -BeTrue
    }
}

Describe 'Resurrection between the re-enumeration and the delete (TC-198, SR-017, SR-075, LLR-017)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'fails the NON-RECURSIVE delete, keeps the folder with its bytes, and continues (TC-198, SR-017, SR-075, LLR-017)' {
        $fx = New-BackupSetFixture -Name 'tc198'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        New-AbandonedTemp -ChgPath $fx.Chg -MarkerAgeSeconds 10800 | Out-Null

        $payload = 'LANDED IN THE LAST WINDOW'
        $hook = {
            param($asidePath)
            [System.IO.File]::WriteAllText((Join-Path $asidePath 'late-arrival.dat'), $payload)
        }.GetNewClosure()
        Set-EngineStagingHook -Name 'StagingReclaimTestHook_BeforeAsideDelete' -Hook $hook

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue

        $aside = Get-AsideFolder -ChgPath $fx.Chg
        $aside.Count | Should -Be 1
        $late = Join-Path $aside[0].FullName 'late-arrival.dat'
        [System.IO.File]::ReadAllText($late) | Should -Be $payload

        $log = Get-SetLog $fx
        $log | Should -Match 'the non-recursive delete failed, so it is no longer empty'
        $log | Should -Match 'is being KEPT'
        $log | Should -Match 'A run refuses because Temp exists \(stale Temp folder error\)'
        $log | Should -Match '----- Backup set .* completed -----'
    }

    It 'NEGATIVE CONTROL: a RECURSIVE delete in the same window destroys the arrival (TC-198, SR-017, SR-075)' {
        # The banned variant, built in the test rather than by editing shipped
        # code: Directory.Delete(path, recursive:true) cannot fail on a
        # non-empty directory, so the last race becomes data loss instead of a
        # safe failure. This is the entire reason -Recurse is banned.
        $aside = Join-Path $TestDrive ('tc198-neg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $aside | Out-Null
        $late = Join-Path $aside 'late-arrival.dat'
        [System.IO.File]::WriteAllText($late, 'LANDED IN THE LAST WINDOW')

        { [System.IO.Directory]::Delete($aside, $false) } |
            Should -Throw -Because 'the shipped non-recursive delete FAILS, which is what saves the bytes'
        Test-Path -LiteralPath $late -PathType Leaf | Should -BeTrue

        [System.IO.Directory]::Delete($aside, $true)
        Test-Path -LiteralPath $late | Should -BeFalse -Because 'the recursive variant sweeps the arrival up silently'
    }
}

Describe 'Two reclaimers racing one stale lock (TC-191, SR-075, LLR-017)' {

    AfterEach { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'lets exactly ONE proceed; the loser refuses without retrying (TC-191, SR-075, LLR-017)' {
        # Real concurrency, in two CHILD PROCESSES against one store: the
        # Directory.Move at step 2 and the -Force-less New-Item at step 3 are
        # the two atomic gates, and nothing in this runspace can serialize them.
        $chg = Join-Path $TestDrive 'tc191-chg'
        New-Item -ItemType Directory -Path $chg | Out-Null
        New-AbandonedTemp -ChgPath $chg -MarkerAgeSeconds 10800 | Out-Null
        $barrier = Join-Path $TestDrive 'tc191.go'

        $body = {
            param($repo, $chgPath, $barrierPath)
            Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
            Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
            while (-not (Test-Path -LiteralPath $barrierPath)) { [System.Threading.Thread]::Sleep(20) }
            try {
                $lock = Initialize-StagingFolder -ChgPath $chgPath -Log { param($m, $l) } -SetName 'race' `
                            -HeartbeatIntervalSeconds 60 -ConfirmationSampleSeconds 0.6
                Stop-StagingHeartbeat $lock.Heartbeat
                [pscustomobject]@{ Won = $true; RunId = $lock.RunId; Message = '' }
            } catch {
                [pscustomobject]@{ Won = $false; RunId = ''; Message = $_.Exception.Message }
            }
        }
        $jobs = @(1, 2 | ForEach-Object { Start-Job -ScriptBlock $body -ArgumentList $script:RepoRoot, $chg, $barrier })
        try {
            Start-Sleep -Seconds 6           # both processes reach the barrier
            New-Item -ItemType File -Path $barrier | Out-Null
            $results = @($jobs | Receive-Job -Wait)

            $results.Count | Should -Be 2
            @($results | Where-Object Won).Count | Should -Be 1 -Because 'creation-as-lock stays the atomic primitive (I-2)'
            @($results | Where-Object { -not $_.Won }).Count | Should -Be 1
            $winner = @($results | Where-Object Won)[0]
            $loser = @($results | Where-Object { -not $_.Won })[0]
            # THREE refusal shapes are correct here, and which one a given
            # scheduling produces is not ours to fix: the loser fails the
            # Directory.Move, or the -Force-less New-Item, or - when it moved
            # first and the other racer then reclaimed its freshly created,
            # not-yet-published Temp - its own EXCLUSIVE marker publish (2.1,
            # the create->marker window closed from the victim's side). All
            # three abort without retrying and without deleting anything.
            $loser.Message | Should -Match '(Cannot initialize staging folder|StagingLockLost)'
            $loser.Message | Should -Match '\[SR-075/(content-refused|owner-live|lock-lost)\]'

            @(Get-ChildItem -LiteralPath $chg -Directory -Force | Where-Object Name -eq 'Temp').Count | Should -Be 1
            (Read-StagingOwnerRecord -MarkerPath (Join-Path $chg 'Temp\RUN.inprogress')).Record.RunId |
                Should -Be $winner.RunId -Because 'the surviving marker is the WINNERs'
            $asides = Get-AsideFolder -ChgPath $chg
            # The TC's "exactly one aside folder" predates step 4: the winner's
            # aside folder held ONLY the dead run's owner record, so step 4
            # removes it and 0 is the normal outcome. What must never happen is
            # two SURVIVING asides (two reclaims both completing), and no aside
            # may ever hold anything but its marker.
            $asides.Count | Should -BeLessOrEqual 1 -Because 'one reclaim proceeded, not two'
            foreach ($a in $asides) {
                @(Get-ChildItem -LiteralPath $a.FullName -Force | Where-Object Name -cne 'RUN.inprogress') |
                    Should -BeNullOrEmpty
            }
        } finally {
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $barrier -Force -ErrorAction SilentlyContinue
        }
    }

    It 'NEGATIVE CONTROL: a delete-then-create acquisition lets the loser take the lock (TC-191, SR-075)' {
        # The banned alternative, built in the test: replacing the atomic
        # move+create with "remove it and recreate it" makes the SECOND arrival
        # win and takes the first one's staging folder with it.
        $chg = Join-Path $TestDrive 'tc191-neg'
        New-Item -ItemType Directory -Path $chg | Out-Null
        New-AbandonedTemp -ChgPath $chg -MarkerAgeSeconds 10800 | Out-Null

        $a = Initialize-StagingFolder -ChgPath $chg -Log { param($m, $l) } -SetName 'A' -ConfirmationSampleSeconds 0.2
        try {
            # The shipped path REFUSES a second acquisition of A's fresh lock...
            { Initialize-StagingFolder -ChgPath $chg -Log { param($m, $l) } -SetName 'B' -ConfirmationSampleSeconds 0.2 } |
                Should -Throw -ExpectedMessage '*Cannot initialize staging folder*'
            (Read-StagingOwnerRecord -MarkerPath $a.MarkerPath).Record.RunId | Should -Be $a.RunId
        } finally { Stop-StagingHeartbeat $a.Heartbeat }

        # ...whereas delete-then-create hands the lock to the loser.
        $temp = Join-Path $chg 'Temp'
        Remove-Item -LiteralPath $temp -Recurse -Force
        New-Item -ItemType Directory -Path $temp | Out-Null
        $b = Write-StagingOwnerRecord -StagingFolder $temp -SetName 'B'
        (Read-StagingOwnerRecord -MarkerPath (Join-Path $temp 'RUN.inprogress')).Record.RunId |
            Should -Be $b.RunId -Because 'without the atomic gates the later arrival simply wins'
        $b.RunId | Should -Not -Be $a.RunId
    }
}

Describe 'The empty-Temp branches and the create-to-marker gate (TC-192, SR-017, SR-075, LLR-017)' {

    BeforeEach { Set-EngineConfirmationSample -Seconds 0.3 }
    AfterEach  { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'reclaims an EMPTY Temp whose own directory mtime is stale - the pre-WP14 upgrade path (TC-192, SR-017, SR-075, LLR-017)' {
        # Literally the hub's state: an empty Temp dated 2026-08-30, left by a
        # store that predates the owner record entirely.
        $fx = New-BackupSetFixture -Name 'tc192-stale'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        New-AbandonedTemp -ChgPath $fx.Chg -NoMarker -DirectoryAgeSeconds 10800 | Out-Null

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
            Should -BeTrue -Because 'the upgrade path from a pre-WP14 store must cost nothing'

        (Get-SetLog $fx) | Should -Match '\[SR-075/reclaimed\]'
        Get-AsideFolder -ChgPath $fx.Chg |
            Should -BeNullOrEmpty -Because 'an EMPTY aside folder is removed by the non-recursive delete alone'
    }

    It 'REFUSES an empty Temp whose directory mtime is fresh - the create-to-marker theft gate (TC-192, SR-017, SR-075, LLR-017)' {
        $fx = New-BackupSetFixture -Name 'tc192-fresh'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        $temp = New-AbandonedTemp -ChgPath $fx.Chg -NoMarker
        $before = Get-FixtureTreeHash $fx

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
            Should -BeFalse -Because 'a live run may be inside its own create-to-marker window'

        $log = Get-SetLog $fx
        $log | Should -Match '\[SR-075/owner-live\]'
        $log | Should -Match 'create-to-marker window'
        Test-Path -LiteralPath $temp | Should -BeTrue
        Get-AsideFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
        Get-FixtureTreeHash $fx | Should -Be $before
    }
}

Describe 'A future-dated marker is fresh, never proof of death (TC-193, SR-075, LLR-080)' {

    It 'classifies a marker dated <_> s INTO THE FUTURE as OwnerLive and refuses (TC-193, SR-075, LLR-080)' -ForEach @(60, 900, 36000) {
        $offset = $_
        $dir = New-StagingDir
        $rec = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'library'
        [System.IO.File]::SetLastWriteTimeUtc($rec.MarkerPath, [datetime]::UtcNow.AddSeconds($offset))

        $read = Read-StagingOwnerRecord -MarkerPath $rec.MarkerPath
        $read.State | Should -Be 'Parsed'
        $read.AgeSeconds | Should -BeLessThan 0
        $verdict = Get-StagingLockState -Entries @('RUN.inprogress') -OwnerRecord $read
        $verdict.State | Should -Be 'OwnerLive'
        $verdict.Reclaimable | Should -BeFalse -Because 'a future mtime can only be a clock disagreement'
        $verdict.Token | Should -Be '[SR-075/owner-live]'
    }
}

Describe 'The theft window, victim side (TC-197, SR-075, LLR-017, LLR-080)' {

    AfterEach { Set-EngineConfirmationSample -Seconds 90; Clear-EngineStagingHooks }

    It 'fails As exclusive publish and aborts it touching NOTHING after B reclaims As directory (TC-197, SR-075, LLR-017, LLR-080)' {
        $fx = New-BackupSetFixture -Name 'tc197'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        New-Item -ItemType Directory -Path $fx.Chg -Force | Out-Null
        Set-EngineConfirmationSample -Seconds 0.2

        # A is parked between its New-Item and its marker publish. B arrives in
        # that window: A's Temp is empty, and ageing its directory mtime here is
        # what makes B's classification the TC-192 stale-empty branch (the real
        # window is microseconds wide; correctness must not depend on that).
        $state = @{ Fired = $false; Successor = $null }
        $hook = {
            param($folder)
            if ($state.Fired) { return }
            $state.Fired = $true
            [System.IO.Directory]::SetLastWriteTimeUtc($folder, [datetime]::UtcNow.AddSeconds(-10800))
            $state.Successor = Initialize-StagingFolder -ChgPath (Split-Path -Parent $folder) `
                                 -Log { param($m, $l) } -SetName 'successor' -ConfirmationSampleSeconds 0.2
        }.GetNewClosure()
        Set-EngineStagingHook -Name 'StagingTestHook_AfterCreateBeforePublish' -Hook $hook

        try {
            Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') |
                Should -BeFalse -Because 'A provably lost the lock and must abort'

            $state.Fired | Should -BeTrue
            $log = Get-SetLog $fx
            $log | Should -Match '\[SR-075/lock-lost\]'
            $log | Should -Match 'StagingLockLost'

            # A touched NOTHING: B's staging folder and marker stand, no change
            # folder was written, and no backup state was published.
            $marker = Join-Path $fx.Chg 'Temp\RUN.inprogress'
            Test-Path -LiteralPath $marker -PathType Leaf | Should -BeTrue
            (Read-StagingOwnerRecord -MarkerPath $marker).Record.RunId |
                Should -Be $state.Successor.RunId -Because 'the marker is the SUCCESSORs'
            Get-SnapshotFolder -ChgPath $fx.Chg | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $fx.Bkp 'MANIFEST.csv') | Should -BeFalse
        } finally {
            if ($state.Successor) { Stop-StagingHeartbeat $state.Successor.Heartbeat }
        }
    }

    It 'NEGATIVE CONTROL: a non-exclusive publish lets A silently take over Bs staging folder (TC-197, SR-075, LLR-080)' {
        # The fix removed: File.Move WITH overwrite instead of the exclusive
        # move. A then writes into a folder that is not its own and never finds
        # out - which is the whole failure the exclusive publish exists to stop.
        $dir = New-StagingDir
        $b = Write-StagingOwnerRecord -StagingFolder $dir -SetName 'B'
        $marker = Join-Path $dir 'RUN.inprogress'

        $aRunId = [guid]::NewGuid().ToString()
        $tmp = Join-Path $dir 'RUN.inprogress.naive.tmp'
        [System.IO.File]::WriteAllText($tmp, (New-ForeignMarkerJson -RunId $aRunId))
        [System.IO.File]::Move($tmp, $marker, $true)

        (Read-StagingOwnerRecord -MarkerPath $marker).Record.RunId |
            Should -Be $aRunId -Because 'an overwriting publish silently steals the successors lock'
        $aRunId | Should -Not -Be $b.RunId
    }
}

Describe 'The RunId fence at the three phase boundaries (TC-204, SR-075, LLR-017)' {

    AfterEach { Clear-EngineStagingHooks }

    It 'aborts before <_> mutates anything, cleaning up NOTHING (TC-204, SR-075, LLR-017)' -ForEach @(
        'Move-RemovedFilesToStaging', 'Save-SupersededData', 'Complete-ChangeFolder'
    ) {
        # A fixture with real work at every fenced phase: one changed file
        # (step 10), one removal (Move-RemovedFilesToStaging) and one superseded
        # object (Save-SupersededData).
        $phase = $_
        $fx = New-BackupSetFixture -Name ('tc204-' + $phase)
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'gone.txt'), 'DOOMED')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Remove-Item -LiteralPath (Join-Path $fx.Src 'gone.txt') -Force

        $manifestBefore = [System.IO.File]::ReadAllText((Join-Path $fx.Bkp 'MANIFEST.csv'))
        $snapsBefore = (Get-SnapshotFolder -ChgPath $fx.Chg).Count
        $foreign = [guid]::NewGuid().ToString()
        # Rendered HERE, not inside the hook: a closure captures VARIABLES, and
        # the engine resolves function names in its own module scope.
        $foreignJson = New-ForeignMarkerJson -RunId $foreign

        $hook = {
            param($ctx)
            if ($ctx.Phase -ne $phase) { return }
            # The successor's marker, published over ours by a run that
            # reclaimed this lock while we were frozen.
            [System.IO.File]::WriteAllText($ctx.StagingLock.MarkerPath, $foreignJson)
        }.GetNewClosure()
        Set-EngineStagingHook -Name 'StagingFenceTestHook' -Hook $hook

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') |
            Should -BeFalse -Because "the fence before $phase must abort the run"

        $log = Get-SetLog $fx
        $log | Should -Match '\[SR-075/lock-lost\]'
        $log | Should -Match ([regex]::Escape("at the '$phase' boundary"))
        $log | Should -Match 'cleaning up NOTHING'

        # Cleaned up NOTHING: the successor's Temp and its marker are intact.
        $marker = Join-Path $fx.Chg 'Temp\RUN.inprogress'
        Test-Path -LiteralPath $marker -PathType Leaf |
            Should -BeTrue -Because 'the staging folder is no longer this runs to delete'
        (Read-StagingOwnerRecord -MarkerPath $marker).Record.RunId | Should -Be $foreign

        # Nothing was published: no new snapshot, and no state stamped.
        (Get-SnapshotFolder -ChgPath $fx.Chg).Count | Should -Be $snapsBefore
        Get-LastBackupRun -BackupRoot $fx.Bkp | Should -Be ([datetime]'2024-01-01 00:00:01')

        if ($phase -ne 'Complete-ChangeFolder') {
            # Fences 1 and 2 sit before the manifest is rewritten at step 12.
            [System.IO.File]::ReadAllText((Join-Path $fx.Bkp 'MANIFEST.csv')) |
                Should -Be $manifestBefore -Because "the $phase phase never ran"
        }
    }

    It 'NEGATIVE CONTROL: with the fence removed the run deletes the successors marker and finalizes over it (TC-204, SR-075, LLR-017)' {
        # The fix removed: Assert-StagingLockOwned neutered to do the marker swap
        # WITHOUT the identity check. The run then proceeds through step 12.9,
        # strips the successor's owner record and publishes a snapshot - which
        # is precisely what the fence prevents above.
        $fx = New-BackupSetFixture -Name 'tc204-neg'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ONE')
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'gone.txt'), 'DOOMED')
        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01') | Should -BeTrue
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'TWO')
        Remove-Item -LiteralPath (Join-Path $fx.Src 'gone.txt') -Force

        Mock -ModuleName FileBackup.Engine Assert-StagingLockOwned {
            if ($Phase -eq 'Complete-ChangeFolder') {
                # A successor's record, minted here: this stand-in still performs
                # the swap, it just never checks the identity.
                [System.IO.File]::WriteAllText($StagingLock.MarkerPath,
                    ('{"SchemaVersion":1,"Kind":"backup","RunId":"' + [guid]::NewGuid().ToString() + '","StaleAfterSeconds":1800}'))
            }
        }

        Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-02-02 00:00:02') |
            Should -BeTrue -Because 'nothing stops it once the fence is gone'

        (Get-SetLog $fx) | Should -Not -Match '\[SR-075/lock-lost\]'
        $snap = Get-SnapshotFolder -ChgPath $fx.Chg
        $snap.Count | Should -Be 1 -Because 'the run finalized over a lock it no longer held'
        @(Get-ChildItem -LiteralPath $snap[0].FullName -Recurse -Force -File | Where-Object Name -eq 'RUN.inprogress') |
            Should -BeNullOrEmpty -Because 'the successors owner record was deleted by step 12.9'
    }
}
