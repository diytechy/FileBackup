<#
.SYNOPSIS
    Pester 5 tests for the bounded backup run (docs/plans/bounded-run-loop.md):
    the run order, kill safety, checkpoints, retries, outcome codes and the
    manifest writer it relies on.

.DESCRIPTION
    Most tests drive Invoke-BackupSet in-process, so the module's test seams
    (the run hook, the retry spacing, the checkpoint interval) can be set.
    "Restorable" is checked the way the restore kit resolves a row (plan §7):
    the row's own DataPath when that file is in the row's folder, otherwise
    the object named for the row's content anywhere in the pool - and the
    bytes found must hash to the row.
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    Initialize-XxHashLibrary | Out-Null
    $script:engine = Get-Module FileBackup.Engine

    function New-Store {
        param([string]$Name)
        $root = Join-Path $TestDrive $Name
        $s = [pscustomobject]@{
            Root = $root
            Src  = Join-Path $root 'src'
            Bkp  = Join-Path $root 'store\Backup'
            Chg  = Join-Path $root 'store\Changes'
        }
        New-Item -ItemType Directory -Path $s.Src, $s.Bkp, $s.Chg -Force | Out-Null
        $s | Add-Member -NotePropertyName Set -NotePropertyValue ([pscustomobject]@{
            Name = $Name; SourcePath = $s.Src; BackupPath = $s.Bkp; ChangePath = $s.Chg
            HashRecalcFreq = 'N'; CompressEnabled = $false; CompressProbe = 'always'; BrowseView = 'off'
        })
        return $s
    }

    function Set-SourceFile {
        param($Store, [string]$Rel, [string]$Text)
        $full = Join-Path $Store.Src $Rel
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($full)) -Force | Out-Null
        [IO.File]::WriteAllText($full, $Text)
    }

    function Invoke-Run {
        param($Store, [string]$When)
        $logs = [System.Collections.Generic.List[string]]::new()
        return (Invoke-BackupSet -Set $Store.Set -Deps @{ '7z' = $null; ffprobe = $null } -LogPaths $logs -BackupTime ([datetime]$When))
    }

    function Get-SnapshotNames {
        param($Store)
        @(Get-ChildItem -LiteralPath $Store.Chg -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name | ForEach-Object Name)
    }

    function Get-PoolObject {
        # Every object file in the pool: name -> list of full paths.
        param($Store)
        $map = @{}
        $folders = @($Store.Bkp) + @(Get-ChildItem -LiteralPath $Store.Chg -Directory | Where-Object Name -like 'Snapshot_*' | ForEach-Object FullName)
        foreach ($f in $folders) {
            foreach ($file in Get-ChildItem -LiteralPath $f -File -Force) {
                if ($null -eq (ConvertFrom-StoredObjectName -Name $file.Name)) { continue }
                if (-not $map.ContainsKey($file.Name)) { $map[$file.Name] = [System.Collections.Generic.List[string]]::new() }
                $map[$file.Name].Add($file.FullName)
            }
        }
        return $map
    }

    function Get-StateContent {
        # Resolves every row of one state's manifest as the kit does and returns
        # RelativePath -> text, throwing when a row cannot be resolved or its
        # bytes do not hash to it.
        param($Store, [string]$Folder)
        $byPrefix = @{}
        $folders = @($Store.Bkp) + @(Get-ChildItem -LiteralPath $Store.Chg -Directory | Where-Object Name -like 'Snapshot_*' | ForEach-Object FullName)
        foreach ($f in $folders) {
            foreach ($file in Get-ChildItem -LiteralPath $f -File -Force) {
                $p = ConvertFrom-StoredObjectName -Name $file.Name
                if ($p -and -not $byPrefix.ContainsKey($p.Prefix)) { $byPrefix[$p.Prefix] = $file.FullName }
            }
        }
        $out = @{}
        foreach ($row in @(Read-Manifest -FolderPath $Folder)) {
            $path = $null
            if ($row.DataPath -and (Test-Path -LiteralPath (Join-Path $Folder $row.DataPath) -PathType Leaf)) {
                $path = Join-Path $Folder $row.DataPath
            } else {
                $prefix = Get-StoredObjectPrefix -HashHex $row.xxH2Hash -Length ([long]$row.Length)
                $path = $byPrefix[$prefix]
            }
            if (-not $path) { throw "row '$($row.RelativePath)' in '$Folder' resolves to nothing" }
            if ((Get-FileXxHash -FilePath $path) -ne $row.xxH2Hash) { throw "row '$($row.RelativePath)' in '$Folder' resolves to bytes of other content" }
            $out[$row.RelativePath] = [IO.File]::ReadAllText($path)
        }
        return $out
    }

    function Format-State { param([hashtable]$State) (($State.Keys | Sort-Object | ForEach-Object { "$_=$($State[$_])" }) -join ';') }

    function Set-EngineVar { param([string]$Name, $Value) & $script:engine { param($n, $v) Set-Variable -Scope Script -Name $n -Value $v } $Name $Value }
}

Describe 'The bounded backup run' {
AfterEach {
    Set-EngineVar 'BackupRunTestHook' $null
    Set-EngineVar 'RetryMinSpacingSeconds' 60
    Set-EngineVar 'CheckpointMinSeconds' 60
    Set-EngineVar 'CheckpointWriteFactor' 10
}

Describe 'Stored-object names are read without decoding the hash (SR-069)' {
    It 'agrees with Common''s parser on prefix, length and extension' {
        $rng = [System.Random]::new(11)
        foreach ($i in 1..200) {
            $hash = '{0:X16}{1:X16}' -f $rng.NextInt64(), $rng.NextInt64()
            $len  = [long]$rng.NextInt64(0, 50000000000)
            $ext  = @('', '.txt', '.7z', '.foo bar', '.tar.gz')[$i % 5]
            $name = Get-HashSizeFileName -HashHex $hash -Length $len -Extension $ext
            $fast = ConvertFrom-StoredObjectName -Name $name
            $slow = ConvertFrom-HashSizeFileName -Name $name
            $fast.Length | Should -Be $slow.Length
            $fast.Extension | Should -Be $slow.Extension
            $fast.Prefix | Should -Be (Get-StoredObjectPrefix -HashHex $hash -Length $len)
        }
    }
    It 'returns nothing for a name outside the grammar' {
        foreach ($n in 'MANIFEST.csv', 'RECONSTRUCT.ps1', 'short_2.txt', 'a.txt', '') {
            ConvertFrom-StoredObjectName -Name $n | Should -BeNullOrEmpty
        }
    }
}

Describe 'Write-Manifest writes what Export-Csv wrote, and no witness (SR-025, R5)' {
    BeforeAll {
        function New-TrickyRow([int]$i) {
            [pscustomobject]@{
                DataPath = @('', $null, 'x "q" y', 'a,b')[$i % 4]; RelativePath = "dir\f$i ünï ""q"".txt"
                Length = [long]($i * 1000); LastWriteTime = [datetime]::new(2025, 1, 2, 3, 4, 5).AddTicks($i * 7)
                xxH2Hash = ('{0:X32}' -f $i); Compressed = @('Yes', 'No', $null)[$i % 3]; StoredAsHashSize = 'Hash'
                Duplicate = $i % 2; MediaMBPerSec = @($null, '', 1.5)[$i % 3]
            }
        }
        function Get-ExportCsvBytes($rows, $dir) {
            $p = Join-Path $dir 'ref.csv'
            $rows | ForEach-Object {
                [pscustomobject]@{ DataPath = $_.DataPath; RelativePath = $_.RelativePath; Length = $_.Length
                    LastWriteTimeStr = ConvertTo-ManifestDateString $_.LastWriteTime; xxH2Hash = $_.xxH2Hash
                    Compressed = $_.Compressed; StoredAsHashSize = $_.StoredAsHashSize; Duplicate = $_.Duplicate
                    MediaMBPerSec = $_.MediaMBPerSec }
            } | Export-Csv -LiteralPath $p -NoTypeInformation
            return [IO.File]::ReadAllBytes($p)
        }
    }
    It 'is byte-identical on the PowerShell path and on the compiled path' {
        $rows = @(0..40 | ForEach-Object { New-TrickyRow $_ })
        $dir = Join-Path $TestDrive 'wm'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $ref = Get-ExportCsvBytes $rows $dir
        $common = Get-Module FileBackup.Common
        foreach ($threshold in 1000000, 1) {
            & $common { param($t) $script:ManifestCompiledWriterMinRows = $t } $threshold
            try { Write-Manifest -FolderPath $dir -Records $rows }
            finally { & $common { $script:ManifestCompiledWriterMinRows = 5000 } }
            $got = [IO.File]::ReadAllBytes((Join-Path $dir 'MANIFEST.csv'))
            [System.Linq.Enumerable]::SequenceEqual([byte[]]$got, [byte[]]$ref) | Should -BeTrue -Because "threshold $threshold"
        }
    }
    It 'writes the header for an empty record set' {
        $dir = Join-Path $TestDrive 'wm-empty'
        Write-Manifest -FolderPath $dir -Records @()
        (Get-Content -LiteralPath (Join-Path $dir 'MANIFEST.csv') -TotalCount 1) | Should -Match 'RelativePath'
        @(Read-Manifest -FolderPath $dir).Count | Should -Be 0
    }
    It 'removes a witness an older build left beside the manifest' {
        $dir = Join-Path $TestDrive 'wm-meta'
        Write-Manifest -FolderPath $dir -Records @(New-TrickyRow 1)
        Write-ManifestWitness -FolderPath $dir | Out-Null
        Test-Path -LiteralPath (Join-Path $dir 'MANIFEST.csv.meta') | Should -BeTrue
        Write-Manifest -FolderPath $dir -Records @(New-TrickyRow 2)
        Test-Path -LiteralPath (Join-Path $dir 'MANIFEST.csv.meta') | Should -BeFalse
    }
}

Describe 'Snapshots follow rows, not objects (R7, SR-005, SR-100)' {
    It 'keeps no snapshot for a run that changed nothing' {
        $s = New-Store 'nochange'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-01-01T10:00:00' | Should -Be 0
        Invoke-Run $s '2026-01-02T10:00:00' | Should -Be 0
        Get-SnapshotNames $s | Should -BeNullOrEmpty
    }
    It 'keeps a snapshot for a rename, which moves no object' {
        $s = New-Store 'rename'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-01-01T10:00:00' | Should -Be 0
        Rename-Item -LiteralPath (Join-Path $s.Src 'a.txt') -NewName 'b.txt'
        Invoke-Run $s '2026-01-02T10:00:00' | Should -Be 0
        Get-SnapshotNames $s | Should -Be @('Snapshot_2026_01_01_10_00_00')
        Format-State (Get-StateContent $s (Join-Path $s.Chg 'Snapshot_2026_01_01_10_00_00')) | Should -Be 'a.txt=alpha'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'b.txt=alpha'
    }
    It 'keeps a snapshot for a time-only change and for an added duplicate' {
        $s = New-Store 'timeonly'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-01-01T10:00:00' | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $s.Src 'a.txt')).LastWriteTime = [datetime]'2020-05-05'
        Invoke-Run $s '2026-01-02T10:00:00' | Should -Be 0
        Set-SourceFile $s 'copy.txt' 'alpha'
        Invoke-Run $s '2026-01-03T10:00:00' | Should -Be 0
        Get-SnapshotNames $s | Should -Be @('Snapshot_2026_01_01_10_00_00', 'Snapshot_2026_01_02_10_00_00')
    }
}

Describe 'Content moves by rename and is never deleted (R6, R9, SR-003, SR-059)' {
    It 'moves re-added content back from its snapshot instead of storing a second copy, and every state still restores' {
        $s = New-Store 'readd'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-01-01T10:00:00' | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $s.Src 'b.txt')
        Invoke-Run $s '2026-01-02T10:00:00' | Should -Be 0
        $pool = Get-PoolObject $s
        $bravo = @($pool.Keys | Where-Object { $pool[$_][0] -like '*Snapshot_*' })
        $bravo.Count | Should -Be 1
        Set-SourceFile $s 'again\b2.txt' 'bravo'
        Invoke-Run $s '2026-01-03T10:00:00' | Should -Be 0
        $pool = Get-PoolObject $s
        $pool[$bravo[0]].Count | Should -Be 1
        $pool[$bravo[0]][0] | Should -BeLike "$($s.Bkp)*"
        Format-State (Get-StateContent $s (Join-Path $s.Chg 'Snapshot_2026_01_01_10_00_00')) | Should -Be 'a.txt=alpha;b.txt=bravo'
        Format-State (Get-StateContent $s (Join-Path $s.Chg 'Snapshot_2026_01_02_10_00_00')) | Should -Be 'a.txt=alpha'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;again\b2.txt=bravo'
    }
    It 'uses re-added content where it is when its snapshot carries a kit older than revision 4' {
        # Such a kit (an older engine's snapshot) finds a row's object only
        # where the row names it, so moving the object out would break it.
        $s = New-Store 'readd-oldkit'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-01-01T10:00:00' | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $s.Src 'b.txt')
        Invoke-Run $s '2026-01-02T10:00:00' | Should -Be 0
        $snap = Join-Path $s.Chg 'Snapshot_2026_01_01_10_00_00'
        $kit = Join-Path $snap 'RECONSTRUCT.ps1'
        [IO.File]::WriteAllText($kit, ([IO.File]::ReadAllText($kit) -replace '# KitRevision: \d+', '# KitRevision: 3'))
        $pool = Get-PoolObject $s
        $bravo = @($pool.Keys | Where-Object { $pool[$_][0] -like "$snap*" })
        $bravo.Count | Should -Be 1
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-01-03T10:00:00' | Should -Be 0
        $pool = Get-PoolObject $s
        $pool[$bravo[0]].Count | Should -Be 1
        $pool[$bravo[0]][0] | Should -BeLike "$snap*"
        Format-State (Get-StateContent $s $snap) | Should -Be 'a.txt=alpha;b.txt=bravo'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo'
    }
    It 'never deletes an object across a sequence of edits, removals and re-adds' {
        $s = New-Store 'nodelete'
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $steps = @(
            { Set-SourceFile $s 'a.txt' 'v1'; Set-SourceFile $s 'b.txt' 'b1' },
            { Set-SourceFile $s 'a.txt' 'v2' },
            { Remove-Item -LiteralPath (Join-Path $s.Src 'b.txt') },
            { Set-SourceFile $s 'a.txt' 'v1' },
            { Remove-Item -LiteralPath (Join-Path $s.Src 'a.txt'); Set-SourceFile $s 'c.txt' 'b1' }
        )
        $day = 1
        foreach ($step in $steps) {
            & $step
            Invoke-Run $s ('2026-02-{0:D2}T10:00:00' -f $day) | Should -Be 0
            $day++
            $pool = Get-PoolObject $s
            foreach ($name in $seen) { $pool.ContainsKey($name) | Should -BeTrue -Because "'$name' was stored before" }
            foreach ($name in $pool.Keys) { [void]$seen.Add($name); $pool[$name].Count | Should -Be 1 }
        }
    }
}

Describe 'A kill at any stage leaves every state restorable, and the next run finishes the job (plan §3)' {
    It 'survives a kill at <Stage>' -ForEach @(
        @{ Stage = 'BeforeSnapshotPublish' }, @{ Stage = 'AfterSnapshotPublished' }, @{ Stage = 'AfterFileCaptured' }, @{ Stage = 'BeforeFinalManifest' },
        @{ Stage = 'AfterFinalManifest' }, @{ Stage = 'BeforeSupersededMove' }
    ) {
        $s = New-Store "kill-$Stage"
        Set-SourceFile $s 'keep.txt' 'keep'
        Set-SourceFile $s 'edit.txt' 'old'
        Set-SourceFile $s 'gone.txt' 'gone'
        Invoke-Run $s '2026-03-01T10:00:00' | Should -Be 0
        $prior = Format-State (Get-StateContent $s $s.Bkp)

        Set-SourceFile $s 'edit.txt' 'new'
        Remove-Item -LiteralPath (Join-Path $s.Src 'gone.txt')
        Set-SourceFile $s 'add.txt' 'added'
        Set-EngineVar 'CheckpointMinSeconds' 0
        Set-EngineVar 'CheckpointWriteFactor' 0
        $kill = $Stage
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx) if ($st -eq $kill) { throw "simulated kill at $st" } }.GetNewClosure())
        Invoke-Run $s '2026-03-02T10:00:00' | Should -Be 4
        Set-EngineVar 'BackupRunTestHook' $null

        # Every visible state restores right after the kill.
        foreach ($snap in Get-SnapshotNames $s) { { Get-StateContent $s (Join-Path $s.Chg $snap) } | Should -Not -Throw }
        { Get-StateContent $s $s.Bkp } | Should -Not -Throw
        # The prior state is held by its snapshot from the moment it was published.
        if ($Stage -notin 'BeforeSnapshotPublish', 'AfterSnapshotPublished') {
            Format-State (Get-StateContent $s (Join-Path $s.Chg 'Snapshot_2026_03_01_10_00_00')) | Should -Be $prior
        }

        Invoke-Run $s '2026-03-03T10:00:00' | Should -Be 0
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'add.txt=added;edit.txt=new;keep.txt=keep'
        Format-State (Get-StateContent $s (Join-Path $s.Chg 'Snapshot_2026_03_01_10_00_00')) | Should -Be $prior
        @(Get-ChildItem -LiteralPath $s.Chg -Directory | Where-Object { $_.Name -like 'Building_*' -or $_.Name -eq 'Incoming' }).Count | Should -Be 0
    }
}

Describe 'Progress checkpoints (R13)' {
    It 'saves captured rows during the loop, keeping the rows it has not reached' {
        $s = New-Store 'checkpoint'
        foreach ($i in 1..4) { Set-SourceFile $s "f$i.txt" "one-$i" }
        Invoke-Run $s '2026-04-01T10:00:00' | Should -Be 0
        foreach ($i in 1..4) { Set-SourceFile $s "f$i.txt" "two-$i" }
        Set-EngineVar 'CheckpointMinSeconds' 0
        Set-EngineVar 'CheckpointWriteFactor' 0
        $count = [ref]0
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx) if ($st -eq 'AfterFileCaptured') { $count.Value++; if ($count.Value -eq 3) { throw 'simulated kill' } } }.GetNewClosure())
        Invoke-Run $s '2026-04-02T10:00:00' | Should -Be 4
        $rows = @(Read-Manifest -FolderPath $s.Bkp)
        $rows.Count | Should -Be 4
        $state = Get-StateContent $s $s.Bkp
        @($state.Values | Where-Object { $_ -like 'two-*' }).Count | Should -Be 2
        @($state.Values | Where-Object { $_ -like 'one-*' }).Count | Should -Be 2
    }
}

Describe 'A locked file is retried, then warned about (R12, SR-091)' {
    It 'keeps the earlier copy of a file that stays locked, and reports 1' {
        $s = New-Store 'locked'
        Set-SourceFile $s 'a.txt' 'first'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-05-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'a.txt' 'second'
        Set-EngineVar 'RetryMinSpacingSeconds' 1
        $hold = [IO.File]::Open((Join-Path $s.Src 'a.txt'), 'Open', 'ReadWrite', 'None')
        try { Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 1 } finally { $hold.Dispose() }
        (Get-StateContent $s $s.Bkp)['a.txt'] | Should -Be 'first'
        Get-Content -LiteralPath (Join-Path $s.Chg 'backup.log') -Raw | Should -Match "Not capturing 'a\.txt' after 3 attempt"
        Invoke-Run $s '2026-05-03T10:00:00' | Should -Be 0
        (Get-StateContent $s $s.Bkp)['a.txt'] | Should -Be 'second'
    }
    It 'captures a file that is released before the retry pass, and reports 0' {
        $s = New-Store 'released'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-EngineVar 'RetryMinSpacingSeconds' 1
        $hold = [IO.File]::Open((Join-Path $s.Src 'a.txt'), 'Open', 'ReadWrite', 'None')
        $h = [ref]$hold
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx) if ($st -eq 'BeforeRetryPass') { $h.Value.Dispose() } }.GetNewClosure())
        try { Invoke-Run $s '2026-05-01T10:00:00' | Should -Be 0 } finally { $hold.Dispose() }
        (Get-StateContent $s $s.Bkp)['a.txt'] | Should -Be 'alpha'
    }
}

Describe 'Corner cases warn and the run carries on (R1, C2)' {
    It 'moves everything into the snapshot when the source is empty, and back when it returns' {
        $s = New-Store 'empty'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-06-01T10:00:00' | Should -Be 0
        Move-Item -LiteralPath (Join-Path $s.Src 'a.txt') -Destination (Join-Path $s.Root 'aside.txt')
        Invoke-Run $s '2026-06-02T10:00:00' | Should -Be 0
        Get-Content -LiteralPath (Join-Path $s.Chg 'backup.log') -Raw | Should -Match 'is empty while the latest state holds 1 file'
        @(Read-Manifest -FolderPath $s.Bkp).Count | Should -Be 0
        Move-Item -LiteralPath (Join-Path $s.Root 'aside.txt') -Destination (Join-Path $s.Src 'a.txt')
        Invoke-Run $s '2026-06-03T10:00:00' | Should -Be 0
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha'
        (Get-PoolObject $s).Count | Should -Be 1
    }
    It 'dates the prior state by the manifest file when the run-state file is missing' {
        $s = New-Store 'nostate'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-06-01T10:00:00' | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'FileBackupState.json')
        (Get-Item -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv')).LastWriteTime = [datetime]'2026-05-31T08:09:10'
        Set-SourceFile $s 'a.txt' 'alpha-2'
        Invoke-Run $s '2026-06-02T10:00:00' | Should -Be 0
        Get-SnapshotNames $s | Should -Be @('Snapshot_2026_05_31_08_09_10')
    }
    It 'leaves an older engine''s Temp folder alone, with a warning' {
        $s = New-Store 'oldtemp'
        Set-SourceFile $s 'a.txt' 'alpha'
        $old = Join-Path $s.Chg 'Temp'
        New-Item -ItemType Directory -Path $old | Out-Null
        [IO.File]::WriteAllText((Join-Path $old 'precious.bin'), 'only copy')
        Invoke-Run $s '2026-06-01T10:00:00' | Should -Be 0
        Test-Path -LiteralPath (Join-Path $old 'precious.bin') | Should -BeTrue
        Get-Content -LiteralPath (Join-Path $s.Chg 'backup.log') -Raw | Should -Match 'is left alone'
    }
    It 'reports content that changed without a size or time change, on a scheduled re-read (SR-105)' {
        $s = New-Store 'silent'
        $s.Set.HashRecalcFreq = 'A'
        Set-SourceFile $s 'a.txt' 'AAAA'
        Invoke-Run $s '2026-06-01T10:00:00' | Should -Be 0
        $f = Get-Item -LiteralPath (Join-Path $s.Src 'a.txt')
        $t = $f.LastWriteTime
        [IO.File]::WriteAllText($f.FullName, 'BBBB')
        $f.LastWriteTime = $t
        Invoke-Run $s '2026-06-02T10:00:00' | Should -Be 0
        (Get-StateContent $s $s.Bkp)['a.txt'] | Should -Be 'BBBB'
        Get-Content -LiteralPath (Join-Path $s.Chg 'backup.log') -Raw | Should -Match 'has new content although its size and modification time did not change'
    }
}

Describe 'Verify sets duplicates and damaged objects aside, deleting nothing (R9, R10, C4)' {
    It 'reports a second copy, and -RepairStorage moves it into Verify while every state still restores' {
        $s = New-Store 'dups'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-08-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-08-02T10:00:00' | Should -Be 0
        # An older engine could leave the same content in two folders.
        $alpha = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        $snap = Join-Path $s.Chg 'Snapshot_2026_08_01_10_00_00'
        Copy-Item -LiteralPath $alpha.FullName -Destination $snap
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'DuplicateObject'
        $found[0].Path | Should -BeLike "$snap*"
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 1
        Test-Path -LiteralPath (Join-Path $s.Chg "Verify\Snapshot_2026_08_01_10_00_00\$($alpha.Name)") | Should -BeTrue
        @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg).Count | Should -Be 0
        Format-State (Get-StateContent $s $snap) | Should -Be 'a.txt=alpha;b.txt=bravo'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo-2'
    }
    It 'reports a second copy in a folder whose kit is older than revision 4, but does not move it' {
        $s = New-Store 'dups-oldkit'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-08-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-08-02T10:00:00' | Should -Be 0
        $alpha = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        $snap = Join-Path $s.Chg 'Snapshot_2026_08_01_10_00_00'
        Copy-Item -LiteralPath $alpha.FullName -Destination $snap
        $kit = Join-Path $snap 'RECONSTRUCT.ps1'
        [IO.File]::WriteAllText($kit, ([IO.File]::ReadAllText($kit) -replace '# KitRevision: \d+', '# KitRevision: 3'))
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $found.Count | Should -Be 1
        $found[0].Repairable | Should -BeFalse
        $found[0].Observed | Should -Match 'RefreshKits'
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 0
        Test-Path -LiteralPath (Join-Path $snap $alpha.Name) | Should -BeTrue
    }
    It 'keeps the good copy when the preferred one is damaged (-Deep)' {
        $s = New-Store 'damaged'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-08-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-08-02T10:00:00' | Should -Be 0
        $alpha = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        $snap = Join-Path $s.Chg 'Snapshot_2026_08_01_10_00_00'
        Copy-Item -LiteralPath $alpha.FullName -Destination $snap
        [IO.File]::WriteAllText($alpha.FullName, 'alphX')       # same length, wrong bytes
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep)
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'DamagedObject'
        $found[0].Path | Should -Be $alpha.FullName
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 1
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo-2'
    }
}

Describe 'Verify and prune work on what the bounded run writes (R6, SR-045, SR-049)' {
    BeforeAll {
        function New-ChurnedStore([string]$Name) {
            # Edits, a removal and a re-add of content that by then lives only
            # in a snapshot: the shapes that leave DataPaths stale.
            $s = New-Store $Name
            Set-SourceFile $s 'keep.txt' 'keep'
            Set-SourceFile $s 'edit.txt' 'edit-1'
            Set-SourceFile $s 'gone.txt' 'gone'
            # Unchanged through two runs, then removed: its object ends up only
            # in the NEWEST snapshot while the oldest still needs it, through a
            # DataPath that went stale - pruning the newest must re-home it.
            Set-SourceFile $s 'stable.txt' 'stable'
            Invoke-Run $s '2026-09-01T10:00:00' | Should -Be 0
            Set-SourceFile $s 'edit.txt' 'edit-2'
            Remove-Item -LiteralPath (Join-Path $s.Src 'gone.txt')
            Invoke-Run $s '2026-09-02T10:00:00' | Should -Be 0
            Set-SourceFile $s 'back\gone-again.txt' 'gone'
            Set-SourceFile $s 'edit.txt' 'edit-3'
            Remove-Item -LiteralPath (Join-Path $s.Src 'stable.txt')
            Invoke-Run $s '2026-09-03T10:00:00' | Should -Be 0
            return $s
        }
    }
    It 'verifies clean: no storage-form, pool or object finding' {
        $s = New-ChurnedStore 'verify-clean'
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
        @(Test-PoolResolves -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
        @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep) | Should -BeNullOrEmpty
    }
    It 'prunes the <Which> snapshot, and every remaining state still restores' -ForEach @(
        @{ Which = 'oldest'; Index = 0 }, @{ Which = 'newest'; Index = 1 }
    ) {
        $s = New-ChurnedStore "prune-$Which"
        $names = Get-SnapshotNames $s
        $names.Count | Should -Be 2
        $before = @{}
        foreach ($n in $names) { $before[$n] = Format-State (Get-StateContent $s (Join-Path $s.Chg $n)) }
        $latest = Format-State (Get-StateContent $s $s.Bkp)
        $result = @(Remove-BackupSnapshot -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Name $names[$Index] -Confirm:$false)
        "$($result[0].Status)/$($result[0].Code)" | Should -Be 'Pruned/0' -Because ($result | ConvertTo-Json -Depth 4)
        foreach ($n in $names | Where-Object { $_ -ne $names[$Index] }) {
            Format-State (Get-StateContent $s (Join-Path $s.Chg $n)) | Should -Be $before[$n]
        }
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be $latest
    }
}

Describe 'Refusals need a person (2); a held lock is retry later (4) (plan §6)' {
    It 'refuses a set whose source is missing with 2' {
        $s = New-Store 'nosrc'
        Remove-Item -LiteralPath $s.Src -Recurse
        Invoke-Run $s '2026-07-01T10:00:00' | Should -Be 2
    }
    It 'refuses a damaged latest manifest with 2 and changes nothing' {
        $s = New-Store 'garbage'
        Set-SourceFile $s 'a.txt' 'alpha'
        [IO.File]::WriteAllText((Join-Path $s.Bkp 'MANIFEST.csv'), "not,a,manifest`r`n1,2,3`r`n")
        Invoke-Run $s '2026-07-01T10:00:00' | Should -Be 2
        [IO.File]::ReadAllText((Join-Path $s.Bkp 'MANIFEST.csv')) | Should -Match 'not,a,manifest'
    }
    It 'returns 4 and touches nothing while another holder has the lock' {
        $s = New-Store 'held'
        Set-SourceFile $s 'a.txt' 'alpha'
        $lock = Enter-StagingOsLock -ChgPath $s.Chg -Log $null
        try { Invoke-Run $s '2026-07-01T10:00:00' | Should -Be 4 } finally { Exit-StagingOsLock -Lock $lock -Log $null }
        Test-Path -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Should -BeFalse
    }
    It 'refuses a backup and change root that a rename cannot cross (R8)' -Skip:(-not $IsWindows) {
        $s = New-Store 'twomounts'
        $letter = @('Q', 'P', 'O', 'N', 'M', 'L', 'K') | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
        cmd /c "subst ${letter}: `"$($s.Chg)`"" | Out-Null
        try {
            { Assert-SingleStoreMount -BackupRoot $s.Bkp -ChangeRoot "${letter}:\" } | Should -Throw '*one volume and one mount*'
            { Assert-SingleStoreMount -BackupRoot $s.Bkp -ChangeRoot $s.Chg } | Should -Not -Throw
        } finally { cmd /c "subst ${letter}: /d" | Out-Null }
    }
}
}
