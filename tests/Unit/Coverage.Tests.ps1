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

    # --- WP4 retention fixtures (TC-081, TC-084..087) ------------------------
    function New-PruneTimeline {
        <#
        .SYNOPSIS
            Builds a three-run store: shared content, superseded content and a
            deleted file, so the NEWEST snapshot holds bytes an older snapshot
            can only reach by hash (Save-SupersededData parks superseded bytes
            in the newest snapshot — the expensive prune case).
        #>
        param([string]$Root, [bool]$Compress = $false, [bool]$ContentAddressed = $false,
              [bool]$SuffixNamedUserFiles = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress -ContentAddressed $ContentAddressed
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        [IO.File]::WriteAllText((Join-Path $src 'keep.txt'),  'KEEP ' * 40)
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'), 'VERSION-ONE ' * 40)
        [IO.File]::WriteAllText((Join-Path $src 'gone.txt'),  'DOOMED ' * 40)
        # B6: a NESTED file named like infrastructure is user data and must
        # travel through prune like any other content.
        [IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv'), 'nested,not,infrastructure' * 5)
        # WP4 review finding H1: a genuine user file whose name ends in the
        # prune mechanism's staging suffix. In Mirror mode it is stored at its
        # verbatim path, so a bare-suffix sweep destroyed it in every folder at
        # once. Root-level AND nested, because the sweep recursed.
        if ($SuffixNamedUserFiles) {
            [IO.File]::WriteAllText((Join-Path $src 'notes.fbprune.tmp'), 'USER CONTENT THAT MERELY LOOKS LIKE RESIDUE ' * 3)
            [IO.File]::WriteAllText((Join-Path $src 'sub\notes.fbprune.tmp'), 'NESTED USER CONTENT ' * 7)
        }
        & $run ([datetime]'2024-01-01 00:00:01')                        # state1
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'), 'VERSION-TWO ' * 40)
        & $run ([datetime]'2024-02-02 00:00:02')                        # state2 => Snapshot(D1)
        Remove-Item -LiteralPath (Join-Path $src 'gone.txt') -Force
        & $run ([datetime]'2024-03-03 00:00:03')                        # state3 => Snapshot(D2)
        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg
            Oldest = 'Snapshot_2024_01_01_00_00_01'; Newest = 'Snapshot_2024_02_02_00_00_02'
        }
    }
    function Get-StoreFingerprint {
        # '*.fbprune.tmp' is deliberately excluded: an aborted re-home may leave
        # a staged copy behind, which is invisible to both restorers and swept by
        # the next invocation (SR-046). Everything else must be byte-identical.
        param([string[]]$Folder)
        $out = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -Recurse | Where-Object { $_.Name -notlike '*.fbprune.tmp' })) {
            $out[$f.FullName] = "$($f.Length)|$(Get-FileXxHash -FilePath $f.FullName)"
        }
        return $out
    }
    function Get-StoreBytes {
        param([string[]]$Folder)
        return [long](Get-ChildItem -LiteralPath $Folder -File -Recurse | Measure-Object -Property Length -Sum).Sum
    }
    function Assert-StoreUnchanged {
        param([hashtable]$Before, [string[]]$Folder)
        $after = Get-StoreFingerprint -Folder $Folder
        $after.Count | Should -Be $Before.Count
        foreach ($k in $Before.Keys) { $after[$k] | Should -Be $Before[$k] }
    }
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

Describe 'Optimize-ChangeFolders is unchanged by the shared index (SR-026)' {
    # TC-089 — the regression pin for WP4 phase A. Optimize-ChangeFolders'
    # inline reference scan is lifted into Get-BackupContentIndex so prune can
    # reuse it; these post-conditions are asserted against a hand-built pool so
    # the lift can be proven behavior-preserving rather than assumed.
    BeforeAll {
        function New-PoolRow {
            param([string]$DataPath, [string]$RelativePath, [long]$Length,
                  [string]$Hash, [string]$Compressed = 'No', [string]$StoredAs = 'Original')
            [pscustomobject]@{
                DataPath = $DataPath; RelativePath = $RelativePath; Length = $Length
                LastWriteTime = [datetime]'2024-01-01 00:00:00'; xxH2Hash = $Hash
                Compressed = $Compressed; StoredAsHashSize = $StoredAs
                Duplicate = 'No'; MediaMBPerSec = ''
            }
        }
        function New-PoolFile {
            param([string]$Folder, [string]$Name, [string]$Content)
            $full = Join-Path $Folder $Name
            $dir = [IO.Path]::GetDirectoryName($full)
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.File]::WriteAllText($full, $Content)
            return $full
        }
    }

    It 'keeps the backup copy, elects the newest snapshot without one, blanks vanished rows, and leaves one physical copy per key (SR-026)' {
        $root = Join-Path $TestDrive 'tc089'
        $bkp  = Join-Path $root 'bkp'
        $chg  = Join-Path $root 'chg'
        $s1   = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        $s2   = Join-Path $chg 'Snapshot_2024_02_02_00_00_02'
        New-Item -ItemType Directory -Path $bkp, $s1, $s2 -Force | Out-Null

        $X = 'ROOT-KEPT-CONTENT ' * 20      # lives in the root AND both snapshots
        $Y = 'SNAPSHOT-ONLY-CONTENT ' * 20  # lives in both snapshots only
        $Z = 'VANISHED-CONTENT ' * 20       # referenced by a snapshot row, no file anywhere

        $fx = New-PoolFile $bkp 'x.txt' $X
        New-PoolFile $s1 'x.txt' $X | Out-Null
        New-PoolFile $s2 'x.txt' $X | Out-Null
        New-PoolFile $s1 'y.txt' $Y | Out-Null
        New-PoolFile $s2 'y.txt' $Y | Out-Null
        $hx = Get-FileXxHash -FilePath $fx; $lx = (Get-Item -LiteralPath $fx).Length
        $hy = Get-FileXxHash -FilePath (Join-Path $s1 'y.txt'); $ly = (Get-Item -LiteralPath (Join-Path $s1 'y.txt')).Length

        Write-Manifest -FolderPath $bkp -Records @(New-PoolRow 'x.txt' 'x.txt' $lx $hx)
        Write-Manifest -FolderPath $s1 -Records @(
            (New-PoolRow 'x.txt' 'x.txt' $lx $hx),
            (New-PoolRow 'y.txt' 'y.txt' $ly $hy),
            (New-PoolRow 'gone.txt' 'gone.txt' $Z.Length 'DEADBEEFDEADBEEFDEADBEEFDEADBEEF'))
        Write-Manifest -FolderPath $s2 -Records @(
            (New-PoolRow 'x.txt' 'x.txt' $lx $hx),
            (New-PoolRow 'y.txt' 'y.txt' $ly $hy))

        Optimize-ChangeFolders -ChangeRoot $chg -BackupRoot $bkp -Log { param($m, $l) } | Out-Null

        # 1. The backup copy is always the keeper, and no backup-root file is deleted.
        Test-Path -LiteralPath (Join-Path $bkp 'x.txt') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $s1 'x.txt') -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $s2 'x.txt') -PathType Leaf | Should -BeFalse

        # 2. Absent a root copy the NEWEST snapshot wins.
        Test-Path -LiteralPath (Join-Path $s2 'y.txt') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $s1 'y.txt') -PathType Leaf | Should -BeFalse

        # 3. Every row whose data file went away is blanked (restore recovers by hash),
        #    including the row whose file never existed.
        $m1 = @(Read-Manifest -FolderPath $s1)
        ($m1 | Where-Object { $_.RelativePath -eq 'x.txt' }).DataPath    | Should -BeNullOrEmpty
        ($m1 | Where-Object { $_.RelativePath -eq 'y.txt' }).DataPath    | Should -BeNullOrEmpty
        ($m1 | Where-Object { $_.RelativePath -eq 'gone.txt' }).DataPath | Should -BeNullOrEmpty
        $m2 = @(Read-Manifest -FolderPath $s2)
        ($m2 | Where-Object { $_.RelativePath -eq 'x.txt' }).DataPath | Should -BeNullOrEmpty
        ($m2 | Where-Object { $_.RelativePath -eq 'y.txt' }).DataPath | Should -Be 'y.txt'

        # 4. Row sets are otherwise untouched — Optimize only ever blanks DataPath.
        $m1.Count | Should -Be 3
        $m2.Count | Should -Be 2

        # 5. Every rewritten manifest is re-witnessed (Write-Manifest, never Export-Csv).
        foreach ($folder in $bkp, $s1, $s2) {
            (Test-ManifestWitness -FolderPath $folder).Status | Should -Be 'Verified'
        }

        # 6. TC-049's property on the quiescent pool: exactly one physical copy per key.
        foreach ($pair in @(@($hx, $lx), @($hy, $ly))) {
            @(Get-ChildItem -LiteralPath $bkp, $chg -File -Recurse |
                Where-Object { $_.Name -notmatch '^MANIFEST\.csv' -and $_.Length -eq $pair[1] -and
                               (Get-FileXxHash -FilePath $_.FullName) -eq $pair[0] }).Count | Should -Be 1
        }
    }

    It 'does nothing when the change root has no snapshot folders (SR-026)' {
        $root = Join-Path $TestDrive 'tc089b'
        $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $bkp, $chg -Force | Out-Null
        $f = New-PoolFile $bkp 'only.txt' 'ONLY'
        Write-Manifest -FolderPath $bkp -Records @(New-PoolRow 'only.txt' 'only.txt' (Get-Item -LiteralPath $f).Length (Get-FileXxHash -FilePath $f))
        $before = Get-FileXxHash -FilePath (Join-Path $bkp 'MANIFEST.csv')

        Optimize-ChangeFolders -ChangeRoot $chg -BackupRoot $bkp -Log { param($m, $l) } | Out-Null

        Test-Path -LiteralPath (Join-Path $bkp 'only.txt') -PathType Leaf | Should -BeTrue
        Get-FileXxHash -FilePath (Join-Path $bkp 'MANIFEST.csv') | Should -Be $before
    }
}

Describe 'Snapshot inventory reports true dedup-aware reclaim (SR-047)' {
    # TC-087. The reclaim figure is the one number HomeHub cannot compute for
    # itself: because of dedup, a snapshot folder's size is NOT what removing it
    # frees. Get-BackupSnapshot reports the figure the real removal achieves,
    # and reports it without touching a single byte.
    It 'reports one record per snapshot with all six fields, and modifies nothing (SR-047)' {
        $root = Join-Path $TestDrive 'tc087'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $inv = @(Get-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg)
        $inv.Count | Should -Be 2
        $inv[0].Name | Should -Be 'Snapshot_2024_01_01_00_00_01'
        $inv[1].Name | Should -Be 'Snapshot_2024_02_02_00_00_02'
        $inv[0].Date | Should -Be ([datetime]'2024-01-01 00:00:01')
        foreach ($rec in $inv) {
            $rec.Rows | Should -BeGreaterThan 0
            $rec.PhysicalBytes | Should -BeGreaterThan 0
            ($rec.BytesReclaimed + $rec.BytesReHomed) | Should -Be $rec.PhysicalBytes
            $rec.Rows | Should -Be @(Read-Manifest -FolderPath (Join-Path $env.Chg $rec.Name)).Count
        }

        # The report is read-only: every file in the store is byte-identical.
        $after = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)
        $after.Count | Should -Be $before.Count
        foreach ($k in $before.Keys) { $after[$k] | Should -Be $before[$k] }
    }

    It 'serializes to one JSON object per snapshot carrying all six fields (SR-047)' {
        $root = Join-Path $TestDrive 'tc087-json'
        $env  = New-PruneTimeline -Root $root
        $json = @(Get-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg) | ConvertTo-Json -Depth 4
        $parsed = @($json | ConvertFrom-Json)
        $parsed.Count | Should -Be 2
        foreach ($rec in $parsed) {
            foreach ($field in 'Name', 'Date', 'Rows', 'PhysicalBytes', 'BytesReclaimed', 'BytesReHomed') {
                $rec.PSObject.Properties.Name | Should -Contain $field
            }
        }
    }

    It 'costs nothing to prune the OLDEST snapshot and reports the newest''s re-home cost (SR-045, SR-047)' {
        $root = Join-Path $TestDrive 'tc087-cost'
        $env  = New-PruneTimeline -Root $root
        $plans = @('Snapshot_2024_01_01_00_00_01', 'Snapshot_2024_02_02_00_00_02') |
            ForEach-Object { Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $_ }

        # The oldest snapshot holds no content another state can only get from it
        # (Save-SupersededData parks superseded bytes in the NEWEST snapshot).
        $plans[0].Items.Count | Should -Be 0
        $plans[0].BytesReHomed | Should -Be 0
        # The newest holds the superseded + deleted bytes the older state needs.
        $plans[1].Items.Count | Should -BeGreaterThan 0
        $plans[1].BytesReHomed | Should -BeGreaterThan 0
        foreach ($plan in $plans) { $plan.Problems.Count | Should -Be 0 }
    }

    It 'refuses an unknown snapshot name with code 2 and no plan (SR-046)' {
        $root = Join-Path $TestDrive 'tc087-unknown'
        $env  = New-PruneTimeline -Root $root
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name 'Snapshot_1999_09_09_09_09_09'
        $plan.Problems.Count | Should -Be 1
        $plan.Problems[0].Code | Should -Be 2
        $plan.Items.Count | Should -Be 0
    }
}

Describe 'Prune refuses before mutating (SR-046)' {
    # TC-084. Each rail is induced on a real store, and every refusal must name
    # its SR-040 code AND leave the tree byte-identical — FileBackupState.json,
    # every manifest and every witness included. Manifests tampered with on
    # purpose are re-stamped with Write-ManifestWitness, or the failure observed
    # would be exit 3 instead of the one the case means to exercise (AGENTS.md §3).
    BeforeAll {
        function Get-Refusal {
            param([pscustomobject]$Env, [string]$Name, [hashtable]$Extra = @{})
            $plan = Get-SnapshotPrunePlan -BackupRoot $Env.Bkp -ChangeRoot $Env.Chg -Name $Name
            return @(Assert-PrunePrecondition -BackupRoot $Env.Bkp -ChangeRoot $Env.Chg -Plan $plan @Extra)
        }
    }

    It 'accepts a healthy store with no refusals at all (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-clean'
        $env  = New-PruneTimeline -Root $root
        (Get-Refusal -Env $env -Name $env.Newest).Count | Should -Be 0
    }

    It 'refuses <Kind> with code <Code>, leaving the store byte-identical (SR-046, SR-040)' -ForEach @(
        @{ Kind = 'bad-target'; Code = 2; Target = 'Snapshot_1999_09_09_09_09_09'; Extra = @{}; Induce = { param($e) } }
        @{ Kind = 'bad-target'; Code = 2; Target = '..\elsewhere';                 Extra = @{}; Induce = { param($e) } }
        @{ Kind = 'run-state';  Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e) [IO.File]::WriteAllText((Join-Path $e.Bkp 'FileBackupState.json'), '{ not json') } }
        @{ Kind = 'staging-busy'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e) New-Item -ItemType Directory -Path (Join-Path $e.Chg 'Temp') -Force | Out-Null } }
        @{ Kind = 'unreferenced-data'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e) [IO.File]::WriteAllText((Join-Path (Join-Path $e.Chg $e.Newest) 'mystery.dat'), 'UNEXPLAINED BYTES') } }
        @{ Kind = 'broken-pool'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e)
                # A backup-root row left pointing at a file that is not there.
                $rows = @(Read-Manifest -FolderPath $e.Bkp)
                $rows[0].DataPath = 'no-such-file.txt'
                Write-Manifest -FolderPath $e.Bkp -Records $rows } }
        @{ Kind = 'form-mismatch'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e)
                # Claim a plain data file is compressed: hash recovery would hand
                # raw bytes to the 7-Zip branch (the finding-C family).
                $rows = @(Read-Manifest -FolderPath $e.Bkp)
                ($rows | Where-Object { $_.RelativePath -eq 'keep.txt' })[0].Compressed = 'Yes'
                Write-Manifest -FolderPath $e.Bkp -Records $rows } }
        @{ Kind = 'witness-mismatch'; Code = 3; Target = $null; Extra = @{}; Induce = {
                param($e)
                $m = Join-Path $e.Bkp 'MANIFEST.csv'
                [IO.File]::AppendAllText($m, "`r`n")   # deliberately NOT re-stamped: this case IS the witness
            } }
        @{ Kind = 'witness-absent'; Code = 3; Target = $null; Extra = @{}; Induce = {
                param($e) Remove-Item -LiteralPath (Get-ManifestWitnessPath -FolderPath $e.Bkp) -Force } }
        @{ Kind = 'no-7zip'; Code = 2; Target = $null; Extra = @{ SevenZipPath = 'Z:\no\such\7z.exe' }; Compress = $true; Induce = { param($e) } }
        # The two plan-time rails WP4 shipped untested (review finding M3). The
        # reviewer hand-verified destination-collision; both are pinned here.
        @{ Kind = 'destination-collision'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e)
                # Occupy the elected destination name with DIFFERENT bytes:
                # identical bytes are an interrupted run's completed copy and
                # must NOT refuse, anything else must never be overwritten.
                $plan = Get-SnapshotPrunePlan -BackupRoot $e.Bkp -ChangeRoot $e.Chg -Name $e.Newest
                $item = $plan.Items.ToArray()[0]
                [IO.File]::WriteAllText((Join-Path $item.DestinationFolder $item.DestinationDataPath),
                                        'A DIFFERENT FILE IS ALREADY PARKED ON THIS NAME') } }
        @{ Kind = 'infrastructure-name'; Code = 2; Target = $null; Extra = @{}; Induce = {
                param($e)
                # Make the endangered row's re-homed name a ROOT-LEVEL
                # infrastructure name at the destination — hash recovery skips
                # those (B6), so re-homing onto one would hide the bytes.
                $plan   = Get-SnapshotPrunePlan -BackupRoot $e.Bkp -ChangeRoot $e.Chg -Name $e.Newest
                $item   = $plan.Items.ToArray()[0]
                $folder = Join-Path $e.Chg $e.Newest
                Rename-Item -LiteralPath (Join-Path $folder $item.SourceDataPath) -NewName 'backup.log'
                $rows = @(Read-Manifest -FolderPath $folder)
                $row  = @($rows | Where-Object { $_.DataPath -eq $item.SourceDataPath })[0]
                $row.DataPath = 'backup.log'; $row.RelativePath = 'backup.log'
                Write-Manifest -FolderPath $folder -Records $rows } }
    ) {
        $root = Join-Path $TestDrive ('tc084-' + $Kind + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $env  = New-PruneTimeline -Root $root -Compress ([bool]$Compress)
        & $Induce $env
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $target = if ($Target) { $Target } else { $env.Newest }
        $refusals = Get-Refusal -Env $env -Name $target -Extra $Extra

        @($refusals | Where-Object { $_.Kind -eq $Kind }).Count | Should -BeGreaterThan 0
        @($refusals | Where-Object { $_.Kind -eq $Kind })[0].Code | Should -Be $Code
        @($refusals | Where-Object { $_.Kind -eq $Kind })[0].Message | Should -Not -BeNullOrEmpty
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
    }

    It '-AllowUnverifiedIndex converts the absent-witness refusal into a go (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-allowunverified'
        $env  = New-PruneTimeline -Root $root
        Remove-Item -LiteralPath (Get-ManifestWitnessPath -FolderPath $env.Bkp) -Force

        (Get-Refusal -Env $env -Name $env.Newest).Count | Should -BeGreaterThan 0
        (Get-Refusal -Env $env -Name $env.Newest -Extra @{ AllowUnverifiedIndex = $true }).Count | Should -Be 0
    }

    It '-DiscardUnreferencedData converts the unexplained-bytes refusal into a go (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-discard'
        $env  = New-PruneTimeline -Root $root
        [IO.File]::WriteAllText((Join-Path (Join-Path $env.Chg $env.Newest) 'mystery.dat'), 'UNEXPLAINED BYTES')

        (Get-Refusal -Env $env -Name $env.Newest).Count | Should -BeGreaterThan 0
        (Get-Refusal -Env $env -Name $env.Newest -Extra @{ DiscardUnreferencedData = $true }).Count | Should -Be 0
    }

    It 'still refuses a mismatched witness when -AllowUnverifiedIndex is passed (absent is not damaged) (SR-039)' {
        $root = Join-Path $TestDrive 'tc084-tamper'
        $env  = New-PruneTimeline -Root $root
        [IO.File]::AppendAllText((Join-Path $env.Bkp 'MANIFEST.csv'), "`r`n")

        $refusals = Get-Refusal -Env $env -Name $env.Newest -Extra @{ AllowUnverifiedIndex = $true }
        @($refusals | Where-Object { $_.Kind -eq 'witness-mismatch' })[0].Code | Should -Be 3
    }

    # TC-084's capacity rail (review finding M3). WP4 grouped destinations by
    # `Split-Path -Qualifier` INSIDE a Group-Object key, which throws on a UNC
    # path and took the whole rail with it (the Get-PSDrive fallback was
    # swallowed), so on a UNC store the rail silently did not exist. It is now
    # built on Common's cross-platform probes (SR-052) and is exercised on both
    # path shapes with the probe stubbed.
    It 'refuses with code 2 when a destination volume lacks room, on <Shape> paths (SR-046, SR-052)' -ForEach @(
        @{ Shape = 'drive-qualified'; Folder = 'C:\store\bkp' }
        @{ Shape = 'UNC';             Folder = '\\server\share\store\bkp' }
    ) {
        $items = @([pscustomobject]@{ DestinationFolder = $Folder; Bytes = [long]5000 },
                   [pscustomobject]@{ DestinationFolder = $Folder; Bytes = [long]6000 })

        Mock -ModuleName FileBackup.Engine Get-VolumeIdentity { 'VOL' }
        Mock -ModuleName FileBackup.Engine Get-FreeSpaceBytes { [long]10000 }
        $refusals = @(Get-PruneCapacityRefusal -Item $items -PlanName 'Snapshot_X')
        $refusals.Count | Should -Be 1                       # both items summed on one volume
        $refusals[0].Code | Should -Be 2
        $refusals[0].Kind | Should -Be 'capacity'
        $refusals[0].Message | Should -Match 'required 11000, free 10000'

        Mock -ModuleName FileBackup.Engine Get-FreeSpaceBytes { [long]11000 }
        @(Get-PruneCapacityRefusal -Item $items -PlanName 'Snapshot_X') | Should -BeNullOrEmpty
    }

    It 'skips the capacity rail when the volume cannot be measured, rather than refusing (SR-052)' {
        Mock -ModuleName FileBackup.Engine Get-VolumeIdentity { $null }
        Mock -ModuleName FileBackup.Engine Get-FreeSpaceBytes { $null }
        @(Get-PruneCapacityRefusal -Item @([pscustomobject]@{ DestinationFolder = '\\server\share\x'; Bytes = [long]9 }) `
            -PlanName 'Snapshot_X') | Should -BeNullOrEmpty
    }

    It 'neither probe fails on a UNC or rooted path, where Split-Path -Qualifier cannot answer (AGENTS.md 4)' {
        foreach ($path in '\\server\share\store', '/backup') {
            { Get-VolumeIdentity -Path $path } | Should -Not -Throw
            { Get-FreeSpaceBytes -Path $path } | Should -Not -Throw
            # What the old rail was built on: no qualifier to parse. Under the
            # entry point's $ErrorActionPreference='Stop' that is terminating —
            # inside a Group-Object key it took the whole rail with it; with
            # 'Continue' it yields an empty drive name the swallowed Get-PSDrive
            # fallback then rejects. Either way the rail did not exist on a UNC
            # or POSIX-rooted store.
            { Split-Path -Qualifier $path -ErrorAction Stop } | Should -Throw '*does not have a qualifier*'
        }
    }

    It 'the whole precondition set refuses on capacity against a real store, mutating nothing (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-capacity'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        Mock -ModuleName FileBackup.Engine Get-FreeSpaceBytes { [long]1 }
        $refusals = Get-Refusal -Env $env -Name $env.Newest
        @($refusals | Where-Object { $_.Kind -eq 'capacity' }).Count | Should -Be 1
        @($refusals | Where-Object { $_.Kind -eq 'capacity' })[0].Code | Should -Be 2
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
    }

    It 'proves the surviving pool resolves with the target excluded, and does not without a re-home (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-poolproof'
        $env  = New-PruneTimeline -Root $root
        $newest = Join-Path $env.Chg $env.Newest

        # As it stands the pool resolves...
        Test-PoolResolves -BackupRoot $env.Bkp -ChangeRoot $env.Chg | Should -BeNullOrEmpty
        # ...but pretending the newest snapshot is already gone breaks the older
        # state, which is exactly the content the re-home has to rescue.
        $withoutNewest = @(Test-PoolResolves -BackupRoot $env.Bkp -ChangeRoot $env.Chg -ExcludeFolder $newest)
        $withoutNewest.Count | Should -BeGreaterThan 0
        $withoutNewest[0].Code | Should -Be 2
        $withoutNewest[0].Kind | Should -Be 'broken-pool'
    }
}

Describe 'Prune re-homes the last copy before deleting (SR-045)' {
    # TC-081 across the four storage modes. The newest snapshot holds the only
    # physical copy of content an older snapshot's blank-DataPath row needs
    # (the eviction of gone.txt), so removing it MUST re-home those bytes first.
    BeforeAll {
        function Restore-Folder {
            param([string]$Origin, [string]$Target)
            if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
            & (Join-Path $Origin 'RECONSTRUCT.ps1') -TargetRoot $Target *>&1 | Out-Null
            return $Target
        }
    }

    It 'in <Mode> re-homes the endangered bytes and every remaining state still restores byte-exact (SR-045)' -ForEach @(
        @{ Mode = 'Mirror';                  Compress = $false; Hashed = $false }
        @{ Mode = 'Mirror+Compress';         Compress = $true;  Hashed = $false }
        @{ Mode = 'HashAddressed';           Compress = $false; Hashed = $true  }
        @{ Mode = 'HashAddressed+Compress';  Compress = $true;  Hashed = $true  }
    ) {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if ($Compress -and -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because "no 7-Zip at '$sevenZip' for the compressed modes"
            return
        }
        $root = Join-Path $TestDrive ('tc081-' + $Mode.Replace('+', '-'))
        $env  = New-PruneTimeline -Root $root -Compress $Compress -ContentAddressed $Hashed

        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        $plan.Items.Count | Should -BeGreaterThan 0
        $item = $plan.Items.ToArray()[0]

        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest -SevenZipPath $sevenZip)
        $result.Count | Should -Be 1
        $result[0].Status | Should -Be 'Pruned'
        $result[0].Code | Should -Be 0
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $env.Chg -Directory | Where-Object { $_.Name -like 'Pruning_*' }) | Should -BeNullOrEmpty

        # The re-homed file is where the plan said, with the SOURCE row's form
        # adopted on the destination row, and its content hashes to the row.
        $destFull = Join-Path $item.DestinationFolder $item.DestinationDataPath
        Test-Path -LiteralPath $destFull -PathType Leaf | Should -BeTrue
        $destRow = @(Read-Manifest -FolderPath $item.DestinationFolder |
                     Where-Object { $_.DataPath -eq $item.DestinationDataPath })[0]
        $destRow.Compressed | Should -Be $item.Compressed
        $destRow.StoredAsHashSize | Should -Be $item.StoredAsHashSize
        if ($destRow.Compressed -eq 'Yes') {
            $scratch = Join-Path $root 'verify.tmp'
            Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $destFull -DestinationFile $scratch
            Get-FileXxHash -FilePath $scratch | Should -Be $destRow.xxH2Hash
            (Get-Item -LiteralPath $scratch).Length | Should -Be ([long]$destRow.Length)
        } else {
            Get-FileXxHash -FilePath $destFull | Should -Be $destRow.xxH2Hash
            (Get-Item -LiteralPath $destFull).Length | Should -Be ([long]$destRow.Length)
        }

        # State1 (the surviving snapshot) restores byte-exact, INCLUDING the file
        # whose only copy lived in the folder just removed.
        $r1 = Restore-Folder -Origin (Join-Path $env.Chg $env.Oldest) -Target (Join-Path $root 'r-state1')
        [IO.File]::ReadAllText((Join-Path $r1 'gone.txt'))  | Should -Be ('DOOMED ' * 40)
        [IO.File]::ReadAllText((Join-Path $r1 'super.txt')) | Should -Be ('VERSION-ONE ' * 40)
        [IO.File]::ReadAllText((Join-Path $r1 'keep.txt'))  | Should -Be ('KEEP ' * 40)
        [IO.File]::ReadAllText((Join-Path $r1 'sub\MANIFEST.csv')) | Should -Be ('nested,not,infrastructure' * 5)

        # ...and so does the latest state from the backup root.
        $r0 = Restore-Folder -Origin $env.Bkp -Target (Join-Path $root 'r-latest')
        [IO.File]::ReadAllText((Join-Path $r0 'super.txt')) | Should -Be ('VERSION-TWO ' * 40)
        Test-Path -LiteralPath (Join-Path $r0 'gone.txt') | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $r0 'sub\MANIFEST.csv')) | Should -Be ('nested,not,infrastructure' * 5)
    }

    It 'copies nothing when the target endangers nothing, and still removes it (SR-045)' {
        $root = Join-Path $TestDrive 'tc081-noop'
        $env  = New-PruneTimeline -Root $root
        $bytesBefore = Get-StoreBytes -Folder @($env.Bkp, $env.Chg)
        $oldestBytes = Get-StoreBytes -Folder @(Join-Path $env.Chg $env.Oldest)

        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Oldest)
        $result[0].Status | Should -Be 'Pruned'
        $result[0].BytesReHomed | Should -Be 0
        (Get-StoreBytes -Folder @($env.Bkp, $env.Chg)) | Should -Be ($bytesBefore - $oldestBytes)
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Oldest) | Should -BeFalse
    }

    It '-WhatIf runs the full preflight, mutates nothing, and reports what the real run then achieves (SR-046)' {
        $root = Join-Path $TestDrive 'tc081-whatif'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $dry = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest -WhatIf)
        $dry[0].Status | Should -Be 'WhatIf'
        $dry[0].Code | Should -Be 0
        $dry[0].BytesReHomed | Should -BeGreaterThan 0
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)

        $real = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $real[0].BytesReclaimed | Should -Be $dry[0].BytesReclaimed
        $real[0].BytesReHomed   | Should -Be $dry[0].BytesReHomed
    }

    It 'removes the LAST remaining snapshot without refusing (SR-045)' {
        $root = Join-Path $TestDrive 'tc081-last'
        $env  = New-PruneTimeline -Root $root
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest, $env.Oldest)
        $result.Count | Should -Be 2
        @($result | Where-Object { $_.Status -eq 'Pruned' }).Count | Should -Be 2
        (Get-PruneBatchExitCode -Result $result) | Should -Be 0
        @(Get-PoolSnapshotFolder -ChangeRoot $env.Chg) | Should -BeNullOrEmpty

        # The latest state is the live backup root and is unaffected.
        $t = Join-Path $root 'r-latest'
        & (Join-Path $env.Bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t 'super.txt')) | Should -Be ('VERSION-TWO ' * 40)
    }
}

Describe 'Prune changes only the storage-form columns (SR-045)' {
    # TC-086: a column-wise before/after diff of EVERY manifest in the pool.
    It 'in <Mode> leaves the row sets and the six logical columns identical (SR-045)' -ForEach @(
        @{ Mode = 'Mirror';                  Compress = $false; Hashed = $false }
        @{ Mode = 'Mirror+Compress';         Compress = $true;  Hashed = $false }
        @{ Mode = 'HashAddressed';           Compress = $false; Hashed = $true  }
        @{ Mode = 'HashAddressed+Compress';  Compress = $true;  Hashed = $true  }
    ) {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if ($Compress -and -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because "no 7-Zip at '$sevenZip' for the compressed modes"
            return
        }
        $root = Join-Path $TestDrive ('tc086-' + $Mode.Replace('+', '-'))
        $env  = New-PruneTimeline -Root $root -Compress $Compress -ContentAddressed $Hashed
        $survivors = @($env.Bkp, (Join-Path $env.Chg $env.Oldest))

        $before = @{}
        foreach ($folder in $survivors) { $before[$folder] = @(Import-Csv -LiteralPath (Join-Path $folder 'MANIFEST.csv')) }
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        $planned = @($plan.Items.ToArray() | ForEach-Object { "$($_.DestinationFolder)|$($_.DestinationRow.RelativePath)" })

        Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest -SevenZipPath $sevenZip | Out-Null

        foreach ($folder in $survivors) {
            $after = @(Import-Csv -LiteralPath (Join-Path $folder 'MANIFEST.csv'))
            $after.Count | Should -Be $before[$folder].Count
            for ($i = 0; $i -lt $after.Count; $i++) {
                $b = $before[$folder][$i]; $a = $after[$i]
                foreach ($col in 'RelativePath', 'Length', 'LastWriteTimeStr', 'xxH2Hash', 'Duplicate', 'MediaMBPerSec') {
                    $a.$col | Should -Be $b.$col
                }
                if ($planned -notcontains "$folder|$($b.RelativePath)") {
                    foreach ($col in 'DataPath', 'Compressed', 'StoredAsHashSize') {
                        $a.$col | Should -Be $b.$col
                    }
                }
            }
        }
    }
}

Describe 'Prune re-stamps every manifest it rewrites (SR-038)' {
    # TC-085. The witness is written by Write-Manifest ONLY, and never copied
    # between folders (AGENTS.md 3 "the single most dangerous mistake").
    It 'leaves every pool manifest Verified after re-homing into <Destination>' -ForEach @(
        @{ Destination = 'snapshot' }, @{ Destination = 'backup-root' }
    ) {
        $root = Join-Path $TestDrive ('tc085-' + $Destination)
        $env  = New-PruneTimeline -Root $root
        if ($Destination -eq 'backup-root') {
            # Make the ROOT the demander: re-introduce the deleted content, so the
            # live state needs the bytes the newest snapshot holds.
            [IO.File]::WriteAllText((Join-Path $env.Src 'gone.txt'), 'DOOMED ' * 40)
            & $entry -ConfigPath $env.Cfg -NoMail -NonInteractive -BackupTime ([datetime]'2024-04-04 00:00:04') *>&1 | Out-Null
        }
        $newest = @(Get-PoolSnapshotFolder -ChangeRoot $env.Chg)[-1].Name
        Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $newest | Out-Null

        $folders = @($env.Bkp) + @(Get-PoolSnapshotFolder -ChangeRoot $env.Chg | ForEach-Object { $_.FullName })
        foreach ($folder in $folders) {
            (Test-ManifestWitness -FolderPath $folder).Status | Should -Be 'Verified'
            $target = Join-Path $root ('rw-' + [IO.Path]::GetFileName($folder))
            & (Join-Path $folder 'RECONSTRUCT.ps1') -TargetRoot $target -RequireWitness *>&1 | Out-Null
        }
        # Each folder's witness is its OWN: no two folders share a digest for
        # different manifests (the copied-witness mistake).
        $digests = foreach ($folder in $folders) {
            (Get-Content -LiteralPath (Get-ManifestWitnessPath -FolderPath $folder) | Where-Object { $_ -like 'XxH128=*' })
        }
        @($digests | Select-Object -Unique).Count | Should -Be $folders.Count
    }

    It 'the prune path calls neither Export-Csv nor Write-ManifestWitness directly (SR-038)' {
        $src = Get-Content -LiteralPath (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$null)
        $pruneFunctions = 'Remove-BackupSnapshot', 'Get-SnapshotPrunePlan', 'Copy-ReHomedDataFile',
                          'Publish-PruneManifest', 'Complete-PruneDeletion', 'Assert-PrunePrecondition',
                          'Test-PoolResolves', 'Invoke-PruneEntrySweep', 'Get-BackupSnapshot'
        $found = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                                          $pruneFunctions -contains $n.Name }, $true)
        @($found).Count | Should -Be $pruneFunctions.Count
        foreach ($fn in $found) {
            $calls = $fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                     ForEach-Object { $_.GetCommandName() }
            $calls | Should -Not -Contain 'Export-Csv'
            $calls | Should -Not -Contain 'Write-ManifestWitness'
        }
    }
}

Describe 'Prune reports host I/O as code 4 before the commit point (SR-046, SR-040)' {
    # TC-084's tenth case, plus the batch precedence rule.
    It 'aborts with code 4 when the source data file cannot be read, losing nothing' {
        $root = Join-Path $TestDrive 'tc084-io'
        $env  = New-PruneTimeline -Root $root
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        $source = $plan.Items.ToArray()[0].SourceFullPath
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        # FileShare::None makes the copy throw the way a real locked file does.
        $lock = [IO.File]::Open($source, 'Open', 'Read', 'None')
        try {
            $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        } finally { $lock.Dispose() }

        $result[0].Status | Should -Be 'Refused'
        $result[0].Code | Should -Be 4
        $result[0].Message | Should -Match 'no data was lost'
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) -PathType Container | Should -BeTrue
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
        # No lock is left behind: the Temp mutual-exclusion marker is released.
        Test-Path -LiteralPath (Join-Path $env.Chg 'Temp') | Should -BeFalse

        # Re-running now that the file is readable completes the operation and
        # sweeps any staged copy the aborted attempt left behind.
        $retry = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $retry[0].Status | Should -Be 'Pruned'
        @(Get-ChildItem -LiteralPath $env.Bkp, $env.Chg -File -Recurse -Filter '*.fbprune.tmp') | Should -BeNullOrEmpty
    }

    It 'collapses a batch to the worst code by the 2 > 3 > 4 > 1 precedence (SR-040)' {
        $mixed = @(
            [pscustomobject]@{ Name = 'a'; Code = 0 }
            [pscustomobject]@{ Name = 'b'; Code = 4 }
            [pscustomobject]@{ Name = 'c'; Code = 3 }
            [pscustomobject]@{ Name = 'd'; Code = 2 }
        )
        (Get-PruneBatchExitCode -Result $mixed) | Should -Be 2
        (Get-PruneBatchExitCode -Result @($mixed[0], $mixed[1], $mixed[2])) | Should -Be 3
        (Get-PruneBatchExitCode -Result @($mixed[0], $mixed[1])) | Should -Be 4
        (Get-PruneBatchExitCode -Result @($mixed[0])) | Should -Be 0
        (Get-PruneBatchExitCode -Result @()) | Should -Be 0
    }

    It 'refuses a batch member without touching the ones that already succeeded (SR-046)' {
        $root = Join-Path $TestDrive 'tc084-batch'
        $env  = New-PruneTimeline -Root $root
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg `
                        -Name $env.Newest, 'Snapshot_1999_09_09_09_09_09')
        $result.Count | Should -Be 2
        $result[0].Status | Should -Be 'Pruned'
        $result[1].Code | Should -Be 2
        (Get-PruneBatchExitCode -Result $result) | Should -Be 2
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Oldest) -PathType Container | Should -BeTrue
    }
}

Describe 'Reported reclaim equals measured reclaim (SR-047)' {
    # The second half of TC-087: the figure the inventory promised is the figure
    # the removal actually achieves, measured over the whole store.
    It 'matches the measured whole-store drop and the measured copied bytes' {
        $root = Join-Path $TestDrive 'tc087-measured'
        $env  = New-PruneTimeline -Root $root
        $inv  = @(Get-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg)
        $newest = @($inv | Where-Object { $_.Name -eq $env.Newest })[0]

        # A destination manifest gains a few bytes of DataPath text (and its
        # witness is re-stamped), which is index, not content: measure that
        # delta explicitly rather than pretending it does not exist.
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        $destFolders = @($plan.Items.ToArray() | ForEach-Object { $_.DestinationFolder } | Select-Object -Unique)
        $indexBytes = {
            [long](@($destFolders | ForEach-Object {
                Get-Item -LiteralPath (Join-Path $_ 'MANIFEST.csv'), (Get-ManifestWitnessPath -FolderPath $_)
            } | Measure-Object -Property Length -Sum).Sum)
        }
        $indexBefore = & $indexBytes

        $bytesBefore = Get-StoreBytes -Folder @($env.Bkp, $env.Chg)
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $result[0].Status | Should -Be 'Pruned'
        $bytesAfter = Get-StoreBytes -Folder @($env.Bkp, $env.Chg)
        $indexDelta = (& $indexBytes) - $indexBefore

        ($bytesBefore - $bytesAfter + $indexDelta) | Should -Be $newest.BytesReclaimed
        $result[0].BytesReclaimed | Should -Be $newest.BytesReclaimed
        $result[0].BytesReHomed   | Should -Be $newest.BytesReHomed
    }
}

Describe 'Prune is idempotent and resumable (SR-046)' {
    # TC-083. The transaction is stopped at each phase boundary by executing the
    # steps up to that point and no further — every half-state must be harmless
    # and invisible, and re-invoking the same command must finish the job and
    # sweep the residue. There is no journal anywhere in the store.
    BeforeAll {
        function Assert-EveryStateRestores {
            param([pscustomobject]$Env, [string]$Root, [string]$Tag)
            $origins = @($Env.Bkp) + @(Get-PoolSnapshotFolder -ChangeRoot $Env.Chg | ForEach-Object { $_.FullName })
            foreach ($origin in $origins) {
                $target = Join-Path $Root ("$Tag-" + [IO.Path]::GetFileName($origin))
                if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
                & (Join-Path $origin 'RECONSTRUCT.ps1') -TargetRoot $target -ExitCode:$false *>&1 | Out-Null
                [IO.File]::ReadAllText((Join-Path $target 'keep.txt')) | Should -Be ('KEEP ' * 40)
                [IO.File]::ReadAllText((Join-Path $target 'sub\MANIFEST.csv')) | Should -Be ('nested,not,infrastructure' * 5)
            }
        }
    }

    It 'interrupted after the copy: the staged file is invisible, and re-running completes and sweeps it' {
        $root = Join-Path $TestDrive 'tc083-copy'
        $env  = New-PruneTimeline -Root $root
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        $item = $plan.Items.ToArray()[0]

        # Stop right after the materialize step: a staged copy, nothing published.
        $staged = (Join-Path $item.DestinationFolder $item.DestinationDataPath) + '.fbprune.tmp'
        Copy-Item -LiteralPath $item.SourceFullPath -Destination $staged -Force

        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-copy'
        @(Get-ChildItem -LiteralPath $env.Bkp, $env.Chg -File -Recurse -Filter '*journal*') | Should -BeNullOrEmpty

        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $result[0].Status | Should -Be 'Pruned'
        @(Get-ChildItem -LiteralPath $env.Bkp, $env.Chg -File -Recurse -Filter '*.fbprune.tmp') | Should -BeNullOrEmpty
        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-copy-done'
    }

    It 'interrupted after the manifest publish: the pool is redundant, and re-running completes it' {
        $root = Join-Path $TestDrive 'tc083-manifest'
        $env  = New-PruneTimeline -Root $root
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest

        # Phases 1 and 2 only: the bytes are re-homed and published, the snapshot
        # folder is still there — the deliberately redundant state.
        foreach ($item in $plan.Items.ToArray()) { Copy-ReHomedDataFile -Item $item | Out-Null }
        Publish-PruneManifest -Plan $plan -Log { param($m, $l) } | Out-Null

        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) -PathType Container | Should -BeTrue
        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-manifest'
        (Test-ManifestWitness -FolderPath (Join-Path $env.Chg $env.Oldest)).Status | Should -Be 'Verified'

        # Re-running recomputes the plan from disk: nothing is endangered any
        # more, so it copies nothing and simply finishes the deletion.
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $result[0].Status | Should -Be 'Pruned'
        $result[0].BytesReHomed | Should -Be 0
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) | Should -BeFalse
        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-manifest-done'
    }

    It 'interrupted after the commit rename: the folder is invisible to every consumer, and the next run sweeps it' {
        $root = Join-Path $TestDrive 'tc083-commit'
        $env  = New-PruneTimeline -Root $root
        $plan = Get-SnapshotPrunePlan -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest
        foreach ($item in $plan.Items.ToArray()) { Copy-ReHomedDataFile -Item $item | Out-Null }
        Publish-PruneManifest -Plan $plan -Log { param($m, $l) } | Out-Null
        Rename-Item -LiteralPath $plan.Folder -NewName ('Pruning_' + $env.Newest)   # the commit point

        # Invisible to the inventory, to Optimize, and to both restorers'
        # ^Snapshot_ pattern — one atomic rename removed it from every view.
        @(Get-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg | ForEach-Object { $_.Name }) |
            Should -Not -Contain $env.Newest
        @(Get-PoolSnapshotFolder -ChangeRoot $env.Chg).Count | Should -Be 1
        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-commit'

        # Any subsequent invocation sweeps it, with no journal to consult.
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $result[0].Code | Should -Be 2                       # it is genuinely gone now
        @(Get-ChildItem -LiteralPath $env.Chg -Directory | Where-Object { $_.Name -like 'Pruning_*' }) |
            Should -BeNullOrEmpty
        Assert-EveryStateRestores -Env $env -Root $root -Tag 'after-commit-done'
    }
}

Describe 'The entry sweep removes residue only, never user content (SR-046)' {
    # TC-083, extended after the WP4 review. H1: the sweep deleted every
    # '*.fbprune.tmp' under the backup root and the change root by BARE SUFFIX.
    # In Mirror mode a user file called 'notes.fbprune.tmp' is stored at its
    # verbatim path with a manifest row naming it, so a refused prune (a typo'd
    # snapshot name) destroyed every copy of it across root and snapshots and
    # then wedged the store on the broken-pool rail. A staged copy is
    # unreferenced by construction; real content never is.
    BeforeAll {
        function Get-SuffixFile {
            param([pscustomobject]$Env)
            return @((Join-Path $Env.Bkp 'notes.fbprune.tmp'), (Join-Path $Env.Bkp 'sub\notes.fbprune.tmp'))
        }
        function Assert-SuffixFilesIntact {
            param([pscustomobject]$Env, [hashtable]$Expected)
            foreach ($path in (Get-SuffixFile -Env $Env)) {
                Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue -Because "'$path' is user content, not prune residue"
                (Get-FileXxHash -FilePath $path) | Should -Be $Expected[$path]
            }
        }
    }

    It 'a user file named *.fbprune.tmp survives refusal, dry run and a real prune, and still restores byte-exact' {
        $root = Join-Path $TestDrive 'h1-userfile'
        $env  = New-PruneTimeline -Root $root -SuffixNamedUserFiles $true
        $expected = @{}
        foreach ($path in (Get-SuffixFile -Env $env)) {
            Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
            $expected[$path] = Get-FileXxHash -FilePath $path
        }

        # 1. A REFUSED prune (the reviewer's repro: a typo'd snapshot name).
        $refused = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name 'Snapshot_1999_09_09_09_09_09')
        $refused[0].Code | Should -Be 2
        Assert-SuffixFilesIntact -Env $env -Expected $expected

        # 2. A dry run.
        $dry = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest -WhatIf)
        $dry[0].Status | Should -Be 'WhatIf'
        Assert-SuffixFilesIntact -Env $env -Expected $expected

        # 3. A real, successful prune of another snapshot.
        $pruned = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $pruned[0].Status | Should -Be 'Pruned'
        Assert-SuffixFilesIntact -Env $env -Expected $expected

        # 4. And every surviving origin still restores them byte-exact.
        $origins = @($env.Bkp) + @(Get-PoolSnapshotFolder -ChangeRoot $env.Chg | ForEach-Object { $_.FullName })
        foreach ($origin in $origins) {
            $target = Join-Path $root ('h1-' + [IO.Path]::GetFileName($origin))
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            & (Join-Path $origin 'RECONSTRUCT.ps1') -TargetRoot $target -ExitCode:$false *>&1 | Out-Null
            foreach ($rel in 'notes.fbprune.tmp', 'sub\notes.fbprune.tmp') {
                $restored = Join-Path $target $rel
                Test-Path -LiteralPath $restored -PathType Leaf | Should -BeTrue -Because "'$rel' must restore from '$origin'"
                (Get-FileXxHash -FilePath $restored) | Should -Be (Get-FileXxHash -FilePath (Join-Path $env.Src $rel))
            }
        }
    }

    It 'still sweeps a genuine staged copy sitting beside the user file in the same folder' {
        $root = Join-Path $TestDrive 'h1-mixed'
        $env  = New-PruneTimeline -Root $root -SuffixNamedUserFiles $true
        $residue = Join-Path $env.Bkp 'keep.txt.fbprune.tmp'       # unreferenced: real residue
        Copy-Item -LiteralPath (Join-Path $env.Bkp 'keep.txt') -Destination $residue

        $removed = Invoke-PruneEntrySweep -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Log { param($m, $l) }
        $removed | Should -Be 1
        Test-Path -LiteralPath $residue | Should -BeFalse
        foreach ($path in (Get-SuffixFile -Env $env)) { Test-Path -LiteralPath $path | Should -BeTrue }
    }
}

Describe 'Prune mutates only inside the transaction (SR-046)' {
    # Review findings H2/M1: the sweep ran before the rails, so a refusal
    # (code 2/3) had already deleted things, -WhatIf logged and counted removals
    # it never performed, and an undeletable residue escaped unclassified as a
    # process exit 1 instead of the retriable code 4.
    It 'a refused prune leaves an interrupted run''s residue exactly where it was' {
        $root = Join-Path $TestDrive 'h2-refused'
        $env  = New-PruneTimeline -Root $root
        $staged  = (Join-Path $env.Bkp 'keep.txt') + '.fbprune.tmp'
        Copy-Item -LiteralPath (Join-Path $env.Bkp 'keep.txt') -Destination $staged
        $pruning = Join-Path $env.Chg ('Pruning_' + $env.Oldest + '_other')
        New-Item -ItemType Directory -Path $pruning -Force | Out-Null

        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name 'Snapshot_1999_09_09_09_09_09')
        $result[0].Status | Should -Be 'Refused'
        $result[0].Code | Should -Be 2
        Test-Path -LiteralPath $staged  | Should -BeTrue
        Test-Path -LiteralPath $pruning | Should -BeTrue
    }

    It '-WhatIf sweeps nothing and reports nothing it did not do' {
        $root = Join-Path $TestDrive 'h2-whatif'
        $env  = New-PruneTimeline -Root $root
        $staged = (Join-Path $env.Bkp 'keep.txt') + '.fbprune.tmp'
        Copy-Item -LiteralPath (Join-Path $env.Bkp 'keep.txt') -Destination $staged
        $pruning = Join-Path $env.Chg ('Pruning_' + $env.Newest)
        New-Item -ItemType Directory -Path $pruning -Force | Out-Null

        $lines = New-Object System.Collections.Generic.List[string]
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest `
                        -Log { param($m, $l) $lines.Add($m) } -WhatIf)
        $result[0].Status | Should -Be 'WhatIf'
        Test-Path -LiteralPath $staged  | Should -BeTrue
        Test-Path -LiteralPath $pruning | Should -BeTrue
        @($lines | Where-Object { $_ -match 'staged copy|past the commit point' }) | Should -BeNullOrEmpty
    }

    It 'classifies an undeletable committed residue as the retriable code 4, not an unclassified throw' {
        $root = Join-Path $TestDrive 'h2-locked'
        $env  = New-PruneTimeline -Root $root
        $pruning = Join-Path $env.Chg ('Pruning_' + $env.Newest)
        New-Item -ItemType Directory -Path $pruning -Force | Out-Null

        # A held handle inside the folder is the real-world cause; the mock
        # reproduces its effect deterministically (Windows' behavior for a
        # locked file under Remove-Item -Recurse is not stable enough to pin).
        Mock -ModuleName FileBackup.Engine Remove-CommittedPruneResidue {
            throw "The process cannot access the file because it is being used by another process."
        }
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)

        $result[0].Status | Should -Be 'Refused'
        $result[0].Code   | Should -Be 4
        (Get-PruneBatchExitCode -Result $result) | Should -Be 4
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) -PathType Container | Should -BeTrue
    }

    It 'completes the outstanding deletion of the SAME name only, and no other' {
        $root = Join-Path $TestDrive 'h2-scoped'
        $env  = New-PruneTimeline -Root $root
        $mine    = Join-Path $env.Chg ('Pruning_' + $env.Newest)
        $someone = Join-Path $env.Chg ('Pruning_' + $env.Oldest)
        New-Item -ItemType Directory -Path $mine, $someone -Force | Out-Null

        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)
        $result[0].Status | Should -Be 'Pruned'
        Test-Path -LiteralPath $mine    | Should -BeFalse
        Test-Path -LiteralPath $someone | Should -BeTrue
    }

    It 'takes the Temp lock by CREATING it, so a folder appearing after the rails refuses with staging-busy (2)' {
        # The TOCTOU window (review finding M4): New-Item -Force succeeded on an
        # existing folder, so two prunes could both pass the staging-busy rail.
        # The mock reproduces exactly that race — the rails pass, then the folder
        # appears — and the lock creation must be the thing that catches it.
        $root = Join-Path $TestDrive 'm4-toctou'
        $env  = New-PruneTimeline -Root $root
        $staging = Join-Path $env.Chg 'Temp'
        $marker  = Join-Path $staging 'OTHER.marker'

        # The mock body runs in module scope, so it derives the paths from its
        # own bound -ChangeRoot rather than from this scope's variables.
        Mock -ModuleName FileBackup.Engine Assert-PrunePrecondition {
            $held = Join-Path $ChangeRoot 'Temp'
            New-Item -ItemType Directory -Path $held -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $held 'OTHER.marker'), 'held by the other run')
            return @()
        }
        $result = @(Remove-BackupSnapshot -BackupRoot $env.Bkp -ChangeRoot $env.Chg -Name $env.Newest)

        $result[0].Status | Should -Be 'Refused'
        $result[0].Code   | Should -Be 2
        $result[0].Refusals[0].Kind | Should -Be 'staging-busy'
        # The other holder's lock is still there: the finally must never delete
        # a folder this invocation did not create.
        Test-Path -LiteralPath $marker | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) -PathType Container | Should -BeTrue
    }

    It 'creates the staging lock without -Force, so creation IS the atomic test (source guard)' {
        $source = [IO.File]::ReadAllText((Join-Path $repo 'Modules\FileBackup.Engine.psm1'))
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                          $n.Name -eq 'Remove-BackupSnapshot' }, $true)
        $lockCall = @($fn.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                                 $n.GetCommandName() -eq 'New-Item' }, $true))
        $lockCall.Count | Should -BeGreaterThan 0
        foreach ($call in $lockCall) { $call.Extent.Text | Should -Not -Match '-Force' }
    }
}

Describe 'Retention at the entry point and the container boundary (SR-048)' {
    # TC-088's locally runnable halves. The in-container half (the same actions
    # driven through docker run) belongs to the Docker CI job; Docker is not
    # available on this host, so it is NOT claimed here.
    BeforeAll {
        function Invoke-FBAction {
            param([string]$Cfg, [string[]]$Arguments)
            $out = & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Cfg `
                        -NoMail -NonInteractive -ExitCode @Arguments 2>&1
            return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
        }
    }

    It 'exposes -Action Backup|Prune|Snapshots|Verify (default Backup) and -Snapshot as a string list' {
        $cmd = Get-Command $entry
        $action = $cmd.Parameters['Action']
        $action | Should -Not -BeNullOrEmpty
        $validate = @($action.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0]
        # WP5 extends the ONE dispatch with Verify (SR-049); it never adds a
        # parallel one.
        $validate.ValidValues | Should -Be @('Backup', 'Prune', 'Snapshots', 'Verify')
        $cmd.Parameters['Snapshot'].ParameterType.Name | Should -Be 'String[]'
    }

    It 'prints the inventory as parseable JSON, exits 0 and modifies nothing (-Action Snapshots)' {
        $root = Join-Path $TestDrive 'tc088-inventory'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $run = Invoke-FBAction -Cfg $env.Cfg -Arguments @('-Action', 'Snapshots')
        $run.Code | Should -Be 0
        # The logger writes to the same stream, so take the document from the
        # line that IS '[' (ConvertTo-Json -AsArray) to the end.
        $lines = $run.Output -split "`r?`n"
        $start = [array]::IndexOf($lines, '[')
        $start | Should -BeGreaterThan -1
        $json = @(($lines[$start..($lines.Count - 1)] -join "`n") | ConvertFrom-Json)
        $json.Count | Should -Be 2
        foreach ($field in 'Name', 'Date', 'Rows', 'PhysicalBytes', 'BytesReclaimed', 'BytesReHomed') {
            $json[0].PSObject.Properties.Name | Should -Contain $field
        }
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
    }

    It 'prints the literal empty JSON document for a store with no snapshots (-Action Snapshots)' {
        # WP5 residual (surfaced by TC-102's harness): piping zero objects into
        # ConvertTo-Json emits nothing at all rather than '[]', and the IF-001
        # inventory contract promises a parseable document even when there is
        # nothing to list.
        $root = Join-Path $TestDrive 'tc088-empty'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'only.txt'), ('CONTENT ' * 10))
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null    # first run: no snapshot yet

        $run = Invoke-FBAction -Cfg $cfg -Arguments @('-Action', 'Snapshots')
        $run.Code | Should -Be 0
        ($run.Output -split "`r?`n") | Should -Contain '[]'
    }

    It 'prunes a named snapshot with exit 0, leaving every remaining state restorable (-Action Prune)' {
        $root = Join-Path $TestDrive 'tc088-prune'
        $env  = New-PruneTimeline -Root $root

        $run = Invoke-FBAction -Cfg $env.Cfg -Arguments @('-Action', 'Prune', '-Snapshot', $env.Newest)
        $run.Code | Should -Be 0
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) | Should -BeFalse

        $target = Join-Path $root 'r-state1'
        & (Join-Path (Join-Path $env.Chg $env.Oldest) 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'gone.txt')) | Should -Be ('DOOMED ' * 40)
    }

    It 'exits 2 for an unknown snapshot name, leaving the tree unchanged' {
        $root = Join-Path $TestDrive 'tc088-unknown'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $run = Invoke-FBAction -Cfg $env.Cfg -Arguments @('-Action', 'Prune', '-Snapshot', 'Snapshot_1999_09_09_09_09_09')
        $run.Code | Should -Be 2
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
    }

    It 'exits 2 when -Action Prune is given no -Snapshot (policy belongs to the caller)' {
        $root = Join-Path $TestDrive 'tc088-noname'
        $env  = New-PruneTimeline -Root $root
        (Invoke-FBAction -Cfg $env.Cfg -Arguments @('-Action', 'Prune')).Code | Should -Be 2
    }

    It 'exits 0 for a dry run and changes nothing (-Action Prune -WhatIf)' {
        $root = Join-Path $TestDrive 'tc088-dryrun'
        $env  = New-PruneTimeline -Root $root
        $before = Get-StoreFingerprint -Folder @($env.Bkp, $env.Chg)

        $run = Invoke-FBAction -Cfg $env.Cfg -Arguments @('-Action', 'Prune', '-Snapshot', $env.Newest, '-WhatIf')
        $run.Code | Should -Be 0
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) -PathType Container | Should -BeTrue
        Assert-StoreUnchanged -Before $before -Folder @($env.Bkp, $env.Chg)
    }

    It 'refuses -Action Backup -WhatIf loudly instead of performing a half-run (SR-048)' {
        # Review finding L1: -WhatIf binds on every action because Prune needs
        # SupportsShouldProcess, but the backup pipeline does not honor it.
        $root = Join-Path $TestDrive 'l1-whatif'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v1')

        $run = Invoke-FBAction -Cfg $cfg -Arguments @('-WhatIf')
        $run.Code | Should -Be 2
        $run.Output | Should -Match 'WhatIf is not supported for -Action Backup'
        # Nothing was attempted: no backup root, no change root, no log dir.
        Test-Path -LiteralPath $bkp | Should -BeFalse
        Test-Path -LiteralPath $chg | Should -BeFalse

        # Without -ExitCode it is a terminating error, like every other
        # precondition failure at this boundary.
        { & $entry -ConfigPath $cfg -NoMail -NonInteractive -WhatIf } | Should -Throw '*only available for -Action Prune*'
        Test-Path -LiteralPath $bkp | Should -BeFalse
    }

    It 'leaves the default action untouched: a flags-only invocation still runs a backup and exits 0' {
        $root = Join-Path $TestDrive 'tc088-legacy'
        $env  = New-PruneTimeline -Root $root
        [IO.File]::WriteAllText((Join-Path $env.Src 'later.txt'), 'ADDED AFTER')

        (Invoke-FBAction -Cfg $env.Cfg -Arguments @()).Code | Should -Be 0
        @(Import-Csv -LiteralPath (Join-Path $env.Bkp 'MANIFEST.csv') |
            Where-Object { $_.RelativePath -eq 'later.txt' }) | Should -Not -BeNullOrEmpty
    }

    It 'container/entrypoint.sh dispatches on the action word and passes ''-'' arguments through unchanged' {
        $sh = Get-Content -LiteralPath (Join-Path $repo 'container\entrypoint.sh') -Raw
        $sh | Should -Match 'FILEBACKUP_ACTION'
        $sh | Should -Match 'backup\|prune\|snapshots\|verify\)'   # only these WORDS are consumed
        $sh | Should -Match '-Action Prune'
        $sh | Should -Match '-Action Snapshots'
        $sh | Should -Match 'FILEBACKUP_SNAPSHOT'
        $sh | Should -Match 'FILEBACKUP_DRY_RUN'
        $sh | Should -Match '-WhatIf'
        # The pass-through contract that keeps TC-060/TC-076 valid.
        $sh | Should -Match '-ExitCode'
        $sh | Should -Match '"\$@"'
        # A leading '-' argument matches no case branch, so it stays in "$@".
        $sh | Should -Not -Match 'case "\$\{1:-\}" in\s*\r?\n\s*-'
    }

    It 'there is no prune in bash: reconstruct.sh carries no snapshot-removal path' {
        $sh = Get-Content -LiteralPath (Join-Path $repo 'bash\reconstruct.sh') -Raw
        $sh | Should -Not -Match '(?i)prune'
        $sh | Should -Not -Match 'Pruning_'
        # No line deletes a snapshot folder or a manifest.
        foreach ($line in ($sh -split "`n")) {
            if ($line -match '\brm\b') {
                $line | Should -Not -Match 'Snapshot'
                $line | Should -Not -Match 'MANIFEST'
            }
        }
    }
}

Describe 'Backup pipeline crash-window hardening (2026-08-23 review round)' {
    BeforeAll {
        function Invoke-FBExit {
            # Child process so the SR-040 exit code is observable.
            param([string]$Cfg)
            & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Cfg `
                -NoMail -NonInteractive -ExitCode *>&1 | Out-Null
            return $LASTEXITCODE
        }
    }

    It 'refuses to back up over a manifest whose witness disagrees, with exit 3 and nothing mutated (SR-038, SR-040)' {
        $root = Join-Path $TestDrive 'wg-mismatch'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('ALPHA ' * 40))
        Invoke-FB $cfg

        # A torn Export-Csv is a size change the witness catches; simulate the
        # damage without re-running the writer (the writer would re-stamp).
        $manifest = Join-Path $bkp 'MANIFEST.csv'
        [IO.File]::AppendAllText($manifest, "torn trailing bytes")
        $before = Get-StoreFingerprint -Folder @($bkp, $chg)

        Invoke-FBExit -Cfg $cfg | Should -Be 3 -Because 'IF-001 maps a witness failure to 3 for every action, backup included'
        Assert-StoreUnchanged -Before $before -Folder @($bkp, $chg)
    }

    It 'still backs up a legacy store that has no witness at all (SR-038)' {
        $root = Join-Path $TestDrive 'wg-legacy'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('ALPHA ' * 40))
        Invoke-FB $cfg

        Remove-Item -LiteralPath (Join-Path $bkp 'MANIFEST.csv.meta') -Force
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('BETA ' * 40))
        Invoke-FBExit -Cfg $cfg | Should -Be 0 -Because 'Absent is legal: a pre-SR-038 store must still back up'
    }

    It 'fails the set on an unreadable source file without stranding Temp for the next run (SR-017)' {
        $root = Join-Path $TestDrive 'wg-locked'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('ALPHA ' * 40))
        Invoke-FB $cfg

        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), ('LOCKED ' * 40))
        $handle = [IO.File]::Open((Join-Path $src 'b.txt'), 'Open', 'Read', 'None')
        try {
            Invoke-FBExit -Cfg $cfg | Should -Be 1
            Test-Path -LiteralPath (Join-Path $chg 'Temp') |
                Should -BeFalse -Because 'a step-5 failure must not wedge every later run on the stale-Temp guard'
        } finally { $handle.Dispose() }
        Invoke-FBExit -Cfg $cfg | Should -Be 0 -Because 'with the lock gone the next scheduled run just works'
    }

    It 'refuses a Mirror source file whose data path is a root-level infrastructure name, without corrupting the store (SR-022)' {
        $root = Join-Path $TestDrive 'wg-infra'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $state = Join-Path $root 'state'; $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        # External SourceStatePath: EVERY source file is user data, including a
        # root-level MANIFEST.csv (the container's default arrangement).
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
            SourceStatePath = $state
            HashRecalcFreq = 'A'; CompressEnabled = $false; PreserveFolderTree = $true
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg
        [IO.File]::WriteAllText((Join-Path $src 'MANIFEST.csv'), 'user,data,that,is,not,an,index')
        [IO.File]::WriteAllText((Join-Path $src 'ok.txt'), ('FINE ' * 40))

        Invoke-FBExit -Cfg $cfg | Should -Be 1 -Because 'the colliding file is refused, not silently corrupted'

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        @($rows | Where-Object RelativePath -eq 'ok.txt').Count | Should -Be 1
        @($rows | Where-Object RelativePath -eq 'MANIFEST.csv').Count |
            Should -Be 0 -Because 'a row pointing at the index would restore index bytes as user data'
        # No FileBackupState torn-write residue either (publish-by-rename).
        Test-Path -LiteralPath (Join-Path $bkp 'FileBackupState.json.tmp') | Should -BeFalse
    }

    It 'restores a COPIED backup folder from the copy, not from the still-live original the sidecar records (B10, SR-010)' {
        $root = Join-Path $TestDrive 'wg-copied'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('VERSION-ONE ' * 40))
        Invoke-FB $cfg

        # The archived copy — then the ORIGINAL keeps evolving.
        $copy = Join-Path $root 'bkp-archived'
        Copy-Item -LiteralPath $bkp -Destination $copy -Recurse
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('VERSION-TWO ' * 40))
        Invoke-FB $cfg

        $target = Join-Path $root 'restored'
        # In-process invocation: a completed restore ends without `exit`, so
        # assert the outcome (bytes restored FROM THE COPY), not $LASTEXITCODE.
        $out = & (Join-Path $copy 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-String
        $out | Should -Match 'records roots this folder no longer lives in'
        [IO.File]::ReadAllText((Join-Path $target 'a.txt')) |
            Should -Be ('VERSION-ONE ' * 40) -Because 'the copy is the restore origin; the recorded original must not hijack it'
    }

    It 'hash-recovers a row whose named data file is gone but whose bytes survive in the pool (SR-031, SR-010)' {
        $root = Join-Path $TestDrive 'wg-hint'
        $env  = New-PruneTimeline -Root $root
        # The Optimize crash window: the file a row NAMES is gone while
        # byte-identical content survives elsewhere in the pool. Renaming the
        # root file reproduces exactly that shape.
        Move-Item -LiteralPath (Join-Path $env.Bkp 'keep.txt') -Destination (Join-Path $env.Bkp 'keep.survives')

        $target = Join-Path $root 'restored'
        & (Join-Path $env.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'keep.txt')) |
            Should -Be ('KEEP ' * 40) -Because 'DataPath is a locator hint; (hash,length) is the content authority'
    }
}
