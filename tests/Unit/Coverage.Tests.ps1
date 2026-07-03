<#
.SYNOPSIS  G3 truth-up tests for the previously-Open SRs (SR-005/014/023/026).
.NOTES     In-process backup/reconstruct drives the engine I/O shells, so these
           also lift measured module coverage. Run: Invoke-Pester -Path tests\Unit
#>
BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry = Join-Path $repo 'FileBackup.ps1'

    function New-FBConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $false, [bool]$ContentAddressed = $false, [string]$Name = 'S')
        $set = [pscustomobject]@{
            Name = $Name; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress; PreserveFolderTree = (-not $ContentAddressed)
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }
    function Invoke-FB { param([string]$Cfg) & $entry -ConfigPath $Cfg -NoMail -NonInteractive *>&1 | Out-Null }
}

Describe 'Dated point-in-time snapshot (SR-005)' {
    It 'creates a Snapshot_<date> folder carrying its own MANIFEST.csv (SR-005)' {
        $src = Join-Path $TestDrive 's5\src'; $bkp = Join-Path $TestDrive 's5\bkp'; $chg = Join-Path $TestDrive 's5\chg'
        $cfg = Join-Path $TestDrive 's5\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v1'); Invoke-FB $cfg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v2'); Invoke-FB $cfg

        $cf = Get-ChildItem -LiteralPath $chg -Directory |
              Where-Object { $_.Name -match '^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}' }
        $cf | Should -Not -BeNullOrEmpty
        @($cf | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'MANIFEST.csv') }).Count |
            Should -BeGreaterThan 0
    }
}

Describe 'Independent multi-set processing (SR-014)' {
    It 'runs the good set and exits non-zero when another set fails (SR-014)' {
        $good = Join-Path $TestDrive 's14\good'; $bkp = Join-Path $TestDrive 's14\bkp'; $chg = Join-Path $TestDrive 's14\chg'
        $cfg  = Join-Path $TestDrive 's14\c.xml'
        New-Item -ItemType Directory -Path $good, (Split-Path $cfg) -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $good 'g.txt'), 'good')

        $bad = [pscustomobject]@{ Name='Bad'; SourcePath=(Join-Path $TestDrive 's14\does-not-exist')
            BackupPath=(Join-Path $TestDrive 's14\bbkp'); ChangePath=(Join-Path $TestDrive 's14\bchg')
            HashRecalcFreq='A'; CompressEnabled=$false; PreserveFolderTree=$true }
        $goodSet = [pscustomobject]@{ Name='Good'; SourcePath=$good; BackupPath=$bkp; ChangePath=$chg
            HashRecalcFreq='A'; CompressEnabled=$false; PreserveFolderTree=$true }
        @{ Secrets=$null; BackupSets=@($bad, $goodSet) } | Export-Clixml -LiteralPath $cfg

        # Child process so we can read the exit code without affecting this runspace.
        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        $code = $LASTEXITCODE

        # The good set still produced its backup...
        Test-Path -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Should -BeTrue
        @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
            Where-Object { $_.RelativePath -eq 'g.txt' }) | Should -Not -BeNullOrEmpty
        # ...and the failed set forced a non-zero exit.
        $code | Should -Be 1
    }
}

Describe 'Restore capacity check (SR-023)' {
    It 'aborts the restore when the target lacks free space (SR-023)' {
        $src = Join-Path $TestDrive 's23\src'; $bkp = Join-Path $TestDrive 's23\bkp'; $chg = Join-Path $TestDrive 's23\chg'
        $cfg = Join-Path $TestDrive 's23\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'small.txt'), 'tiny'); Invoke-FB $cfg

        # Inflate the recorded (uncompressed) length beyond any real free space.
        $bm = Join-Path $bkp 'MANIFEST.csv'
        $rows = Import-Csv -LiteralPath $bm
        $rows[0].Length = '9000000000000000'   # 9 PB
        $rows | Export-Csv -LiteralPath $bm -NoTypeInformation

        $recon  = Join-Path $bkp 'RECONSTRUCT.ps1'
        $target = Join-Path $TestDrive 's23-restore'   # outside the backup root
        { & $recon -TargetRoot $target } | Should -Throw -ExpectedMessage '*free space*'
    }
}

Describe 'Compressed backup roundtrip (SR-004, SR-008)' {
    It 'compresses a compressible file and restores it byte-for-byte' {
        $src = Join-Path $TestDrive 'c4\src'; $bkp = Join-Path $TestDrive 'c4\bkp'; $chg = Join-Path $TestDrive 'c4\chg'
        $cfg = Join-Path $TestDrive 'c4\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true
        $orig = Join-Path $src 'doc.txt'
        [IO.File]::WriteAllText($orig, ('LOREM ipsum dolor sit amet ' * 400))   # very compressible
        Invoke-FB $cfg

        $recon  = Join-Path $bkp 'RECONSTRUCT.ps1'
        $target = Join-Path $TestDrive 'c4-restore'
        & $recon -TargetRoot $target *>&1 | Out-Null
        $restored = Join-Path $target 'doc.txt'
        (Get-FileHash -LiteralPath $orig).Hash | Should -Be (Get-FileHash -LiteralPath $restored).Hash
    }
}

Describe 'Storage-layout migration roundtrip (SR-012, SR-013)' {
    It 'migrates Mirror -> HashAddressed and still restores byte-for-byte' {
        $src = Join-Path $TestDrive 'm12\src'; $bkp = Join-Path $TestDrive 'm12\bkp'; $chg = Join-Path $TestDrive 'm12\chg'
        $cfgMirror = Join-Path $TestDrive 'm12\mirror.xml'
        $cfgHash   = Join-Path $TestDrive 'm12\hash.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfgMirror) -Force | Out-Null
        $orig = Join-Path $src 'data.bin'
        [IO.File]::WriteAllBytes($orig, [byte[]](1..200))

        New-FBConfig -Path $cfgMirror -Src $src -Bkp $bkp -Chg $chg -ContentAddressed $false
        Invoke-FB $cfgMirror
        New-FBConfig -Path $cfgHash -Src $src -Bkp $bkp -Chg $chg -ContentAddressed $true
        Invoke-FB $cfgHash   # triggers Sync-BackupStorageLayout migration

        $row = Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Where-Object { $_.RelativePath -eq 'data.bin' }
        $row.StoredAsHashSize | Should -Be 'Hash'

        $recon  = Join-Path $bkp 'RECONSTRUCT.ps1'
        $target = Join-Path $TestDrive 'm12-restore'
        & $recon -TargetRoot $target *>&1 | Out-Null
        (Get-FileHash -LiteralPath $orig).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $target 'data.bin')).Hash
    }
}

Describe 'Direct 7-Zip compress/expand (SR-004, SR-008)' {
    It 'round-trips a file through Compress-FileWithSevenZip / Expand-FileWithSevenZip' {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if (-not (Test-Path -LiteralPath $sevenZip)) { Set-ItResult -Skipped -Because '7-Zip not installed'; return }
        $src = Join-Path $TestDrive 'z\in.txt'
        New-Item -ItemType Directory -Path (Split-Path $src) -Force | Out-Null
        [IO.File]::WriteAllText($src, ('payload ' * 500))
        $arch = Join-Path $TestDrive 'z\out.7z'; $back = Join-Path $TestDrive 'z\back.txt'
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $src -Destination7z $arch
        Test-Path -LiteralPath $arch | Should -BeTrue
        Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $arch -DestinationFile $back
        (Get-FileHash -LiteralPath $src).Hash | Should -Be (Get-FileHash -LiteralPath $back).Hash
    }
}

Describe 'Removed-file eviction (SR-006)' {
    It 'drops a deleted file''s manifest row on the next run (SR-006)' {
        $src = Join-Path $TestDrive 's6\src'; $bkp = Join-Path $TestDrive 's6\bkp'; $chg = Join-Path $TestDrive 's6\chg'
        $cfg = Join-Path $TestDrive 's6\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'keep.txt'), 'KEEP')
        [IO.File]::WriteAllText((Join-Path $src 'gone.txt'), 'GONE-unique-content')
        Invoke-FB $cfg
        Remove-Item -LiteralPath (Join-Path $src 'gone.txt') -Force
        Invoke-FB $cfg

        $rows = Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv')
        @($rows | Where-Object { $_.RelativePath -eq 'gone.txt' }) | Should -BeNullOrEmpty
        @($rows | Where-Object { $_.RelativePath -eq 'keep.txt' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Media metric degradation (SR-020)' {
    It 'returns null when ffprobe is unavailable (SR-020)' {
        $f = Join-Path $TestDrive 'mm.bin'; [IO.File]::WriteAllBytes($f, [byte[]](1, 2, 3))
        Get-MediaMBPerSec -FilePath $f -FfprobePath $null | Should -BeNullOrEmpty
        Get-MediaMBPerSec -FilePath $f -FfprobePath 'Z:\no\ffprobe.exe' | Should -BeNullOrEmpty
    }
}

Describe 'Storage-layout chain with compression (SR-012)' {
    It 'survives Mirror -> Mirror+Compress -> HashAddressed+Compress with intact restore' {
        $src = Join-Path $TestDrive 'ch\src'; $bkp = Join-Path $TestDrive 'ch\bkp'; $chg = Join-Path $TestDrive 'ch\chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $orig = Join-Path $src 'doc.txt'
        [IO.File]::WriteAllText($orig, ('compress-me ' * 300))

        $stages = @(
            @{ File = 'a.xml'; Compress = $false; Hash = $false },
            @{ File = 'b.xml'; Compress = $true;  Hash = $false },
            @{ File = 'c.xml'; Compress = $true;  Hash = $true }
        )
        foreach ($s in $stages) {
            $cfg = Join-Path $TestDrive "ch\$($s.File)"
            New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $s.Compress -ContentAddressed $s.Hash
            Invoke-FB $cfg
        }

        $recon  = Join-Path $bkp 'RECONSTRUCT.ps1'
        $target = Join-Path $TestDrive 'ch-restore'
        & $recon -TargetRoot $target *>&1 | Out-Null
        (Get-FileHash -LiteralPath $orig).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $target 'doc.txt')).Hash
    }
}

Describe 'Cross-change duplicate collapse (SR-026)' {
    It 'keeps one physical copy of identical data shared across change folders (SR-026)' {
        $bkpRoot = Join-Path $TestDrive 's26\bkp'; $chgRoot = Join-Path $TestDrive 's26\chg'
        New-Item -ItemType Directory -Path $bkpRoot, $chgRoot -Force | Out-Null
        Write-Manifest -FolderPath $bkpRoot -Records @()   # backup not a keeper here

        $bytes = [byte[]](1,2,3,4,5,6,7,8)
        foreach ($name in 'Snapshot_2024_01_01_00_00_01','Snapshot_2024_01_01_00_00_02') {
            $d = Join-Path $chgRoot $name
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $d 'd.bin'), $bytes)
            $row = [pscustomobject]@{
                DataPath='d.bin'; RelativePath='d.bin'; Length=$bytes.Length; LastWriteTime=(Get-Date)
                xxH2Hash='DEADBEEFDEADBEEFDEADBEEFDEADBEEF'; Compressed='No'; StoredAsHashSize='No'
                Duplicate='No'; MediaMBPerSec=''
            }
            Write-Manifest -FolderPath $d -Records @($row)
        }

        Optimize-ChangeFolders -ChangeRoot $chgRoot -BackupRoot $bkpRoot -Log { param($m, $lvl) }

        @(Get-ChildItem -LiteralPath $chgRoot -Recurse -Filter 'd.bin').Count | Should -Be 1
    }
}

Describe 'Clean cutover from Pre_*_Changes (SR-028)' {
    It 'engine, common and reconstruct contain no Pre_*_Changes logic (SR-028)' {
        foreach ($f in 'Modules\FileBackup.Engine.psm1','Modules\FileBackup.Common.psm1','Reconstruct.ps1') {
            (Get-Content -LiteralPath (Join-Path $repo $f) -Raw) | Should -Not -Match 'Pre_'
        }
    }
}

Describe 'Point-in-time restore from a dated snapshot (SR-010)' {
    It 'restores a modified file at its OLD version from the snapshot, latest from the root (<Mode>)' -ForEach @(
        @{ Mode = 'Mirror';              Compress = $false; CA = $false }
        @{ Mode = 'Mirror+Compress';     Compress = $true;  CA = $false }
        @{ Mode = 'HashAddressed';       Compress = $false; CA = $true  }
        @{ Mode = 'HashAddressed+Comp';  Compress = $true;  CA = $true  }
    ) {
        $root = Join-Path $TestDrive ("pit\" + ($Mode -replace '\W', ''))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src, $root -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress -ContentAddressed $CA

        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'VERSION-ONE'); Invoke-FB $cfg   # run1 (no snapshot)
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'VERSION-TWO'); Invoke-FB $cfg   # run2 ⇒ Snapshot of state-1

        $snap = Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' } | Select-Object -First 1
        $snap | Should -Not -BeNullOrEmpty

        # Restoring the dated snapshot reproduces the OLD content (the SR-010 fix).
        $tSnap = Join-Path $root 'restore-snap'
        & (Join-Path $snap.FullName 'RECONSTRUCT.ps1') -TargetRoot $tSnap *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $tSnap 'f.txt')) | Should -Be 'VERSION-ONE'

        # Restoring the backup root reproduces the latest content.
        $tRoot = Join-Path $root 'restore-root'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $tRoot *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $tRoot 'f.txt')) | Should -Be 'VERSION-TWO'
    }
}

Describe 'Re-deleted content stored once across snapshots (SR-028, SR-010)' {
    # Adversarial-review scenario: delete -> reintroduce identical bytes -> delete
    # again. The content's physical data must exist exactly ONCE across the backup
    # root + all snapshots, while each dated state stays restorable (older
    # snapshot rows resolve the hash from wherever the single copy lives).
    It 'keeps one physical copy through a delete/re-add/delete cycle and restores each state' {
        $root = Join-Path $TestDrive 'cycle'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        function RunAt([datetime]$d) { & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        $C = 'CYCLE-CONTENT ' + ('data ' * 50)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), $C)
        RunAt ([datetime]'2024-01-01 00:00:01')                       # f present
        Remove-Item -LiteralPath (Join-Path $src 'f.txt')
        RunAt ([datetime]'2024-02-02 00:00:02')                       # f deleted
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), $C)
        RunAt ([datetime]'2024-03-03 00:00:03')                       # f reintroduced, identical
        Remove-Item -LiteralPath (Join-Path $src 'f.txt')
        RunAt ([datetime]'2024-04-04 00:00:04')                       # f deleted again

        # Exactly one physical copy of C's bytes across backup root + snapshots.
        $tmp = Join-Path $root 'c.tmp'
        [IO.File]::WriteAllText($tmp, $C)
        $h = Get-FileXxHash -FilePath $tmp
        $len = (Get-Item -LiteralPath $tmp).Length
        Remove-Item -LiteralPath $tmp
        $skip = '^(MANIFEST\.csv|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState|backup\.log)'
        $copies = @(Get-ChildItem -LiteralPath $bkp, $chg -File -Recurse |
            Where-Object { $_.Name -notmatch $skip -and $_.Length -eq $len -and
                           (Get-FileXxHash -FilePath $_.FullName) -eq $h })
        $copies.Count | Should -Be 1

        # Each dated state still restores correctly from that single copy.
        $snapD1 = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        $snapD3 = Join-Path $chg 'Snapshot_2024_03_03_00_00_03'
        foreach ($snap in $snapD1, $snapD3) {                          # f existed at D1/D3
            $t = Join-Path $root ('r-' + [IO.Path]::GetFileName($snap))
            & (Join-Path $snap 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
            [IO.File]::ReadAllText((Join-Path $t 'f.txt')) | Should -Be $C
        }
        $tRoot = Join-Path $root 'r-latest'                            # latest: f absent
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $tRoot *>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $tRoot 'f.txt') | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $tRoot 'steady.txt')) | Should -Be 'STEADY'
    }
}

Describe 'Manifest-only change creates a snapshot (SR-005)' {
    # 2026-07-02 review finding: the old gate counted physical byte I/O, so a run
    # whose only change was a dedup-served duplicate add or a shared-content
    # removal produced NO snapshot and the prior state was lost forever.
    It 'snapshots on dup-add and shared-removal runs; none on a true no-op' {
        $root = Join-Path $TestDrive 'mfc'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        function RunAt([datetime]$d) { & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'X-CONTENT')
        RunAt ([datetime]'2024-01-01 00:00:01')                       # D0: A only
        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'X-CONTENT')
        RunAt ([datetime]'2024-02-02 00:00:02')                       # D1: dup-content add (no byte copied)
        Remove-Item -LiteralPath (Join-Path $src 'b.txt')
        RunAt ([datetime]'2024-03-03 00:00:03')                       # D2: shared-content removal (no byte evicted)
        RunAt ([datetime]'2024-04-04 00:00:04')                       # D3: true no-op

        $snapD0 = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        $snapD1 = Join-Path $chg 'Snapshot_2024_02_02_00_00_02'
        Test-Path -LiteralPath (Join-Path $snapD0 'MANIFEST.csv') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $snapD1 'MANIFEST.csv') | Should -BeTrue
        # The manifest-identical run must still create none.
        Test-Path -LiteralPath (Join-Path $chg 'Snapshot_2024_03_03_00_00_03') | Should -BeFalse

        # Each preserved state restores byte-exact: D0 = a only; D1 = a + b.
        $t0 = Join-Path $root 'r-d0'
        & (Join-Path $snapD0 'RECONSTRUCT.ps1') -TargetRoot $t0 *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t0 'a.txt')) | Should -Be 'X-CONTENT'
        Test-Path -LiteralPath (Join-Path $t0 'b.txt') | Should -BeFalse
        $t1 = Join-Path $root 'r-d1'
        & (Join-Path $snapD1 'RECONSTRUCT.ps1') -TargetRoot $t1 *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t1 'a.txt')) | Should -Be 'X-CONTENT'
        [IO.File]::ReadAllText((Join-Path $t1 'b.txt')) | Should -Be 'X-CONTENT'
    }
}

Describe 'Restore fails loudly when content is unrecoverable (SR-029)' {
    # 2026-07-02 review finding: an unrecoverable row was logged as WARN and
    # skipped, and the restore exited 0 — a scripted caller saw a clean success
    # on an incomplete tree.
    It 'restores everything recoverable, then throws naming the unrestored count' {
        $root = Join-Path $TestDrive 's29'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'good.txt'), 'GOOD')
        [IO.File]::WriteAllText((Join-Path $src 'doomed.txt'), 'DOOMED')
        Invoke-FB $cfg

        $recon = Join-Path $bkp 'RECONSTRUCT.ps1'
        $tOk = Join-Path $root 'r-ok'                       # untampered ⇒ clean
        { & $recon -TargetRoot $tOk } | Should -Not -Throw
        [IO.File]::ReadAllText((Join-Path $tOk 'doomed.txt')) | Should -Be 'DOOMED'

        # Destroy doomed.txt's only data source (Mirror mode: the mirrored file).
        Remove-Item -LiteralPath (Join-Path $bkp 'doomed.txt') -Force
        $tBad = Join-Path $root 'r-bad'
        { & $recon -TargetRoot $tBad } | Should -Throw -ExpectedMessage '*1 file(s) could not be restored*'
        # The recoverable row was still restored before the failure surfaced.
        [IO.File]::ReadAllText((Join-Path $tBad 'good.txt')) | Should -Be 'GOOD'
        Test-Path -LiteralPath (Join-Path $tBad 'doomed.txt') | Should -BeFalse
    }
}

Describe 'Reconstruct sidecar is infrastructure (SR-022)' {
    # 2026-07-02 review finding: RECONSTRUCT.paths.json was missing from the
    # Test-IsInfrastructureFile allowlist, producing false orphan WARNs each run.
    It 'logs no orphan/not-in-DB warning for RECONSTRUCT.paths.json' {
        $root = Join-Path $TestDrive 's22s'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'data')
        Invoke-FB $cfg
        Invoke-FB $cfg   # warnings (if any) surface on the run AFTER the sidecar exists

        (Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw) |
            Should -Not -Match 'RECONSTRUCT\.paths\.json'
    }
}

Describe 'Restore target guard (SR-009)' {
    # Independent-review finding: the old '-like' guard falsely rejected a sibling
    # whose name shares the backup-root prefix (e.g. bk vs bk-restore).
    It 'rejects a target inside the backup but allows a prefix-sharing sibling' {
        $root = Join-Path $TestDrive 's9'
        $src = Join-Path $root 'src'; $bk = Join-Path $root 'bk'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src, $root -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bk -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'data'); Invoke-FB $cfg
        $recon = Join-Path $bk 'RECONSTRUCT.ps1'

        { & $recon -TargetRoot (Join-Path $bk 'inside') } | Should -Throw   # inside backup ⇒ rejected
        $sib = Join-Path $root 'bk-restore'                                 # prefix-sharing sibling ⇒ allowed
        { & $recon -TargetRoot $sib } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $sib 'f.txt') | Should -BeTrue
    }
}
