<#
.SYNOPSIS  Pester 5 tests for the staging OS lock (SR-085, SR-086, SR-087;
           LLR-090..LLR-093; TC-241..TC-250).
.NOTES     The lock is <ChangePath>/Temp.lock opened with FileShare.None. Since the
           bounded run loop (docs/plans/bounded-run-loop.md, R2) it is the ONLY
           exclusion: there is no owner record, heartbeat, fence or reclaim, and
           concurrent runs are unsupported - a second changing operation simply
           refuses while the first holds the lock, and the OS releases it however
           the holder dies.

           Live holders are REAL processes wherever liveness is the claim: a child
           pwsh is parked at a stage of the backup run (the module's
           BackupRunTestHook seam) or in a prune transaction, and later killed
           with Stop-Process -Force, so nothing in it can release anything on the
           way out.

           Every negative case asserts BYTES: the SHA-256 of every file under the
           backup root and the change root, before and after. Two exclusions,
           both deliberate: the change root's backup.log, which a refusing run is
           REQUIRED to write its refusal into (and New-Logger truncates); and a
           file a live holder has open with FileShare.None -- the lock file itself
           -- which cannot be opened to hash, so it is recorded by its length.

           The Windows run is the only one this suite has had. On Linux the lock is
           an advisory flock; see SR-085 for what that does and does not exclude.
#>

BeforeAll {
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:Repo = $repo
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    $script:LockHeldToken = '[SR-075/lock-held]'
    $script:D1 = [datetime]'2024-01-01 00:00:01'
    $script:D2 = [datetime]'2024-02-02 00:00:02'
    $script:D3 = [datetime]'2024-03-03 00:00:03'
    $script:D4 = [datetime]'2024-04-04 00:00:04'

    function Set-EngineVariable {
        param([Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Value)
        InModuleScope FileBackup.Engine -Parameters @{ N = $Name; V = $Value } {
            Set-Variable -Name $N -Value $V -Scope Script
        }
    }

    function Clear-OsLockSeams {
        foreach ($name in @('BackupRunTestHook', 'PruneTestHook_InTransaction', 'StagingOsLockTestHook_BeforeOpen')) {
            Set-EngineVariable -Name $name -Value $null
        }
    }

    function New-LockFixture {
        # The set object Invoke-BackupSet takes, over sibling folders on one
        # volume (plan R8).
        param([string]$Name)
        $root = Join-Path $TestDrive $Name
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        [pscustomobject]@{
            Root = $root; Src = $src; Bkp = $bkp; Chg = $chg
            Set  = [pscustomobject]@{
                Name = $Name; SourcePath = $src; SourceStatePath = ''; BackupPath = $bkp
                ChangePath = $chg; HashRecalcFreq = 'A'; CompressEnabled = $false
                AllowEmptySource = $false; BrowseView = 'off'; ViewPath = ''
            }
        }
    }

    function Invoke-LockBackup {
        # $true when the run reported 0 (every file captured).
        param([object]$Fixture, [datetime]$When)
        $code = Invoke-BackupSet -Set $Fixture.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
            -LogPaths (New-Object System.Collections.Generic.List[string]) -BackupTime $When
        return ($code -eq 0)
    }

    function Initialize-TwoRunStore {
        # Run 1 (D1) and run 2 (D2), in-process: the store then holds a
        # Snapshot_<D1> to prune, and the source is edited so a THIRD run
        # supersedes content (a changed file and a removed one) and therefore
        # publishes a snapshot and moves objects into it.
        param([object]$Fixture)
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'a.txt'), 'ALPHA one')
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'b.txt'), 'BRAVO one')
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'sub\c.txt'), 'CHARLIE one')
        if (-not (Invoke-LockBackup -Fixture $Fixture -When $script:D1)) { throw 'fixture error: run 1 failed' }
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'a.txt'), 'ALPHA two')
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'd.txt'), 'DELTA two')
        if (-not (Invoke-LockBackup -Fixture $Fixture -When $script:D2)) { throw 'fixture error: run 2 failed' }
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Src 'a.txt'), 'ALPHA three')
        Remove-Item -LiteralPath (Join-Path $Fixture.Src 'b.txt')
        $snaps = @(Get-ChildItem -LiteralPath $Fixture.Chg -Directory | Where-Object Name -match '^Snapshot_')
        if ($snaps.Count -ne 1) { throw "fixture error: expected one snapshot after run 2, found $($snaps.Count)" }
        return $snaps[0].Name
    }

    function Get-StoreHashMap {
        # SHA-256 of EVERY file under the given roots, as one comparable string.
        # A file that cannot be opened -- the lock a live holder has open with
        # FileShare.None -- is recorded by its length instead, so it still
        # appears, and a change to it still shows.
        param([string[]]$Roots)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($root in $Roots) {
            if (-not (Test-Path -LiteralPath $root)) { $lines.Add("$root=ABSENT"); continue }
            $rootFull = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\', '/')
            foreach ($file in (Get-ChildItem -LiteralPath $root -Recurse -Force -File | Sort-Object FullName)) {
                if ($file.Name -eq 'backup.log' -and $file.DirectoryName -eq $rootFull) { continue }
                $hash = $null
                try { $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
                catch { $hash = "UNOPENABLE(len=$($file.Length))" }
                $lines.Add("$($file.FullName)=$hash")
            }
        }
        return ($lines -join "`n")
    }

    function Get-FixtureStoreHash {
        param([object]$Fixture)
        return (Get-StoreHashMap -Roots @($Fixture.Bkp, $Fixture.Chg))
    }

    function Get-LockSetLog {
        param([object]$Fixture)
        $path = Join-Path $Fixture.Chg 'backup.log'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
        return (Get-Content -LiteralPath $path -Raw)
    }

    function Test-LockAcquirable {
        # $true when THIS process can take the change root's OS lock now (and
        # releases it again at once).
        param([string]$ChgPath)
        try {
            $l = Enter-StagingOsLock -ChgPath $ChgPath -Log $null
            Exit-StagingOsLock -Lock $l -Log $null
            return $true
        } catch {
            return $false
        }
    }

    # --- the parked child ------------------------------------------------
    # One driver script. Mode Backup runs a backup that parks at the named
    # stage of the run; Prune runs Remove-BackupSnapshot with the prune seam set
    # to park; Hold just takes the OS lock and parks. 'Parked' means: write the
    # ready flag, then sleep 600 s (or, with -Go, wait for that file and carry
    # on).
    $script:ChildScript = Join-Path $TestDrive 'oslock-child.ps1'
    $childText = @'
param([string]$Repo, [string]$Mode, [string]$Stage, [string]$Ready,
      [string]$Src, [string]$Bkp, [string]$Chg, [string]$When, [string]$SnapshotName,
      [string]$Go)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
Import-Module (Join-Path $Repo 'Modules/FileBackup.Engine.psm1') -Force
$parked = @{ Done = $false }
$park = {
    if ($parked.Done) { return }
    $parked.Done = $true
    [System.IO.File]::WriteAllText($Ready, 'parked')
    if ($Go) { while (-not (Test-Path -LiteralPath $Go)) { Start-Sleep -Milliseconds 100 } }
    else { Start-Sleep -Seconds 600 }
}.GetNewClosure()
$engine = Get-Module FileBackup.Engine
if ($Mode -eq 'Backup' -and $Stage) {
    $hook = { param($s, $c) if ($s -eq $Stage) { & $park } }.GetNewClosure()
    & $engine { param($h) $script:BackupRunTestHook = $h } $hook
}
if ($Mode -eq 'Prune') {
    $hook = { param($c) & $park }.GetNewClosure()
    & $engine { param($h) $script:PruneTestHook_InTransaction = $h } $hook
}
switch ($Mode) {
    'Backup' {
        $set = [pscustomobject]@{ Name = 'oslock'; SourcePath = $Src; SourceStatePath = ''; BackupPath = $Bkp
            ChangePath = $Chg; HashRecalcFreq = 'A'; CompressEnabled = $false
            AllowEmptySource = $false; BrowseView = 'off'; ViewPath = '' }
        Invoke-BackupSet -Set $set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
            -LogPaths (New-Object System.Collections.Generic.List[string]) -BackupTime ([datetime]$When) | Out-Null
    }
    'Prune' {
        Remove-BackupSnapshot -BackupRoot $Bkp -ChangeRoot $Chg -Name $SnapshotName -Confirm:$false | Out-Null
    }
    'Hold' {
        $lock = Enter-StagingOsLock -ChgPath $Chg -Log $null
        [System.IO.File]::WriteAllText($Ready, 'parked')
        Start-Sleep -Seconds 600
    }
}
[System.IO.File]::WriteAllText($Ready + '.unparked', 'the child finished without ever parking')
'@
    [System.IO.File]::WriteAllText($script:ChildScript, $childText)

    function Start-ParkedChild {
        # Starts the driver and waits until it reports PARKED. A child that
        # finishes or dies first is a fixture error -- the test would prove
        # nothing -- and its output is quoted.
        param([object]$Fixture, [string]$Mode, [string]$Stage = '', [string]$When = '', [string]$SnapshotName = '',
              [string]$Go = '')
        $tag   = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $ready = Join-Path $TestDrive "ready-$tag.flag"
        $out   = Join-Path $TestDrive "child-$tag.out"
        $err   = Join-Path $TestDrive "child-$tag.err"
        $pwsh  = (Get-Process -Id $PID).Path
        $argv  = @('-NoProfile', '-NonInteractive', '-File', $script:ChildScript,
            '-Repo', $script:Repo, '-Mode', $Mode, '-Ready', $ready,
            '-Src', $Fixture.Src, '-Bkp', $Fixture.Bkp, '-Chg', $Fixture.Chg)
        if ($Stage) { $argv += @('-Stage', $Stage) }
        if ($When) { $argv += @('-When', $When) }
        if ($SnapshotName) { $argv += @('-SnapshotName', $SnapshotName) }
        if ($Go) { $argv += @('-Go', $Go) }
        $proc = Start-Process -FilePath $pwsh -PassThru -WindowStyle Hidden -ArgumentList $argv `
            -RedirectStandardOutput $out -RedirectStandardError $err
        $deadline = [datetime]::UtcNow.AddSeconds(120)
        while (-not (Test-Path -LiteralPath $ready) -and -not $proc.HasExited -and [datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        if (-not (Test-Path -LiteralPath $ready)) {
            if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
            $proc.WaitForExit(30000) | Out-Null
            $detail = (@(Get-Content -LiteralPath $out, $err -ErrorAction SilentlyContinue) | Select-Object -Last 25) -join "`n"
            throw "fixture error: the $Mode child never parked at '$Stage' (exited=$($proc.HasExited)):`n$detail"
        }
        return $proc
    }

    function Stop-ParkedChild {
        param([AllowNull()][System.Diagnostics.Process]$Process)
        if ($null -eq $Process) { return }
        if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force }
        $Process.WaitForExit(30000) | Out-Null
    }
}

AfterAll { Clear-OsLockSeams }

Describe 'The staging OS lock primitive (TC-241, SR-085, SR-087, LLR-090)' {

    BeforeAll {
        $script:P = Join-Path $TestDrive 'primitive'
        New-Item -ItemType Directory -Path $script:P | Out-Null
    }

    It 'lives at <ChangeRoot>/Temp.lock, outside Temp (TC-241, SR-085)' {
        Get-StagingOsLockPath -ChgPath $script:P | Should -Be (Join-Path $script:P 'Temp.lock')
    }

    It 'refuses a second holder with the lock-held token while the first holds it (TC-241, SR-085)' {
        $first = Enter-StagingOsLock -ChgPath $script:P -Log $null
        $message = ''
        try {
            try { Exit-StagingOsLock -Lock (Enter-StagingOsLock -ChgPath $script:P -Log $null) -Log $null } catch { $message = $_.Exception.Message }
        } finally { Exit-StagingOsLock -Lock $first -Log $null }
        $message | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'can be taken again once released (TC-241, SR-085)' {
        $first = Enter-StagingOsLock -ChgPath $script:P -Log $null
        Exit-StagingOsLock -Lock $first -Log $null
        Test-LockAcquirable -ChgPath $script:P | Should -BeTrue
    }

    It 'releases idempotently and accepts $null (TC-241, SR-085)' {
        $first = Enter-StagingOsLock -ChgPath $script:P -Log $null
        { Exit-StagingOsLock -Lock $first -Log $null; Exit-StagingOsLock -Lock $first -Log $null; Exit-StagingOsLock -Lock $null -Log $null } |
            Should -Not -Throw
    }

    It 'leaves the lock file in place, zero-length, after release (TC-241, SR-087)' {
        $first = Enter-StagingOsLock -ChgPath $script:P -Log $null
        Exit-StagingOsLock -Lock $first -Log $null
        ([System.IO.FileInfo](Get-StagingOsLockPath -ChgPath $script:P)).Length | Should -Be 0
    }

    It 'cannot be deleted while held (Windows share mode) (TC-241, SR-087)' -Skip:(-not $IsWindows) {
        $first = Enter-StagingOsLock -ChgPath $script:P -Log $null
        try {
            { [System.IO.File]::Delete((Get-StagingOsLockPath -ChgPath $script:P)) } | Should -Throw
        } finally { Exit-StagingOsLock -Lock $first -Log $null }
    }

    It 'still takes the lock when the file carries a read-only attribute (TC-241, SR-087)' {
        $dir = Join-Path $TestDrive 'primitive-ro'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Exit-StagingOsLock -Lock (Enter-StagingOsLock -ChgPath $dir -Log $null) -Log $null
        $file = Get-Item -LiteralPath (Get-StagingOsLockPath -ChgPath $dir)
        $file.IsReadOnly = $true
        try { Test-LockAcquirable -ChgPath $dir | Should -BeTrue } finally { $file.IsReadOnly = $false }
    }
}

Describe 'The lock is released on every way a run ends in-process (TC-242, SR-085, LLR-091)' {

    BeforeAll {
        $script:Released = @{}

        # Normal completion.
        $fx = New-LockFixture 'rel-normal'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'A')
        if (-not (Invoke-LockBackup -Fixture $fx -When $script:D1)) { throw 'fixture error: the normal run failed' }
        $script:Released.Normal = Test-LockAcquirable -ChgPath $fx.Chg

        # An ordinary throw late in the run: the run stops with 4.
        $fx = New-LockFixture 'rel-throw'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'A')
        Invoke-LockBackup -Fixture $fx -When $script:D1 | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'A changed')
        Mock -ModuleName FileBackup.Engine Move-SupersededObject { throw 'SIMULATED FAILURE at step 8' }
        $code = Invoke-BackupSet -Set $fx.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
                    -LogPaths (New-Object System.Collections.Generic.List[string]) -BackupTime $script:D2
        if ($code -ne 4) { throw "fixture error: the mocked step-8 failure did not stop the run (code $code)" }
        $script:Released.Throw = Test-LockAcquirable -ChgPath $fx.Chg

        # A refusal before anything changes: a damaged latest manifest (2).
        $fx = New-LockFixture 'rel-refusal'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'A')
        New-Item -ItemType Directory -Path $fx.Bkp -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fx.Bkp 'MANIFEST.csv'), "not,a,manifest`r`n")
        $code = Invoke-BackupSet -Set $fx.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
                    -LogPaths (New-Object System.Collections.Generic.List[string]) -BackupTime $script:D1
        if ($code -ne 2) { throw "fixture error: the damaged manifest did not refuse (code $code)" }
        $script:Released.Refusal = Test-LockAcquirable -ChgPath $fx.Chg
    }

    It 'is released after a run that completes normally (TC-242, SR-085)' {
        $script:Released.Normal | Should -BeTrue
    }

    It 'is released after an ordinary throw late in the run, by the finally (TC-242, SR-085)' {
        $script:Released.Throw | Should -BeTrue
    }

    It 'is released after a refusal (TC-242, SR-085)' {
        $script:Released.Refusal | Should -BeTrue
    }
}

Describe 'A hard kill releases the lock (TC-243, SR-085, LLR-091)' {

    BeforeAll {
        $fx = New-LockFixture 'kill'
        Initialize-TwoRunStore -Fixture $fx | Out-Null
        $child = Start-ParkedChild -Fixture $fx -Mode Backup -Stage 'AfterSnapshotPublished' -When ($script:D3.ToString('o'))
        try {
            $script:WhileParked = Test-LockAcquirable -ChgPath $fx.Chg
        } finally {
            Stop-ParkedChild -Process $child
        }
        $script:AfterKill = Test-LockAcquirable -ChgPath $fx.Chg
    }

    It 'is held by the parked child (TC-243, SR-085)' {
        $script:WhileParked | Should -BeFalse
    }

    It 'is free once the child is killed with Stop-Process -Force (TC-243, SR-085)' {
        $script:AfterKill | Should -BeTrue
    }
}

Describe 'The lock is held across the whole run (TC-244, TC-245, SR-085, SR-086, LLR-091, LLR-092)' {
    # A run parked at each end of what it changes: just after it published the
    # prior state's snapshot, and just before it moves superseded objects into
    # that snapshot. A second backup and a prune must both refuse on the lock,
    # touching nothing.

    BeforeAll {
        $script:Window = @{}
        foreach ($stage in 'AfterSnapshotPublished', 'BeforeSupersededMove') {
            $fx = New-LockFixture ("whole-" + $stage)
            $snapshot = Initialize-TwoRunStore -Fixture $fx
            $child = Start-ParkedChild -Fixture $fx -Mode Backup -Stage $stage -When ($script:D3.ToString('o'))
            try {
                $r = @{}
                $r.Published = Test-Path -LiteralPath (Join-Path $fx.Chg ('Snapshot_' + $script:D2.ToString('yyyy_MM_dd_HH_mm_ss'))) -PathType Container
                $before = Get-FixtureStoreHash -Fixture $fx
                $r.ProbeAcquired = Test-LockAcquirable -ChgPath $fx.Chg
                $r.BackupCode = Invoke-BackupSet -Set $fx.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
                                    -LogPaths (New-Object System.Collections.Generic.List[string]) -BackupTime $script:D4
                $r.BackupLog = Get-LockSetLog -Fixture $fx
                $r.AfterBackupHash = Get-FixtureStoreHash -Fixture $fx
                $r.Prune = @(Remove-BackupSnapshot -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Name $snapshot -Confirm:$false)
                $r.AfterPruneHash = Get-FixtureStoreHash -Fixture $fx
                $r.Before = $before
            } finally {
                Stop-ParkedChild -Process $child
            }
            $script:Window[$stage] = $r
        }
    }

    It 'parks the run after it published the prior state at <_> (precondition) (TC-244)' -ForEach @(
        'AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].Published | Should -BeTrue
    }

    It 'holds the OS lock at <_> (TC-244, SR-085)' -ForEach @('AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].ProbeAcquired | Should -BeFalse
    }

    It 'makes a concurrent BACKUP refuse on the OS lock with 4 at <_> (TC-244, SR-086)' -ForEach @(
        'AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].BackupLog | Should -Match ([regex]::Escape($script:LockHeldToken))
        $script:Window[$_].BackupCode | Should -Be 4
    }

    It 'leaves every byte under BkpPath and ChgPath unchanged by the refused backup at <_> (TC-244, SR-086)' -ForEach @(
        'AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].AfterBackupHash | Should -Be $script:Window[$_].Before
    }

    It 'makes a concurrent PRUNE refuse on the OS lock with code 2 at <_> (TC-245, SR-086)' -ForEach @(
        'AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].Prune[0].Message | Should -Match ([regex]::Escape($script:LockHeldToken))
        "$($script:Window[$_].Prune[0].Status)/$($script:Window[$_].Prune[0].Code)" | Should -Be 'Refused/2'
    }

    It 'leaves every byte unchanged by the refused prune at <_> (TC-245, SR-086)' -ForEach @(
        'AfterSnapshotPublished', 'BeforeSupersededMove') {
        $script:Window[$_].AfterPruneHash | Should -Be $script:Window[$_].Before
    }
}

Describe 'Backup against a live prune (TC-246, SR-085, LLR-092)' {

    BeforeAll {
        $fx = New-LockFixture 'backup-vs-prune'
        $snapshot = Initialize-TwoRunStore -Fixture $fx
        $child = Start-ParkedChild -Fixture $fx -Mode Prune -SnapshotName $snapshot
        try {
            $script:BvP = @{}
            $before = Get-FixtureStoreHash -Fixture $fx
            $script:BvP.Ok     = Invoke-LockBackup -Fixture $fx -When $script:D3
            $script:BvP.Log    = Get-LockSetLog -Fixture $fx
            $script:BvP.After  = Get-FixtureStoreHash -Fixture $fx
            $script:BvP.Before = $before
        } finally {
            Stop-ParkedChild -Process $child
        }
    }

    It 'refuses the backup on the OS lock (TC-246, SR-086)' {
        $script:BvP.Log | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'fails the backup set (TC-246, SR-014)' {
        $script:BvP.Ok | Should -BeFalse
    }

    It 'leaves every byte under BkpPath and ChgPath unchanged, the prune''s own Temp included (TC-246, SR-086)' {
        $script:BvP.After | Should -Be $script:BvP.Before
    }
}

Describe 'An open failure that is not a sharing violation is LIVE (TC-249, SR-086, LLR-090)' {
    # Each arm has a source edit pending, so "proceeding" would be visible: the
    # run would publish a snapshot and change the latest state.

    BeforeAll {
        $script:OpenFail = @{}

        $arms = @(
            @{ Name = 'directory-at-path'; Seam = $null }
            @{ Name = 'io-error';          Seam = { param($p) throw [System.IO.IOException]::new('SIMULATED I/O error on the lock volume') } }
            @{ Name = 'access-denied';     Seam = { param($p) throw [System.UnauthorizedAccessException]::new('SIMULATED access denied') } }
        )
        foreach ($arm in $arms) {
            $fx = New-LockFixture ("openfail-" + $arm.Name)
            $snapshot = Initialize-TwoRunStore -Fixture $fx
            if ($arm.Name -eq 'directory-at-path') {
                Remove-Item -LiteralPath (Get-StagingOsLockPath -ChgPath $fx.Chg) -Force
                New-Item -ItemType Directory -Path (Get-StagingOsLockPath -ChgPath $fx.Chg) | Out-Null
            }
            Set-EngineVariable -Name 'StagingOsLockTestHook_BeforeOpen' -Value $arm.Seam
            try {
                $r = @{}
                $before = Get-FixtureStoreHash -Fixture $fx
                $r.Ok    = Invoke-LockBackup -Fixture $fx -When $script:D3
                $r.Log   = Get-LockSetLog -Fixture $fx
                $r.Prune = @(Remove-BackupSnapshot -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Name $snapshot -Confirm:$false)
                $r.After  = Get-FixtureStoreHash -Fixture $fx
                $r.Before = $before
            } finally {
                Set-EngineVariable -Name 'StagingOsLockTestHook_BeforeOpen' -Value $null
            }
            $script:OpenFail[$arm.Name] = $r
        }
    }

    It 'refuses the backup on the OS lock for <_> (TC-249, SR-086)' -ForEach @('directory-at-path', 'io-error', 'access-denied') {
        $script:OpenFail[$_].Log | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'refuses the prune with code 2 for <_> (TC-249, SR-086)' -ForEach @('directory-at-path', 'io-error', 'access-denied') {
        "$($script:OpenFail[$_].Prune[0].Status)/$($script:OpenFail[$_].Prune[0].Code)" | Should -Be 'Refused/2'
    }

    It 'leaves every byte unchanged for <_> (TC-249, SR-086)' -ForEach @('directory-at-path', 'io-error', 'access-denied') {
        $script:OpenFail[$_].After | Should -Be $script:OpenFail[$_].Before
    }
}

Describe 'The lock file is invisible to every consumer of the store (TC-250, SR-087, LLR-093)' {

    BeforeAll {
        $fx = New-LockFixture 'invisible'
        $script:Inv = $fx
        Initialize-TwoRunStore -Fixture $fx | Out-Null
        if (-not (Invoke-LockBackup -Fixture $fx -When $script:D3)) { throw 'fixture error: run 3 failed' }
        $script:InvSnapshots = @(Get-ChildItem -LiteralPath $fx.Chg -Directory | Where-Object Name -match '^Snapshot_' | Sort-Object Name)
        $script:InvExpected = @{}
        foreach ($f in (Get-ChildItem -LiteralPath $fx.Src -Recurse -File)) {
            $script:InvExpected[$f.FullName.Substring($fx.Src.Length).TrimStart('\', '/')] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        }

        # Every check below runs with the lock HELD, as it would be while a
        # backup is running: a consumer that opened the file would fail.
        $script:InvHolder = Enter-StagingOsLock -ChgPath $fx.Chg -Log $null
    }

    AfterAll { Exit-StagingOsLock -Lock $script:InvHolder -Log $null }

    It 'leaves Temp.lock at the change root, zero-length, after three runs (TC-250, SR-087)' {
        ([System.IO.FileInfo](Join-Path $script:Inv.Chg 'Temp.lock')).Length | Should -Be 0
    }

    It 'is not listed as a snapshot (TC-250, SR-087)' {
        (@(Get-PoolSnapshotFolder -ChangeRoot $script:Inv.Chg | ForEach-Object Name) -join '|') |
            Should -Be (@($script:InvSnapshots | ForEach-Object Name) -join '|')
    }

    It 'raises no storage-form finding (TC-250, SR-087, SR-049)' {
        @(Test-BackupStorageForm -BackupRoot $script:Inv.Bkp -ChangeRoot $script:Inv.Chg).Count | Should -Be 0
    }

    It 'leaves the pool resolving (TC-250, SR-087, SR-046)' {
        @(Test-PoolResolves -BackupRoot $script:Inv.Bkp -ChangeRoot $script:Inv.Chg).Count | Should -Be 0
    }

    It 'is not indexed as a stored object (TC-250, SR-087)' {
        @((Get-StoreObjectIndex -BackupRoot $script:Inv.Bkp -ChangeRoot $script:Inv.Chg).Objects.Values |
            Where-Object { $_.Name -eq 'Temp.lock' }).Count | Should -Be 0
    }

    It 'lets the latest state restore byte-exact while the lock is held (TC-250, SR-087, SR-008)' {
        $target = Join-Path $TestDrive 'invisible-restore-latest'
        & (Join-Path $script:Inv.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        $got = @{}
        foreach ($f in (Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object Name -ne 'Reconstruct.log')) {
            $got[$f.FullName.Substring($target.Length).TrimStart('\', '/')] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        }
        (($got.Keys | Sort-Object | ForEach-Object { "$_=$($got[$_])" }) -join '|') |
            Should -Be (($script:InvExpected.Keys | Sort-Object | ForEach-Object { "$_=$($script:InvExpected[$_])" }) -join '|')
    }

    It 'lets every snapshot restore while the lock is held (TC-250, SR-087, SR-010)' {
        $failures = @()
        foreach ($snap in $script:InvSnapshots) {
            $target = Join-Path $TestDrive ("invisible-restore-" + $snap.Name)
            try { & (Join-Path $snap.FullName 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null }
            catch { $failures += "$($snap.Name): $($_.Exception.Message)" }
        }
        ($failures -join '; ') | Should -Be ''
    }
}

Describe 'Where the lock is taken and released, statically (TC-250, SR-085, LLR-091, LLR-092)' {

    BeforeAll {
        $engine = Join-Path $script:Repo 'Modules\FileBackup.Engine.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($engine, [ref]$null, [ref]$null)
        $script:Fns = @{}
        foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $script:Fns[$fn.Name] = $fn
        }
        function Get-CallLine {
            param([string]$Function, [string]$Command)
            return @($script:Fns[$Function].Body.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Command }, $true) |
                    ForEach-Object { $_.Extent.StartLineNumber })
        }
        $script:CallLine = ${function:Get-CallLine}
    }

    It 'takes the OS lock in Invoke-BackupSet exactly once and releases it only in its finally (TC-250, SR-085)' {
        $enter = @(& $script:CallLine 'Invoke-BackupSet' 'Enter-StagingOsLock')
        $exits = @(& $script:CallLine 'Invoke-BackupSet' 'Exit-StagingOsLock')
        $finally = $script:Fns['Invoke-BackupSet'].Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally }, $true) |
                   ForEach-Object { $_.Finally.Extent }
        "$($enter.Count)/$($exits.Count)" | Should -Be '1/1'
        @($finally | Where-Object { $_.StartLineNumber -le $exits[0] -and $_.EndLineNumber -ge $exits[0] }).Count | Should -BeGreaterThan 0
    }

    It 'reads no store state in Invoke-BackupSet before taking the OS lock (TC-250, SR-085)' {
        $enter = @(& $script:CallLine 'Invoke-BackupSet' 'Enter-StagingOsLock')[0]
        $reads = @(& $script:CallLine 'Invoke-BackupSet' 'Get-PriorBackupDate') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Get-LastHashRun') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Read-Manifest') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Get-StoreObjectIndex') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Clear-InterruptedRunResidue') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Assert-SingleStoreMount') +
                 @(& $script:CallLine 'Invoke-BackupSet' 'Test-Path')
        $reads.Count | Should -BeGreaterThan 0
        @($reads | Where-Object { $_ -lt $enter }).Count | Should -Be 0
    }

    It 'takes the OS lock in Remove-BackupSnapshot before the residue completion (TC-250, SR-085)' {
        $enter   = @(& $script:CallLine 'Remove-BackupSnapshot' 'Enter-StagingOsLock')
        $residue = @(& $script:CallLine 'Remove-BackupSnapshot' 'Remove-CommittedPruneResidue')
        ($enter.Count -eq 1 -and $residue.Count -eq 1 -and $enter[0] -lt $residue[0]) | Should -BeTrue
    }
}

Describe 'Storage repair against a live backup (TC-251, SR-085, SR-086, LLR-094)' {
    # -RepairStorage renames pool objects and rewrites manifests. A backup is
    # parked inside the no-marker window; the store carries a genuinely
    # repairable finding (a raw object under a Compressed=Yes row in the older
    # snapshot), so a repair that ran would visibly change bytes -- the control
    # arm proves it does, once the backup is gone.

    BeforeAll {
        $fx = New-LockFixture 'repair-vs-backup'
        $snapshot = Initialize-TwoRunStore -Fixture $fx
        $snapDir  = Join-Path $fx.Chg $snapshot
        $rows = @(Read-Manifest -FolderPath $snapDir)
        # A row whose object is in the snapshot's own folder: the snapshot keeps
        # every DataPath (plan C10), most naming objects in the backup root.
        $target = @($rows | Where-Object { $_.DataPath -and (Test-Path -LiteralPath (Join-Path $snapDir $_.DataPath) -PathType Leaf) })[0]
        if ($null -eq $target) { throw 'fixture error: the snapshot holds no object of its own to tamper' }
        $target.Compressed = 'Yes'
        Write-Manifest -FolderPath $snapDir -Records $rows
        $script:Rep = @{}
        $script:Rep.Repairable = @(Test-BackupStorageForm -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg | Where-Object Repairable).Count

        $child = Start-ParkedChild -Fixture $fx -Mode Backup -Stage 'AfterSnapshotPublished' -When ($script:D3.ToString('o'))
        try {
            $lines = New-Object System.Collections.Generic.List[string]
            $before = Get-FixtureStoreHash -Fixture $fx
            $script:Rep.Message = ''
            try {
                Repair-BackupStorageForm -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) $lines.Add("$l $m") }.GetNewClosure() | Out-Null
            } catch { $script:Rep.Message = $_.Exception.Message }
            $script:Rep.Log    = ($lines -join "`n")
            $script:Rep.After  = Get-FixtureStoreHash -Fixture $fx
            $script:Rep.Before = $before
        } finally {
            Stop-ParkedChild -Process $child
        }
        # Control arm: the holder gone, the same repair runs.
        $script:Rep.Control = Repair-BackupStorageForm -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) }
    }

    It 'has a repairable finding to work on (precondition) (TC-251)' {
        $script:Rep.Repairable | Should -BeGreaterThan 0
    }

    It 'leaves every byte under BkpPath and ChgPath unchanged while the backup holds the lock (TC-251, SR-086)' {
        $script:Rep.After | Should -Be $script:Rep.Before
    }

    It 'refuses by throwing the lock-held token (TC-251, SR-086)' {
        $script:Rep.Message | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'logs the refusal through the caller''s logger (TC-251, SR-086)' {
        $script:Rep.Log | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'control: repairs the finding once the backup is gone (TC-251, SR-049)' {
        $script:Rep.Control.Repaired | Should -BeGreaterThan 0
    }
}

Describe 'Kit refresh against a live backup (TC-252, SR-085, SR-086, LLR-094)' {
    # -RefreshKits overwrites kit files inside every Snapshot_* folder. The older
    # snapshot carries a STALE kit (its RECONSTRUCT.ps1 differs from the root's),
    # so a refresh that ran would visibly change bytes.

    BeforeAll {
        $fx = New-LockFixture 'refresh-vs-backup'
        $snapshot = Initialize-TwoRunStore -Fixture $fx
        $script:RefSnapKit = Join-Path (Join-Path $fx.Chg $snapshot) 'RECONSTRUCT.ps1'
        $script:RefRootKit = Join-Path $fx.Bkp 'RECONSTRUCT.ps1'
        [System.IO.File]::AppendAllText($script:RefSnapKit, "`n# an older kit revision`n")
        $script:Ref = @{}
        $script:Ref.Stale = ((Get-FileHash -LiteralPath $script:RefSnapKit).Hash -ne (Get-FileHash -LiteralPath $script:RefRootKit).Hash)

        $child = Start-ParkedChild -Fixture $fx -Mode Backup -Stage 'AfterSnapshotPublished' -When ($script:D3.ToString('o'))
        try {
            $lines = New-Object System.Collections.Generic.List[string]
            $before = Get-FixtureStoreHash -Fixture $fx
            $script:Ref.Message = ''
            try {
                Update-BackupSnapshotKit -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) $lines.Add("$l $m") }.GetNewClosure() | Out-Null
            } catch { $script:Ref.Message = $_.Exception.Message }
            $script:Ref.Log    = ($lines -join "`n")
            $script:Ref.After  = Get-FixtureStoreHash -Fixture $fx
            $script:Ref.Before = $before
        } finally {
            Stop-ParkedChild -Process $child
        }
        Update-BackupSnapshotKit -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) } | Out-Null
        $script:Ref.ControlRefreshed = ((Get-FileHash -LiteralPath $script:RefSnapKit).Hash -eq (Get-FileHash -LiteralPath $script:RefRootKit).Hash)
    }

    It 'has a stale snapshot kit to refresh (precondition) (TC-252)' {
        $script:Ref.Stale | Should -BeTrue
    }

    It 'leaves every byte under BkpPath and ChgPath unchanged while the backup holds the lock (TC-252, SR-086)' {
        $script:Ref.After | Should -Be $script:Ref.Before
    }

    It 'refuses by throwing the lock-held token (TC-252, SR-086)' {
        $script:Ref.Message | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'logs the refusal through the caller''s logger (TC-252, SR-086)' {
        $script:Ref.Log | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'control: refreshes the stale kit once the backup is gone (TC-252, SR-049)' {
        $script:Ref.ControlRefreshed | Should -BeTrue
    }
}

Describe '-Action Verify through the entry point with the lock held (TC-253, SR-085, SR-086, SR-040, LLR-094)' {
    # The real FileBackup.ps1 in a child process, so the SR-040 code is the
    # process exit code. THIS process holds the store's OS lock throughout,
    # standing in for a live backup.

    BeforeAll {
        $fx = New-LockFixture 'verify-entry'
        Initialize-TwoRunStore -Fixture $fx | Out-Null
        $cfg = Join-Path $fx.Root 'config.xml'
        @{ Secrets = $null; BackupSets = @([pscustomobject]@{
                    Name = 'V'; SourcePath = $fx.Src; BackupPath = $fx.Bkp
                    ChangePath = $fx.Chg; HashRecalcFreq = 'A'; CompressEnabled = $false }) } |
            Export-Clixml -LiteralPath $cfg
        $entry = Join-Path $script:Repo 'FileBackup.ps1'
        $pwsh  = (Get-Process -Id $PID).Path
        $run = {
            param([string[]]$Extra)
            $out = & $pwsh -NoProfile -File $entry -ConfigPath $cfg -Action Verify -NoMail -NonInteractive -ExitCode @Extra *>&1
            return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($out | Out-String) }
        }
        $script:VE = @{}
        $holder = Enter-StagingOsLock -ChgPath $fx.Chg -Log $null
        try {
            $before = Get-FixtureStoreHash -Fixture $fx
            $script:VE.Plain   = & $run @()
            $script:VE.Repair  = & $run @('-RepairStorage')
            $script:VE.Refresh = & $run @('-RefreshKits')
            $script:VE.After   = Get-FixtureStoreHash -Fixture $fx
            $script:VE.Before  = $before
        } finally {
            Exit-StagingOsLock -Lock $holder -Log $null
        }
    }

    It 'still runs a read-only Verify, which takes no lock (exit 0) (TC-253, SR-049)' {
        $script:VE.Plain.Code | Should -Be 0
    }

    It 'refuses -RepairStorage with exit 2 (TC-253, SR-086, SR-040)' {
        $script:VE.Repair.Code | Should -Be 2
    }

    It 'names the lock in the -RepairStorage refusal (TC-253, SR-086)' {
        $script:VE.Repair.Text | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'refuses -RefreshKits with exit 2 (TC-253, SR-086, SR-040)' {
        $script:VE.Refresh.Code | Should -Be 2
    }

    It 'names the lock in the -RefreshKits refusal (TC-253, SR-086)' {
        $script:VE.Refresh.Text | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'leaves every byte unchanged across all three invocations (TC-253, SR-086)' {
        $script:VE.After | Should -Be $script:VE.Before
    }
}

Describe 'The maintenance lock edge cases and placement (TC-254, SR-085, SR-086, LLR-094)' {

    BeforeAll {
        $script:Edge = @{}
        $fx = New-LockFixture 'maint-edge'
        Initialize-TwoRunStore -Fixture $fx | Out-Null
        $script:EdgeFx = $fx

        # -WhatIf takes no lock: it must run while the lock is held.
        $holder = Enter-StagingOsLock -ChgPath $fx.Chg -Log $null
        try {
            $script:Edge.WhatIfRepair = $null
            try { Repair-BackupStorageForm -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) } -WhatIf | Out-Null; $script:Edge.WhatIfRepair = 'ran' }
            catch { $script:Edge.WhatIfRepair = $_.Exception.Message }
            try { Update-BackupSnapshotKit -BackupRoot $fx.Bkp -ChangeRoot $fx.Chg -Log { param($m, $l) } -WhatIf | Out-Null; $script:Edge.WhatIfRefresh = 'ran' }
            catch { $script:Edge.WhatIfRefresh = $_.Exception.Message }
        } finally { Exit-StagingOsLock -Lock $holder -Log $null }

        # No change root at all: refused.
        $script:Edge.NoRoot = ''
        try { Repair-BackupStorageForm -BackupRoot $fx.Bkp -Log { param($m, $l) } | Out-Null } catch { $script:Edge.NoRoot = $_.Exception.Message }

        # A change root that does not exist yet: created, locked, and released.
        $missing = Join-Path $fx.Root 'chg-not-yet'
        Repair-BackupStorageForm -BackupRoot $fx.Bkp -ChangeRoot $missing -BackupRootOnly -Log { param($m, $l) } | Out-Null
        $script:Edge.MissingLock = Test-Path -LiteralPath (Join-Path $missing 'Temp.lock') -PathType Leaf
        $script:Edge.MissingReleased = Test-LockAcquirable -ChgPath $missing

        $engine = Join-Path $script:Repo 'Modules\FileBackup.Engine.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($engine, [ref]$null, [ref]$null)
        $script:EdgeFns = @{}
        foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $script:EdgeFns[$fn.Name] = $fn
        }
        $script:EdgeCallLines = {
            param([string]$Function, [string[]]$Command)
            @($script:EdgeFns[$Function].Body.FindAll({ param($n)
                        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in $Command }, $true) |
                    ForEach-Object { $_.Extent.StartLineNumber })
        }
    }

    It 'lets Repair-BackupStorageForm -WhatIf run while the lock is held (TC-254, SR-085)' {
        $script:Edge.WhatIfRepair | Should -Be 'ran'
    }

    It 'lets Update-BackupSnapshotKit -WhatIf run while the lock is held (TC-254, SR-085)' {
        $script:Edge.WhatIfRefresh | Should -Be 'ran'
    }

    It 'refuses a repair given no change root, with the lock-held token (TC-254, SR-086)' {
        $script:Edge.NoRoot | Should -Match ([regex]::Escape($script:LockHeldToken))
    }

    It 'creates a missing change root, takes the lock there and releases it (TC-254, SR-085)' {
        "$($script:Edge.MissingLock)/$($script:Edge.MissingReleased)" | Should -Be 'True/True'
    }

    It 'takes the lock in <_> before any mutating command (TC-254, SR-085)' -ForEach @('Repair-BackupStorageForm', 'Update-BackupSnapshotKit') {
        $enter = @(& $script:EdgeCallLines $_ @('Enter-StoreMutationLock'))
        $first = @(& $script:EdgeCallLines $_ @('Test-BackupStorageForm', 'Move-Item', 'Write-Manifest', 'Copy-Item', 'Get-PoolSnapshotFolder') | Sort-Object)
        ($enter.Count -eq 1 -and $first.Count -gt 0 -and $enter[0] -lt $first[0]) | Should -BeTrue
    }
}

Describe 'A run reads the prior store state only after it holds the lock (TC-250, SR-085, LLR-091)' {
    # Run A is the store's FIRST backup. It is parked holding the lock after its
    # first file, before it has written a manifest or LastBackupRun. Run B
    # starts then; the moment B goes for the lock, the seam lets A run to
    # completion (writing LastBackupRun = D1) and waits for it to exit, so B's
    # open then succeeds. A B that read the prior state BEFORE the lock would
    # still believe this is the first backup and keep no snapshot of A's state.

    BeforeAll {
        $fx = New-LockFixture 'read-after-lock'
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'a.txt'), 'ALPHA as run A stored it')
        [System.IO.File]::WriteAllText((Join-Path $fx.Src 'b.txt'), 'BRAVO')
        $script:RalAHash = (Get-FileHash -LiteralPath (Join-Path $fx.Src 'a.txt') -Algorithm SHA256).Hash
        $go = Join-Path $TestDrive 'read-after-lock.go'
        $child = Start-ParkedChild -Fixture $fx -Mode Backup -Stage 'AfterFileCaptured' `
                    -Go $go -When ($script:D1.ToString('o'))
        $null = $child.Handle   # cache the handle, so ExitCode is readable after the exit
        $st = @{ Fired = $false; AExited = $false; AExitCode = $null }
        try {
            $aFile = Join-Path $fx.Src 'a.txt'
            Set-EngineVariable -Name 'StagingOsLockTestHook_BeforeOpen' -Value ({
                    param($p)
                    if ($st.Fired) { return }
                    $st.Fired = $true
                    [System.IO.File]::WriteAllText($go, 'go')
                    $st.AExited = $child.WaitForExit(120000)
                    if ($st.AExited) { $st.AExitCode = $child.ExitCode }
                    # Only now does the source change: run A copied it unchanged,
                    # and run B walks the source after it holds the lock.
                    [System.IO.File]::WriteAllText($aFile, 'ALPHA as run B found it')
                }.GetNewClosure())
            $script:RalBError = ''
            try { $script:RalBOk = Invoke-LockBackup -Fixture $fx -When $script:D2 }
            catch { $script:RalBOk = $false; $script:RalBError = $_.Exception.Message }
        } finally {
            Set-EngineVariable -Name 'StagingOsLockTestHook_BeforeOpen' -Value $null
            Stop-ParkedChild -Process $child
        }
        $script:RalState = $st
        $script:RalSnapshots = @(Get-ChildItem -LiteralPath $fx.Chg -Directory | Where-Object Name -match '^Snapshot_' | ForEach-Object Name)
        $script:RalHashes = @(foreach ($root in $fx.Bkp, $fx.Chg) {
                Get-ChildItem -LiteralPath $root -Recurse -Force -File |
                    Where-Object Name -ne 'Temp.lock' |
                    ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
    }

    It 'let run A finish while run B was going for the lock (precondition) (TC-250)' {
        "$($script:RalState.Fired)/$($script:RalState.AExited)/$($script:RalState.AExitCode)" | Should -Be 'True/True/0'
    }

    It 'keeps the bytes run A stored for a.txt (TC-250, SR-085)' {
        $script:RalHashes | Should -Contain $script:RalAHash
    }

    It 'makes run B see run A''s state: one snapshot, dated by run A (TC-250, SR-085, SR-005)' {
        ($script:RalSnapshots -join '|') | Should -Be ('Snapshot_' + $script:D1.ToString('yyyy_MM_dd_HH_mm_ss'))
    }

    It 'completes run B (TC-250, SR-014)' {
        $script:RalBOk | Should -BeTrue
    }
}
