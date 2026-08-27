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
    It 'a deduplicated twin keeps its OWN mtime, not the pool object owner''s (TC-136, <Mode>)' {
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

    It 'a store carrying a sidecar still audits CLEAN, in the root and in a snapshot (TC-137)' {
        # The sidecar is a new root-level file in every folder the store owns.
        # Get-DataFile filters through Test-IsInfrastructureFile, so SR-064's
        # unreferenced-data audit must not see it - if it did, every store with
        # an empty directory would report an orphan on every run, and prune's
        # unreferenced-data rail would refuse every snapshot.
        $root = Join-Path $TestDrive 'dirs-audit'
        $s = New-FidelityStore -Root $root
        Set-Content -LiteralPath (Join-Path $s.Src 'uniq.txt') -Value ('CHANGED-Q' * 4000) -NoNewline
        & $entry -ConfigPath $s.Cfg -NoMail -NonInteractive *>&1 | Out-Null
        $snap = @(Get-ChildItem -LiteralPath $s.Chg -Directory -Force |
                    Where-Object { $_.Name -like 'Snapshot_*' })[0]
        Test-Path -LiteralPath (Join-Path $snap.FullName $sidecarName) | Should -BeTrue

        $verifyOut = & $pwshExe -NoProfile -File $entry -ConfigPath $s.Cfg -NoMail `
                        -NonInteractive -Action Verify -ExitCode *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $verifyOut | Should -Not -Match 'DIRECTORIES\.csv'
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

Describe 'The stored form is decided by the bytes, not the Compressed column (SR-068)' -ForEach @(
    @{ Mode = 'Plain'; Compress = $false }, @{ Mode = 'Compress'; Compress = $true }
) {
    It 'restores byte-exact with EVERY row''s Compressed value flipped (TC-141, <Mode>)' {
        # The decisive case. Before SR-068 a row resolved through its own
        # DataPath was expanded-or-copied on the column's word, so flipping the
        # column produced 7z container bytes written under the real filename
        # (exit 0, silently wrong) or a failed expand of raw bytes.
        $root = Join-Path $TestDrive ('form-flip-' + $Mode)
        $s = New-FidelityStore -Root $root -Compress $Compress
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        foreach ($r in $rows) { $r.Compressed = if ($r.Compressed -eq 'Yes') { 'No' } else { 'Yes' } }
        Set-FidelityManifest -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 'restored'
        (Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t).Code | Should -Be 0
        foreach ($rel in 'twin-a.txt', 'twin-b.txt', 'uniq.txt', 'hidden-dir\secret.txt') {
            (Get-FileXxHash -FilePath (Join-Path $t $rel)) |
                Should -Be (Get-FileXxHash -FilePath (Join-Path $s.Src $rel)) -Because "$rel must survive a lying column"
        }
    }

    It 'an already-compressed SOURCE file is never expanded, column right or wrong (TC-141, <Mode>)' {
        # The case the human asked about: a real .7z in the SOURCE is stored RAW
        # (SR-004 declines to re-compress it), so its stored bytes ARE a 7z
        # archive while the row correctly says Compressed='No'. Sniffing alone
        # would call it an archive and expand the user's own file; only "do
        # these bytes already reproduce the row?" gets it right.
        if (-not $sevenZip -or -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because '7-Zip is not available on this host'
        }
        $root = Join-Path $TestDrive ('form-source7z-' + $Mode)
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null
        # A GENUINE archive in the source. '.7z' is on the non-compressible list,
        # so SR-004 stores it raw - which is exactly the shape that makes a
        # magic-byte sniff insufficient. (The restorer never consults the stored
        # object's name, so the extension is not what saves it here; the row's
        # own hash is.)
        $payload = Join-Path $root 'payload.txt'
        Set-Content -LiteralPath $payload -Value ('INSIDE-THE-USERS-ARCHIVE ' * 200) -NoNewline
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $payload `
            -Destination7z (Join-Path $src 'backup-of-mine.7z')
        Set-Content -LiteralPath (Join-Path $src 'plain.txt') -Value ('PLAIN ' * 500) -NoNewline

        $cfg = Join-Path $root 'cfg.xml'
        New-FidelityConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null

        $manifest = Join-Path $bkp 'MANIFEST.csv'
        $rows = @(Import-Csv -LiteralPath $manifest)
        $arc = @($rows | Where-Object RelativePath -eq 'backup-of-mine.7z')[0]
        $arc.Compressed | Should -Be 'No' -Because 'SR-004 does not re-compress an already-compressed source'

        # Correct column: restores byte-exact, NOT expanded.
        $t1 = Join-Path $root 'restored-correct'
        (Invoke-FidelityRestore -Recon (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t1).Code | Should -Be 0
        (Get-FileXxHash -FilePath (Join-Path $t1 'backup-of-mine.7z')) |
            Should -Be (Get-FileXxHash -FilePath (Join-Path $src 'backup-of-mine.7z'))

        # LYING column ('Yes'): the bytes still win, so the user's archive comes
        # back as their archive rather than being unpacked over its own name.
        $arc.Compressed = 'Yes'
        Set-FidelityManifest -Folder $bkp -Rows $rows
        $t2 = Join-Path $root 'restored-lying'
        (Invoke-FidelityRestore -Recon (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t2).Code | Should -Be 0
        (Get-FileXxHash -FilePath (Join-Path $t2 'backup-of-mine.7z')) |
            Should -Be (Get-FileXxHash -FilePath (Join-Path $src 'backup-of-mine.7z'))
    }

    It 'genuine damage is still reported, not silently reinterpreted (TC-141, <Mode>)' {
        # Deriving the form must not become a licence to accept anything: bytes
        # that reproduce NEITHER form are damage and must fail loudly.
        $root = Join-Path $TestDrive ('form-damage-' + $Mode)
        $s = New-FidelityStore -Root $root -Compress $Compress
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $victim = @($rows | Where-Object RelativePath -eq 'uniq.txt')[0]
        [IO.File]::WriteAllText((Join-Path $s.Bkp $victim.DataPath), 'NEITHER RAW CONTENT NOR AN ARCHIVE')

        $t = Join-Path $root 'restored'
        $r = Invoke-FidelityRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 1 -Because 'unreproducible bytes are content damage'
        $r.Output | Should -Match 'INCOMPLETE'
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
        $r.Output | Should -Match 'not a store this kit can restore'
        Test-Path -LiteralPath (Join-Path $t 'twin-a.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $t 'uniq.txt')   | Should -BeFalse
    }
}

Describe 'A transiently unreadable source file is retried, not lost (SR-067)' {
    It 'a file whose content is UNIQUE is rescued when the lock clears (TC-140)' {
        # Before SR-067 this file got exactly ONE attempt: the SR-060 candidate
        # loop only falls back to other MEMBERS of a content group, and a unique
        # file's group has one member.
        #
        # The lock is held IN-PROCESS (FileShare.None denies even this process's
        # own other handles) and released from inside the LOG callback, the
        # instant the retry line is emitted. Deterministic in both directions:
        # there is no wall-clock race to lose, and the release CANNOT happen
        # unless the retry path actually ran. The first version of this test
        # raced a Start-Job and passed vacuously whenever the copy won.
        $root = Join-Path $TestDrive 'retry-rescued'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $src, $bkp -Force | Out-Null
        $victim = Join-Path $src 'locked.txt'
        Set-Content -LiteralPath $victim -Value 'LOCKED-BUT-RECOVERABLE' -NoNewline

        $group = [pscustomobject]@{
            RelativePath = 'locked.txt'
            Length       = (Get-Item -LiteralPath $victim).Length
            xxH2Hash     = (Get-FileXxHash -FilePath $victim)
            LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
        }

        $holder = @{ Stream = [IO.File]::Open($victim, 'Open', 'Read', 'None') }
        $map = @{}; $changed = 0; $ok = $true
        $lines = New-Object System.Collections.Generic.List[string]
        $log = {
            param($m, $l = 'INFO')
            $lines.Add("[$l] $m")
            if ($m -match 'Retrying in' -and $holder.Stream) {
                $holder.Stream.Dispose(); $holder.Stream = $null
            }
        }.GetNewClosure()
        try {
            Invoke-BackupFileGroup -Group @($group) -SrcPath $src -BkpPath $bkp `
                -CompressEnabled $false -SevenZipPath $sevenZip `
                -BackupDb @() -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) `
                -Log $log -OverallSuccess ([ref]$ok)
        } finally {
            if ($holder.Stream) { $holder.Stream.Dispose() }
        }

        ($lines -join "`n") | Should -Match 'Retrying in \d+ ms' -Because 'attempt 1 met a real lock'
        $ok | Should -BeTrue -Because 'the lock cleared within the retry window'
        $map.Keys | Should -HaveCount 1
        # The bytes really landed, proven from disk rather than from the map.
        $stored = Join-Path $bkp $map['locked.txt'].DataPath
        Get-Content -LiteralPath $stored -Raw | Should -Be 'LOCKED-BUT-RECOVERABLE'
    }

    It 'a permanently unreadable file is failed loudly and gets NO manifest row (TC-140)' {
        $root = Join-Path $TestDrive 'retry-exhausted'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $src, $bkp -Force | Out-Null
        $victim = Join-Path $src 'gone.txt'
        Set-Content -LiteralPath $victim -Value 'ABOUT-TO-VANISH' -NoNewline
        $group = [pscustomobject]@{
            RelativePath = 'gone.txt'
            Length       = (Get-Item -LiteralPath $victim).Length
            xxH2Hash     = (Get-FileXxHash -FilePath $victim)
            LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
        }
        Remove-Item -LiteralPath $victim -Force          # unreadable for good

        $map = @{}; $changed = 0; $ok = $true
        $lines = New-Object System.Collections.Generic.List[string]
        $log = { param($m, $l = 'INFO') $lines.Add("[$l] $m") }
        Invoke-BackupFileGroup -Group @($group) -SrcPath $src -BkpPath $bkp `
            -CompressEnabled $false -SevenZipPath $sevenZip `
            -BackupDb @() -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) `
            -Log $log -OverallSuccess ([ref]$ok)

        $ok | Should -BeFalse -Because 'a file that exists in source and not in the backup is a failed set'
        $map.Keys | Should -HaveCount 0 -Because 'the manifest must never name content the store does not hold'
        ($lines -join "`n") | Should -Match 'This file is NOT in the backup'
        ($lines -join "`n") | Should -Match 'after 3 attempt\(s\)'
    }

    It 'END-TO-END: a file that vanishes between the walk and the copy is omitted, not faked (TC-140)' {
        # The unit cases above build the group by hand. This one drives the real
        # entry point and deletes the file inside the actual window, to prove the
        # whole pipeline - not just the copy stage - handles a file that was
        # enumerated and hashed and then disappeared before its bytes were read.
        #
        # The seam is Update-SourceManifest's source hash cache: it is written at
        # the end of step 5 and strictly precedes step 10's copies. A SEPARATE
        # process polls for it and deletes the victim the instant it appears - a
        # separate process because the parent runspace is blocked on the backup
        # child and cannot pump a FileSystemWatcher event until it returns (the
        # first version of this test failed for exactly that reason and never
        # entered the window at all).
        #
        # Ordering is guaranteed; callback LATENCY is not, so the test proves it
        # entered the window before asserting anything, and SKIPS rather than
        # failing if a loaded host starved the sniper. It can therefore never go
        # falsely green: the assertions only run once the precondition holds.
        $root  = Join-Path $TestDrive 'vanish-midrun'
        $src   = Join-Path $root 'src';   $bkp   = Join-Path $root 'bkp'
        $chg   = Join-Path $root 'chg';   $state = Join-Path $root 'state'
        New-Item -ItemType Directory -Path $src, $bkp, $chg, $state -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'keep.txt')   -Value ('KEEP '   * 500) -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'vanish.txt') -Value ('VANISH ' * 500) -NoNewline

        $victim = Join-Path $src 'vanish.txt'
        $cache  = Join-Path $state 'MANIFEST.csv'
        $stamp  = Join-Path $root 'sniped.at'
        $sniperScript = Join-Path $root 'sniper.ps1'
        @"
`$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt `$deadline) {
    if (Test-Path -LiteralPath '$cache') {
        Remove-Item -LiteralPath '$victim' -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath '$victim')) { Set-Content -LiteralPath '$stamp' -Value 'x' }
        break
    }
    Start-Sleep -Milliseconds 1
}
"@ | Set-Content -LiteralPath $sniperScript -Encoding UTF8
        $sniper = Start-Process -FilePath $pwshExe -ArgumentList @('-NoProfile', '-File', $sniperScript) `
                                -PassThru -WindowStyle Hidden

        $cfg = Join-Path $root 'cfg.xml'
        $set = [pscustomobject]@{
            Name = 'V'; SourcePath = $src; SourceStatePath = $state; BackupPath = $bkp
            ChangePath = $chg; HashRecalcFreq = 'A'; CompressEnabled = $false
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg

        & $pwshExe -NoProfile -File $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        $code = $LASTEXITCODE
        $sniper | Wait-Process -Timeout 70 -ErrorAction SilentlyContinue

        # Precondition: the walk DID see the file (so it was hashed) and the
        # sniper DID delete it before the copy stage reached it.
        $walked = @(Import-Csv -LiteralPath $cache | Where-Object RelativePath -eq 'vanish.txt').Count
        if (-not (Test-Path -LiteralPath $stamp) -or $walked -ne 1) {
            Set-ItResult -Skipped -Because 'the sniper did not enter the walk-to-copy window on this host'
        }

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        @($rows | Where-Object RelativePath -eq 'vanish.txt').Count |
            Should -Be 0 -Because 'the manifest must never name content the store does not hold'
        @($rows | Where-Object RelativePath -eq 'keep.txt').Count |
            Should -Be 1 -Because 'one vanished file must not cost the healthy ones'
        $code | Should -Be 1 -Because 'a file present at the walk and absent from the backup fails the set'
        $log = Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw
        $log | Should -Match 'This file is NOT in the backup'
        $log | Should -Match 'after 3 attempt\(s\)'
        # The stored object for the healthy file really exists on disk.
        $keepRow = @($rows | Where-Object RelativePath -eq 'keep.txt')[0]
        Test-Path -LiteralPath (Join-Path $bkp $keepRow.DataPath) | Should -BeTrue
    }

    It 'a deterministic failure is not retried at all, so the budget survives it (TC-140)' {
        # A DIRECTORY occupying the destination cannot become a file by waiting.
        Test-CopyFailureIsTransient -Message "destination 'x' is a directory; refusing to copy into it" |
            Should -BeFalse
        Test-CopyFailureIsTransient -Message 'The process cannot access the file because it is being used' |
            Should -BeTrue
        Get-CopyRetryDelayMs -Attempt 1 | Should -BeGreaterThan 0
        Get-CopyRetryDelayMs -Attempt 3 | Should -BeNullOrEmpty -Because 'three attempts is the cap'
    }

    It 'a spent run budget stops the waiting and says so (TC-140)' {
        $root = Join-Path $TestDrive 'retry-budget'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $src, $bkp -Force | Out-Null
        $victim = Join-Path $src 'gone.txt'
        Set-Content -LiteralPath $victim -Value 'ABOUT-TO-VANISH' -NoNewline
        $group = [pscustomobject]@{
            RelativePath = 'gone.txt'
            Length       = (Get-Item -LiteralPath $victim).Length
            xxH2Hash     = (Get-FileXxHash -FilePath $victim)
            LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
        }
        Remove-Item -LiteralPath $victim -Force

        $map = @{}; $changed = 0; $ok = $true; $budget = 0
        $lines = New-Object System.Collections.Generic.List[string]
        $log = { param($m, $l = 'INFO') $lines.Add("[$l] $m") }
        $elapsed = Measure-Command {
            Invoke-BackupFileGroup -Group @($group) -SrcPath $src -BkpPath $bkp `
                -CompressEnabled $false -SevenZipPath $sevenZip `
                -BackupDb @() -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) `
                -Log $log -OverallSuccess ([ref]$ok) -RetryBudgetMs ([ref]$budget)
        }
        ($lines -join "`n") | Should -Match "copy-retry budget is spent"
        ($lines -join "`n") | Should -Match 'after 1 attempt\(s\)'
        $elapsed.TotalMilliseconds | Should -BeLessThan 1000 -Because 'a spent budget must not sleep'
        $map.Keys | Should -HaveCount 0
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
