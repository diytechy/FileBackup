<#
.SYNOPSIS  M-1 (defect review 2026-10-05): the lean content index that prune
           and the storage-form audit read. TC-234 (structure + memory ratio,
           Smoke), TC-236 (production-shape memory, Full - tagged so the Smoke
           gate in scripts/check.ps1 excludes it). TC-235's Optimize-ChangeFolders
           cases went with that function: a backup run no longer collapses
           duplicates (bounded-run-loop plan R9, R10).
.NOTES     Run: Invoke-Pester -Path tests\Unit\ContentIndex.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    function New-IdxRow {
        param([string]$DataPath, [string]$RelativePath, [long]$Length, [string]$Hash)
        [pscustomobject]@{
            DataPath = $DataPath; RelativePath = $RelativePath; Length = $Length
            LastWriteTime = [datetime]'2024-01-01 00:00:00'; xxH2Hash = $Hash
            Compressed = 'No'; StoredAsHashSize = 'Hash'; Duplicate = 'No'; MediaMBPerSec = ''
        }
    }
    function New-IdxFile {
        param([string]$Folder, [string]$Name, [string]$Content)
        $full = Join-Path $Folder $Name
        $dir = [IO.Path]::GetDirectoryName($full)
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllText($full, $Content)
        return $full
    }


    # Synthetic pool for the memory tests: N snapshot folders of R rows each,
    # mostly blank DataPath, with D rows naming a real tiny file per folder.
    function New-SyntheticPool {
        param([string]$Root, [int]$Snapshots, [int]$Rows, [int]$DataRows)
        $bkp = Join-Path $Root 'bkp'
        $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path $bkp, $chg -Force | Out-Null
        $snaps = for ($s = 1; $s -le $Snapshots; $s++) {
            $dir = Join-Path $chg ('Snapshot_2024_{0:D2}_01_00_00_00' -f $s)
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $manifestRows = for ($i = 1; $i -le $Rows; $i++) {
                if ($i -le $DataRows) {
                    $name = "d$s-$i.bin"
                    [IO.File]::WriteAllText((Join-Path $dir $name), "data $s $i")
                    New-IdxRow $name "d$s-$i.bin" 8 ('{0:X16}' -f (($s * 100000L) + $i))
                } else {
                    New-IdxRow '' "r$s-$i.txt" 1000 ('{0:X16}' -f (($s * 100000L) + $i))
                }
            }
            Write-Manifest -FolderPath $dir -Records @($manifestRows)
            $dir
        }
        return [pscustomobject]@{ Bkp = $bkp; Chg = $chg; Snapshots = @($snaps) }
    }

    # Retained managed bytes of whatever $Build returns, measured after a full
    # collection. $held stays referenced until after the second measurement.
    function Measure-RetainedBytes {
        param([scriptblock]$Build)
        [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
        $before = [GC]::GetTotalMemory($true)
        $held = & $Build
        $after = [GC]::GetTotalMemory($true)
        if ($null -eq $held) { throw 'Measured build returned nothing; the measurement would be meaningless.' }
        return ($after - $before)
    }
}

Describe 'Lean content index structure (TC-234)' {
    BeforeAll {
        $script:smallRoot = Join-Path $TestDrive 'tc234'
        $script:pool = New-SyntheticPool -Root $script:smallRoot -Snapshots 2 -Rows 6 -DataRows 2
    }

    It 'default call retains no Manifest on any folder record and lists exactly the non-blank DataPaths (SR-026, LLR-047)' {
        $index = Get-BackupContentIndex -BackupRoot $pool.Bkp -SnapshotFolder $pool.Snapshots
        $index.Folders.Count | Should -Be 2
        foreach ($rec in $index.Folders) {
            $rec.PSObject.Properties['Manifest'] | Should -BeNullOrEmpty
            $rec.IsBackup | Should -BeFalse
        }
        $i = 0
        foreach ($rec in $index.Folders) {
            $i++
            @($rec.DataPaths) | Should -Be @("d$i-1.bin", "d$i-2.bin")
        }
    }

    It 'an empty backup root with no manifest yields no DataPaths and no Manifest (SR-026)' {
        $empty = Join-Path $TestDrive 'tc234-empty'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        $index = Get-BackupContentIndex -BackupRoot $empty -SnapshotFolder @()
        $index.Folders.Count | Should -Be 0
        $index.Map.Count | Should -Be 0
    }

    It '-IncludeManifests keeps Manifest equal to Read-Manifest and still reports DataPaths (SR-045, SR-047)' {
        $index = Get-BackupContentIndex -BackupRoot $pool.Bkp -SnapshotFolder $pool.Snapshots -IncludeManifests
        foreach ($rec in $index.Folders) {
            $rec.PSObject.Properties['Manifest'] | Should -Not -BeNullOrEmpty
            $fresh = @(Read-Manifest -FolderPath $rec.Folder)
            @($rec.Manifest).Count | Should -Be $fresh.Count
            (@($rec.Manifest) | ForEach-Object { $_.RelativePath }) -join '|' |
                Should -Be (($fresh | ForEach-Object { $_.RelativePath }) -join '|')
            @($rec.DataPaths).Count | Should -Be 2
        }
    }

    It 'the map is identical with and without -IncludeManifests (SR-026)' {
        $lean = Get-BackupContentIndex -BackupRoot $pool.Bkp -SnapshotFolder $pool.Snapshots
        $full = Get-BackupContentIndex -BackupRoot $pool.Bkp -SnapshotFolder $pool.Snapshots -IncludeManifests
        @($lean.Map.Keys | Sort-Object) | Should -Be @($full.Map.Keys | Sort-Object)
        $lean.Map.Count | Should -Be 4
    }

    It 'lean retained memory is under 25% of the -IncludeManifests figure and under two manifests (TC-234 memory, Smoke)' {
        # 12 snapshots x 5,000 rows, 5 real data rows each (reduced from 20,000 to
        # keep the Smoke run under ~60 s). Ratios, not bytes,
        # so the assertion is machine-independent.
        $big = New-SyntheticPool -Root (Join-Path $TestDrive 'tc234-mem') -Snapshots 12 -Rows 5000 -DataRows 5
        $snaps = $big.Snapshots

        $leanBytes = Measure-RetainedBytes { Get-BackupContentIndex -BackupRoot $big.Bkp -SnapshotFolder $snaps }
        $fullBytes = Measure-RetainedBytes { Get-BackupContentIndex -BackupRoot $big.Bkp -SnapshotFolder $snaps -IncludeManifests }
        $oneManifest = Measure-RetainedBytes { Read-Manifest -FolderPath $snaps[0] }

        Write-Host ("TC-234 memory: lean={0:N0} B, IncludeManifests={1:N0} B, one manifest={2:N0} B, ratio={3:P1}" -f `
            $leanBytes, $fullBytes, $oneManifest, ($leanBytes / [double]$fullBytes))

        $leanBytes | Should -BeLessThan (0.25 * $fullBytes)
        $leanBytes | Should -BeLessThan (2 * $oneManifest)
    }
}

Describe 'Lean content index at production shape (TC-236)' -Tag 'Full' {
    It 'indexes 30 snapshots x 180,000 rows with the lean default in at most 1 GB retained (LLR-047, performance budget)' {
        $big = New-SyntheticPool -Root (Join-Path $TestDrive 'tc236') -Snapshots 30 -Rows 180000 -DataRows 6
        $leanBytes = Measure-RetainedBytes { Get-BackupContentIndex -BackupRoot $big.Bkp -SnapshotFolder $big.Snapshots }
        Write-Host ("TC-236 production shape: lean retained={0:N0} B" -f $leanBytes)
        $leanBytes | Should -BeLessThan 1GB
    }
}
