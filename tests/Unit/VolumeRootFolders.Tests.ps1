<#
.SYNOPSIS  SR-074: the pseudo-folders Windows puts at the ROOT of every NTFS
           volume are not data, and must not fail a backup set or a restore.
.NOTES     TC-175, TC-176, TC-177, TC-178.
           SR-057 added -Force so hidden files would finally be backed up. That
           also exposed 'System Volume Information' (unreadable by design, which
           marked the whole set FAILED - so a SourcePath of D:\ could never
           report success) and $RECYCLE.BIN (readable by its owner, so deleted
           files were being backed up). Both are excluded at the ROOT level only.
           Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
}

Describe 'Volume-root pseudo-folder predicate (SR-074, TC-175)' {
    It 'matches the folder itself, at the root' {
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\System Volume Information' | Should -BeTrue
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\$RECYCLE.BIN' | Should -BeTrue
    }
    It 'matches everything underneath it' {
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\System Volume Information\tracking.log' | Should -BeTrue
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\$RECYCLE.BIN\S-1-5-21-x\$RABCDEF.txt' | Should -BeTrue
    }
    It 'is case-insensitive, as the filesystem is' {
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\$Recycle.Bin' | Should -BeTrue
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\system volume information\x' | Should -BeTrue
    }
    It 'treats a NESTED folder of the same name as ordinary user data (B6)' {
        # The same root-level-only rule the infrastructure names follow: a user
        # who has a folder called 'System Volume Information' inside their tree
        # owns those files and must get them back.
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\docs\System Volume Information\notes.txt' | Should -BeFalse
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\a\$RECYCLE.BIN\x.txt' | Should -BeFalse
    }
    It 'does not match ordinary paths, a prefix-sharing sibling, or the root itself' {
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\normal.txt' | Should -BeFalse
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src\System Volume Information Backup\x' | Should -BeFalse
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\src' | Should -BeFalse
        Test-IsVolumeRootPseudoPath -Root 'C:\src' -FullPath 'C:\other\System Volume Information' | Should -BeFalse
    }
}

Describe 'Source enumeration skips them (SR-074, TC-176)' {
    BeforeAll {
        $script:src = Join-Path $TestDrive 'vr-src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'real.txt') -Value 'keep me' -Encoding ASCII

        # $RECYCLE.BIN is READABLE by its owner, so before SR-074 its deleted
        # files were enumerated and backed up.
        $script:recycle = Join-Path $src '$RECYCLE.BIN'
        New-Item -ItemType Directory -Path $recycle -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $recycle 'deleted.txt') -Value 'should never be backed up' -Encoding ASCII

        # A same-named folder NESTED in the tree is a user's folder (B6).
        $script:nested = Join-Path $src 'docs\System Volume Information'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $nested 'mine.txt') -Value 'user data' -Encoding ASCII

        $script:files = @(Get-DataFile -Root $src | ForEach-Object { $_.FullName })
    }

    It 'enumerates ordinary files' {
        $files | Where-Object { $_ -like '*real.txt' } | Should -Not -BeNullOrEmpty
    }
    It 'does NOT enumerate the recycle bin at the root - deleted files are not backup material' {
        $files | Where-Object { $_ -like '*deleted.txt' } | Should -BeNullOrEmpty
    }
    It 'DOES enumerate a nested folder of the same name (B6)' {
        $files | Where-Object { $_ -like '*mine.txt' } |
            Should -Not -BeNullOrEmpty -Because 'a nested folder with that name is the user''s own data'
    }
}

Describe 'An unreadable volume-root folder does not fail the set (SR-074, TC-177)' {
    It 'is not reported as an enumeration error' {
        # 'System Volume Information' carries a Deny ACE even for an admin, and
        # that error used to set OverallSuccess=$false - so a SourcePath at a
        # volume root failed EVERY run, forever, while still backing up
        # everything reachable. It is a property of a volume root, not a
        # misconfiguration, so it must not be reported at all.
        $src = Join-Path $TestDrive 'vr-err'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'real.txt') -Value 'x' -Encoding ASCII

        $svi = Join-Path $src 'System Volume Information'
        New-Item -ItemType Directory -Path $svi -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $svi 'tracking.log') -Value 'y' -Encoding ASCII
        # A DENY ACE, not just a folder of that name: without it the walk reads
        # the folder happily, no enumeration error is raised, and this test
        # would pass whether or not the filter exists. Same shape the SR-057
        # test uses (RestoreVerify.Tests.ps1).
        (Get-Item -LiteralPath $svi -Force).Attributes = 'Hidden, System, Directory'
        icacls $svi /deny "${env:USERNAME}:(OI)(CI)(R)" | Out-Null
        try {
            $errors = New-Object System.Collections.Generic.List[object]
            $found = @(Get-DataFile -Root $src -EnumerationErrorOut $errors | ForEach-Object { $_.FullName })

            @($errors | Where-Object { "$($_.Path)" -like '*System Volume Information*' }) |
                Should -BeNullOrEmpty -Because 'the set must not be marked failed by a folder that is never data'
            $found | Where-Object { $_ -like '*tracking.log' } | Should -BeNullOrEmpty
            $found | Where-Object { $_ -like '*real.txt' } | Should -Not -BeNullOrEmpty
        } finally {
            icacls $svi /remove:d "${env:USERNAME}" | Out-Null
        }
    }
}

Describe 'A backup at a volume root still restores (SR-074, TC-178)' {
    It 'does not report StorageUnreadable for a volume-root pseudo-folder in the pool' {
        # The mirror-image defect: the restorer counted the same folder as a
        # pool read failure and returned exit 4 - a host problem to retry -
        # against a wholly intact store.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repo 'Reconstruct.ps1'), [ref]$null, [ref]$null)
        $text = $ast.Extent.Text
        # The candidate filter and the error filter must BOTH consult it, or one
        # half of the false verdict survives.
        ([regex]::Matches($text, 'Test-IsVolumeRootPseudoPath')).Count |
            Should -BeGreaterOrEqual 2 -Because 'both the candidate list and the enumeration errors are filtered'
        $text | Should -Match 'realEnumErrors'
    }
}

Describe 'A store at a volume root CLASSIFIES a failure honestly (SR-074, SR-040, TC-180)' {
    # gen_cases pairwise cases 2/4 and 3/4: side=restore.
    #
    # WHAT THE RESTORE-SIDE FILTER ACTUALLY DOES, established by writing this
    # test twice and running a negative control both times:
    # Find-DataFileByHash returns as soon as it FINDS the bytes and consults its
    # collected host issues only when it does not. So on an INTACT store the
    # enumeration error is discarded and the restore exits 0 whether or not the
    # filter exists - an earlier version of this test asserted exit 0 and passed
    # against a deliberately broken restorer.
    #
    # The filter's real effect is CLASSIFICATION. When content genuinely cannot
    # be found, an unreadable volume-root folder made the run report
    # StorageUnreadable / exit 4 - 'fix this host and retry' - instead of
    # ContentMissing / exit 1. Under SR-040 that is the difference between a
    # wrapper retrying forever and reporting real data loss.
    It 'reports ContentMissing (1), not StorageUnreadable (4), when the bytes really are gone' {
        $root = Join-Path $TestDrive 'vr-class'
        $src  = Join-Path $root 'src'
        $bkp  = Join-Path $root 'bkp'
        $chg  = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'ALPHA-CONTENT' -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'b.txt') -Value ('BETA-' * 500) -NoNewline

        $cfg = Join-Path $root 'cfg.xml'
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
            HashRecalcFreq = 'A'; CompressEnabled = $false
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg
        & (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Should -BeTrue

        # Force the pool scan AND make it fail: blank the row's DataPath so the
        # restorer must search by (hash, length), and delete the object so the
        # search cannot succeed. Re-stamp the witness or the run exits 3 on the
        # edited index instead of ever reaching the pool.
        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        $victim = $rows | Where-Object RelativePath -eq 'a.txt'
        Remove-Item -LiteralPath (Join-Path $bkp $victim.DataPath) -Force
        $victim.DataPath = ''
        $rows | Export-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $bkp | Out-Null

        $svi    = Join-Path $bkp 'System Volume Information'
        $rec    = Join-Path $bkp '$RECYCLE.BIN'
        $nested = Join-Path $bkp 'sub\System Volume Information'
        New-Item -ItemType Directory -Path $svi, $rec, $nested -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $rec 'deleted.bin') -Value 'deleted noise' -NoNewline
        Set-Content -LiteralPath (Join-Path $nested 'keep.bin') -Value 'nested noise' -NoNewline
        Set-Content -LiteralPath (Join-Path $svi 'tracking.log') -Value 'volume noise' -NoNewline
        # The DENY ACE is the whole point: a merely-named folder is readable, so
        # no enumeration error is raised and the filter is never exercised.
        (Get-Item -LiteralPath $svi -Force).Attributes = 'Hidden, System, Directory'
        icacls $svi /deny "${env:USERNAME}:(OI)(CI)(R)" | Out-Null
        try {
            $target = Join-Path $root 'restored'
            $out = & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target -ExitCode 2>&1
            $code = $LASTEXITCODE

            $code | Should -Be 1 -Because "the bytes are genuinely gone, which is content damage - not a host problem to retry. Output: $out"
            $log = Get-Content -LiteralPath (Join-Path $target 'RECONSTRUCT.log') -Raw
            $log | Should -Match 'ContentMissing'
            $log | Should -Not -Match 'StorageUnreadable'

            # The undamaged row still restores - failing loudly means salvaging
            # everything recoverable first (SR-029).
            (Get-Content -LiteralPath (Join-Path $target 'b.txt') -Raw) | Should -Be ('BETA-' * 500)
        } finally {
            icacls $svi /remove:d "${env:USERNAME}" | Out-Null
        }
    }
}
