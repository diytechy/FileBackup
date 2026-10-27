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

Describe 'A prune''s staged copy is never taken for an object (review 2026-10-26 A3)' {
    # A prune killed while re-homing content into the backup root leaves
    # '<object>.fbprune.tmp' there (Copy-ReHomedDataFile), possibly partial,
    # and the SR-069 grammar accepts '.txt.fbprune.tmp' as an extension.
    BeforeEach {
        $script:s = New-Store "residue-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-03-01T10:00:00' | Should -Be 0
        Remove-Item -LiteralPath (Join-Path $s.Src 'b.txt')
        Invoke-Run $s '2026-03-02T10:00:00' | Should -Be 0
        $snap = Join-Path $s.Chg 'Snapshot_2026_03_01_10_00_00'
        $script:bravo = @(Get-ChildItem -LiteralPath $snap -File | Where-Object { ConvertFrom-StoredObjectName -Name $_.Name })[0]
        $bravo | Should -Not -BeNullOrEmpty -Because 'the fixture needs bravo''s only copy in the snapshot'
        # The half-written copy a kill leaves: the first bytes only.
        $script:residue = Join-Path $s.Bkp "$($bravo.Name).fbprune.tmp"
        [IO.File]::WriteAllText($residue, 'bra')
    }
    It 'does not index a prune staged copy as an object (review 2026-10-26 A3)' {
        $index = Get-StoreObjectIndex -BackupRoot $s.Bkp -ChangeRoot $s.Chg
        $prefix = (ConvertFrom-StoredObjectName -Name $bravo.Name).Prefix
        $index.Objects[$prefix].Path | Should -Be $bravo.FullName
        @(@($index.Objects.Values) + @($index.Duplicates) | Where-Object Name -like '*.fbprune.tmp').Count | Should -Be 0
        @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg).Count | Should -Be 0 -Because 'the staged copy is no second copy of anything'
        Test-Path -LiteralPath $residue | Should -BeTrue -Because 'residue is left for the prune sweep, never deleted by its suffix'
    }
    It 'records re-added content against the object, not a prune staged copy (review 2026-10-26 A3)' {
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-03-03T10:00:00' | Should -Be 0
        $row = @(Read-Manifest -FolderPath $s.Bkp | Where-Object RelativePath -eq 'b.txt')[0]
        $row.DataPath | Should -Be $bravo.Name
        Get-FileXxHash -FilePath (Join-Path $s.Bkp $row.DataPath) | Should -Be $row.xxH2Hash
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

Describe 'An object a killed run left in the latest state goes back to the snapshot that names it (C10, C12)' {
    It 'heals on the next run that keeps a snapshot, so retention sees every object again' {
        $s = New-Store 'leftover'
        Set-SourceFile $s 'keep.txt' 'keep'
        Set-SourceFile $s 'edit.txt' 'old'
        Invoke-Run $s '2026-05-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'edit.txt' 'new'
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx) if ($st -eq 'BeforeSupersededMove') { throw 'simulated kill' } })
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 4
        Set-EngineVar 'BackupRunTestHook' $null
        $snap = Join-Path $s.Chg 'Snapshot_2026_05_01_10_00_00'
        $old = @((Get-PoolObject $s).GetEnumerator() | Where-Object { [IO.File]::ReadAllText($_.Value[0]) -eq 'old' })[0]
        $old.Value[0] | Should -BeLike "$($s.Bkp)*" -Because 'the kill came before the superseded move'
        @(Test-PoolResolves -BackupRoot $s.Bkp -ChangeRoot $s.Chg).Count | Should -BeGreaterThan 0 -Because 'retention cannot see the stranded object yet'

        Set-SourceFile $s 'keep.txt' 'keep-2'
        Invoke-Run $s '2026-05-03T10:00:00' | Should -Be 0
        $pool = Get-PoolObject $s
        $pool[$old.Key].Count | Should -Be 1
        $pool[$old.Key][0] | Should -BeLike "$snap*" -Because 'it goes to the snapshot whose own rows name it'
        @(Test-PoolResolves -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
        Format-State (Get-StateContent $s $snap) | Should -Be 'edit.txt=old;keep.txt=keep'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'edit.txt=new;keep.txt=keep-2'
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

Describe 'A source that goes away is no state of the source (plan section 6)' {
    It 'stops with 4 and keeps the latest state when the source root disappears mid-run' {
        $s = New-Store 'src-vanish'
        foreach ($n in 'a', 'b', 'c', 'd') { Set-SourceFile $s "$n.txt" "one-$n" }
        Invoke-Run $s '2026-06-01T10:00:00' | Should -Be 0
        foreach ($n in 'a', 'b', 'c', 'd') { Set-SourceFile $s "$n.txt" "two-$n" }
        $away = "$($s.Src)-unplugged"
        $src = $s.Src
        # The drive goes away after the first file is captured.
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx) if ($st -eq 'AfterFileCaptured' -and (Test-Path -LiteralPath $src)) { Rename-Item -LiteralPath $src -NewName (Split-Path $away -Leaf) } }.GetNewClosure())
        Invoke-Run $s '2026-06-02T10:00:00' | Should -Be 4
        Set-EngineVar 'BackupRunTestHook' $null
        @(Read-Manifest -FolderPath $s.Bkp).Count | Should -Be 4 -Because 'the latest state still lists every file'
        Rename-Item -LiteralPath $away -NewName (Split-Path $src -Leaf)
        Invoke-Run $s '2026-06-03T10:00:00' | Should -Be 0
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=two-a;b.txt=two-b;c.txt=two-c;d.txt=two-d'
    }
    It 'keeps every earlier row when the source root cannot be listed, and reports 1' -Skip:(-not $IsWindows) {
        $s = New-Store 'src-denied'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'sub\b.txt' 'bravo'
        Invoke-Run $s '2026-06-04T10:00:00' | Should -Be 0
        icacls $s.Src /deny "${env:USERNAME}:(OI)(CI)(RD)" | Out-Null
        try {
            Invoke-Run $s '2026-06-05T10:00:00' | Should -Be 1
        } finally {
            icacls $s.Src /remove:d "${env:USERNAME}" | Out-Null
        }
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;sub\b.txt=bravo'
    }
}

Describe 'Setting aside an unneeded snapshot never fails a finished run (SR-100)' {
    It 'keeps the snapshot whole, and reports 0, when it cannot be set aside' {
        $s = New-Store 'unneeded-held'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-07-01T10:00:00' | Should -Be 0
        $snap = Join-Path $s.Chg 'Snapshot_2026_07_01_10_00_00'
        $held = [ref]$null
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx)
            if ($st -eq 'AfterFinalManifest') { $held.Value = [IO.File]::Open((Join-Path $snap 'MANIFEST.csv'), 'Open', 'Read', 'None') }
        }.GetNewClosure())
        try {
            Invoke-Run $s '2026-07-02T10:00:00' | Should -Be 0 -Because 'the run finished; the snapshot is only redundant'
        } finally {
            Set-EngineVar 'BackupRunTestHook' $null
            if ($held.Value) { $held.Value.Dispose() }
        }
        Test-Path -LiteralPath (Join-Path $snap 'MANIFEST.csv') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $snap 'RECONSTRUCT.ps1') | Should -BeTrue
        Format-State (Get-StateContent $s $snap) | Should -Be 'a.txt=alpha'
        @(Get-ChildItem -LiteralPath $s.Chg -Directory | Where-Object Name -like 'Building_*').Count | Should -Be 0
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
        if (-not (Test-Path -LiteralPath (Get-FileBackupDefaults).SevenZipDefaultPath -PathType Leaf)) { Set-ItResult -Skipped -Because '-Deep needs 7-Zip'; return }
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
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath)
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'DamagedObject'
        $found[0].Path | Should -Be $alpha.FullName
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 1
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo-2'
    }
}

Describe 'Verify moves nothing aside on missing evidence (R9, C4)' {
    BeforeAll { $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath }
    It 'refuses -Deep without 7-Zip before any object is judged' {
        $s = New-Store 'deep-no7z'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-09-01T10:00:00' | Should -Be 0
        { Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $null } | Should -Throw -ExpectedMessage '*needs 7-Zip*'
    }
    It 'reports an archive that will not expand as unverified, and does not move it' {
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $s = New-Store 'deep-unexpandable'
        $s.Set.CompressEnabled = $true
        Set-SourceFile $s 'big.txt' ('COMPRESSIBLE ' * 2000)
        $logs = [System.Collections.Generic.List[string]]::new()
        Invoke-BackupSet -Set $s.Set -Deps @{ '7z' = $sevenZip; ffprobe = $null } -LogPaths $logs -BackupTime ([datetime]'2026-09-02T10:00:00') | Should -Be 0
        $archive = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object Name -like '*.7z')[0]
        $archive | Should -Not -BeNullOrEmpty -Because 'the fixture needs a stored archive'
        # Bytes 7-Zip cannot open, at the archive's own length: as a corrupt
        # archive or a full scratch volume looks from here.
        $len = $archive.Length
        [IO.File]::WriteAllBytes($archive.FullName, [byte[]]::new($len))
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $sevenZip)
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'UnverifiedObject'
        $found[0].Repairable | Should -BeFalse
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 0
        Test-Path -LiteralPath $archive.FullName | Should -BeTrue
    }
    It 'reports an intact archive as unverified when its expanded bytes cannot be written (a full volume)' -Skip:(-not $IsWindows) {
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $s = New-Store 'deep-noscratch'
        $s.Set.CompressEnabled = $true
        Set-SourceFile $s 'big.txt' ('COMPRESSIBLE ' * 2000)
        $logs = [System.Collections.Generic.List[string]]::new()
        Invoke-BackupSet -Set $s.Set -Deps @{ '7z' = $sevenZip; ffprobe = $null } -LogPaths $logs -BackupTime ([datetime]'2026-09-04T10:00:00') | Should -Be 0
        # The scratch folder refuses writes, as a full backup volume would; the
        # caller's error preference is Continue, as at an interactive prompt.
        $scratch = Join-Path $s.Chg 'Verify\.expand'
        New-Item -ItemType Directory -Path $scratch -Force | Out-Null
        icacls $scratch /deny "${env:USERNAME}:(OI)(CI)(W)" | Out-Null
        try {
            $ErrorActionPreference = 'Continue'
            $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $sevenZip 2>$null)
        } finally {
            icacls $scratch /remove:d "${env:USERNAME}" | Out-Null
        }
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'UnverifiedObject' -Because 'no comparison was completed, so nothing is evidence of damage'
        $found[0].Repairable | Should -BeFalse
    }
}

Describe 'A run says where its time went (plan C29)' {
    It 'logs step timings, the work per kind of read, and one metrics JSON line' {
        $s = New-Store 'metrics'
        foreach ($i in 1..4) { Set-SourceFile $s "f$i.txt" "one-$i" }
        Invoke-Run $s '2026-10-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'f1.txt' 'two-1'
        Invoke-Run $s '2026-10-02T10:00:00' | Should -Be 0
        $log = Get-Content -LiteralPath (Join-Path $s.Chg 'backup.log')
        $timings = @($log | Where-Object { $_ -match '\[INFO\] Timings: ' })
        $timings.Count | Should -Be 1
        foreach ($step in 'read latest state', 'index the store', 'publish snapshot', 'walk source', 'capture files', 'finish latest state', 'move superseded') {
            $timings[0] | Should -Match ([regex]::Escape($step))
        }
        @($log | Where-Object { $_ -match '\[INFO\] Work: unchanged, not read 3; copy while hashing \(new or changed\) 1' }).Count | Should -Be 1
        $line = @($log | Where-Object { $_ -match '\[INFO\] metrics \{' })[0]
        $doc = $line.Substring($line.IndexOf('metrics ') + 8) | ConvertFrom-Json
        $doc.kept | Should -Be 3
        $doc.files | Should -Be 4
        $doc.steps.'capture files' | Should -BeGreaterOrEqual 0
        $doc.ops.'copy while hashing (new or changed)'.count | Should -Be 1
    }
}

Describe 'A store drive that is missing, or a store that lost its backup folder (plan C25, C26)' {
    It 'returns 4 and writes nothing when the backup drive is not attached' -Skip:(-not $IsWindows) {
        $letter = @([char[]](90..68) | Where-Object { -not (Test-Path -LiteralPath "$($_):\") })[0]
        if (-not $letter) { Set-ItResult -Skipped -Because 'no free drive letter'; return }
        $s = New-Store 'nodrive'
        Set-SourceFile $s 'a.txt' 'alpha'
        $s.Set.BackupPath = "$($letter):\FileBackup\Backup"
        $s.Set.ChangePath = "$($letter):\FileBackup\Changes"
        Invoke-Run $s '2026-10-03T10:00:00' 3>$null | Should -Be 4
        Test-Path -LiteralPath "$($letter):\" | Should -BeFalse
    }
    It 'refuses with 2, creating nothing, when the backup folder is gone but its snapshots are not' {
        $s = New-Store 'lostbackup'
        Set-SourceFile $s 'a.txt' 'alpha'
        Invoke-Run $s '2026-10-04T10:00:00' | Should -Be 0
        Set-SourceFile $s 'a.txt' 'alpha-2'
        Invoke-Run $s '2026-10-05T10:00:00' | Should -Be 0
        @(Get-SnapshotNames $s).Count | Should -Be 1
        Rename-Item -LiteralPath $s.Bkp -NewName 'Backup-moved-away'
        Invoke-Run $s '2026-10-06T10:00:00' 3>$null | Should -Be 2
        Test-Path -LiteralPath $s.Bkp | Should -BeFalse -Because 'a fresh full backup must not start beside the old snapshots'
    }
}

Describe 'A source that empties during the run stops it (plan C27)' {
    It 'stops with 4 and keeps the latest state when every file vanishes but the root folder stays' {
        $s = New-Store 'src-emptied'
        foreach ($n in 'a', 'b', 'c') { Set-SourceFile $s "$n.txt" "one-$n" }
        Set-SourceFile $s 'sub\d.txt' 'one-d'
        Invoke-Run $s '2026-10-07T10:00:00' | Should -Be 0
        foreach ($n in 'a', 'b', 'c') { Set-SourceFile $s "$n.txt" "two-$n" }
        $src = $s.Src
        # The mount drops after the first file: the mount point stays, empty.
        Set-EngineVar 'BackupRunTestHook' ({ param($st, $ctx)
            if ($st -eq 'AfterFileCaptured' -and @(Get-ChildItem -LiteralPath $src -Force).Count -gt 0) {
                Get-ChildItem -LiteralPath $src -Force | Remove-Item -Recurse -Force
            }
        }.GetNewClosure())
        Invoke-Run $s '2026-10-08T10:00:00' | Should -Be 4
        Set-EngineVar 'BackupRunTestHook' $null
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=one-a;b.txt=one-b;c.txt=one-c;sub\d.txt=one-d'
    }
}

Describe 'A repair confirms the copy it keeps before setting a duplicate aside (plan C28)' {
    It 'reports the cost on a plain Verify, and leaves a duplicate in place when the kept copy is damaged' {
        $s = New-Store 'dup-badkeeper'
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-10-09T10:00:00' | Should -Be 0
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-10-10T10:00:00' | Should -Be 0
        $alpha = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        $snap = Join-Path $s.Chg 'Snapshot_2026_10_09_10_00_00'
        Copy-Item -LiteralPath $alpha.FullName -Destination $snap
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $cost = Measure-DuplicateRepairCost -Finding $found
        "$($cost.Copies)|$($cost.Contents)|$($cost.ConfirmCount)|$($cost.ConfirmBytes)" | Should -Be "1|1|1|$($alpha.Length)"

        # The copy kept rots (same length, wrong bytes): the duplicate is the
        # only good copy left, and a restore heals from it - so it stays.
        [IO.File]::WriteAllText($alpha.FullName, 'alphX')
        $lines = [System.Collections.Generic.List[string]]::new()
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { param($m, $l) $lines.Add("[$l] $m") }.GetNewClosure() | Should -Be 0
        Test-Path -LiteralPath (Join-Path $snap $alpha.Name) | Should -BeTrue
        ($lines -join "`n") | Should -Match 'left .* in place: the copy kept'
        ($lines -join "`n") | Should -Match 'Confirmed 1 kept cop'
    }
}

Describe 'Setting objects aside holds the OS lock, and -WhatIf moves nothing (review 2026-10-26 A5)' {
    # The same content in two folders, as an older engine could leave it: the
    # backup root's copy is kept, the snapshot's is the duplicate.
    BeforeEach {
        $script:s = New-Store "aside-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-04-01T10:00:00' | Should -Be 0
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-04-02T10:00:00' | Should -Be 0
        $alpha = @(Get-ChildItem -LiteralPath $s.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        Copy-Item -LiteralPath $alpha.FullName -Destination (Join-Path $s.Chg 'Snapshot_2026_04_01_10_00_00')
        $script:dup = Join-Path $s.Chg "Snapshot_2026_04_01_10_00_00\$($alpha.Name)"
    }
    It 'refuses before anything moves while another holder has the lock (review 2026-10-26 A5)' {
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $found.Count | Should -Be 1
        $holder = Enter-StagingOsLock -ChgPath $s.Chg -Log $null
        try {
            { Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } } | Should -Throw -ExpectedMessage '*lock-held*'
        } finally { Exit-StagingOsLock -Lock $holder -Log $null }
        Test-Path -LiteralPath $dup | Should -BeTrue -Because 'nothing may move while a backup or prune holds the lock'
        Test-Path -LiteralPath (Join-Path $s.Chg 'Verify') | Should -BeFalse
    }
    It 'moves nothing under -WhatIf, takes no lock, and says what it would move (review 2026-10-26 A5)' {
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $lines = [System.Collections.Generic.List[string]]::new()
        $holder = Enter-StagingOsLock -ChgPath $s.Chg -Log $null
        try {
            Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { param($m, $l) $lines.Add("[$l] $m") }.GetNewClosure() -WhatIf |
                Should -Be 0
        } finally { Exit-StagingOsLock -Lock $holder -Log $null }
        Test-Path -LiteralPath $dup | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $s.Chg 'Verify') | Should -BeFalse
        ($lines -join "`n") | Should -Match ([regex]::Escape("would move '$dup'"))
    }
    It 'leaves a duplicate in place when the copy kept is gone by the time it holds the lock (review 2026-10-26 A5)' {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '-Deep needs 7-Zip'; return }
        # -Deep proved the copy kept during the audit, so the repair does not
        # read it again; a prune that ran after the audit then deleted it.
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $sevenZip)
        $found.Count | Should -Be 1
        $found[0].KeptVerified | Should -BeTrue
        Remove-Item -LiteralPath $found[0].Kept.Path
        $lines = [System.Collections.Generic.List[string]]::new()
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -SevenZipPath $sevenZip -Log { param($m, $l) $lines.Add("[$l] $m") }.GetNewClosure() |
            Should -Be 0
        Test-Path -LiteralPath $dup | Should -BeTrue -Because 'it is now the only copy of that content'
        ($lines -join "`n") | Should -Match 'is no longer where the audit found it'
    }
}

Describe 'An object a power loss left damaged is set aside, never reused (review 2026-10-26 G1)' {
    # A power loss after an object was renamed to its content name, before its
    # bytes reached the disk, leaves it empty (ext4) or torn. The run used to
    # index it by name and reuse it for every unchanged file, forever.
    BeforeAll {
        function Get-AlphaObject {
            param($Store)
            @(Get-ChildItem -LiteralPath $Store.Bkp -File | Where-Object { (ConvertFrom-StoredObjectName -Name $_.Name) -and
                (Get-Content -LiteralPath $_.FullName -Raw) -eq 'alpha' })[0]
        }
        function Get-RunLog { param($Store) Get-Content -LiteralPath (Join-Path $Store.Chg 'backup.log') }
        function Get-RunMetricDoc {
            param($Store)
            $line = @(Get-RunLog $Store | Where-Object { $_ -match '\[INFO\] metrics \{' })[-1]
            $line.Substring($line.IndexOf('metrics ') + 8) | ConvertFrom-Json
        }
    }
    BeforeEach {
        $script:s = New-Store "g1-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Set-SourceFile $s 'a.txt' 'alpha'
        Set-SourceFile $s 'b.txt' 'bravo'
        Invoke-Run $s '2026-05-01T10:00:00' | Should -Be 0
        $script:alpha = Get-AlphaObject $s
        $alpha | Should -Not -BeNullOrEmpty
        $script:aside = Join-Path $s.Chg "Verify\$([IO.Path]::GetFileName($s.Bkp))\$($alpha.Name)"
    }

    It 'sets a zero-length object aside into Verify and stores the content again (review 2026-10-26 G1)' {
        [IO.File]::WriteAllBytes($alpha.FullName, [byte[]]@())
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 1 -Because 'a damaged object set aside must be seen'
        (Get-Item -LiteralPath $aside).Length | Should -Be 0 -Because 'the damaged file is kept in Verify, never deleted (R9)'
        [IO.File]::ReadAllText($alpha.FullName) | Should -Be 'alpha' -Because 'the unchanged source content is stored again under its name'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo'
        $log = Get-RunLog $s
        @($log | Where-Object { $_ -match '\[WARN\] \[DamagedObject\] ' -and $_ -match [regex]::Escape($alpha.Name) }).Count | Should -Be 1
        @($log | Where-Object { $_ -match '\[WARN\] Set aside 1 of 1 damaged stored object' -and $_ -match 'reports 1' }).Count | Should -Be 1
        (Get-RunMetricDoc $s).damagedSetAside | Should -Be 1
        Invoke-Run $s '2026-05-03T10:00:00' | Should -Be 0 -Because 'the store is whole again'
    }

    It 'sets a truncated raw object aside and stores the content again (review 2026-10-26 G1)' {
        [IO.File]::WriteAllText($alpha.FullName, 'alp')
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 1
        [IO.File]::ReadAllText($aside) | Should -Be 'alp'
        [IO.File]::ReadAllText($alpha.FullName) | Should -Be 'alpha'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo'
    }

    It 'leaves an older engine''s mislabelled archive alone (review 2026-10-26 G1)' {
        # Archive bytes under a raw name, of another length than the content:
        # the restorers read its form from its bytes (SR-068), so it is no damage.
        $archive = [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4, 1, 2, 3, 4, 5, 6, 7, 8)
        [IO.File]::WriteAllBytes($alpha.FullName, $archive)
        $index = Get-StoreObjectIndex -BackupRoot $s.Bkp -ChangeRoot $s.Chg
        $index.Damaged.Count | Should -Be 0
        $index.Objects[(ConvertFrom-StoredObjectName -Name $alpha.Name).Prefix].Path | Should -Be $alpha.FullName
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 0
        Test-Path -LiteralPath (Join-Path $s.Chg 'Verify') | Should -BeFalse
        [System.Linq.Enumerable]::SequenceEqual([IO.File]::ReadAllBytes($alpha.FullName), $archive) | Should -BeTrue
    }

    It 'judges a .7z name by its length only when it is empty (review 2026-10-26 G1)' {
        $prefix = Get-StoredObjectPrefix -HashHex ('AB' * 16) -Length 1000
        $short = Join-Path $s.Bkp "$prefix.7z"
        [IO.File]::WriteAllText($short, 'not 1000 bytes, and no archive signature either')
        $emptyPrefix = Get-StoredObjectPrefix -HashHex ('CD' * 16) -Length 1000
        $empty = Join-Path $s.Bkp "$emptyPrefix.7z"
        [IO.File]::WriteAllBytes($empty, [byte[]]@())
        $index = Get-StoreObjectIndex -BackupRoot $s.Bkp -ChangeRoot $s.Chg
        $index.Objects[$prefix].Path | Should -Be $short -Because 'a .7z of nonzero length is never judged by its length'
        @($index.Damaged | ForEach-Object Path) | Should -Be @($empty)
        $index.Objects.ContainsKey($emptyPrefix) | Should -BeFalse
    }

    It 'gives changed content its own name and does not rewrite the damaged history (review 2026-10-26 G1)' {
        [IO.File]::WriteAllBytes($alpha.FullName, [byte[]]@())
        Set-SourceFile $s 'a.txt' 'alpha-2'
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 1
        Test-Path -LiteralPath $aside | Should -BeTrue
        (Get-PoolObject $s).ContainsKey($alpha.Name) | Should -BeFalse -Because 'only bytes that hash to a name ever land at it, and no source holds alpha any more'
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha-2;b.txt=bravo'
        $snapRow = @(Read-Manifest -FolderPath (Join-Path $s.Chg 'Snapshot_2026_05_01_10_00_00') | Where-Object RelativePath -eq 'a.txt')[0]
        $snapRow.DataPath | Should -Be $alpha.Name -Because 'the snapshot keeps its record of the content it had'
    }

    It 'sets a damaged object in a snapshot aside into Verify/<snapshot> (review 2026-10-26 G1)' {
        Set-SourceFile $s 'b.txt' 'bravo-2'
        Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 0
        $snap = Join-Path $s.Chg 'Snapshot_2026_05_01_10_00_00'
        $bravo = @(Get-ChildItem -LiteralPath $snap -File | Where-Object { ConvertFrom-StoredObjectName -Name $_.Name })[0]
        [IO.File]::ReadAllText($bravo.FullName) | Should -Be 'bravo' -Because 'the fixture needs bravo''s only copy in the snapshot'
        [IO.File]::WriteAllBytes($bravo.FullName, [byte[]]@())
        Invoke-Run $s '2026-05-03T10:00:00' | Should -Be 1
        Test-Path -LiteralPath (Join-Path $s.Chg "Verify\Snapshot_2026_05_01_10_00_00\$($bravo.Name)") | Should -BeTrue
        Test-Path -LiteralPath $bravo.FullName | Should -BeFalse
        Format-State (Get-StateContent $s $s.Bkp) | Should -Be 'a.txt=alpha;b.txt=bravo-2'
    }

    It 'reports a zero-length object on a plain Verify, and -RepairStorage moves it (review 2026-10-26 G1)' {
        [IO.File]::WriteAllBytes($alpha.FullName, [byte[]]@())
        $found = @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        $found.Count | Should -Be 1
        $found[0].Class | Should -Be 'DamagedObject'
        $found[0].Path | Should -Be $alpha.FullName
        $found[0].Observed | Should -Match 'empty'
        $found[0].Repairable | Should -BeTrue
        Move-StoreObjectToVerify -Finding $found -ChangeRoot $s.Chg -Log { } | Should -Be 1
        Test-Path -LiteralPath $aside | Should -BeTrue
    }

    It 'does not take a damaged object it could not set aside for the content it names (review 2026-10-26 G1)' -Skip:(-not $IsWindows) {
        [IO.File]::WriteAllText($alpha.FullName, 'alp')
        Set-EngineVar 'RetryMinSpacingSeconds' 0
        # Open without delete sharing, so the object cannot be moved (Windows).
        $hold = [IO.File]::Open($alpha.FullName, 'Open', 'Read', 'Read')
        try {
            Invoke-Run $s '2026-05-02T10:00:00' | Should -Be 1
        } finally { $hold.Dispose() }
        $log = Get-RunLog $s
        @($log | Where-Object { $_ -match 'could not be moved into Verify' }).Count | Should -Be 1
        @($log | Where-Object { $_ -match "\[WARN\] Not capturing 'a\.txt'" -and $_ -match 'is damaged' }).Count | Should -Be 1 `
            -Because 'the good copy is not dropped in favour of the damaged one; the file is warned about instead'
        [IO.File]::ReadAllText($alpha.FullName) | Should -Be 'alp'
    }
}

Describe 'An archive exactly as long as its content (plan C30)' {
    It 'is stored raw instead, so its listing cannot be mistaken' {
        $root = Join-Path $TestDrive 'eqlen-write'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $staged = Join-Path $root 'staged'
        [IO.File]::WriteAllText($staged, 'EXACTLY-AS-LONG')
        $len = (Get-Item -LiteralPath $staged).Length
        $hash = Get-FileXxHash -FilePath $staged
        $set = [pscustomobject]@{ Name = 'E'; CompressEnabled = $true; CompressProbe = 'off' }
        $stored = InModuleScope FileBackup.Engine -Parameters @{ Staged = $staged; Len = $len; Hash = $hash; Root = $root; Set = $set } {
            param($Staged, $Len, $Hash, $Root, $Set)
            $Stats = New-ProbeStatistic
            # An "archive" that comes out exactly as long as the content.
            Mock Compress-FileWithSevenZip { param($SevenZipPath, $SourceFile, $Destination7z) [IO.File]::WriteAllBytes($Destination7z, [byte[]]::new((Get-Item -LiteralPath $SourceFile).Length)) }
            Mock Resolve-GroupStorageForm { [pscustomobject]@{ Compress = $true; Reason = 'ListSaysCompress'; SampledBytes = 0; Ratio = $null; Windows = @() } }
            Publish-StagedObject -StagedPath $Staged -SourceName 'note.txt' -Hash $Hash -Length $Len -BackupRoot $Root -Set $Set `
                -SevenZipPath 'C:\fake\7z.exe' -ProbeStats $Stats -Metrics $null -Log { }
        }
        $stored.Compressed | Should -Be 'No'
        $stored.Name | Should -BeLike '*.txt'
        [IO.File]::ReadAllText((Join-Path $root $stored.Name)) | Should -Be 'EXACTLY-AS-LONG'
    }
    It 'is expanded by Verify before it is called damaged' {
        $root = Join-Path $TestDrive 'eqlen-verify'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $content = Join-Path $root 'content.bin'
        [IO.File]::WriteAllText($content, 'THE-REAL-CONTENT-OF-THIS-OBJECT')
        $len = (Get-Item -LiteralPath $content).Length
        $name = Get-HashSizeFileName -HashHex (Get-FileXxHash -FilePath $content) -Length $len -Extension '.7z'
        # An archive-shaped object as long as its content: 7-Zip's signature,
        # then padding. Expanding it (mocked) yields the real content.
        $obj = Join-Path $root $name
        $bytes = [byte[]]::new($len); ([byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C)).CopyTo($bytes, 0)
        [IO.File]::WriteAllBytes($obj, $bytes)
        $entry = [pscustomobject]@{ Name = $name; Path = $obj; FileLength = $len; ContentLength = $len; Extension = '.7z' }
        $verdict = InModuleScope FileBackup.Engine -Parameters @{ Entry = $entry; Content = $content; Scratch = (Join-Path $root 'scratch') } {
            param($Entry, $Content, $Scratch)
            Mock Expand-FileWithSevenZip { param($SevenZipPath, $Archive, $DestinationFile) Copy-Item -LiteralPath $Content -Destination $DestinationFile }
            Get-StoredObjectVerdict -Entry $Entry -ScratchFolder $Scratch -SevenZipPath 'C:\fake\7z.exe'
        }
        $verdict.Verdict | Should -Be 'Good'
    }
}

Describe 'Expanding an archive never needs the system temp folder (plan C31)' {
    It 'expands beside the destination even when the system temp cannot be written' -Skip:(-not $IsWindows) {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $root = Join-Path $TestDrive 'expand-beside'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $src = Join-Path $root 'in.txt'
        [IO.File]::WriteAllText($src, ('PAYLOAD ' * 500))
        $archive = Join-Path $root 'in.7z'
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $src -Destination7z $archive
        # TMP and TEMP name a FILE, so nothing can be created under the system
        # temp folder: an expand that used it would fail here.
        $blocker = Join-Path $root 'not-a-folder'
        [IO.File]::WriteAllText($blocker, 'x')
        $saved = $env:TMP, $env:TEMP
        try {
            $env:TMP = $blocker; $env:TEMP = $blocker
            Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $archive -DestinationFile (Join-Path $root 'out\out.txt')
        } finally {
            $env:TMP, $env:TEMP = $saved
        }
        [IO.File]::ReadAllText((Join-Path $root 'out\out.txt')) | Should -Be ('PAYLOAD ' * 500)
        @(Get-ChildItem -LiteralPath (Join-Path $root 'out') -Force).Count | Should -Be 1 -Because 'the hidden expand folder is removed'
    }
}

Describe 'Checks on the backup volume when it is nearly full (plan C33, C34)' {
    BeforeAll {
        $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        function New-CompressedChurn([string]$Name) {
            # Three runs: the third removes gone.txt, so the newest snapshot
            # holds its compressed object and an older one still needs it.
            $s = New-Store $Name
            $s.Set.CompressEnabled = $true
            $deps = @{ '7z' = $script:sevenZip; ffprobe = $null }
            $logs = [System.Collections.Generic.List[string]]::new()
            Set-SourceFile $s 'keep.txt' ('KEEP ' * 400)
            Set-SourceFile $s 'super.txt' ('VERSION-ONE ' * 400)
            Set-SourceFile $s 'gone.txt' ('DOOMED ' * 400)
            Invoke-BackupSet -Set $s.Set -Deps $deps -LogPaths $logs -BackupTime ([datetime]'2026-11-01T10:00:00') | Should -Be 0
            Set-SourceFile $s 'super.txt' ('VERSION-TWO ' * 400)
            Invoke-BackupSet -Set $s.Set -Deps $deps -LogPaths $logs -BackupTime ([datetime]'2026-11-02T10:00:00') | Should -Be 0
            Remove-Item -LiteralPath (Join-Path $s.Src 'gone.txt')
            Invoke-BackupSet -Set $s.Set -Deps $deps -LogPaths $logs -BackupTime ([datetime]'2026-11-03T10:00:00') | Should -Be 0
            return $s
        }
    }
    It 'reports no payload mismatch when an expand cannot complete' {
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $s = New-CompressedChurn 'deep-full'
        Mock -ModuleName FileBackup.Engine Expand-FileWithSevenZip { throw 'No space left on device' }
        $found = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $sevenZip)
        @($found | Where-Object Class -eq 'PayloadMismatch').Count | Should -Be 0 -Because 'no comparison was made'
    }
    It 'counts the largest payload it must expand to verify in the prune space check' {
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $s = New-CompressedChurn 'prune-room'
        $newest = @(Get-SnapshotNames $s)[-1]
        $plan = Get-SnapshotPrunePlan -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Name $newest
        $compressed = @($plan.Items.ToArray() | Where-Object Compressed -eq 'Yes')
        $compressed.Count | Should -BeGreaterThan 0 -Because 'the fixture needs a compressed object to re-home'
        $copies = [long](@($plan.Items.ToArray() | Measure-Object -Property Bytes -Sum).Sum)
        $largest = [long](@($compressed | ForEach-Object { [long]$_.SourceRow.Length } | Measure-Object -Maximum).Maximum)
        Mock -ModuleName FileBackup.Engine Get-VolumeIdentity { 'VOL' }
        $script:free = $copies + $largest - 1
        Mock -ModuleName FileBackup.Engine Get-FreeSpaceBytes { [long]$script:free }
        $refused = @(Assert-PrunePrecondition -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Plan $plan -SevenZipPath $sevenZip)
        @($refused | Where-Object Kind -eq 'capacity').Count | Should -Be 1 -Because 'one byte short of the copies plus the largest expand'
        $script:free = $copies + $largest
        $refused = @(Assert-PrunePrecondition -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Plan $plan -SevenZipPath $sevenZip)
        @($refused | Where-Object Kind -eq 'capacity').Count | Should -Be 0
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
        if (-not (Test-Path -LiteralPath (Get-FileBackupDefaults).SevenZipDefaultPath -PathType Leaf)) { Set-ItResult -Skipped -Because '-Deep needs 7-Zip'; return }
        $s = New-ChurnedStore 'verify-clean'
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
        @(Test-PoolResolves -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
        @(Get-StoreObjectFinding -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath) | Should -BeNullOrEmpty
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
