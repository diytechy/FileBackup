<#
.SYNOPSIS  G3 truth-up tests for the previously-Open SRs (SR-005/014/023/026).
.NOTES     In-process backup/reconstruct drives the engine I/O shells, so these
           also lift measured module coverage. Run: Invoke-Pester -Path tests\Unit
#>

# Discovery-time: the ONE shared configuration-fixture corpus (SR-042), also
# consumed by TC-074/TC-075 in tests/Unit/Engine.Tests.ps1. TC-077 runs the
# published JSON schema against exactly the list the validator is tested with,
# so the two cannot drift.
. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'tests\Common\ConfigFixtures.ps1')
$configCorpus = Get-ConfigFixtureCorpus

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

Describe 'Cross-platform restore kit deposition (SR-007, SR-031)' {
    It 'bundles Windows and POSIX restore entry points in the live backup and snapshot' {
        $src = Join-Path $TestDrive 'kit\src'; $bkp = Join-Path $TestDrive 'kit\bkp'; $chg = Join-Path $TestDrive 'kit\chg'
        $cfg = Join-Path $TestDrive 'kit\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v1'); Invoke-FB $cfg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v2'); Invoke-FB $cfg

        $snap = Get-ChildItem -LiteralPath $chg -Directory |
                Where-Object { $_.Name -match '^Snapshot_' } | Select-Object -First 1
        $snap | Should -Not -BeNullOrEmpty
        foreach ($folder in $bkp, $snap.FullName) {
            foreach ($entryPoint in 'RECONSTRUCT.bat', 'RECONSTRUCT.ps1', 'reconstruct.sh') {
                Test-Path -LiteralPath (Join-Path $folder $entryPoint) -PathType Leaf | Should -BeTrue
            }
        }

        # The deployed POSIX entry point must be the tested repository artifact,
        # not a generated or stale variant.
        (Get-FileHash -LiteralPath (Join-Path $bkp 'reconstruct.sh') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $repo 'bash\reconstruct.sh') -Algorithm SHA256).Hash
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
        # Deliberate tampering: re-stamp the witness so the failure this test
        # observes is the capacity refusal (exit 2), not witness mismatch (3).
        Write-ManifestWitness -FolderPath $bkp | Out-Null

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

Describe 'Restore dependency preflight (SR-008, SR-029)' {
    It 'refuses a restore origin whose MANIFEST.csv is missing' {
        $root = Join-Path $TestDrive 'missing-manifest'
        $origin = Join-Path $root 'backup'; $target = Join-Path $root 'restore'
        New-Item -ItemType Directory -Path $origin -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo 'Reconstruct.ps1') -Destination $origin
        Copy-Item -LiteralPath (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Destination $origin

        { & (Join-Path $origin 'Reconstruct.ps1') -TargetRoot $target } |
            Should -Throw -ExpectedMessage '*MANIFEST.csv not found*'
    }

    It 'refuses compressed rows when 7-Zip is unavailable instead of copying archive bytes as the file' {
        $root = Join-Path $TestDrive 'missing7z'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'not-an-archive')
        Invoke-FB $cfg

        # Model a compressed row without depending on whether 7-Zip is installed
        # on the test host. Before the guard, this copied the source bytes and
        # reported a successful restore.
        $manifest = Join-Path $bkp 'MANIFEST.csv'
        $rows = Import-Csv -LiteralPath $manifest
        $rows[0].Compressed = 'Yes'
        $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
        # Deliberate tampering: re-stamp the witness so the failure this test
        # observes is the 7-Zip precondition (exit 2), not witness mismatch (3).
        Write-ManifestWitness -FolderPath $bkp | Out-Null

        $target = Join-Path $root 'restore'
        $missingTool = Join-Path $root 'does-not-exist\7z.exe'
        { & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target -SevenZipPath $missingTool } |
            Should -Throw -ExpectedMessage '*7-Zip is required*'
        Test-Path -LiteralPath (Join-Path $target 'f.txt') | Should -BeFalse
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

Describe 'Manifest witness is infrastructure (SR-022, SR-038)' {
    # TC-067. Two halves of B6: the ROOT-level MANIFEST.csv.meta is infrastructure
    # (no orphan WARN), a NESTED user file of the same name is real data. Plus the
    # single most dangerous mistake available in SR-038 — the witness must NOT be
    # copied into snapshots with the restore kit, or every snapshot would carry the
    # backup root's witness and fail verification against its own manifest.
    It 'logs no orphan warning for the root witness, keeps a nested one as data, and gives each snapshot its own (SR-038)' {
        $root = Join-Path $TestDrive 's38'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        $witnessName = (Get-FileBackupDefaults).WitnessFilename

        # A nested user file named exactly like the witness (B6).
        [IO.File]::WriteAllText((Join-Path $src "sub\$witnessName"), 'NESTED-USER-WITNESS')
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v1')
        Invoke-FB $cfg                                   # run1 (no snapshot)
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v2')
        Invoke-FB $cfg                                   # run2 ⇒ snapshot of state-1

        # Half 1: root-level witness is infrastructure — no orphan/not-in-DB WARN.
        (Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw) |
            Should -Not -Match ([regex]::Escape($witnessName))

        # Half 2: the nested same-named file is data — it is in the manifest...
        @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
            Where-Object { $_.RelativePath -eq "sub\$witnessName" }) | Should -Not -BeNullOrEmpty
        # ...and restores byte-exact.
        $t = Join-Path $root 'restore'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t "sub\$witnessName")) | Should -Be 'NESTED-USER-WITNESS'

        # Every origin carrying a manifest carries a witness that verifies against
        # ITS OWN manifest — the backup root, and each snapshot independently.
        $snaps = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' })
        $snaps.Count | Should -BeGreaterThan 0
        foreach ($origin in @($bkp) + $snaps.FullName) {
            Test-Path -LiteralPath (Join-Path $origin $witnessName) -PathType Leaf | Should -BeTrue
            (Test-ManifestWitness -FolderPath $origin).Status | Should -Be 'Verified'
        }
        # The snapshot's witness is its OWN, not a copy of the backup root's: the
        # two manifests differ (blanked DataPaths), so the digests must differ too.
        # Compare the DIGESTS the sidecars actually carry (an earlier revision of
        # this test compared the sidecar's *path*, which can never be empty).
        $rootDigest = ([regex]::Match(
            [IO.File]::ReadAllText((Join-Path $bkp $witnessName)),
            '(?m)^XxH128=(?<h>[0-9A-Fa-f]{32})$')).Groups['h'].Value
        $rootDigest | Should -Not -BeNullOrEmpty
        $rootDigest | Should -Be (Get-FileXxHash -FilePath (Join-Path $bkp 'MANIFEST.csv'))
        foreach ($snap in $snaps) {
            $snapHash = Get-FileXxHash -FilePath (Join-Path $snap.FullName 'MANIFEST.csv')
            $snapHash | Should -Not -Be $rootDigest
            ([IO.File]::ReadAllText((Join-Path $snap.FullName $witnessName))) |
                Should -Match ([regex]::Escape("XxH128=$snapHash"))
        }
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

    It 'refuses a manifest RelativePath that escapes the target root' {
        $root = Join-Path $TestDrive 's9-traversal'
        $src = Join-Path $root 'src'; $bk = Join-Path $root 'bk'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bk -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'payload.txt'), 'payload'); Invoke-FB $cfg

        $manifest = Join-Path $bk 'MANIFEST.csv'
        $rows = Import-Csv -LiteralPath $manifest
        $rows[0].RelativePath = '..\ESCAPED.txt'
        $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
        # Deliberate tampering: re-stamp the witness so the failure this test
        # observes is the traversal refusal (exit 1), not witness mismatch (3).
        Write-ManifestWitness -FolderPath $bk | Out-Null

        $target = Join-Path $root 'restore'
        { & (Join-Path $bk 'RECONSTRUCT.ps1') -TargetRoot $target } |
            Should -Throw -ExpectedMessage '*1 file(s) could not be restored*'
        Test-Path -LiteralPath (Join-Path $root 'ESCAPED.txt') | Should -BeFalse
    }
}

Describe 'Hash recovery of a nested infra-named row (SR-022, SR-010)' {
    # 2026-07-03 bash-v1 finding (human-approved fix): Find-DataFileByHash applied
    # the infrastructure-name skip RECURSIVELY, so a nested user file named like
    # infrastructure (B6: sub\MANIFEST.csv) was unrecoverable from a Mirror-mode
    # snapshot — its only surviving copy is the Mirror data file of the same name.
    # The contract (AGENTS.md §3) is root-level-only. The skip is an optimization,
    # not a correctness mechanism: recovery matches on (xxH2Hash, Length).
    It 'restores a Mirror snapshot whose blanked sub\MANIFEST.csv row recovers from the backup root (B6, TC-058)' {
        $root = Join-Path $TestDrive 'nestedinfra'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg    # Mirror, no compress

        [IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv'), 'NESTED-USER-DATA')
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v1')
        Invoke-FB $cfg                                            # run1 (no snapshot)
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v2')
        Invoke-FB $cfg                                            # run2 ⇒ Snapshot of state-1

        # In the snapshot, the unchanged sub\MANIFEST.csv row is blanked (bytes
        # live only as the backup root's Mirror data file bkp\sub\MANIFEST.csv).
        $snap = Get-ChildItem -LiteralPath $chg -Directory |
                Where-Object { $_.Name -match '^Snapshot_' } | Select-Object -First 1
        $snap | Should -Not -BeNullOrEmpty

        $t = Join-Path $root 'restore-snap'
        { & (Join-Path $snap.FullName 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null } |
            Should -Not -Throw                                    # would throw INCOMPLETE pre-fix (SR-029)
        [IO.File]::ReadAllText((Join-Path $t 'sub\MANIFEST.csv')) | Should -Be 'NESTED-USER-DATA'
        [IO.File]::ReadAllText((Join-Path $t 'other.txt'))        | Should -Be 'v1'
    }
}

Describe 'Manifest witness verification on restore (SR-039)' {
    # TC-068. A damaged index must refuse the restore rather than "succeed"
    # against a shrunken job (HomeHub cross-check finding E). Legacy backups
    # written before the witness contract must still restore, with a warning.
    BeforeAll {
        function New-WitnessOrigin {
            param([string]$Root)
            $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
            $cfg = Join-Path $Root 'c.xml'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
            [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'AAA')
            [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'BBB')
            Invoke-FB $cfg
            return $bkp
        }
        # A refusal writes NOTHING into the target — not a restored row, not even
        # the restorer's own RECONSTRUCT.log, because verification runs before the
        # target folder and log are created (SR-039). This is what makes README's
        # "no file is written to the target" literally true, and it is what
        # reconstruct.sh has always done.
        function Get-TargetContents {
            param([string]$Target)
            if (-not (Test-Path -LiteralPath $Target)) { return @() }
            @(Get-ChildItem -LiteralPath $Target -Recurse -File | ForEach-Object { $_.Name })
        }
    }

    It 'refuses a truncated, byte-edited or garbage manifest without restoring a row (SR-039)' {
        $root = Join-Path $TestDrive 'w39-damage'
        $bkp = New-WitnessOrigin $root
        $manifest = Join-Path $bkp 'MANIFEST.csv'
        $recon = Join-Path $bkp 'RECONSTRUCT.ps1'
        $pristine = [IO.File]::ReadAllBytes($manifest)

        # 1. Truncated (a half-written manifest) — caught by Bytes.
        [IO.File]::WriteAllBytes($manifest, $pristine[0..($pristine.Length - 30)])
        $t1 = Join-Path $root 'r-trunc'
        { & $recon -TargetRoot $t1 } | Should -Throw -ExpectedMessage '*witness verification failed*'
        # Nothing at all: the target folder was never even created.
        Test-Path -LiteralPath $t1 | Should -BeFalse

        # 2. Byte-edited at the same length — slips past Bytes/Rows, caught by the digest.
        $edited = [byte[]]::new($pristine.Length)
        [Array]::Copy($pristine, $edited, $pristine.Length)
        $edited[$edited.Length - 6] = [byte]0x51
        [IO.File]::WriteAllBytes($manifest, $edited)
        # An EXISTING target must come out untouched too — no RECONSTRUCT.log
        # dropped into a folder the operator already had.
        $t2 = Join-Path $root 'r-edit'
        New-Item -ItemType Directory -Path $t2 -Force | Out-Null
        { & $recon -TargetRoot $t2 } | Should -Throw -ExpectedMessage '*witness verification failed*'
        Get-TargetContents $t2 | Should -BeNullOrEmpty

        # 3. Replaced by unrelated text — the header guard catches it first
        #    (exit 2 class), which is the legacy corrupt-file path.
        [IO.File]::WriteAllText($manifest, "hello, this is not a manifest at all`r`n")
        $t3 = Join-Path $root 'r-garbage'
        { & $recon -TargetRoot $t3 } | Should -Throw -ExpectedMessage '*not a FileBackup manifest*'
        Test-Path -LiteralPath $t3 | Should -BeFalse

        # 4. Re-stamping the witness makes the SAME (restored) manifest verify.
        [IO.File]::WriteAllBytes($manifest, $pristine)
        Write-ManifestWitness -FolderPath $bkp | Out-Null
        $t4 = Join-Path $root 'r-ok'
        { & $recon -TargetRoot $t4 *>&1 | Out-Null } | Should -Not -Throw
        [IO.File]::ReadAllText((Join-Path $t4 'a.txt')) | Should -Be 'AAA'
    }

    It 'restores a sidecar-less legacy origin with an unverified warning, and refuses it under -RequireWitness (SR-039)' {
        $root = Join-Path $TestDrive 'w39-legacy'
        $bkp = New-WitnessOrigin $root
        $recon = Join-Path $bkp 'RECONSTRUCT.ps1'
        # Model a backup written before the witness contract.
        Remove-Item -LiteralPath (Join-Path $bkp (Get-FileBackupDefaults).WitnessFilename) -Force

        $t = Join-Path $root 'r-legacy'
        & $recon -TargetRoot $t *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t 'a.txt')) | Should -Be 'AAA'
        [IO.File]::ReadAllText((Join-Path $t 'b.txt')) | Should -Be 'BBB'
        (Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw) | Should -Match 'UNVERIFIED'

        # Opt-in strict mode turns that absence into the same abort.
        $tStrict = Join-Path $root 'r-strict'
        { & $recon -TargetRoot $tStrict -RequireWitness } |
            Should -Throw -ExpectedMessage '*RequireWitness*'
        Test-Path -LiteralPath $tStrict | Should -BeFalse
    }
}

Describe 'Hash-recovery failure causes are distinguishable (SR-040)' {
    # TC-072. Find-DataFileByHash used to collapse four causes into one warning
    # (HomeHub cross-check finding D), so a wrapper could not tell "your bytes
    # are gone" from "this host is broken; retry".
    BeforeAll {
        $script:reconSource = Join-Path $repo 'Reconstruct.ps1'
        # Bind to the function AS SHIPPED: lift it out of the real script's AST
        # rather than copying it into the test.
        function Import-FindDataFileByHash {
            $tokens = $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:reconSource, [ref]$tokens, [ref]$errs)
            $fn = $ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $n.Name -eq 'Find-DataFileByHash' }, $true) | Select-Object -First 1
            $fn | Should -Not -BeNullOrEmpty
            return [scriptblock]::Create($fn.Extent.Text)
        }
    }

    It 'reports ContentMissing, StorageUnreadable and DependencyMissing distinctly (SR-040)' {
        . (Import-FindDataFileByHash)
        $root = Join-Path $TestDrive 'cause'
        $pool = Join-Path $root 'pool'
        New-Item -ItemType Directory -Path $pool -Force | Out-Null

        # ContentMissing: the pool is readable, the bytes simply are not there.
        [IO.File]::WriteAllText((Join-Path $pool 'unrelated.txt'), 'nope')
        $r = Find-DataFileByHash -Hash 'F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0' -Length 4 `
                -SearchFolders @($pool) -SevenZipPath $null
        $r.Cause | Should -Be 'ContentMissing'
        $r.Path  | Should -BeNullOrEmpty

        # StorageUnreadable: a search folder that is not there at all.
        $r = Find-DataFileByHash -Hash 'F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0' -Length 4 `
                -SearchFolders @((Join-Path $root 'gone')) -SevenZipPath $null
        $r.Cause | Should -Be 'StorageUnreadable'

        # DependencyMissing: an archive candidate met with no usable 7-Zip.
        # Outranks StorageUnreadable — it is the one with a precise remediation.
        [IO.File]::WriteAllText((Join-Path $pool 'data.7z'), 'PK-not-really')
        $r = Find-DataFileByHash -Hash 'F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0' -Length 4 `
                -SearchFolders @($pool, (Join-Path $root 'gone')) `
                -SevenZipPath (Join-Path $root 'no-such-7z.exe')
        $r.Cause  | Should -Be 'DependencyMissing'
        $r.Detail | Should -Match '7-Zip'

        # Found still wins over any host issue met along the way.
        $hit = Join-Path $pool 'hit.bin'
        [IO.File]::WriteAllText($hit, 'FINDME')
        $h = Get-FileXxHash -FilePath $hit
        $r = Find-DataFileByHash -Hash $h -Length ([IO.FileInfo]$hit).Length `
                -SearchFolders @((Join-Path $root 'gone'), $pool) -SevenZipPath $null
        $r.Cause | Should -Be 'Found'
        $r.Path  | Should -Be $hit
    }

    It 'names the count per class in the terminating summary (SR-040)' {
        $root = Join-Path $TestDrive 'summary'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'keep.txt'), 'KEEP')
        [IO.File]::WriteAllText((Join-Path $src 'lost.txt'), 'LOST')
        Invoke-FB $cfg

        # Destroy one row's only data source (Mirror mode).
        Remove-Item -LiteralPath (Join-Path $bkp 'lost.txt') -Force
        $t = Join-Path $root 'r'
        { & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t } |
            Should -Throw -ExpectedMessage '*1 file(s) could not be restored (1 content-missing, 0 host)*'
        # The salvageable row was still restored first.
        [IO.File]::ReadAllText((Join-Path $t 'keep.txt')) | Should -Be 'KEEP'
        # ...and the log carries a per-cause message, not one generic warning.
        (Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw) | Should -Match '\[MissingDataFile\]'
    }
}

Describe 'Restore exit-code table (SR-040)' {
    # TC-070. The whole point of SR-040: a wrapper (HomeHub/NagLight) decides
    # between "your bytes are gone", "fix this host and retry" and "you pointed
    # me at the wrong folder" from the exit STATUS alone. Driven as a child
    # process, because in-process callers keep the terminating-error behavior.
    BeforeAll {
        $script:pwshPath = (Get-Process -Id $PID).Path
        function Invoke-ReconProcess {
            param([string]$Script, [string[]]$Arguments)
            & $script:pwshPath -NoProfile -File $Script -ExitCode @Arguments *>&1 | Out-Null
            return $LASTEXITCODE
        }
        function New-ExitCodeOrigin {
            param([string]$Root)
            $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
            $cfg = Join-Path $Root 'c.xml'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
            [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'AAA')
            Invoke-FB $cfg
            return $bkp
        }
    }

    It 'returns 0 for a clean restore (SR-040)' {
        $root = Join-Path $TestDrive 'x0'
        $bkp = New-ExitCodeOrigin $root
        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') @('-TargetRoot', (Join-Path $root 'r')) |
            Should -Be 0
    }

    It 'returns 1 when a row only data source is gone (content class) (SR-040)' {
        $root = Join-Path $TestDrive 'x1'
        $bkp = New-ExitCodeOrigin $root
        Remove-Item -LiteralPath (Join-Path $bkp 'a.txt') -Force
        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') @('-TargetRoot', (Join-Path $root 'r')) |
            Should -Be 1
    }

    It 'returns 2 for a target inside the backup and for a missing manifest (SR-040)' {
        $root = Join-Path $TestDrive 'x2'
        $bkp = New-ExitCodeOrigin $root
        $recon = Join-Path $bkp 'RECONSTRUCT.ps1'
        Invoke-ReconProcess $recon @('-TargetRoot', (Join-Path $bkp 'inside')) | Should -Be 2

        Remove-Item -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -Force
        Remove-Item -LiteralPath (Join-Path $bkp (Get-FileBackupDefaults).WitnessFilename) -Force
        Invoke-ReconProcess $recon @('-TargetRoot', (Join-Path $root 'r')) | Should -Be 2
    }

    It 'returns 2 when a FILE occupies the target path (SR-040)' {
        # An unclassified terminating error (New-Item over a file) used to escape
        # and leave the status at 1 — which the table reserves for "content
        # unrecoverable / data loss". Nothing was attempted, so it is a
        # PRECONDITION failure, and reconstruct.sh's `mkdir -p || die` returns 2
        # for exactly this cause: the two restorers must agree.
        $root = Join-Path $TestDrive 'x2-file'
        $bkp = New-ExitCodeOrigin $root
        $blocked = Join-Path $root 'r-is-a-file'
        [IO.File]::WriteAllText($blocked, 'I am a file, not a folder')
        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') @('-TargetRoot', $blocked) | Should -Be 2
        # The file is left exactly as it was.
        [IO.File]::ReadAllText($blocked) | Should -Be 'I am a file, not a folder'
    }

    It 'returns 3 when the manifest disagrees with its witness (SR-040)' {
        $root = Join-Path $TestDrive 'x3'
        $bkp = New-ExitCodeOrigin $root
        $manifest = Join-Path $bkp 'MANIFEST.csv'
        $bytes = [IO.File]::ReadAllBytes($manifest)
        [IO.File]::WriteAllBytes($manifest, $bytes[0..($bytes.Length - 25)])
        $t = Join-Path $root 'r'
        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') @('-TargetRoot', $t) | Should -Be 3
        # 3 means the index is untrustworthy: NOTHING reached the target — not a
        # manifest row, not even the restorer's own log, because verification
        # runs before the target folder exists (SR-039).
        Test-Path -LiteralPath $t | Should -BeFalse
    }

    It 'returns 4 when hash recovery needs a 7-Zip this host lacks (host class) (SR-040)' {
        $root = Join-Path $TestDrive 'x4'
        $bkp = New-ExitCodeOrigin $root
        $manifest = Join-Path $bkp 'MANIFEST.csv'

        # Blank the DataPath so the row must be hash-recovered, and leave only an
        # ARCHIVE candidate in the pool. The row itself stays Compressed=No, so
        # the up-front 7-Zip precondition (exit 2) does not fire — the dependency
        # is discovered during recovery, which is a HOST problem, not lost data.
        $rows = Import-Csv -LiteralPath $manifest
        $rows[0].DataPath = ''
        $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
        Write-ManifestWitness -FolderPath $bkp | Out-Null
        Move-Item -LiteralPath (Join-Path $bkp 'a.txt') -Destination (Join-Path $bkp 'a.7z') -Force

        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') `
            @('-TargetRoot', (Join-Path $root 'r'), '-SevenZipPath', (Join-Path $root 'no-7z.exe')) |
            Should -Be 4
    }

    It 'still THROWS with the existing wording when called in-process (SR-040)' {
        # The -ExitCode switch is opt-in precisely so every in-process caller and
        # the six Should -Throw assertions keep working unchanged.
        $root = Join-Path $TestDrive 'x-inproc'
        $bkp = New-ExitCodeOrigin $root
        Remove-Item -LiteralPath (Join-Path $bkp 'a.txt') -Force
        { & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot (Join-Path $root 'r') } |
            Should -Throw -ExpectedMessage '*1 file(s) could not be restored*'
    }
}

Describe 'Move loops aggregate failures (SR-041)' {
    # TC-073. HomeHub cross-check finding J: one failed Move-Item escaped
    # Invoke-BackupSet, which hid every other failure, skipped snapshot
    # finalization, and left the Temp staging folder behind — so the NEXT run
    # aborted on the SR-017 stale-staging guard. A single locked file must not
    # cost the user their next backup too.
    It 'logs an ERROR per failed move, still finalizes the snapshot, and leaves no Temp behind (SR-041)' {
        $root = Join-Path $TestDrive 's41'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg    # Mirror, no compress

        # Run 1: four files, two of which this run will supersede/remove.
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'),  'OLD-SUPERSEDED')
        [IO.File]::WriteAllText((Join-Path $src 'gone.txt'),   'OLD-REMOVED')
        [IO.File]::WriteAllText((Join-Path $src 'super2.txt'), 'OLD-SUPERSEDED-2')
        [IO.File]::WriteAllText((Join-Path $src 'gone2.txt'),  'OLD-REMOVED-2')
        Invoke-FB $cfg

        # Set up run 2: supersede one file (Save-SupersededData path) and remove
        # another (Move-RemovedFilesToStaging path), so BOTH loops have work.
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'),  'NEW-CONTENT')
        [IO.File]::WriteAllText((Join-Path $src 'super2.txt'), 'NEW-CONTENT-2')
        Remove-Item -LiteralPath (Join-Path $src 'gone.txt')  -Force
        Remove-Item -LiteralPath (Join-Path $src 'gone2.txt') -Force

        # Hold TWO backup data files open with no sharing, so their moves fail —
        # one in each loop. FileShare::None makes Move-Item throw exactly the way
        # a real locked file (AV scanner, open handle) does.
        $lock1 = [IO.File]::Open((Join-Path $bkp 'super.txt'), 'Open', 'Read', 'None')
        $lock2 = [IO.File]::Open((Join-Path $bkp 'gone.txt'),  'Open', 'Read', 'None')
        try {
            # Child process so the exit code is observable.
            & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
            $code = $LASTEXITCODE
        }
        finally {
            $lock1.Dispose(); $lock2.Dispose()
        }

        $log = Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw

        # 1. Each failure is logged as its own ERROR naming the file — not one
        #    generic abort that hides the second failure.
        $log | Should -Match "ERROR.*Failed to preserve superseded data for 'super\.txt'"
        $log | Should -Match "ERROR.*Failed to evict 'gone\.txt'"
        # 2. ...plus a summary count per loop.
        $log | Should -Match 'Superseded-data preservation finished with 1 failure'
        $log | Should -Match 'Removed-file eviction finished with 1 failure'
        # 3. The run reports overall failure.
        $code | Should -Be 1

        # 4. Every MOVABLE entry was still staged: the loops continued past the
        #    failures instead of aborting on the first one.
        $snaps = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' })
        $snaps.Count | Should -Be 1
        $snap = $snaps[0].FullName
        [IO.File]::ReadAllText((Join-Path $snap 'super2.txt')) | Should -Be 'OLD-SUPERSEDED-2'
        [IO.File]::ReadAllText((Join-Path $snap 'gone2.txt'))  | Should -Be 'OLD-REMOVED-2'

        # 5. The snapshot was still FINALIZED (it has its own manifest + witness)
        #    rather than being abandoned mid-flight.
        Test-Path -LiteralPath (Join-Path $snap 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        (Test-ManifestWitness -FolderPath $snap).Status | Should -Be 'Verified'

        # 6. No Temp staging folder survives...
        @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -eq 'Temp' }) |
            Should -BeNullOrEmpty

        # 7. ...so the NEXT run proceeds normally instead of tripping the SR-017
        #    stale-staging guard. This is the half that actually cost the user a
        #    backup before the fix.
        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw) | Should -Not -Match 'stale'
    }
}

Describe 'The shipped example config is executable (SR-042)' {
    BeforeAll {
        function Get-JsonKeyShape {
            <#
            .SYNOPSIS
                Recursively collects "<path>=<JSON-type>" strings for every key
                in a ConvertFrom-Json object, so two documents can be proven
                key-identical without caring about their (path) values.
            #>
            param($Node, [string]$JsonPath = '$')
            $out = [string[]]@()
            if ($null -eq $Node) { return , $out }
            if ($Node -is [System.Management.Automation.PSCustomObject]) {
                foreach ($prop in ($Node.PSObject.Properties.Name | Sort-Object)) {
                    $childPath = "$JsonPath.$prop"
                    $out += $childPath
                    $out += @(Get-JsonKeyShape -Node $Node.$prop -JsonPath $childPath)
                }
            } elseif ($Node -is [array]) {
                for ($i = 0; $i -lt $Node.Count; $i++) {
                    $out += @(Get-JsonKeyShape -Node $Node[$i] -JsonPath "$JsonPath[$i]")
                }
            }
            # Comma-prefix: an empty array would otherwise enumerate to zero
            # pipeline objects on return, making the captured result $null.
            return , $out
        }
    }

    It 'runs the checked-in container/FileBackup.example.json, with only its paths and 7-Zip path retargeted, to a byte-exact restore (SR-042, SR-034)' {
        $exampleFile = Join-Path $repo 'container\FileBackup.example.json'
        $exampleObj  = Get-Content -LiteralPath $exampleFile -Raw | ConvertFrom-Json

        $src = Join-Path $TestDrive 'ex76\src'; $state = Join-Path $TestDrive 'ex76\state'
        $bkp = Join-Path $TestDrive 'ex76\bkp'; $chg = Join-Path $TestDrive 'ex76\chg'
        New-Item -ItemType Directory -Path $src, $state -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'report.txt'), ('EXAMPLE CONFIG DATA ' * 500))

        # Retarget ONLY the path fields and the 7-Zip tool path; every other key
        # (ConfigVersion, Name, HashRecalcFreq, CompressEnabled, PreserveFolderTree)
        # is kept exactly as checked in.
        $exampleObj.BackupSets[0].SourcePath      = $src
        $exampleObj.BackupSets[0].SourceStatePath = $state
        $exampleObj.BackupSets[0].BackupPath      = $bkp
        $exampleObj.BackupSets[0].ChangePath      = $chg
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        $exampleObj.Tools.SevenZipPath = $sevenZip

        # Keys-only diff (SR-042): the executed document must be key-identical to
        # the checked-in example, so the example can no longer silently drift
        # from the contract it is supposed to demonstrate. This half is cheap and
        # host-independent, so it runs BEFORE the 7-Zip skip guard below -- a
        # runner without 7-Zip must still catch example drift.
        $checkedInShape = Get-JsonKeyShape -Node (Get-Content -LiteralPath $exampleFile -Raw | ConvertFrom-Json)
        $executedShape  = Get-JsonKeyShape -Node $exampleObj
        Compare-Object -ReferenceObject $checkedInShape -DifferenceObject $executedShape | Should -BeNullOrEmpty

        # The rest drives a real compressed backup, which needs a real 7-Zip.
        if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because "No 7-Zip found at the platform default '$sevenZip'; TC-076 needs a real 7-Zip to exercise the example's CompressEnabled=true set."
            return
        }

        $cfgPath = Join-Path $TestDrive 'ex76\config.json'
        $exampleObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8

        Invoke-FB $cfgPath

        Test-Path -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        foreach ($kit in 'RECONSTRUCT.ps1', 'RECONSTRUCT.bat', 'reconstruct.sh', 'FileBackup.Common.psm1') {
            Test-Path -LiteralPath (Join-Path $bkp $kit) -PathType Leaf | Should -BeTrue
        }

        $target = Join-Path $TestDrive 'ex76-restore'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        $restored = Join-Path $target 'report.txt'
        Test-Path -LiteralPath $restored -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath (Join-Path $src 'report.txt')).Hash | Should -Be (Get-FileHash -LiteralPath $restored).Hash
    }
}

Describe 'Published JSON schema matches the validator (SR-042)' {
    BeforeAll {
        # Test-Json is given the JSON and the schema as STRINGS: -Path /
        # -SchemaFile file forms were only added in pwsh 7.4, and AGENTS.md's
        # floor is "PowerShell 7+". The string form works on every 7.x.
        $script:schemaText = Get-Content -LiteralPath (Join-Path $repo 'container\FileBackup.schema.json') -Raw
    }

    It 'agrees with Import-BackupConfiguration on ACCEPTED shared-corpus fixture <Name> (SR-042)' -ForEach $configCorpus.Accepted {
        Test-Json -Json $Json -Schema $schemaText | Should -BeTrue

        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($path, $Json)
        { Import-BackupConfiguration -Path $path } | Should -Not -Throw
    }

    It 'agrees with Import-BackupConfiguration on REJECTED shared-corpus fixture <Name> (SR-042)' -ForEach $configCorpus.Rejected {
        (Test-Json -Json $Json -Schema $schemaText -ErrorAction SilentlyContinue) | Should -BeFalse

        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllText($path, $Json)
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage $Message
    }

    It 'declares the shipped example, the README block, and the smoke config all at ConfigVersion 1 (the loader''s current maximum)' {
        $exampleObj = Get-Content -LiteralPath (Join-Path $repo 'container\FileBackup.example.json') -Raw | ConvertFrom-Json
        $exampleObj.ConfigVersion | Should -Be 1

        $readme = Get-Content -LiteralPath (Join-Path $repo 'README.md') -Raw
        if ($readme -match '(?s)```json\r?\n(\{.*?"BackupSets".*?\})\r?\n```') {
            $readmeObj = $Matches[1] | ConvertFrom-Json
            $readmeObj.ConfigVersion | Should -Be 1
        } else {
            throw "Could not locate the README JSON config block to check its ConfigVersion."
        }

        $invokeContainerSrc = Get-Content -LiteralPath (Join-Path $repo 'scripts\Invoke-Container.ps1') -Raw
        $invokeContainerSrc | Should -Match 'ConfigVersion\s*=\s*1'
    }
}

Describe 'Entry-point status codes (SR-043)' {
    BeforeAll {
        function New-JsonBackupConfig {
            param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg, [string]$Name = 'S')
            [ordered]@{
                ConfigVersion = 1
                BackupSets    = @(
                    [ordered]@{
                        Name = $Name; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
                        HashRecalcFreq = 'A'; CompressEnabled = $false; PreserveFolderTree = $true
                    }
                )
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
        }

        # Child process so the exit code is observable without ending this
        # runspace -- -ExitCode calls `exit`, which would tear down an
        # in-process caller (SR-043's help text: only entry points pass it).
        function Invoke-FBChild {
            param([string]$Cfg, [switch]$WithExitCode)
            $extra = @{}
            if ($WithExitCode) { $extra['ExitCode'] = $true }
            & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Cfg -NoMail -NonInteractive @extra *>&1 | Out-Null
            return $LASTEXITCODE
        }
    }

    It 'returns 2 for a schema-violating config under -ExitCode, creating no backup artifacts' {
        $root = Join-Path $TestDrive 'tc078-bad'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $cfg = Join-Path $root 'config.json'
        '{"BackupSets":[]}' | Set-Content -LiteralPath $cfg -Encoding UTF8   # missing ConfigVersion (SR-042)

        (Invoke-FBChild -Cfg $cfg -WithExitCode) | Should -Be 2
        Test-Path -LiteralPath $bkp | Should -BeFalse
    }

    It 'returns 2 for a MISSING config file under -ExitCode (the likeliest container misconfiguration: retrying will not help) (SR-043)' {
        $root = Join-Path $TestDrive 'tc078-missing'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        (Invoke-FBChild -Cfg (Join-Path $root 'no-such-config.json') -WithExitCode) | Should -Be 2
    }

    It 'returns 2 for an unreadable/unsupported config extension under -ExitCode (SR-043)' {
        $root = Join-Path $TestDrive 'tc078-badext'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $cfg = Join-Path $root 'config.txt'
        [IO.File]::WriteAllText($cfg, 'whatever')
        (Invoke-FBChild -Cfg $cfg -WithExitCode) | Should -Be 2
    }

    It 'a REFUSED config creates no artifacts and never truncates the previous run''s global log (SR-042, SR-043)' {
        $root = Join-Path $TestDrive 'tc078-nolosslog'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        # 1. A seeded log from a "previous run" survives a refused run intact.
        $seededLog = Join-Path $root 'logs\Backup_Global.log'
        New-Item -ItemType Directory -Path (Split-Path $seededLog) -Force | Out-Null
        [IO.File]::WriteAllText($seededLog, "PREVIOUS RUN EVIDENCE`r`n")
        $badCfg = Join-Path $root 'bad.json'
        [IO.File]::WriteAllText($badCfg, '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":"false","PreserveFolderTree":false}]}')

        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $badCfg `
            -GlobalLogPath $seededLog -NoMail -NonInteractive -ExitCode *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 2
        (Get-Content -LiteralPath $seededLog -Raw) | Should -Match 'PREVIOUS RUN EVIDENCE'

        # 2. A refused run against a fresh location creates NOTHING -- not even
        #    the log directory (New-Logger truncates, so the file must not be
        #    created before the configuration is known to be good).
        $freshLog = Join-Path $root 'fresh-logs\Backup_Global.log'
        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $badCfg `
            -GlobalLogPath $freshLog -NoMail -NonInteractive -ExitCode *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 2
        Test-Path -LiteralPath (Split-Path $freshLog) | Should -BeFalse
    }

    It 'returns 1 when the one backup set fails, under -ExitCode' {
        $root = Join-Path $TestDrive 'tc078-setfail'
        $cfg = Join-Path $root 'config.json'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        # A well-formed config (passes SR-042) whose SourcePath does not exist:
        # the set fails at Resolve-BackupSetPaths, which FileBackup.ps1's
        # per-set try/catch turns into overall failure -- exit 1 regardless of
        # -ExitCode, unchanged since before WP2.
        New-JsonBackupConfig -Path $cfg -Src (Join-Path $root 'no-such-source') -Bkp (Join-Path $root 'bkp') -Chg (Join-Path $root 'chg')

        (Invoke-FBChild -Cfg $cfg -WithExitCode) | Should -Be 1
    }

    It 'returns 0 for a clean single-set run under -ExitCode' {
        $root = Join-Path $TestDrive 'tc078-clean'; $src = Join-Path $root 'src'
        $cfg = Join-Path $root 'config.json'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'clean run')
        New-JsonBackupConfig -Path $cfg -Src $src -Bkp (Join-Path $root 'bkp') -Chg (Join-Path $root 'chg')

        (Invoke-FBChild -Cfg $cfg -WithExitCode) | Should -Be 0
    }

    It 'without -ExitCode returns the pre-WP2 codes: a bad config still exits non-zero (1, not 2), a failed set still exits 1, a clean run still exits 0' {
        $root = Join-Path $TestDrive 'tc078-nopswitch'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $badCfg = Join-Path $root 'bad.json'
        '{"BackupSets":[]}' | Set-Content -LiteralPath $badCfg -Encoding UTF8
        (Invoke-FBChild -Cfg $badCfg) | Should -Be 1

        $failCfg = Join-Path $root 'fail.json'
        New-JsonBackupConfig -Path $failCfg -Src (Join-Path $root 'no-such-source-2') -Bkp (Join-Path $root 'bkp2') -Chg (Join-Path $root 'chg2')
        (Invoke-FBChild -Cfg $failCfg) | Should -Be 1

        $cleanSrc = Join-Path $root 'src3'
        New-Item -ItemType Directory -Path $cleanSrc -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $cleanSrc 'f.txt'), 'clean')
        $cleanCfg = Join-Path $root 'clean.json'
        New-JsonBackupConfig -Path $cleanCfg -Src $cleanSrc -Bkp (Join-Path $root 'bkp3') -Chg (Join-Path $root 'chg3')
        (Invoke-FBChild -Cfg $cleanCfg) | Should -Be 0
    }

    It 'still throws for a bad config when invoked in-process without -ExitCode' {
        $root = Join-Path $TestDrive 'tc078-inprocess'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $cfg = Join-Path $root 'bad.json'
        '{"BackupSets":[]}' | Set-Content -LiteralPath $cfg -Encoding UTF8

        { & $entry -ConfigPath $cfg -NoMail -NonInteractive } | Should -Throw -ExpectedMessage '*ConfigVersion*missing*'
    }

    It 'a two-set JSON config logs the IF-001 one-set-per-invocation warning while still processing both sets' {
        $root = Join-Path $TestDrive 'tc078-twoset'
        $cfg = Join-Path $root 'config.json'
        $srcA = Join-Path $root 'srcA'; $srcB = Join-Path $root 'srcB'
        $bkpA = Join-Path $root 'bkpA'; $bkpB = Join-Path $root 'bkpB'
        $log  = Join-Path $root 'logs\global.log'
        New-Item -ItemType Directory -Path $srcA, $srcB -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $srcA 'a.txt'), 'A')
        [IO.File]::WriteAllText((Join-Path $srcB 'b.txt'), 'B')
        [ordered]@{
            ConfigVersion = 1
            BackupSets    = @(
                [ordered]@{ Name = 'A'; SourcePath = $srcA; BackupPath = $bkpA; ChangePath = (Join-Path $root 'chgA'); HashRecalcFreq = 'A'; CompressEnabled = $false; PreserveFolderTree = $true }
                [ordered]@{ Name = 'B'; SourcePath = $srcB; BackupPath = $bkpB; ChangePath = (Join-Path $root 'chgB'); HashRecalcFreq = 'A'; CompressEnabled = $false; PreserveFolderTree = $true }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfg -Encoding UTF8

        & $entry -ConfigPath $cfg -GlobalLogPath $log -NoMail -NonInteractive *>&1 | Out-Null

        Test-Path -LiteralPath (Join-Path $bkpA 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $bkpB 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $log -Raw) | Should -Match '(?i)2 BackupSets entries.*IF-001'
    }
}
