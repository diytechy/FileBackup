<#
.SYNOPSIS  Pester 5 tests that each file a rename, a commit or a deletion relies
           on is flushed to the disk first (review 2026-10-26 A1; SR-082, SR-101).
.NOTES     A journaling filesystem makes a rename or a deletion durable on its own
           schedule, independently of the data: after a power loss ext4 can return
           a file renamed to a new name as 0 bytes and NTFS one that reads as NULs.
           A test cannot cut the power, so it watches the one function every flush
           goes through, Sync-FileToDisk, through Common's FileSyncTestHook seam:
           which files reach the disk, and that each does so while the rename that
           publishes it has not happened yet. The real flush still runs.

           Other unit files leave kit copies of Common loaded, so the seam is set on
           THIS repo's module, addressed by its path (as ManifestAtomicWrite does).
#>

BeforeAll {
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    Initialize-XxHashLibrary | Out-Null

    $script:CommonModulePath = (Resolve-Path (Join-Path $repo 'Modules\FileBackup.Common.psm1')).Path
    function Set-FileSyncHook {
        param([AllowNull()][scriptblock]$Hook)
        $mod = @(Get-Module FileBackup.Common | Where-Object { $_.Path -eq $script:CommonModulePath })[0]
        & $mod { param($h) $script:FileSyncTestHook = $h } $Hook
    }

    function New-Folder {
        param([string]$Name)
        $dir = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        return $dir
    }

    function New-ManifestRow {
        param([string]$Tag, [int]$Count = 3)
        1..$Count | ForEach-Object {
            [pscustomobject]@{ DataPath = "$Tag-$_.txt"; RelativePath = "$Tag-$_.txt"; Length = $_
                LastWriteTime = (Get-Date '2026-01-02T03:04:05'); xxH2Hash = "H$Tag$_"; Compressed = 'No'
                StoredAsHashSize = 'Hash'; Duplicate = '0'; MediaMBPerSec = '' }
        }
    }

    $script:kitFiles = @('RECONSTRUCT.ps1', 'RECONSTRUCT.cmd', 'RECONSTRUCT.command', 'reconstruct.sh',
                         'FileBackup.Common.psm1', 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')
}

Describe 'Each file is on the disk before the rename that relies on it (review 2026-10-26 A1)' {
    AfterEach { Set-FileSyncHook $null }

    It 'flushes MANIFEST.csv.tmp before renaming it over MANIFEST.csv (review 2026-10-26 A1)' {
        $dir = New-Folder 'manifest'
        Write-Manifest -FolderPath $dir -Records @(New-ManifestRow 'old')
        $dest = Join-Path $dir 'MANIFEST.csv'
        $oldHash = (Get-FileHash -LiteralPath $dest).Hash
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; DestHash = (Get-FileHash -LiteralPath $dest).Hash })
        }.GetNewClosure())
        Write-Manifest -FolderPath $dir -Records @(New-ManifestRow 'new' 5)
        $seen.Count | Should -Be 1 -Because 'the manifest is flushed once per write'
        $seen[0].Path | Should -Be (Join-Path $dir 'MANIFEST.csv.tmp')
        $seen[0].DestHash | Should -Be $oldHash -Because 'the flush comes before the rename over the old manifest'
        (Get-FileHash -LiteralPath $dest).Hash | Should -Not -Be $oldHash
        @(Read-Manifest -FolderPath $dir).Count | Should -Be 5
    }

    It 'flushes the run-state temp file before renaming it over FileBackupState.json (review 2026-10-26 A1)' {
        $dir = New-Folder 'state'
        Set-LastBackupRun -BackupRoot $dir -When ([datetime]'2026-01-01T10:00:00')
        $state = Join-Path $dir 'FileBackupState.json'
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Prior = (Get-Content -LiteralPath $state -Raw) })
        }.GetNewClosure())
        Set-LastBackupRun -BackupRoot $dir -When ([datetime]'2026-01-02T10:00:00')
        $seen.Count | Should -Be 1
        $seen[0].Path | Should -Be "$state.tmp"
        $seen[0].Prior | Should -Match '2026-01-01T10:00:00' -Because 'the flush comes before the rename over the state file'
        Get-LastBackupRun -BackupRoot $dir | Should -Be ([datetime]'2026-01-02T10:00:00')
        Test-Path -LiteralPath "$state.tmp" | Should -BeFalse
    }

    It 'flushes each kit file it writes before its rename, and none of an unchanged kit (review 2026-10-26 A1)' {
        $bkp = New-Folder 'kit\bkp'
        $chg = New-Folder 'kit\chg'
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; DestThere = (Test-Path -LiteralPath ($p -replace '\.tmp$', '')) })
        }.GetNewClosure())
        New-ReconstructScript -BackupRoot $bkp -ChangeRoot $chg
        @($seen | ForEach-Object { [IO.Path]::GetFileName($_.Path) } | Sort-Object) |
            Should -Be @($kitFiles | ForEach-Object { "$_.tmp" } | Sort-Object)
        @($seen | Where-Object DestThere).Count | Should -Be 0 -Because 'each temp file is flushed before it is renamed to its name'
        $seen.Clear()
        New-ReconstructScript -BackupRoot $bkp -ChangeRoot $chg
        $seen.Count | Should -Be 0 -Because 'an unchanged kit is not written at all'
    }

    It 'refreshes a snapshot kit through a flushed temp file, rewriting only what differs (review 2026-10-26 A1)' {
        $bkp = New-Folder 'refresh\bkp'
        $chg = New-Folder 'refresh\chg'
        New-ReconstructScript -BackupRoot $bkp -ChangeRoot $chg
        $snap = New-Folder 'refresh\chg\Snapshot_2026_01_01_10_00_00'
        foreach ($f in $kitFiles) { Copy-Item -LiteralPath (Join-Path $bkp $f) -Destination $snap }
        $old = [datetime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        foreach ($f in $kitFiles) { [IO.File]::SetLastWriteTimeUtc((Join-Path $snap $f), $old) }
        $stale = Join-Path $snap 'RECONSTRUCT.ps1'
        [IO.File]::AppendAllText($stale, "`n# an older kit`n")
        $staleHash = (Get-FileHash -LiteralPath $stale).Hash
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Hash = (Get-FileHash -LiteralPath $stale).Hash })
        }.GetNewClosure())
        $r = Update-BackupSnapshotKit -BackupRoot $bkp -ChangeRoot $chg -Log { param($m, $l) }
        $r.Refreshed | Should -Be 1
        $seen.Count | Should -Be 1 -Because 'only the file that differs is written'
        $seen[0].Path | Should -Be "$stale.tmp"
        $seen[0].Hash | Should -Be $staleHash -Because 'the flush comes before the rename over the old kit file'
        (Get-FileHash -LiteralPath $stale).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $bkp 'RECONSTRUCT.ps1')).Hash
        foreach ($f in $kitFiles | Where-Object { $_ -ne 'RECONSTRUCT.ps1' }) {
            [IO.File]::GetLastWriteTimeUtc((Join-Path $snap $f)) | Should -Be $old -Because "'$f' did not differ, so it is not rewritten"
        }
        @(Get-ChildItem -LiteralPath $snap -File -Force | Where-Object Name -like '*.tmp').Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $snap 'MANIFEST.csv.meta') | Should -BeFalse
    }

    It 'flushes every file of Building_<D> before renaming it to Snapshot_<D> (review 2026-10-26 A1)' {
        $bkp = New-Folder 'snap\bkp'
        $chg = New-Folder 'snap\chg'
        New-ReconstructScript -BackupRoot $bkp -ChangeRoot $chg
        Set-Content -LiteralPath (Join-Path $bkp 'DIRECTORIES.csv') -Value '"RelativePath","Attributes"', '"empty",""'
        $final = Join-Path $chg 'Snapshot_2026_01_01_10_00_00'
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Published = (Test-Path -LiteralPath $final) })
        }.GetNewClosure())
        $r = Publish-PriorStateSnapshot -BackupRoot $bkp -ChangeRoot $chg -PriorDate ([datetime]'2026-01-01T10:00:00') `
                 -PriorRows @(New-ManifestRow 'prior') -Log { param($m, $l) }
        $r.BuiltNow | Should -BeTrue
        @($seen | Where-Object Published).Count | Should -Be 0 -Because 'every flush comes before the rename that publishes the snapshot'
        @($seen | Where-Object { [IO.Path]::GetDirectoryName($_.Path) -ne (Join-Path $chg 'Building_2026_01_01_10_00_00') }).Count |
            Should -Be 0
        $flushed = @($seen | ForEach-Object { [IO.Path]::GetFileName($_.Path) -replace '^MANIFEST\.csv\.tmp$', 'MANIFEST.csv' } | Sort-Object)
        $published = @(Get-ChildItem -LiteralPath $final -File -Force | ForEach-Object Name | Sort-Object)
        $flushed | Should -Be $published -Because 'every file in the snapshot was flushed, the manifest through its temp file'
        $published | Should -Contain 'DIRECTORIES.csv'
    }

    It 'flushes a prune''s staged copy before renaming it to its name (review 2026-10-26 A1)' {
        $from = New-Folder 'prune\Snapshot_2026_01_02_10_00_00'
        $to   = New-Folder 'prune\Snapshot_2026_01_01_10_00_00'
        $content = Join-Path (New-Folder 'prune\content') 'c.txt'
        [IO.File]::WriteAllText($content, 'the last copy of this content')
        $hash = Get-FileXxHash -FilePath $content
        $len  = (Get-Item -LiteralPath $content).Length
        $name = Get-HashSizeFileName -HashHex $hash -Length $len -Extension '.txt'
        Copy-Item -LiteralPath $content -Destination (Join-Path $from $name)
        $item = [pscustomobject]@{
            SourceFullPath = (Join-Path $from $name); SourceDataPath = $name
            DestinationFolder = $to; DestinationDataPath = $name; Compressed = 'No'
            SourceRow = [pscustomobject]@{ RelativePath = 'c.txt'; Length = $len; xxH2Hash = $hash }
        }
        $dest = Join-Path $to $name
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Length = (Get-Item -LiteralPath $p).Length; Published = (Test-Path -LiteralPath $dest) })
        }.GetNewClosure())
        Copy-ReHomedDataFile -Item $item | Should -Be $dest
        $seen.Count | Should -Be 1
        $seen[0].Path | Should -Be "$dest.fbprune.tmp"
        $seen[0].Length | Should -Be $len -Because 'the whole copy is flushed'
        $seen[0].Published | Should -BeFalse -Because 'the flush comes before the rename the prune then relies on to delete the source'
        Get-FileXxHash -FilePath $dest | Should -Be $hash
    }

    It 'flushes a new raw object before renaming it to its content name (review 2026-10-26 O1)' {
        $root = New-Folder 'object-raw'
        $staged = Join-Path $root 'staged'
        [IO.File]::WriteAllText($staged, 'NEW CONTENT, STORED RAW')
        $len  = (Get-Item -LiteralPath $staged).Length
        $hash = Get-FileXxHash -FilePath $staged
        $dest = Join-Path $root (Get-HashSizeFileName -HashHex $hash -Length $len -Extension '.txt')
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Length = (Get-Item -LiteralPath $p).Length; Named = (Test-Path -LiteralPath $dest) })
        }.GetNewClosure())
        $set = [pscustomobject]@{ Name = 'O'; CompressEnabled = $false; CompressProbe = 'off' }
        $stored = InModuleScope FileBackup.Engine -Parameters @{ Staged = $staged; Len = $len; Hash = $hash; Root = $root; Set = $set } {
            param($Staged, $Len, $Hash, $Root, $Set)
            Publish-StagedObject -StagedPath $Staged -SourceName 'note.txt' -Hash $Hash -Length $Len -BackupRoot $Root -Set $Set `
                -SevenZipPath $null -ProbeStats (New-ProbeStatistic) -Metrics $null -Log { }
        }
        $stored.Compressed | Should -Be 'No'
        $seen.Count | Should -Be 1
        $seen[0].Path | Should -Be $staged -Because 'the staged copy itself becomes the object'
        $seen[0].Length | Should -Be $len
        $seen[0].Named | Should -BeFalse -Because 'the flush comes before the rename that names the object'
        [IO.File]::ReadAllText($dest) | Should -Be 'NEW CONTENT, STORED RAW'
    }

    It 'flushes a new archive object before renaming it to its content name (review 2026-10-26 O1)' {
        $root = New-Folder 'object-7z'
        $staged = Join-Path $root 'staged'
        [IO.File]::WriteAllText($staged, 'NEW CONTENT, STORED AS AN ARCHIVE ' * 20)
        $len  = (Get-Item -LiteralPath $staged).Length
        $hash = Get-FileXxHash -FilePath $staged
        $dest = Join-Path $root (Get-HashSizeFileName -HashHex $hash -Length $len -Extension '.7z')
        $seen = [System.Collections.Generic.List[object]]::new()
        Set-FileSyncHook ({
            param($p)
            $seen.Add([pscustomobject]@{ Path = $p; Named = (Test-Path -LiteralPath $dest) })
        }.GetNewClosure())
        $set = [pscustomobject]@{ Name = 'O'; CompressEnabled = $true; CompressProbe = 'off' }
        $stored = InModuleScope FileBackup.Engine -Parameters @{ Staged = $staged; Len = $len; Hash = $hash; Root = $root; Set = $set } {
            param($Staged, $Len, $Hash, $Root, $Set)
            # A stand-in archive, shorter than its content, as 7-Zip writes one.
            Mock Compress-FileWithSevenZip { param($SevenZipPath, $SourceFile, $Destination7z)
                [IO.File]::WriteAllBytes($Destination7z, [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 1, 2, 3, 4)) }
            Mock Resolve-GroupStorageForm { [pscustomobject]@{ Compress = $true; Reason = 'ListSaysCompress'; SampledBytes = 0; Ratio = $null; Windows = @() } }
            Publish-StagedObject -StagedPath $Staged -SourceName 'note.txt' -Hash $Hash -Length $Len -BackupRoot $Root -Set $Set `
                -SevenZipPath 'C:\fake\7z.exe' -ProbeStats (New-ProbeStatistic) -Metrics $null -Log { }
        }
        $stored.Compressed | Should -Be 'Yes'
        $seen.Count | Should -Be 1
        $seen[0].Path | Should -Be "$staged.7z" -Because 'the archive is what becomes the object'
        $seen[0].Named | Should -BeFalse -Because 'the flush comes before the rename that names the object'
        (Get-Item -LiteralPath $dest).Length | Should -Be 10
    }

    It 'flushes a read-only file and leaves it read-only (review 2026-10-26 A1)' {
        $file = Join-Path (New-Folder 'readonly') 'kit.ps1'
        [IO.File]::WriteAllText($file, 'copied with its read-only attribute')
        Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $true
        try {
            $seen = [System.Collections.Generic.List[string]]::new()
            Set-FileSyncHook ({ param($p) $seen.Add($p) }.GetNewClosure())
            { Sync-FileToDisk -LiteralPath $file } | Should -Not -Throw
            $seen | Should -Be @($file)
            (Get-Item -LiteralPath $file).IsReadOnly | Should -BeTrue
            [IO.File]::ReadAllText($file) | Should -Be 'copied with its read-only attribute'
        } finally {
            Set-ItemProperty -LiteralPath $file -Name IsReadOnly -Value $false
        }
    }
}
