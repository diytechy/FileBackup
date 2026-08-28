<#
.SYNOPSIS  SR-074: the pseudo-folders Windows puts at the ROOT of every NTFS
           volume are not data, and must not fail a backup set or misclassify a
           restore.
.NOTES     TC-175, TC-176, TC-177, TC-178, TC-180.

           TWO conditions, and the second exists because the first version of
           this feature SILENTLY DELETED USER DATA. Keying only on "first path
           segment below the root" meant that backing up an ordinary folder that
           happened to contain '$RECYCLE.BIN' dropped every file under it from
           the manifest, with no error. The exclusion applies ONLY when the root
           is itself a filesystem volume root (2026-08-28 independent review,
           T2 - which also noted that the FIRST version of these tests encoded
           the defect by using an ordinary folder as the supposed volume root).

           So these tests use a REAL volume root, made with `subst`, and assert
           the negative case as hard as the positive one: an ordinary folder
           must keep its files.
           Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    function New-SubstVolume {
        <#
        .SYNOPSIS
            Maps a free drive letter onto a real directory, so a test has a
            genuine volume root ('X:\') rather than a folder standing in for
            one. Returns the drive, or $null when no letter is free.
        #>
        param([Parameter(Mandatory)][string]$BackingPath)
        $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0,1).ToUpper() })
        foreach ($letter in [char[]]('X','Y','W','V','U','T')) {
            if ($used -contains "$letter") { continue }
            & subst "${letter}:" $BackingPath 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { return "${letter}:" }
        }
        return $null
    }
    function Remove-SubstVolume {
        param([string]$Drive)
        if ($Drive) { & subst $Drive /D 2>&1 | Out-Null }
    }
}

Describe 'Volume-root pseudo-folder predicate (SR-074, TC-175)' {

    Context 'at a genuine volume root' {
        It 'matches the folder itself and everything under it' {
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\System Volume Information' | Should -BeTrue
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\System Volume Information\tracking.log' | Should -BeTrue
            Test-IsVolumeRootPseudoPath -Root 'D:\' -FullPath 'D:\$RECYCLE.BIN\S-1-5-21-x\$RABCDEF.txt' | Should -BeTrue
        }
        It 'is case-insensitive, as the filesystem is' {
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\$Recycle.Bin' | Should -BeTrue
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\system volume information\x' | Should -BeTrue
        }
        It 'treats a NESTED folder of the same name as ordinary user data (B6)' {
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\docs\System Volume Information\notes.txt' | Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\a\$RECYCLE.BIN\x.txt' | Should -BeFalse
        }
        It 'does not match ordinary paths, a prefix-sharing sibling, or the root itself' {
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\normal.txt' | Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\System Volume Information Backup\x' | Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'C:\' | Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root 'C:\' -FullPath 'D:\System Volume Information' | Should -BeFalse
        }
        It 'treats a UNC share root as a volume root' {
            Test-IsVolumeRootPseudoPath -Root '\\srv\share' -FullPath '\\srv\share\$RECYCLE.BIN\x' | Should -BeTrue
        }
    }

    Context 'at an ORDINARY folder - the T2 data-loss regression' {
        # THE GUARD. Without the volume-root condition every one of these
        # returns $true and the user's files vanish from the manifest silently.
        It 'never excludes a user folder that merely carries one of these names' {
            Test-IsVolumeRootPseudoPath -Root 'C:\Users\Pat\Project' -FullPath 'C:\Users\Pat\Project\$RECYCLE.BIN\notes.txt' |
                Should -BeFalse -Because 'these are the user''s own files, and losing them is silent data loss'
            Test-IsVolumeRootPseudoPath -Root 'C:\Users\Pat\Project' -FullPath 'C:\Users\Pat\Project\System Volume Information\notes.txt' |
                Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root 'D:\Data' -FullPath 'D:\Data\$RECYCLE.BIN\x' | Should -BeFalse
            Test-IsVolumeRootPseudoPath -Root '\\srv\share\proj' -FullPath '\\srv\share\proj\$RECYCLE.BIN\x' | Should -BeFalse
        }
    }
}

Describe 'Source enumeration at an ORDINARY root keeps everything (SR-074, TC-176)' {
    It 'backs up a user folder named $RECYCLE.BIN when the source is not a volume root' {
        $src = Join-Path $TestDrive 'ordinary'
        $recycle = Join-Path $src '$RECYCLE.BIN'
        New-Item -ItemType Directory -Path $recycle -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'real.txt') -Value 'keep me' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $recycle 'mine.txt') -Value "ALSO the user's" -Encoding ASCII

        $files = @(Get-DataFile -Root $src | ForEach-Object { $_.FullName })
        $files | Where-Object { $_ -like '*real.txt' } | Should -Not -BeNullOrEmpty
        $files | Where-Object { $_ -like '*mine.txt' } |
            Should -Not -BeNullOrEmpty -Because 'an ordinary folder is not a volume root, so nothing may be excluded'
    }
}

Describe 'Source enumeration at a REAL volume root (SR-074, TC-176/TC-177)' {
    BeforeAll {
        $script:backing = Join-Path $TestDrive 'vol'
        New-Item -ItemType Directory -Path $backing -Force | Out-Null
        $script:drive = New-SubstVolume -BackingPath $backing
    }
    AfterAll { Remove-SubstVolume -Drive $script:drive }

    It 'excludes the volume pseudo-folders, keeps everything else, and does not fail the set' {
        if (-not $script:drive) { Set-ItResult -Skipped -Because 'no free drive letter for subst'; return }
        $root = "$($script:drive)\"
        Set-Content -LiteralPath (Join-Path $root 'real.txt') -Value 'keep me' -Encoding ASCII

        # $RECYCLE.BIN is READABLE by its owner - the FILES half of the defect.
        $recycle = Join-Path $root '$RECYCLE.BIN'
        New-Item -ItemType Directory -Path $recycle -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $recycle 'deleted.txt') -Value 'never backed up' -Encoding ASCII

        # A nested folder of the same name is still the user's data (B6).
        $nested = Join-Path $root 'docs\System Volume Information'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $nested 'mine.txt') -Value 'user data' -Encoding ASCII

        # 'System Volume Information' denies read access - the ERRORS half. A
        # Deny ACE, not merely a folder of that name, or no error is ever raised
        # and the test passes whether or not the filter exists.
        $svi = Join-Path $root 'System Volume Information'
        New-Item -ItemType Directory -Path $svi -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $svi 'tracking.log') -Value 'volume noise' -Encoding ASCII
        icacls $svi /deny "${env:USERNAME}:(OI)(CI)(R)" | Out-Null
        try {
            $errors = New-Object System.Collections.Generic.List[object]
            $found = @(Get-DataFile -Root $root -EnumerationErrorOut $errors | ForEach-Object { $_.FullName })

            $found | Where-Object { $_ -like '*real.txt' } | Should -Not -BeNullOrEmpty
            $found | Where-Object { $_ -like '*mine.txt' } |
                Should -Not -BeNullOrEmpty -Because 'the NESTED folder is user data even at a volume root'
            $found | Where-Object { $_ -like '*deleted.txt' } |
                Should -BeNullOrEmpty -Because 'deleted files are not backup material'
            $found | Where-Object { $_ -like '*tracking.log' } | Should -BeNullOrEmpty
            @($errors | Where-Object { "$($_.Path)" -like '*System Volume Information*' }) |
                Should -BeNullOrEmpty -Because 'a volume root must not fail the set on every single run'
        } finally {
            icacls $svi /remove:d "${env:USERNAME}" | Out-Null
        }
    }
}

Describe 'The restorer filters both halves (SR-074, TC-178)' {
    It 'consults the predicate for candidates AND for enumeration errors' {
        # Filtering one alone leaves half the defect: $RECYCLE.BIN is a files
        # problem, System Volume Information is an errors problem.
        $text = (Get-Content -LiteralPath (Join-Path $repo 'Reconstruct.ps1') -Raw)
        ([regex]::Matches($text, 'Test-IsVolumeRootPseudoPath')).Count | Should -BeGreaterOrEqual 2
        $text | Should -Match 'realEnumErrors'
    }
}

Describe 'A store at a volume root CLASSIFIES a failure honestly (SR-074, SR-040, TC-180)' {
    # What the restore-side filter actually does, established by writing this
    # test three times with a negative control each time: Find-DataFileByHash
    # returns as soon as it FINDS the bytes and consults its host issues only
    # when it does not. On an INTACT store the error is discarded and the
    # restore exits 0 either way - asserting exit 0 here passes against a
    # deliberately broken restorer. The real effect is CLASSIFICATION.
    BeforeAll {
        $script:backing2 = Join-Path $TestDrive 'vol2'
        New-Item -ItemType Directory -Path $backing2 -Force | Out-Null
        $script:drive2 = New-SubstVolume -BackingPath $backing2
    }
    AfterAll { Remove-SubstVolume -Drive $script:drive2 }

    It 'reports ContentMissing (1), not StorageUnreadable (4), when the bytes really are gone' {
        if (-not $script:drive2) { Set-ItResult -Skipped -Because 'no free drive letter for subst'; return }
        $src = Join-Path $TestDrive 'cls-src'
        $chg = Join-Path $TestDrive 'cls-chg'
        $bkp = "$($script:drive2)\"
        New-Item -ItemType Directory -Path $src, $chg -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'ALPHA-CONTENT' -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'b.txt') -Value ('BETA-' * 500) -NoNewline

        $cfg = Join-Path $TestDrive 'cls-cfg.xml'
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
            HashRecalcFreq = 'A'; CompressEnabled = $false
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg
        & (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        Test-Path -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Should -BeTrue

        # Force the pool scan AND make it fail: blank the row's DataPath so the
        # bytes must be located by (hash, length), and delete the object so the
        # search cannot succeed. Re-stamp the witness, or the run exits 3 on the
        # edited index instead of ever reaching the pool.
        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        $victim = $rows | Where-Object RelativePath -eq 'a.txt'
        Remove-Item -LiteralPath (Join-Path $bkp $victim.DataPath) -Force
        $victim.DataPath = ''
        $rows | Export-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $bkp | Out-Null

        $svi = Join-Path $bkp 'System Volume Information'
        New-Item -ItemType Directory -Path $svi -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $svi 'tracking.log') -Value 'volume noise' -NoNewline
        icacls $svi /deny "${env:USERNAME}:(OI)(CI)(R)" | Out-Null
        try {
            $target = Join-Path $TestDrive 'cls-restored'
            $out = & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target -ExitCode 2>&1
            $LASTEXITCODE | Should -Be 1 -Because "the bytes are genuinely gone - content damage, not a host problem to retry. Output: $out"

            $log = Get-Content -LiteralPath (Join-Path $target 'RECONSTRUCT.log') -Raw
            $log | Should -Match 'ContentMissing'
            $log | Should -Not -Match 'StorageUnreadable'
            # Failing loudly means salvaging everything recoverable first (SR-029).
            (Get-Content -LiteralPath (Join-Path $target 'b.txt') -Raw) | Should -Be ('BETA-' * 500)
        } finally {
            icacls $svi /remove:d "${env:USERNAME}" | Out-Null
        }
    }
}
