<#
.SYNOPSIS  M-1 (defect review 2026-10-05): the lean content index and the
           Optimize-ChangeFolders blanking pass that consumes it.
           TC-234 (structure + memory ratio, Smoke), TC-235 (Optimize
           equivalence + not-rewritten, Smoke), TC-236 (production-shape memory,
           Full - tagged so the Smoke gate in scripts/check.ps1 excludes it).
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

    # Reference for TC-235: the pre-M-1 body of Optimize-ChangeFolders, copied
    # verbatim (rename only) and driven by the -IncludeManifests index, which is
    # the shape the old code consumed. Its output is the golden the lean code
    # must reproduce byte for byte.
    function Invoke-ReferenceOptimize {
        param([string]$ChangeRoot, [string]$BackupRoot, [scriptblock]$Log)
        $changeFolderRegex = & (Get-Module FileBackup.Engine) { $script:Def.ChangeFolderRegex }
        $changeDirs = Get-ChildItem -LiteralPath $ChangeRoot -Directory -Force |
                      Where-Object { $_.Name -match $changeFolderRegex } |
                      Sort-Object Name
        if (-not $changeDirs -or $changeDirs.Count -eq 0) { return }

        $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($changeDirs | ForEach-Object { $_.FullName }) -IncludeManifests
        $globalMap       = $index.Map
        $changeManifests = @($index.Folders | Where-Object { -not $_.IsBackup })

        foreach ($key in $globalMap.Keys) {
            $entries = $globalMap[$key]
            if ($entries.Count -le 1) { continue }

            $backupEntry = $entries | Where-Object { $_.IsBackup } | Select-Object -First 1
            $keeper = if ($backupEntry) {
                $backupEntry
            } else {
                $entries | Where-Object { -not $_.IsBackup } | Sort-Object FolderOrder -Descending | Select-Object -First 1
            }

            $toDelete = $entries | Where-Object { $_.FullPath -ne $keeper.FullPath -and -not $_.IsBackup }
            foreach ($del in $toDelete) {
                if (Test-Path -LiteralPath $del.FullPath -PathType Leaf) {
                    try {
                        Remove-Item -LiteralPath $del.FullPath -Force
                        & $Log "Removed duplicate datapath '$($del.DataPath)' from change folder '$($del.Folder)' (hash/len: $key)." 'INFO'
                    } catch {
                        & $Log "Failed to remove duplicate datapath '$($del.DataPath)' from '$($del.Folder)': $($_.Exception.Message)" 'ERROR'
                    }
                }
            }
        }

        foreach ($cm in $changeManifests) {
            $changed = $false
            foreach ($row in $cm.Manifest) {
                if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
                $full = Join-Path $cm.Folder $row.DataPath
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    $row.DataPath = ''
                    $changed = $true
                }
            }
            if ($changed) {
                & $Log "Updating MANIFEST in change folder '$($cm.Folder)' after datapath cleanup." 'INFO'
                Write-Manifest -FolderPath $cm.Folder -Records $cm.Manifest
            }
        }
    }

    # Deterministic pool used by TC-235: duplicates across the backup root and
    # two snapshots, a row whose file vanished, and a clean snapshot that must
    # not be rewritten. Returns the root holding bkp/ and chg/.
    function New-EquivalencePool {
        param([string]$Root)
        $bkp = Join-Path $Root 'bkp'
        $chg = Join-Path $Root 'chg'
        $s1  = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        $s2  = Join-Path $chg 'Snapshot_2024_02_02_00_00_02'
        $s3  = Join-Path $chg 'Snapshot_2024_03_03_00_00_03'
        New-Item -ItemType Directory -Path $bkp, $s1, $s2, $s3 -Force | Out-Null

        $X = 'EQUIV-ROOT-CONTENT ' * 20
        $Y = 'EQUIV-SNAPSHOT-CONTENT ' * 20
        $C = 'EQUIV-CLEAN-CONTENT ' * 20

        $fx = New-IdxFile $bkp 'x.txt' $X
        New-IdxFile $s1 'x.txt' $X | Out-Null
        New-IdxFile $s2 'x.txt' $X | Out-Null
        New-IdxFile $s1 'y.txt' $Y | Out-Null
        New-IdxFile $s2 'y.txt' $Y | Out-Null
        $fc = New-IdxFile $s3 'clean.txt' $C

        $hx = Get-FileXxHash -FilePath $fx; $lx = (Get-Item -LiteralPath $fx).Length
        $hy = Get-FileXxHash -FilePath (Join-Path $s1 'y.txt'); $ly = (Get-Item -LiteralPath (Join-Path $s1 'y.txt')).Length
        $hc = Get-FileXxHash -FilePath $fc; $lc = (Get-Item -LiteralPath $fc).Length

        Write-Manifest -FolderPath $bkp -Records @(New-IdxRow 'x.txt' 'x.txt' $lx $hx)
        Write-Manifest -FolderPath $s1 -Records @(
            (New-IdxRow 'x.txt' 'x.txt' $lx $hx),
            (New-IdxRow 'y.txt' 'y.txt' $ly $hy),
            (New-IdxRow 'gone.txt' 'gone.txt' 99 'DEADBEEFDEADBEEFDEADBEEFDEADBEEF'))
        Write-Manifest -FolderPath $s2 -Records @(
            (New-IdxRow 'x.txt' 'x.txt' $lx $hx),
            (New-IdxRow 'y.txt' 'y.txt' $ly $hy))
        Write-Manifest -FolderPath $s3 -Records @(New-IdxRow 'clean.txt' 'clean.txt' $lc $hc)
        return $Root
    }

    # Every file under the two roots, keyed by relative path, with its bytes hash.
    function Get-TreeFingerprint {
        param([string[]]$Roots)
        $out = [ordered]@{}
        foreach ($r in $Roots) {
            foreach ($f in @(Get-ChildItem -LiteralPath $r -File -Recurse -Force | Sort-Object FullName)) {
                $rel = $f.FullName.Substring($r.Length)
                if ($f.Name -eq 'MANIFEST.csv.meta') {
                    # The witness carries a Written timestamp, so compare its
                    # content fields only (Version/Rows/Bytes/XxH128).
                    $fields = @(Get-Content -LiteralPath $f.FullName | Where-Object { $_ -notmatch '^Written=' })
                    $out["$(Split-Path $r -Leaf)$rel"] = ($fields -join "`n")
                } else {
                    $out["$(Split-Path $r -Leaf)$rel"] = Get-FileXxHash -FilePath $f.FullName
                }
            }
        }
        return $out
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

Describe 'Optimize-ChangeFolders on the lean index (TC-235)' {
    It 'produces change-folder manifests byte-identical to the pre-M-1 reference, and the same physical pool (SR-026, LLR-026)' {
        $refRoot = Join-Path $TestDrive 'tc235-ref'
        $newRoot = Join-Path $TestDrive 'tc235-new'
        New-EquivalencePool -Root $refRoot | Out-Null
        New-EquivalencePool -Root $newRoot | Out-Null

        Invoke-ReferenceOptimize -ChangeRoot (Join-Path $refRoot 'chg') -BackupRoot (Join-Path $refRoot 'bkp') -Log { param($m, $l) }
        Optimize-ChangeFolders   -ChangeRoot (Join-Path $newRoot 'chg') -BackupRoot (Join-Path $newRoot 'bkp') -Log { param($m, $l) }

        # Compare with the roots' own names normalised out.
        $ref = Get-TreeFingerprint -Roots @((Join-Path $refRoot 'bkp'), (Join-Path $refRoot 'chg'))
        $new = Get-TreeFingerprint -Roots @((Join-Path $newRoot 'bkp'), (Join-Path $newRoot 'chg'))
        $ref.Count | Should -Be $new.Count
        foreach ($k in $ref.Keys) {
            $newKey = $k -replace '^tc235-ref', 'tc235-new'
            $new[$newKey] | Should -Be $ref[$k] -Because "file $k must match the reference"
        }

        # The blanking actually happened: vanished rows are blank in the new pool.
        $s1 = Join-Path $newRoot 'chg\Snapshot_2024_01_01_00_00_01'
        $s2 = Join-Path $newRoot 'chg\Snapshot_2024_02_02_00_00_02'
        ((@(Read-Manifest -FolderPath $s1)) | Where-Object { $_.RelativePath -eq 'gone.txt' }).DataPath | Should -BeNullOrEmpty
        ((@(Read-Manifest -FolderPath $s2)) | Where-Object { $_.RelativePath -eq 'x.txt' }).DataPath | Should -BeNullOrEmpty
        ((@(Read-Manifest -FolderPath $s2)) | Where-Object { $_.RelativePath -eq 'y.txt' }).DataPath | Should -Be 'y.txt'
    }

    It 'does not re-read or rewrite a change folder whose DataPaths all still exist (LLR-026)' {
        $root = Join-Path $TestDrive 'tc235-untouched'
        New-EquivalencePool -Root $root | Out-Null
        $s3 = Join-Path $root 'chg\Snapshot_2024_03_03_00_00_03\MANIFEST.csv'
        $pinned = [datetime]::SpecifyKind([datetime]'2001-02-03T04:05:06', [DateTimeKind]::Utc)
        (Get-Item -LiteralPath $s3).LastWriteTimeUtc = $pinned
        $before = Get-FileXxHash -FilePath $s3

        Optimize-ChangeFolders -ChangeRoot (Join-Path $root 'chg') -BackupRoot (Join-Path $root 'bkp') -Log { param($m, $l) }

        (Get-Item -LiteralPath $s3).LastWriteTimeUtc | Should -Be $pinned
        Get-FileXxHash -FilePath $s3 | Should -Be $before
        Test-ManifestWitness -FolderPath (Split-Path $s3 -Parent) | ForEach-Object { $_.Status } | Should -Be 'Verified'
    }

    It 'rewrites a folder with a vanished DataPath and re-witnesses it (LLR-026)' {
        $root = Join-Path $TestDrive 'tc235-witness'
        New-EquivalencePool -Root $root | Out-Null
        $s1 = Join-Path $root 'chg\Snapshot_2024_01_01_00_00_01'

        Optimize-ChangeFolders -ChangeRoot (Join-Path $root 'chg') -BackupRoot (Join-Path $root 'bkp') -Log { param($m, $l) }

        (Test-ManifestWitness -FolderPath $s1).Status | Should -Be 'Verified'
    }
}

Describe 'Optimize-ChangeFolders probes each DataPath once (TC-235, LLR-026)' {
    # The Owner's rule: on the hub every stat crosses an NTFS translation
    # layer, so a probe pass must not be repeated. One snapshot holds six
    # distinct DataPaths and the LAST one has vanished (the shape a dedupe
    # deletion leaves). Optimize-ChangeFolders runs over the REAL index of that
    # folder, captured before the deletion, with its Map emptied so no
    # duplicate-removal probe runs: every leaf probe under the snapshot is then
    # the blanking pass's own. A second probe pass shows up as twelve.

    BeforeEach {
        $script:Root = Join-Path $TestDrive ('probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $bkp = Join-Path $script:Root 'bkp'; $chg = Join-Path $script:Root 'chg'
        $script:Snap = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        New-Item -ItemType Directory -Path $bkp, $script:Snap -Force | Out-Null
        Write-Manifest -FolderPath $bkp -Records @()
        $rows = foreach ($i in 1..6) {
            $name = "obj$i.dat"
            New-IdxFile -Folder $script:Snap -Name $name -Content "content $i" | Out-Null
            New-IdxRow -DataPath $name -RelativePath "f$i.txt" -Length 9 -Hash ("H{0:D31}" -f $i)
        }
        Write-Manifest -FolderPath $script:Snap -Records @($rows)
        $script:Bkp = $bkp; $script:Chg = $chg
    }

    It 'probes exactly once per DataPath when one has vanished (TC-235, LLR-026)' {
        $real = Get-BackupContentIndex -BackupRoot $script:Bkp -SnapshotFolder @($script:Snap)
        $script:Index = [pscustomobject]@{ Map = @{}; Folders = $real.Folders }
        if ($script:Index.Folders[-1].DataPaths.Count -ne 6) { throw 'fixture error: the snapshot must index six DataPaths' }
        Remove-Item -LiteralPath (Join-Path $script:Snap 'obj6.dat')
        Mock -ModuleName FileBackup.Engine Get-BackupContentIndex { $script:Index }
        $prefix = $script:Snap
        Mock -ModuleName FileBackup.Engine Test-Path { [System.IO.File]::Exists($LiteralPath) } `
            -ParameterFilter { $PathType -eq 'Leaf' -and $LiteralPath -like "$prefix*" }

        Optimize-ChangeFolders -ChangeRoot $script:Chg -BackupRoot $script:Bkp -Log { param($m, $l) }

        Should -Invoke -CommandName Test-Path -ModuleName FileBackup.Engine -Exactly -Times 6 `
            -ParameterFilter { $PathType -eq 'Leaf' -and $LiteralPath -like "$prefix*" }
    }

    It 'blanks exactly the vanished row from that one pass (TC-235, LLR-026)' {
        $real = Get-BackupContentIndex -BackupRoot $script:Bkp -SnapshotFolder @($script:Snap)
        $script:Index = [pscustomobject]@{ Map = @{}; Folders = $real.Folders }
        Remove-Item -LiteralPath (Join-Path $script:Snap 'obj6.dat')
        Mock -ModuleName FileBackup.Engine Get-BackupContentIndex { $script:Index }

        Optimize-ChangeFolders -ChangeRoot $script:Chg -BackupRoot $script:Bkp -Log { param($m, $l) }

        (@(Read-Manifest -FolderPath $script:Snap) | ForEach-Object { "$($_.RelativePath)=$($_.DataPath)" }) -join '|' |
            Should -Be 'f1.txt=obj1.dat|f2.txt=obj2.dat|f3.txt=obj3.dat|f4.txt=obj4.dat|f5.txt=obj5.dat|f6.txt='
    }

    It 'does not re-read the manifest when the index already holds its rows (TC-235, LLR-026)' {
        $real = Get-BackupContentIndex -BackupRoot $script:Bkp -SnapshotFolder @($script:Snap) -IncludeManifests
        $script:Index = [pscustomobject]@{ Map = @{}; Folders = $real.Folders }
        Remove-Item -LiteralPath (Join-Path $script:Snap 'obj6.dat')
        Mock -ModuleName FileBackup.Engine Get-BackupContentIndex { $script:Index }
        Mock -ModuleName FileBackup.Engine Read-Manifest { throw 'the rows were already in hand' }

        Optimize-ChangeFolders -ChangeRoot $script:Chg -BackupRoot $script:Bkp -Log { param($m, $l) }

        Should -Invoke -CommandName Read-Manifest -ModuleName FileBackup.Engine -Exactly -Times 0
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
