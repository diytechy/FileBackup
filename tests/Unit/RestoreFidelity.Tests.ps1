<#
.SYNOPSIS  Restore fidelity beyond bytes: each row's own modification time
           (SR-066) and the directory sidecar (SR-065), plus the withdrawn
           legacy-store read path (SR-061) and the 7-Zip replace fix (SR-004).
.NOTES     TC-136, TC-137, TC-138 (Windows half; the bats twins carry the POSIX
           half), TC-139. These drive real backup runs and real restores through
           the DEPLOYED kit, so the restorer under test is the one a user gets.
           Run: Invoke-Pester -Path tests\Unit\RestoreFidelity.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry    = Join-Path $repo 'FileBackup.ps1'
    $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
    $script:sidecarName = (Get-FileBackupDefaults).DirectorySidecarName
    $script:pwshExe  = (Get-Process -Id $PID).Path

    function New-FidelityConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg, [bool]$Compress = $false)
        $set = [pscustomobject]@{
            Name = 'F'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function New-FidelityStore {
        <#
        .SYNOPSIS
            A real store over a tree built to exercise both halves at once: two
            files with IDENTICAL content but different modification times (the
            dedup timestamp leak), a unique file, an empty directory, a nested
            empty directory, a Hidden+System folder holding a file, and an
            ordinary populated folder that must NOT be recorded.
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null

        # Large and repetitive so a Compress-mode store really stores a .7z.
        $shared = 'SHARED-CONTENT-X' * 4000
        Set-Content -LiteralPath (Join-Path $src 'twin-a.txt') -Value $shared -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'twin-b.txt') -Value $shared -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'uniq.txt')   -Value ('UNIQUE-CONTENT-Y' * 4000) -NoNewline
        [IO.File]::SetLastWriteTime((Join-Path $src 'twin-a.txt'), [datetime]'2001-01-01T01:02:03')
        [IO.File]::SetLastWriteTime((Join-Path $src 'twin-b.txt'), [datetime]'2002-02-02T04:05:06')
        [IO.File]::SetLastWriteTime((Join-Path $src 'uniq.txt'),   [datetime]'2003-03-03T07:08:09')

        New-Item -ItemType Directory -Path (Join-Path $src 'empty-dir\nested-empty') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $src 'plain-dir') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'plain-dir\inside.txt') -Value 'PLAIN' -NoNewline
        $hid = New-Item -ItemType Directory -Path (Join-Path $src 'hidden-dir') -Force
        Set-Content -LiteralPath (Join-Path $hid.FullName 'secret.txt') -Value 'HIDDEN-PAYLOAD' -NoNewline
        (Get-Item -LiteralPath $hid.FullName -Force).Attributes = 'Directory,Hidden,System'

        $cfg = Join-Path $Root 'cfg.xml'
        New-FidelityConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg
            Manifest = Join-Path $bkp 'MANIFEST.csv'
            Sidecar  = Join-Path $bkp $sidecarName
            Recon    = Join-Path $bkp 'RECONSTRUCT.ps1'
        }
    }

    function Invoke-FidelityRestore {
        # Child process so RECONSTRUCT.ps1's -ExitCode `exit` is observable at
        # the process boundary, the same numbers reconstruct.sh returns.
        param([string]$Recon, [string]$TargetRoot)
        $out = & $pwshExe -NoProfile -File $Recon -TargetRoot $TargetRoot -ExitCode -NonInteractive *>&1 | Out-String
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    }

    function Set-FidelityManifest {
        # Rewrite a manifest and re-stamp its witness, so the damage a test means
        # to exercise is what the restorer reports (SR-038).
        param([string]$Folder, [object[]]$Rows)
        $Rows | Export-Csv -LiteralPath (Join-Path $Folder 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $Folder | Out-Null
    }
}

Describe 'Restored files carry their own modification time (SR-066)' -ForEach @(
    @{ Mode = 'Plain'; Compress = $false }, @{ Mode = 'Compress'; Compress = $true }
) {
    It 'a deduplicated twin keeps its OWN mtime, not the pool object owner-s (TC-136, <Mode>)' {
        $root = Join-Path $TestDrive ('mtime-' + $Mode)
        $s = New-FidelityStore -Root $root -Compress $Compress
        $t = Join-Path $root 'restored'

        # Precondition: the twins really do share one stored object, or this
        # test would pass without ever exercising the leak.
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $a = @($rows | Where-Object RelativePath -eq 'twin-a.txt')[0]
        $b = @($rows | Where-Object RelativePath -eq 'twin-b.txt')[0]
        $a.xxH2Hash | Should -Be $b.xxH2Hash -Because 'the fixture twins must dedup'
        $a.DataPath | Should -Be $b.DataPath -Because 'both rows must name one stored object'

        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t).Code | Should -Be 0
        [IO.File]::GetLastWriteTime((Join-Path $t 'twin-a.txt')) | Should -Be ([datetime]'2001-01-01T01:02:03')
        [IO.File]::GetLastWriteTime((Join-Path $t 'twin-b.txt')) | Should -Be ([datetime]'2002-02-02T04:05:06')
        [IO.File]::GetLastWriteTime((Join-Path $t 'uniq.txt'))   | Should -Be ([datetime]'2003-03-03T07:08:09')
    }

    It 'a blank or garbage LastWriteTimeStr warns but still restores the bytes (TC-136, <Mode>)' {
        $root = Join-Path $TestDrive ('mtime-bad-' + $Mode)
        $s = New-FidelityStore -Root $root -Compress $Compress
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        @($rows | Where-Object RelativePath -eq 'twin-a.txt')[0].LastWriteTimeStr = ''
        @($rows | Where-Object RelativePath -eq 'uniq.txt')[0].LastWriteTimeStr   = 'not-a-timestamp'
        Set-FidelityManifest -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 'restored'
        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t).Code | Should -Be 0
        (Get-Item -LiteralPath (Join-Path $t 'uniq.txt')).Length |
            Should -Be (Get-Item -LiteralPath (Join-Path $s.Src 'uniq.txt')).Length
        (Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw) |
            Should -Match "could not stamp LastWriteTime on 'uniq\.txt'"
    }
}

Describe 'Directory sidecar (SR-065)' {
    It 'records exactly the empty and attributed directories, and nothing else (TC-137)' {
        $root = Join-Path $TestDrive 'dirs-record'
        $s = New-FidelityStore -Root $root
        Test-Path -LiteralPath $s.Sidecar | Should -BeTrue
        $rows = @(Import-Csv -LiteralPath $s.Sidecar)
        @($rows).Count | Should -Be 3
        @($rows | Where-Object RelativePath -eq 'empty-dir')[0].Attributes              | Should -BeNullOrEmpty
        @($rows | Where-Object RelativePath -eq 'empty-dir\nested-empty')[0].Attributes | Should -BeNullOrEmpty
        @($rows | Where-Object RelativePath -eq 'hidden-dir')[0].Attributes             | Should -Be 'Hidden,System'
        # An ordinary populated folder needs no row: its files recreate it.
        @($rows | Where-Object RelativePath -eq 'plain-dir').Count | Should -Be 0
    }

    It 'recreates empty directories and re-applies folder attributes on restore (TC-137)' {
        $root = Join-Path $TestDrive 'dirs-restore'
        $s = New-FidelityStore -Root $root
        $t = Join-Path $root 'restored'
        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t).Code | Should -Be 0

        Test-Path -LiteralPath (Join-Path $t 'empty-dir') -PathType Container              | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $t 'empty-dir\nested-empty') -PathType Container | Should -BeTrue
        $hid = Get-Item -LiteralPath (Join-Path $t 'hidden-dir') -Force
        $hid.Attributes.HasFlag([IO.FileAttributes]::Hidden) | Should -BeTrue
        $hid.Attributes.HasFlag([IO.FileAttributes]::System) | Should -BeTrue
        # The file inside a Hidden+System folder is still restored and correct.
        Get-Content -LiteralPath (Join-Path $t 'hidden-dir\secret.txt') -Raw | Should -Be 'HIDDEN-PAYLOAD'
    }

    It 'writes NO sidecar for a tree with no empty or attributed directory (TC-137)' {
        $root = Join-Path $TestDrive 'dirs-none'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub'), $bkp, $chg -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'sub\f.txt') -Value 'X' -NoNewline
        $cfg = Join-Path $root 'cfg.xml'
        New-FidelityConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $bkp $sidecarName) | Should -BeFalse
    }

    It 'an absent or garbage sidecar still restores every file and exits 0 (TC-137)' {
        $root = Join-Path $TestDrive 'dirs-damaged'
        $s = New-FidelityStore -Root $root
        [IO.File]::WriteAllText($s.Sidecar, "this is not a directory sidecar`r`n,,,`r`n")
        $t = Join-Path $root 'restored'
        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t).Code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'hidden-dir\secret.txt') -Raw | Should -Be 'HIDDEN-PAYLOAD'

        Remove-Item -LiteralPath $s.Sidecar -Force
        $t2 = Join-Path $root 'restored2'
        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t2).Code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t2 'hidden-dir\secret.txt') -Raw | Should -Be 'HIDDEN-PAYLOAD'
        # Pre-SR-065 behaviour, exactly: no empty directory, no attributes.
        Test-Path -LiteralPath (Join-Path $t2 'empty-dir') | Should -BeFalse
    }

    It 'a snapshot carries the sidecar of the state it preserves, not the live one (TC-137)' {
        $root = Join-Path $TestDrive 'dirs-snapshot'
        $s = New-FidelityStore -Root $root
        # Second run: the empty directory is gone and a NEW one appears, so the
        # live sidecar and the snapshot's must differ.
        Remove-Item -LiteralPath (Join-Path $s.Src 'empty-dir') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $s.Src 'later-empty') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $s.Src 'uniq.txt') -Value ('CHANGED-Z' * 4000) -NoNewline
        & $entry -ConfigPath $s.Cfg -NoMail -NonInteractive *>&1 | Out-Null

        $snap = @(Get-ChildItem -LiteralPath $s.Chg -Directory -Force |
                    Where-Object { $_.Name -like 'Snapshot_*' })[0]
        $snap | Should -Not -BeNullOrEmpty
        $snapRows = @(Import-Csv -LiteralPath (Join-Path $snap.FullName $sidecarName))
        @($snapRows | Where-Object RelativePath -eq 'empty-dir').Count   | Should -Be 1
        @($snapRows | Where-Object RelativePath -eq 'later-empty').Count | Should -Be 0

        $liveRows = @(Import-Csv -LiteralPath $s.Sidecar)
        @($liveRows | Where-Object RelativePath -eq 'empty-dir').Count   | Should -Be 0
        @($liveRows | Where-Object RelativePath -eq 'later-empty').Count | Should -Be 1
    }
}

Describe 'A legacy path-addressed store is refused by the restorer (SR-061)' -ForEach @(
    @{ Marker = 'stored-as-original' }, @{ Marker = 'path-addressed-datapath' }
) {
    It 'refuses with exit 2 and writes nothing (TC-138, <Marker>)' {
        $root = Join-Path $TestDrive ('legacy-' + $Marker)
        $s = New-FidelityStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $victim = @($rows | Where-Object RelativePath -eq 'uniq.txt')[0]
        if ($Marker -eq 'stored-as-original') {
            $victim.StoredAsHashSize = 'Original'
        } else {
            # A path-addressed DataPath with the column left at 'Hash': the
            # structural marker alone must still refuse.
            $victim.DataPath = 'sub\uniq.txt'
        }
        Set-FidelityManifest -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 'restored'
        $r = Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t
        $r.Code   | Should -Be 2
        $r.Output | Should -Match 'legacy path-addressed store'
        Test-Path -LiteralPath (Join-Path $t 'twin-a.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $t 'uniq.txt')   | Should -BeFalse
    }
}

Describe 'Compress-FileWithSevenZip replaces its destination (SR-004, nit-4)' {
    BeforeEach {
        if (-not $sevenZip -or -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because '7-Zip is not available on this host'
        }
    }

    It 'overwrites a valid orphan archive instead of adding a second member (TC-139)' {
        $work = Join-Path $TestDrive 'nit4-valid'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $orphanSrc = Join-Path $work 'orphan.txt'
        $newSrc    = Join-Path $work 'wanted.txt'
        $dest      = Join-Path $work 'object.7z'
        Set-Content -LiteralPath $orphanSrc -Value 'ORPHAN PAYLOAD' -NoNewline
        Set-Content -LiteralPath $newSrc    -Value 'WANTED PAYLOAD' -NoNewline

        # An UNREFERENCED object already parked on the content-addressed name:
        # a run killed before its manifest was written, or a row evicted while
        # its object awaited prune. '7z a' would merge into it.
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $orphanSrc -Destination7z $dest
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $newSrc    -Destination7z $dest

        $listing = & $sevenZip 'l' '-ba' $dest 2>&1 | Out-String
        $listing | Should -Match 'wanted\.txt'
        $listing | Should -Not -Match 'orphan\.txt'

        $out = Join-Path $work 'out.txt'
        Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $dest -DestinationFile $out
        Get-Content -LiteralPath $out -Raw | Should -Be 'WANTED PAYLOAD'
    }

    It 'overwrites truncated debris rather than merging into it (TC-139)' {
        $work = Join-Path $TestDrive 'nit4-debris'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $newSrc = Join-Path $work 'wanted.txt'
        $dest   = Join-Path $work 'object.7z'
        Set-Content -LiteralPath $newSrc -Value 'WANTED PAYLOAD' -NoNewline
        # An interrupted 7-Zip leaves a partial archive at the target name.
        [IO.File]::WriteAllBytes($dest, [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04))

        { Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $newSrc -Destination7z $dest } |
            Should -Not -Throw
        $out = Join-Path $work 'out.txt'
        Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $dest -DestinationFile $out
        Get-Content -LiteralPath $out -Raw | Should -Be 'WANTED PAYLOAD'
    }
}
