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

Describe 'Atomic change folder (SR-005)' {
    It 'creates a Pre_*_Changes folder carrying its own MANIFEST.csv (SR-005)' {
        $src = Join-Path $TestDrive 's5\src'; $bkp = Join-Path $TestDrive 's5\bkp'; $chg = Join-Path $TestDrive 's5\chg'
        $cfg = Join-Path $TestDrive 's5\c.xml'
        New-Item -ItemType Directory -Path $src, (Split-Path $cfg) -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v1'); Invoke-FB $cfg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'v2'); Invoke-FB $cfg

        $cf = Get-ChildItem -LiteralPath $chg -Directory |
              Where-Object { $_.Name -match '^Pre_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_.*_Changes$' }
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
        foreach ($name in 'Pre_2024_01_01_00_00_01_000001_Changes','Pre_2024_01_01_00_00_02_000001_Changes') {
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
