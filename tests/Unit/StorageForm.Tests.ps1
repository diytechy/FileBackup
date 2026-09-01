<#
.SYNOPSIS  WP5 storage-form trust: repro + verification/repair coverage
           (SR-049, SR-050, SR-052).
.NOTES     TC-091..TC-094, TC-096, TC-098, TC-100, TC-101 (Windows half),
           plus WP17 Part A's TC-222, TC-229 and TC-231 arms.
           These drive real backup runs and real restores in-process, so they
           also exercise the engine I/O shells. Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry = Join-Path $repo 'FileBackup.ps1'
    $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath

    function New-FormConfig {
        # Storage is always content-addressed (SR-061): there is no layout axis.
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $false)
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function Invoke-FormBackup {
        # Returns the run's transcript so a test can assert on logged classes.
        param([string]$Cfg, [Nullable[datetime]]$At)
        $extra = @{}
        if ($At) { $extra['BackupTime'] = [datetime]$At }
        $out = & $entry -ConfigPath $Cfg -NoMail -NonInteractive @extra *>&1
        return ($out | Out-String)
    }

    function Invoke-FormBackupExitCode {
        # Child process so the entry point's `exit` is observable without
        # terminating this runspace (same pattern as TC-034).
        param([string]$Cfg)
        & (Get-Process -Id $PID).Path -NoProfile -File $script:entry -ConfigPath $Cfg -NoMail -NonInteractive *>&1 | Out-Null
        return $LASTEXITCODE
    }

    function Invoke-VerifyExitCode {
        # -Action Verify through the real entry point, in a child process so its
        # exit status is observable (the SR-040 codes at the process boundary).
        param([string]$Cfg)
        & (Get-Process -Id $PID).Path -NoProfile -File $script:entry -ConfigPath $Cfg `
            -Action Verify -NoMail -NonInteractive -ExitCode *>&1 | Out-Null
        return $LASTEXITCODE
    }

    function Get-TreeFingerprint {
        param([string[]]$Folder)
        $out = @{}
        foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -Recurse -ErrorAction SilentlyContinue)) {
            $out[$f.FullName] = "$($f.Length)|$((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)"
        }
        return $out
    }

    function Assert-TreeUnchanged {
        param([hashtable]$Before, [string[]]$Folder)
        $after = Get-TreeFingerprint -Folder $Folder
        $after.Count | Should -Be $Before.Count
        foreach ($k in $Before.Keys) { $after[$k] | Should -Be $Before[$k] }
    }

    function Set-ManifestRows {
        <#
        .SYNOPSIS
            Rewrites a folder's MANIFEST.csv from raw CSV rows and re-stamps its
            SR-038 witness, so a deliberately tampered store fails the way the
            test means to exercise instead of exiting 3 (AGENTS.md §3).
        #>
        param([string]$Folder, [object[]]$Rows)
        $Rows | Export-Csv -LiteralPath (Join-Path $Folder 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $Folder | Out-Null
    }

    function New-ArchiveShapedFile {
        <#
        .SYNOPSIS
            Writes a REAL 7z archive (7-Zip's own bytes, so the first six are the
            37 7A BC AF 27 1C signature) to $Path, whatever $Path is called.

            Used for the already-compressed SOURCE fixtures: a literal string
            like 'pretend-archive-source' is Raw to Get-StoredFileForm, so a
            fixture built from one asserts nothing about archive-shaped content.
        #>
        param([string]$Path, [string]$Content = 'INNER-PAYLOAD ')
        $work = Join-Path ([IO.Path]::GetDirectoryName($Path)) ([IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $inner = Join-Path $work 'inner.txt'
        [IO.File]::WriteAllText($inner, ($Content * 50))
        Compress-FileWithSevenZip -SevenZipPath $script:sevenZip -SourceFile $inner `
            -Destination7z (Join-Path $work 'made.7z')
        Move-Item -LiteralPath (Join-Path $work 'made.7z') -Destination $Path -Force
        Remove-Item -LiteralPath $work -Recurse -Force
    }

    function New-MalformedStore {
        <#
        .SYNOPSIS
            A real content-addressed backup of four files, then each row bent
            into one of TC-091's four malformed shapes. The bytes are ground
            truth; only the manifest and the data-file NAMES are tampered with.

            a.txt  flag-over-raw     Compressed=Yes, DataPath 'a.txt.7z', RAW bytes
            b.txt  flag-over-archive Compressed=No,  DataPath 'b.txt',    ARCHIVE bytes
            c.txt  name-lies         Compressed=No,  DataPath 'c.txt.7z', RAW bytes
            d.txt  dangling-datapath Compressed=No,  DataPath 'd.txt',    no file
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        foreach ($n in 'a', 'b', 'c', 'd') {
            [IO.File]::WriteAllText((Join-Path $src "$n.txt"), ("CONTENT-$n " * 40))
        }
        Invoke-FormBackup -Cfg $cfg | Out-Null

        # The shapes are written EXPLICITLY (bytes and DataPath both), so the
        # fixture means the same thing with and without compression rather than
        # inheriting whatever form the seed run happened to produce.
        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        foreach ($row in $rows) {
            $current = Join-Path $bkp $row.DataPath
            $raw     = Join-Path $src $row.RelativePath        # the true, raw bytes
            switch ($row.RelativePath) {
                'a.txt' {
                    Remove-Item -LiteralPath $current -Force
                    Copy-Item -LiteralPath $raw -Destination (Join-Path $bkp 'a.txt.7z') -Force
                    $row.DataPath = 'a.txt.7z'; $row.Compressed = 'Yes'
                }
                'b.txt' {
                    # Real archive bytes parked under a RAW name (shape b).
                    Remove-Item -LiteralPath $current -Force
                    Compress-FileWithSevenZip -SevenZipPath $script:sevenZip -SourceFile $raw `
                        -Destination7z (Join-Path $Root 'b.7z')
                    Move-Item -LiteralPath (Join-Path $Root 'b.7z') -Destination (Join-Path $bkp 'b.txt') -Force
                    $row.DataPath = 'b.txt'; $row.Compressed = 'No'
                }
                'c.txt' {
                    Remove-Item -LiteralPath $current -Force
                    Copy-Item -LiteralPath $raw -Destination (Join-Path $bkp 'c.txt.7z') -Force
                    $row.DataPath = 'c.txt.7z'; $row.Compressed = 'No'
                }
                'd.txt' {
                    Remove-Item -LiteralPath $current -Force
                    $row.DataPath = 'd.txt'
                }
            }
        }
        Set-ManifestRows -Folder $bkp -Rows $rows
        return [pscustomobject]@{ Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg }
    }

    function New-FormDivergedTimeline {
        <#
        .SYNOPSIS
            TC-092/TC-094: a snapshot whose blank-DataPath row claims a form the
            only surviving pool copy does not have.

        .DESCRIPTION
            run1 -> a.txt + b.txt stored in $StartCompressed's form
            run2 -> b.txt superseded => Snapshot_D1, whose a.txt row is blanked
                    by Optimize (the root holds the same content) and keeps
                    run1's Compressed value
            then -> the snapshot's blanked a.txt row is flipped to the OPPOSITE
                    Compressed claim, so it disagrees with the pool copy.

            The divergence is CONSTRUCTED because ordinary operation can no
            longer produce it. Before WP9 this fixture flipped CompressEnabled
            and let the layout migration re-form the backup root while snapshots
            kept their form. SR-061 deleted that migration, so a form
            disagreement now has only one origin: damage or tampering outside
            the tool. That is a real narrowing of the hazard - and it is exactly
            why the assertions below must stay: the restorer (SR-050) and the
            audit (SR-049) still have to handle a store in this state, they just
            can no longer reach it by a supported operation.
        #>
        param([string]$Root, [bool]$StartCompressed)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $cfgA = Join-Path $Root 'a.xml'
        New-FormConfig -Path $cfgA -Src $src -Bkp $bkp -Chg $chg -Compress $StartCompressed

        $aPath = Join-Path $src 'a.txt'
        [IO.File]::WriteAllText($aPath, ('THE-ORIGINAL-BYTES ' * 200))
        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'v1')
        Invoke-FormBackup -Cfg $cfgA -At ([datetime]'2024-01-01 00:00:01') | Out-Null

        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'v2')
        Invoke-FormBackup -Cfg $cfgA -At ([datetime]'2024-02-02 00:00:02') | Out-Null

        $snap = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' })[0]

        # Make the snapshot's blanked a.txt row claim the form the pool copy does
        # NOT have (see .DESCRIPTION for why this is constructed rather than run).
        $snapRows = @(Import-Csv -LiteralPath (Join-Path $snap.FullName 'MANIFEST.csv'))
        $blanked = @($snapRows | Where-Object { $_.RelativePath -eq 'a.txt' })[0]
        if (-not $blanked) { throw "fixture: no a.txt row in $($snap.FullName)" }
        if (-not [string]::IsNullOrWhiteSpace($blanked.DataPath)) {
            throw "fixture: a.txt row in $($snap.FullName) is not blank (DataPath='$($blanked.DataPath)')"
        }
        $blanked.Compressed = if ($StartCompressed) { 'No' } else { 'Yes' }
        Set-ManifestRows -Folder $snap.FullName -Rows $snapRows

        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Snapshot = $snap.FullName
            Original = $aPath
        }
    }
}

Describe 'A backup run never re-forms stored data (SR-049, SR-061)' {
    # TC-091 — REPRO-FIRST. The first two cases pin the DEFECT (they pass on the
    # pre-WP5 code and are the evidence that finding C is real); the third is the
    # requirement and is red until SR-049's verification action exists.
    BeforeAll {
        $script:store = New-MalformedStore -Root (Join-Path $TestDrive 'tc091')
    }

    It 'leaves every malformed row byte-identical and still reports the set successful (SR-049)' {
        $before = Get-TreeFingerprint -Folder $store.Bkp
        Invoke-FormBackup -Cfg $store.Cfg | Out-Null
        # SR-061: nothing already stored is ever re-formed, so a malformed row
        # is left exactly as it is for -Action Verify/-RepairStorage to judge.
        # (Before WP9 this held for a different reason: the migration compared
        # manifest metadata with configuration and never with the bytes.)
        $rows = @(Import-Csv -LiteralPath (Join-Path $store.Bkp 'MANIFEST.csv'))
        ($rows | Where-Object RelativePath -eq 'a.txt').Compressed | Should -Be 'Yes'
        ($rows | Where-Object RelativePath -eq 'b.txt').Compressed | Should -Be 'No'
        ($rows | Where-Object RelativePath -eq 'c.txt').DataPath   | Should -Be 'c.txt.7z'
        # WP7 (SR-053): the DANGLING shape is the exception to "untouched" — a
        # row whose data file is missing is healed from the still-matching
        # source by the run itself. Healing restores missing BYTES; it never
        # rewrites the three FORM-malformed rows above (that is Verify/Repair's
        # job, and the assertions below prove they stayed byte-identical).
        # The healed copy is NAMED by the store (SR-061: a hash-size name), so
        # it is identified from its own row rather than by assuming a path.
        $healed = @($rows | Where-Object RelativePath -eq 'd.txt')[0]
        $healed.DataPath | Should -Not -BeNullOrEmpty
        $healedFull = Join-Path $store.Bkp $healed.DataPath
        Test-Path -LiteralPath $healedFull | Should -BeTrue
        # Infrastructure (manifest, witness, run state, kit) is rewritten by every
        # run; the DATA files are what must be byte-identical. Get-DataFile applies
        # exactly the SR-022 root-level-only rule the engine itself uses.
        $after = Get-TreeFingerprint -Folder $store.Bkp
        foreach ($f in @(Get-DataFile -Root $store.Bkp)) {
            if ($f.FullName -ieq $healedFull) { continue }   # healed above — deliberately not byte-identical
            $after[$f.FullName] | Should -Be $before[$f.FullName] -Because "data file '$($f.Name)' must be untouched"
        }
    }

    It 'reports one finding per malformed row with its class (SR-049)' {
        # Its OWN store: the case above deliberately runs a backup over the
        # fixture, which heals the dangling row by re-copying it from source.
        $store = New-MalformedStore -Root (Join-Path $TestDrive 'tc091-classes')
        $findings = @(Test-BackupStorageForm -BackupRoot $store.Bkp -ChangeRoot $store.Chg)
        ($findings | Where-Object RelativePath -eq 'a.txt').Class | Should -Be 'FlagOverRaw'
        ($findings | Where-Object RelativePath -eq 'b.txt').Class | Should -Be 'FlagOverArchive'
        ($findings | Where-Object RelativePath -eq 'c.txt').Class | Should -Be 'NameLies'
        ($findings | Where-Object RelativePath -eq 'd.txt').Class | Should -Be 'DanglingDataPath'
        @($findings | Where-Object Class -ne 'Unreferenced').Count | Should -Be 4
    }
}

Describe 'Hash recovery trusts the located file''s form (SR-050)' {
    # TC-092 — the no-tampering repro. Before the SR-050 fix the first case exits
    # 0 having written 7z container bytes under the original filename (silent
    # corruption) and the second exits 4 with a misfiled host-class cause.
    It 'restores a snapshot byte-exact after compression is turned <Flip> (SR-050)' -ForEach @(
        @{ Flip = 'on';  StartCompressed = $false }
        @{ Flip = 'off'; StartCompressed = $true  }
    ) {
        $t = New-FormDivergedTimeline -Root (Join-Path $TestDrive "tc092-$Flip") `
                -StartCompressed $StartCompressed
        $target = Join-Path $TestDrive "tc092-$Flip-out"
        & (Join-Path $t.Snapshot 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        $restored = Join-Path $target 'a.txt'
        Test-Path -LiteralPath $restored -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $restored -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $t.Original -Algorithm SHA256).Hash
    }
}

Describe 'Hash recovery reports the located file''s form (SR-050)' {
    # TC-098 — Reconstruct.ps1's half, driven directly against hand-bent stores.
    # The kit (Common module + DLL + RECONSTRUCT.ps1) is deposited by a real run
    # first, so the restore under test is the deployed, standalone one.
    BeforeAll {
        function New-BlankRowStore {
            <#
            .SYNOPSIS
                A one-file backup whose row is blanked to force hash recovery,
                with the single pool copy renamed/re-formed as the case demands.
            .PARAMETER DataName
                What the surviving pool copy is called (its extension is the
                name's claim about its form).
            .PARAMETER Compressed
                What the blanked ROW claims — deliberately the wrong answer.
            .PARAMETER Corrupt
                Replace the pool copy's bytes with garbage, so nothing matches.
            #>
            param([string]$Root, [string]$DataName, [string]$Compressed,
                  [bool]$Compress = $false, [switch]$Corrupt)
            $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
            $cfg = Join-Path $Root 'c.xml'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
            $original = Join-Path $Root 'original.bin'
            [IO.File]::WriteAllText($original, ('PAYLOAD-BYTES ' * 300))
            Copy-Item -LiteralPath $original -Destination (Join-Path $src 'x.txt') -Force
            Invoke-FormBackup -Cfg $cfg | Out-Null

            $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
            $row  = $rows | Where-Object RelativePath -eq 'x.txt'
            Move-Item -LiteralPath (Join-Path $bkp $row.DataPath) -Destination (Join-Path $bkp $DataName) -Force
            if ($Corrupt) { [IO.File]::WriteAllText((Join-Path $bkp $DataName), 'not an archive and not the payload') }
            $row.DataPath = ''          # force the hash-recovery branch
            $row.Compressed = $Compressed
            Set-ManifestRows -Folder $bkp -Rows $rows
            return [pscustomobject]@{ Bkp = $bkp; Original = $original }
        }
        function Invoke-Kit {
            param([string]$Folder, [string]$Target)
            $out = & (Join-Path $Folder 'RECONSTRUCT.ps1') -TargetRoot $Target *>&1
            return ($out | Out-String)
        }
    }

    It 'recovers a .7z-named file that holds RAW bytes instead of calling it a candidate error (SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-rawfallback') -DataName 'x.txt.7z' -Compressed 'Yes'
        $target = Join-Path $TestDrive 'tc098-rawfallback-out'
        Invoke-Kit -Folder $s.Bkp -Target $target | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $target 'x.txt') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $s.Original -Algorithm SHA256).Hash
    }

    It 'copies a raw pool file for a row that wrongly claims Compressed=Yes (SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-rawrow') -DataName 'x.txt' -Compressed 'Yes'
        $target = Join-Path $TestDrive 'tc098-rawrow-out'
        Invoke-Kit -Folder $s.Bkp -Target $target | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $target 'x.txt') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $s.Original -Algorithm SHA256).Hash
    }

    It 'expands an archive pool file for a row that wrongly claims Compressed=No (SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-archiverow') -DataName 'x.txt.7z' `
                -Compressed 'No' -Compress $true
        $target = Join-Path $TestDrive 'tc098-archiverow-out'
        Invoke-Kit -Folder $s.Bkp -Target $target | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $target 'x.txt') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $s.Original -Algorithm SHA256).Hash
    }

    It 'still resolves a NON-blank DataPath row by its own Compressed column (SR-050)' {
        # A compressed backup restored from its own root: every row has a
        # DataPath, so no located form exists and Compressed must still decide.
        $root = Join-Path $TestDrive 'tc098-nonblank'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true
        [IO.File]::WriteAllText((Join-Path $src 'y.txt'), ('COMPRESSIBLE ' * 300))
        Invoke-FormBackup -Cfg $cfg | Out-Null
        (Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'y.txt').Compressed |
            Should -Be 'Yes'
        $target = Join-Path $root 'out'
        Invoke-Kit -Folder $bkp -Target $target | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $target 'y.txt') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $src 'y.txt') -Algorithm SHA256).Hash
    }

    It 'recovers a blank row for a GENUINE .7z source file, with no tampering at all (SR-050, SR-004)' {
        # WP5 review finding H2. An archive candidate that expands SUCCESSFULLY
        # but whose PAYLOAD does not match was dropped without its own bytes ever
        # being tested — and a real '.7z' source file, which SR-004 stores raw,
        # is exactly that shape. The row was then unrecoverable while every
        # checker called the store clean (the .7z RelativePath is the deliberate
        # Test-StorageFormAgreement exemption).
        #
        # Repro recipe: an ordinary two-run timeline. Run 2 supersedes an
        # UNRELATED file, so Optimize-ChangeFolders blanks the archive's row in
        # the snapshot and its bytes survive only in the backup root.
        $root = Join-Path $TestDrive 'tc098-realseven'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg

        # A GENUINE archive as user content: 7-Zip made it, so it expands.
        $inner = Join-Path $root 'inner.txt'
        [IO.File]::WriteAllText($inner, ('ARCHIVE-PAYLOAD ' * 200))
        Compress-FileWithSevenZip -SevenZipPath $script:sevenZip -SourceFile $inner `
            -Destination7z (Join-Path $src 'real.7z')
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v1')
        Invoke-FormBackup -Cfg $cfg -At ([datetime]'2024-01-01 00:00:01') | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v2')
        Invoke-FormBackup -Cfg $cfg -At ([datetime]'2024-02-02 00:00:02') | Out-Null

        $snap = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -match '^Snapshot_')[0].FullName
        $row  = @(Import-Csv -LiteralPath (Join-Path $snap 'MANIFEST.csv') | Where-Object RelativePath -eq 'real.7z')[0]
        $row.DataPath | Should -BeNullOrEmpty -Because 'Optimize blanks a row whose bytes the pool already holds'

        # ...and the audit calls the store clean, which is why this had to be
        # caught in the restorer.
        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty

        $target = Join-Path $root 'out'
        Invoke-Kit -Folder $snap -Target $target | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $target 'real.7z') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $src 'real.7z') -Algorithm SHA256).Hash
    }

    It 'reports an unexpandable, unmatching .7z candidate as CONTENT damage naming the candidate (SR-040, kit rev 6)' {
        # Until kit revision 6 this shape was reported as a HOST failure — but no
        # candidate the locator inspects is the row's own file, so an archive
        # that will not expand is damaged data a retry cannot fix (D-3 ruling,
        # 2026-08-24). The old pin asserted '*0 content-missing, 1 host*'.
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-host') -DataName 'x.txt.7z' `
                -Compressed 'Yes' -Corrupt
        $target = Join-Path $TestDrive 'tc098-host-out'
        { & (Join-Path $s.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null } |
            Should -Throw -ExpectedMessage '*1 content-missing, 0 host*'
        (Get-Content -LiteralPath (Join-Path $target 'RECONSTRUCT.log') -Raw) |
            Should -Match 'could not be expanded'
    }

    It 'still reports genuinely absent content as the CONTENT class (SR-040, SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-content') -DataName 'x.txt' -Compressed 'No'
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'x.txt') -Force
        $target = Join-Path $TestDrive 'tc098-content-out'
        { & (Join-Path $s.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null } |
            Should -Throw -ExpectedMessage '*1 content-missing, 0 host*'
    }
}

Describe 'Storage-form verification reports without mutating (SR-049)' {
    # TC-093 — the audit itself: one finding per disagreeing row across the
    # backup root AND every snapshot, nothing touched, outcome on the SR-040 table.
    It 'reports zero findings for a clean backup in mode <Mode> and exits 0 (SR-049)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $root = Join-Path $TestDrive "tc093-$Mode"
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        [IO.File]::WriteAllText((Join-Path $src 'text.txt'), ('COMPRESSIBLE ' * 200))
        # REAL 7z bytes, under a '.7z' name and under a name that hides it: both
        # are already-compressed SOURCE files stored raw, and a clean-store
        # assertion built on a plain string would pass vacuously (Get-StoredFileForm
        # would call it Raw and never reach the exemption at all).
        New-ArchiveShapedFile -Path (Join-Path $src 'already.7z')
        New-ArchiveShapedFile -Path (Join-Path $src 'archive.7z.bak') -Content 'HIDDEN-ARCHIVE '
        # B6: a NESTED infrastructure-named file is user data and must not be
        # mistaken for infrastructure or reported as unreferenced.
        [IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv'), 'nested,not,infrastructure')
        Invoke-FormBackup -Cfg $cfg | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'text.txt'), ('CHANGED ' * 200))
        Invoke-FormBackup -Cfg $cfg | Out-Null      # produces a snapshot

        @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -match '^Snapshot_').Count |
            Should -BeGreaterThan 0
        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty
        Invoke-VerifyExitCode -Cfg $cfg | Should -Be 0
    }

    It 'leaves an already-compressed source under a non-.7z name alone, in mode <Mode> (SR-049, SR-004)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        # WP5 re-review, residual HIGH. The exemption used to be keyed on the
        # RelativePath ending in '.7z', while the observed form comes from the
        # BYTES: an UNTAMPERED store holding a source file that IS a 7z archive
        # under any other name ('archive.7z.bak', a '.pack' file, an installer
        # payload) was reported FlagOverArchive, and -RepairStorage then set
        # Compressed=Yes so the next restore expanded the user's own archive and
        # wrote its inner file under the original name — exit 0, silent
        # corruption of a store that had been correct.
        $root = Join-Path $TestDrive "tc093-hidden-$Mode"
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        New-ArchiveShapedFile -Path (Join-Path $src 'archive.7z.bak')
        [IO.File]::WriteAllText((Join-Path $src 'plain.txt'), ('PLAIN ' * 200))
        Invoke-FormBackup -Cfg $cfg | Out-Null

        # The fixture is only meaningful if the stored bytes really are archive
        # bytes under a row that says Compressed=No.
        $row = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                 Where-Object RelativePath -eq 'archive.7z.bak')[0]
        Get-StoredFileForm -Path (Join-Path $bkp $row.DataPath) | Should -Be 'Archive'
        if (-not $Compress) { $row.Compressed | Should -Be 'No' -Because 'SR-004 declines to re-compress it' }

        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg) |
            Should -BeNullOrEmpty -Because 'an untampered store has no findings, whatever the source file was named'
        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg -Deep -SevenZipPath $script:sevenZip) |
            Should -BeNullOrEmpty -Because '-Deep must not expand a file whose OWN bytes reproduce the row'
        Invoke-VerifyExitCode -Cfg $cfg | Should -Be 0

        # Restore before repair...
        $before = Join-Path $root 'out-before'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $before *>&1 | Out-Null
        (Get-FileHash -LiteralPath (Join-Path $before 'archive.7z.bak') -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $src 'archive.7z.bak') -Algorithm SHA256).Hash

        # ...repair touches nothing at all...
        $fingerprint = Get-TreeFingerprint -Folder $bkp
        $result = Repair-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg -Log { param($m, $l) }
        $result.Repaired | Should -Be 0
        Assert-TreeUnchanged -Before $fingerprint -Folder $bkp

        # ...and the restore is still byte-exact afterwards.
        $after = Join-Path $root 'out-after'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $after *>&1 | Out-Null
        foreach ($rel in 'archive.7z.bak', 'plain.txt') {
            (Get-FileHash -LiteralPath (Join-Path $after $rel) -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $src $rel) -Algorithm SHA256).Hash
        }
    }

    It 'still finds a genuine FlagOverArchive, whose payload and not whose file matches the row (SR-049)' {
        # The other side of the payload-keyed exemption: shape b of the malformed
        # store is a REAL archive parked under a Compressed=No row, and the row's
        # (hash,length) describe the archive's CONTENT, not the archive. Its own
        # bytes therefore do not reproduce the row, so it stays a finding.
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-genuine')
        $findings = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        @($findings | Where-Object { $_.RelativePath -eq 'b.txt' -and $_.Class -eq 'FlagOverArchive' }).Count |
            Should -Be 1

        Repair-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Log { param($m, $l) } | Out-Null
        $row = @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'b.txt')[0]
        $row.Compressed | Should -Be 'Yes' -Because 'the bytes are an archive of the row content, so the flag was wrong'
        [IO.Path]::GetExtension($row.DataPath) | Should -Be '.7z'
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg |
          Where-Object RelativePath -eq 'b.txt') | Should -BeNullOrEmpty
    }

    It 'audits every snapshot as well as the backup root, and covers the root alone under -BackupRootOnly (SR-049)' {
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-scope')
        # Give the store a snapshot carrying a malformed row of its own.
        $snap = Join-Path $s.Chg 'Snapshot_2024_01_01_00_00_01'
        New-Item -ItemType Directory -Path $snap -Force | Out-Null
        $rows = @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'b.txt')
        Copy-Item -LiteralPath (Join-Path $s.Bkp 'b.txt') -Destination (Join-Path $snap 'b.txt') -Force
        Set-ManifestRows -Folder $snap -Rows $rows

        $all = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        @($all | Where-Object FolderName -eq 'Snapshot_2024_01_01_00_00_01') | Should -Not -BeNullOrEmpty
        $rootOnly = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -BackupRootOnly)
        @($rootOnly | Where-Object FolderName -like 'Snapshot_*') | Should -BeNullOrEmpty
    }

    It 'mutates nothing at all, including MANIFEST.csv and its witness (SR-049)' {
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-nomutate')
        $before = Get-TreeFingerprint -Folder $s.Bkp
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -Not -BeNullOrEmpty
        Assert-TreeUnchanged -Before $before -Folder $s.Bkp
    }

    It 'maps its outcome onto the SR-040 table (SR-049, SR-040)' {
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-codes')
        Invoke-VerifyExitCode -Cfg $s.Cfg | Should -Be 1 -Because 'findings are a content statement, not a usage error'

        # Precondition: no manifest to verify at all.
        $empty = Join-Path $TestDrive 'tc093-codes-empty'
        New-Item -ItemType Directory -Path $empty, (Join-Path $empty 'chg') -Force | Out-Null
        $cfg2 = Join-Path $TestDrive 'tc093-codes-empty.xml'
        New-FormConfig -Path $cfg2 -Src $s.Src -Bkp $empty -Chg (Join-Path $empty 'chg')
        Invoke-VerifyExitCode -Cfg $cfg2 | Should -Be 2

        # Precondition: -Deep with no 7-Zip.
        { Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath 'C:\nope\7z.exe' } |
            Should -Throw -ExpectedMessage '*needs 7-Zip*'
    }

    It 'prints the findings document as parseable JSON, the literal [] when clean (SR-049)' {
        # WP5 residual, caught by TC-102's harness in the first real container
        # run: piping ZERO objects into ConvertTo-Json emits nothing at all
        # rather than '[]', so the clean store — the common case — broke the
        # promised findings document while every exit code stayed correct.
        # Pin both shapes at the process boundary, where IF-001 consumes them.
        function Invoke-VerifyOutput {
            param([string]$Cfg)
            return ((& (Get-Process -Id $PID).Path -NoProfile -File $script:entry -ConfigPath $Cfg `
                -Action Verify -NoMail -NonInteractive -ExitCode *>&1) | Out-String)
        }

        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-json')
        $lines = (Invoke-VerifyOutput -Cfg $s.Cfg) -split "`r?`n"
        $start = [array]::IndexOf($lines, '[')
        $end   = [array]::IndexOf($lines, ']')
        $start | Should -BeGreaterThan -1 -Because 'the findings document opens the stream section'
        $end | Should -BeGreaterThan $start
        $doc = @(($lines[$start..$end] -join "`n") | ConvertFrom-Json)
        $doc.Count | Should -BeGreaterThan 0
        $doc[0].PSObject.Properties.Name | Should -Contain 'Class'

        $root = Join-Path $TestDrive 'tc093-json-clean'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'plain.txt'), ('PLAIN ' * 40))
        Invoke-FormBackup -Cfg $cfg | Out-Null
        (Invoke-VerifyOutput -Cfg $cfg) -split "`r?`n" | Should -Contain '[]'
    }

    It 'creates nothing and does not require SourcePath (SR-049, SR-014)' {
        # WP5 review, finding m2. Verification mutates nothing -- which has to
        # include the ROOTS: routing it through the backup-run path resolver
        # created the backup and change directories before deciding there was
        # nothing to verify, and refused outright when the source was offline.
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-readonly')

        # (a) The source is gone: a verify is about the STORE and must still run.
        Remove-Item -LiteralPath $s.Src -Recurse -Force
        Invoke-VerifyExitCode -Cfg $s.Cfg | Should -Be 1 -Because 'the store still has findings'
        Test-Path -LiteralPath $s.Src | Should -BeFalse -Because 'verification creates no directory'

        # (b) A backup root that is not there is a precondition failure (2), and
        # no root is conjured for the next run to trip over.
        $root = Join-Path $TestDrive 'tc093-readonly-missing'
        $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $cfg = Join-Path $root 'c.xml'
        New-FormConfig -Path $cfg -Src $root -Bkp $bkp -Chg $chg
        Invoke-VerifyExitCode -Cfg $cfg | Should -Be 2
        Test-Path -LiteralPath $bkp | Should -BeFalse
        Test-Path -LiteralPath $chg | Should -BeFalse
    }

    It 'reports a payload that does not reproduce the row under -Deep (SR-049)' {
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc093-deep')
        # c.txt is a NameLies row; repair it first so -Deep reaches the payload
        # check for it, then corrupt the bytes in place.
        Repair-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Log { param($m, $l) } | Out-Null
        $row = @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'c.txt')[0]
        [IO.File]::WriteAllText((Join-Path $s.Bkp $row.DataPath), 'DIFFERENT BYTES ENTIRELY')
        $deep = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $script:sevenZip)
        @($deep | Where-Object { $_.RelativePath -eq 'c.txt' -and $_.Class -eq 'PayloadMismatch' }) |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Storage-form repair makes the index agree with the bytes (SR-049)' {
    # TC-094.
    BeforeAll {
        $script:logSink = { param($m, $l) }
    }

    It 'repairs every unambiguous finding and re-verifies clean, in mode <Mode> (SR-049)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $s = New-MalformedStore -Root (Join-Path $TestDrive "tc094-$Mode") -Compress $Compress
        $logical = @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv'))
        $payloads = @{}
        foreach ($row in $logical) {
            $full = Join-Path $s.Bkp $row.DataPath
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                $payloads[$row.RelativePath] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
            }
        }

        $result = Repair-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Log $logSink
        $result.Repaired | Should -Be 3 -Because 'three of the four shapes are repairable from the bytes in the row own folder'

        # The remaining finding is the dangling DataPath, which is reported only.
        $after = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        @($after | Where-Object Class -in 'FlagOverRaw', 'FlagOverArchive', 'NameLies') | Should -BeNullOrEmpty
        @($after | Where-Object Class -eq 'DanglingDataPath').Count | Should -Be 1

        # The six LOGICAL columns are byte-identical...
        $now = @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv'))
        foreach ($row in $logical) {
            $match = $now | Where-Object RelativePath -eq $row.RelativePath
            foreach ($col in 'RelativePath', 'Length', 'LastWriteTimeStr', 'xxH2Hash', 'Duplicate', 'MediaMBPerSec') {
                $match.$col | Should -Be $row.$col
            }
        }
        # ...and no content was ever re-packed: every data file payload hash is
        # what it was, only its name and its Compressed column moved.
        foreach ($row in $now) {
            $full = Join-Path $s.Bkp $row.DataPath
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash | Should -Be $payloads[$row.RelativePath]
            }
        }
        # Every rewritten folder witness is re-stamped by Write-Manifest.
        (Test-ManifestWitness -FolderPath $s.Bkp).Status | Should -Be 'Verified'
    }

    It 'heals BOTH rows of a deduplicated pair that share one data file (SR-049, SR-003)' {
        # WP5 review finding H1. Findings are per ROW, the repair renames a
        # PHYSICAL file: repairing row-by-row renamed it for the first row and
        # then saw 'Missing' for the second, leaving a dangling reference and an
        # unrestorable row. Two identical-content rows sharing one DataPath, bent
        # into the FlagOverRaw shape, must both come out repaired.
        $root = Join-Path $TestDrive 'tc094-shared'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        $payload = 'DEDUPED-CONTENT ' * 300
        [IO.File]::WriteAllText((Join-Path $src 'one.txt'), $payload)
        Invoke-FormBackup -Cfg $cfg | Out-Null
        # The second file is added in a LATER run: that is when
        # Invoke-BackupFileGroup takes its reuse branch and points the new row at
        # the EXISTING row's DataPath (SR-003).
        [IO.File]::WriteAllText((Join-Path $src 'two.txt'), $payload)
        Invoke-FormBackup -Cfg $cfg | Out-Null

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        $shared = @($rows | Where-Object { $_.RelativePath -in 'one.txt', 'two.txt' })
        $shared.Count | Should -Be 2
        @($shared.DataPath | Select-Object -Unique).Count | Should -Be 1 -Because 'dedup points both rows at one file'

        # FlagOverRaw over the SHARED file: RAW bytes, both rows claiming Yes and
        # naming a '.7z'. Repair must rename once and update both rows.
        $oldName = $shared[0].DataPath
        $newName = "$oldName.7z"
        Move-Item -LiteralPath (Join-Path $bkp $oldName) -Destination (Join-Path $bkp $newName) -Force
        foreach ($row in $shared) { $row.DataPath = $newName; $row.Compressed = 'Yes' }
        Set-ManifestRows -Folder $bkp -Rows $rows

        $findings = @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg)
        @($findings | Where-Object Class -eq 'FlagOverRaw').Count | Should -Be 2

        $result = Repair-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg -Log $logSink
        $result.Repaired | Should -Be 2 -Because 'the shared file is renamed once and BOTH rows adopt it'

        $after = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        foreach ($rel in 'one.txt', 'two.txt') {
            $row = $after | Where-Object RelativePath -eq $rel
            $row.Compressed | Should -Be 'No'
            Test-Path -LiteralPath (Join-Path $bkp $row.DataPath) -PathType Leaf |
                Should -BeTrue -Because "row '$rel' must not be left dangling"
        }
        @($after | Where-Object { $_.RelativePath -in 'one.txt', 'two.txt' } |
          ForEach-Object DataPath | Select-Object -Unique).Count |
            Should -Be 1 -Because 'one physical copy still serves both rows'

        # ...the store re-verifies clean and restores byte-exact.
        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty
        $target = Join-Path $root 'out'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        foreach ($rel in 'one.txt', 'two.txt') {
            (Get-FileHash -LiteralPath (Join-Path $target $rel) -Algorithm SHA256).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $src $rel) -Algorithm SHA256).Hash
        }
    }

    It 'reports blank-row form disagreements without repairing them (SR-049)' {
        $t = New-FormDivergedTimeline -Root (Join-Path $TestDrive 'tc094-blank') -StartCompressed $false
        $findings = @(Test-BackupStorageForm -BackupRoot $t.Bkp -ChangeRoot $t.Chg)
        $blank = @($findings | Where-Object Class -eq 'BlankRowFormDisagreement')
        $blank | Should -Not -BeNullOrEmpty
        $blank[0].Repairable | Should -BeFalse
        $blank[0].KitRevision | Should -BeGreaterOrEqual 2 -Because 'a finding names the kit that snapshot carries'

        $before = Get-TreeFingerprint -Folder $t.Chg
        $result = Repair-BackupStorageForm -BackupRoot $t.Bkp -ChangeRoot $t.Chg -Log $logSink
        @($result.Skipped | Where-Object Class -eq 'BlankRowFormDisagreement') | Should -Not -BeNullOrEmpty
        Assert-TreeUnchanged -Before $before -Folder $t.Chg
    }

    It 'leaves a backup run after a repair idempotent (SR-024, SR-049)' {
        $s = New-MalformedStore -Root (Join-Path $TestDrive 'tc094-idempotent')
        Repair-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Log $logSink | Out-Null
        # run1 is by design NOT idempotent with run0: repair leaves the dangling
        # row for the engine to heal by re-copying it from source. SR-024 is the
        # run2 = run3 property (plan section 7).
        $rowText = {
            # Row CONTENT, ordered by RelativePath. Manifest row ORDER is not a
            # documented contract (G7 owns determinism); SR-024 is about the rows.
            @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Sort-Object RelativePath |
              ForEach-Object { ($_.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '|' }) -join "`n"
        }
        Invoke-FormBackup -Cfg $s.Cfg | Out-Null
        Invoke-FormBackup -Cfg $s.Cfg | Out-Null
        $second = & $rowText
        Invoke-FormBackup -Cfg $s.Cfg | Out-Null
        & $rowText | Should -Be $second

        # ...and the repaired store carries no storage-form finding at all.
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg) | Should -BeNullOrEmpty
    }

    It 'is unreachable from a normal backup run, and never writes a manifest itself (SR-049)' {
        # Source guard. Invoke-BackupSet's transitive call graph must not contain
        # any verification/repair symbol, and the WP5 code must persist ONLY
        # through Write-Manifest (never Export-Csv, never a direct witness stamp).
        $enginePath = Join-Path $repo 'Modules\FileBackup.Engine.psm1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($enginePath, [ref]$null, [ref]$null)
        $functions = @{}
        foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $functions[$fn.Name] = $fn
        }
        $reached = New-Object System.Collections.Generic.HashSet[string]
        $walk = {
            param([string]$Name)
            if (-not $functions.ContainsKey($Name)) { return }
            if (-not $reached.Add($Name)) { return }
            foreach ($call in $functions[$Name].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $called = $call.GetCommandName()
                if ($called) { & $walk $called }
            }
        }
        & $walk 'Invoke-BackupSet'
        foreach ($forbidden in 'Test-BackupStorageForm', 'Repair-BackupStorageForm', 'Get-StorageFormFinding',
                               'Get-StoredFileForm', 'Update-BackupSnapshotKit') {
            $reached.Contains($forbidden) | Should -BeFalse -Because "no backup run may invoke $forbidden"
        }

        # Matched on the AST, not on the source text: the functions' own comments
        # name these commands in order to say they are never used.
        foreach ($name in 'Test-BackupStorageForm', 'Repair-BackupStorageForm', 'Get-StorageFormFinding', 'Update-BackupSnapshotKit') {
            $invoked = @($functions[$name].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                         ForEach-Object { $_.GetCommandName() })
            $invoked | Should -Not -Contain 'Export-Csv'
            $invoked | Should -Not -Contain 'Write-ManifestWitness'
        }
    }
}

Describe 'Verify does not re-hash raw-stored archives (SR-049, SR-081)' {
    # TC-229's Part-A arms, on TC-093's harness. WP17 Part A puts '.z7' on the
    # already-compressed list, which turns 43% of the production library into
    # rows that say Compressed=No over bytes carrying 7-Zip magic - the exact
    # shape Get-StorageFormFinding's own comment used to call "rare" before
    # taking a confirming hash. Re-hashing that shape costs 880 GB per Verify
    # pass, so the non-Deep scan now exempts an object stored raw UNDER ITS OWN
    # EXTENSION at ITS OWN LENGTH without hashing at all, and -Deep keeps the
    # hash. These arms pin both directions.
    #
    # TC-229 full arm (probe-mixed store + both restorers byte-exact): row 7.
    BeforeAll {
        function New-SevenZipMagicFile {
            <#
            .SYNOPSIS
                A file whose first six bytes are the 7-Zip signature over random
                (incompressible) padding - what a genuine '.z7' looks like to
                Get-StoredFileForm, without needing 7-Zip to make one.
            #>
            param([string]$Path, [int]$Size = 8192, [int]$Seed = 20260901)
            $bytes = New-Object byte[] $Size
            [Random]::new($Seed).NextBytes($bytes)
            $magic = [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C)
            [Array]::Copy($magic, 0, $bytes, 0, $magic.Length)
            [IO.File]::WriteAllBytes($Path, $bytes)
        }

        function New-RawArchiveStore {
            <#
            .SYNOPSIS
                A one-file backup of 'library.z7' with CompressEnabled ON: after
                Part A the object is stored RAW, named '<hash>_<len>.z7', with
                Compressed=No - the hub's shape, produced by a real run.
            #>
            param([string]$Root)
            $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
            $cfg = Join-Path $Root 'c.xml'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true
            New-SevenZipMagicFile -Path (Join-Path $src 'library.z7')
            Invoke-FormBackup -Cfg $cfg | Out-Null

            $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
            $row = @($rows | Where-Object RelativePath -eq 'library.z7')[0]
            # The fixture only means anything if it really is that shape.
            $row                                   | Should -Not -BeNullOrEmpty
            $row.Compressed                        | Should -Be 'No'
            [IO.Path]::GetExtension($row.DataPath) | Should -Be '.z7'
            Get-StoredFileForm -Path (Join-Path $bkp $row.DataPath) | Should -Be 'Archive'
            return [pscustomobject]@{ Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; Rows = $rows; Row = $row }
        }

        # The hasher is STUBBED to a fixed answer rather than to real hashes:
        # these arms measure WHETHER the confirming hash is taken, not what it
        # says (a mock body cannot close over the test's variables under
        # -ModuleName, and a global would trip PSAvoidGlobalVars). Where an arm
        # needs the hash to AGREE, the row is stamped with the stub's answer.
        $script:stubHash = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    }

    It 'exempts a raw-stored .z7 without hashing it, and hashes it under -Deep (TC-229)' {
        $s = New-RawArchiveStore -Root (Join-Path $TestDrive 'tc229-exempt')

        # Non-Deep: the cheap path answers, so the hasher is never reached. The
        # stub's answer is not this row's hash, so a scan that DID hash would
        # also raise a finding - the two assertions fail together, not silently.
        Mock -ModuleName FileBackup.Engine Get-FileXxHash { 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }
        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg) |
            Should -BeNullOrEmpty -Because 'raw storage of an already-compressed source is correct'
        Should -Invoke Get-FileXxHash -ModuleName FileBackup.Engine -Times 0 -Exactly `
            -Because 'Part A would otherwise re-hash 880 GB of .z7 on every Verify pass'

        # -Deep still proves payload identity, so the hash IS taken. The row is
        # stamped with the stubbed hasher's answer so that proof succeeds.
        $rows = @($s.Rows | ForEach-Object { $_.PSObject.Copy() })
        @($rows | Where-Object RelativePath -eq 'library.z7')[0].xxH2Hash = $script:stubHash
        Set-ManifestRows -Folder $s.Bkp -Rows $rows

        @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg -Deep -SevenZipPath $script:sevenZip) |
            Should -BeNullOrEmpty
        Should -Invoke Get-FileXxHash -ModuleName FileBackup.Engine -Times 1 `
            -Because '-Deep keeps the confirming hash'
    }

    It 'does not exempt a length that disagrees with the row, and still hashes a name that does (TC-229)' {
        # Negative arm 1 - LENGTH mismatch: the cheap path must not fire, and the
        # confirming hash short-circuits on the same length, so the row is a
        # genuine FlagOverArchive rather than a silent pass.
        # BOTH stores are built BEFORE any Mock: New-RawArchiveStore drives a real
        # run through FileBackup.ps1, which re-imports both modules with -Force
        # and would discard the mock (plan section 5).
        $s = New-RawArchiveStore -Root (Join-Path $TestDrive 'tc229-badlen')
        $t = New-RawArchiveStore -Root (Join-Path $TestDrive 'tc229-badext')

        $bent = @($s.Rows | ForEach-Object { $_.PSObject.Copy() })
        @($bent | Where-Object RelativePath -eq 'library.z7')[0].Length = [string]([long]$s.Row.Length + 7)
        Set-ManifestRows -Folder $s.Bkp -Rows $bent

        Mock -ModuleName FileBackup.Engine Get-FileXxHash { 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }
        $findings = @(Test-BackupStorageForm -BackupRoot $s.Bkp -ChangeRoot $s.Chg)
        @($findings | Where-Object { $_.RelativePath -eq 'library.z7' -and $_.Class -eq 'FlagOverArchive' }).Count |
            Should -Be 1 -Because 'an object that is not its row''s size is not raw storage of that row'

        # Negative arm 2 - EXTENSION mismatch: the object is renamed to a '.7z'
        # name its RelativePath does not carry, so the cheap path declines and
        # the payload-keyed confirming hash decides (and, the row being stamped
        # with the stub's answer, proves the object correct).
        $renamed = [IO.Path]::GetFileNameWithoutExtension($t.Row.DataPath) + '.7z'
        Move-Item -LiteralPath (Join-Path $t.Bkp $t.Row.DataPath) -Destination (Join-Path $t.Bkp $renamed) -Force
        $rows = @($t.Rows | ForEach-Object { $_.PSObject.Copy() })
        $bentRow = @($rows | Where-Object RelativePath -eq 'library.z7')[0]
        $bentRow.DataPath = $renamed
        $bentRow.xxH2Hash = $script:stubHash
        Set-ManifestRows -Folder $t.Bkp -Rows $rows

        @(Test-BackupStorageForm -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty
        Should -Invoke Get-FileXxHash -ModuleName FileBackup.Engine -Times 1 `
            -Because 'only an object under its OWN extension takes the cheap path'
    }
}

Describe 'A .z7 source is stored raw and 7-Zip is never invoked (SR-004, TC-231)' {
    # TC-231's Part-A arm - the hub's actual fix path, and the nine days Part A
    # recovers. Driven at Invoke-BackupFileGroup rather than through the entry
    # point because FileBackup.ps1 re-imports both modules with -Force, which
    # discards the module mock the call counter needs (plan section 5).
    #
    # TC-231's rule-0 arm (CompressEnabled=false x every probe mode): row 5.
    It 'stores <Name> as <Ext> with Compressed=<Compressed> and calls the compressor <Calls> time(s) (TC-231)' -ForEach @(
        @{ Name = 'library.z7'; Compressed = 'No';  Ext = '.z7'; Calls = 0 }
        # The control: without it a "zero calls" assertion could pass simply
        # because the mock never intercepted anything.
        @{ Name = 'notes.txt';  Compressed = 'Yes'; Ext = '.7z'; Calls = 1 }
    ) {
        $root = Join-Path $TestDrive ('tc231-' + ($Name -replace '\W', '-'))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $src, $bkp -Force | Out-Null
        $file = Join-Path $src $Name
        if ($Ext -eq '.z7') {
            $bytes = New-Object byte[] 8192
            [Random]::new(20260901).NextBytes($bytes)
            [Array]::Copy([byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C), 0, $bytes, 0, 6)
            [IO.File]::WriteAllBytes($file, $bytes)
        } else {
            [IO.File]::WriteAllText($file, ('COMPRESSIBLE ' * 200))
        }
        $hash = Get-FileXxHash -FilePath $file
        $len  = (Get-Item -LiteralPath $file).Length
        $group = @([pscustomobject]@{
            RelativePath = $Name; Length = $len; xxH2Hash = $hash
            LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
        })

        Mock -ModuleName FileBackup.Engine Compress-FileWithSevenZip { }
        $map = @{}; $changed = 0; $ok = $true
        Invoke-BackupFileGroup -Group $group -SrcPath $src -BkpPath $bkp `
            -CompressEnabled $true -SevenZipPath $script:sevenZip `
            -BackupDb @() -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) `
            -Log { param($m, $l = 'INFO') } -OverallSuccess ([ref]$ok)

        $ok | Should -BeTrue
        $map[$Name].Compressed | Should -Be $Compressed
        [IO.Path]::GetExtension($map[$Name].DataPath) | Should -Be $Ext
        Should -Invoke Compress-FileWithSevenZip -ModuleName FileBackup.Engine -Times $Calls -Exactly

        if ($Calls -eq 0) {
            # Raw really means raw: the object is the source's own bytes, under
            # its own extension, and nothing in the store is named '.7z'.
            @(Get-ChildItem -LiteralPath $bkp -Filter '*.7z') | Should -BeNullOrEmpty
            Get-FileXxHash -FilePath (Join-Path $bkp $map[$Name].DataPath) | Should -Be $hash
        }
    }
}

Describe 'The already-compressed extension list is one list (SR-004)' {
    # TC-096 — amends TC-002 rather than replacing it: TC-002 keeps the
    # extension-not-path property, this pins the merged membership and the
    # single definition site.
    It 'declines to compress <Ext> (SR-004)' -ForEach @(
        # the original seventeen...
        @{ Ext = '.zip' }, @{ Ext = '.7z' },  @{ Ext = '.rar' }
        @{ Ext = '.gz' },  @{ Ext = '.bz2' }, @{ Ext = '.xz' }
        @{ Ext = '.mp4' }, @{ Ext = '.mkv' }, @{ Ext = '.mov' }, @{ Ext = '.avi' }
        @{ Ext = '.mp3' }, @{ Ext = '.aac' }, @{ Ext = '.flac' }
        @{ Ext = '.jpg' }, @{ Ext = '.jpeg' }, @{ Ext = '.png' }, @{ Ext = '.webp' }
        # ...plus the eight merged in by WP5...
        @{ Ext = '.jar' }, @{ Ext = '.tgz' }, @{ Ext = '.zst' }, @{ Ext = '.gif' }
        @{ Ext = '.webm' }, @{ Ext = '.ogg' }, @{ Ext = '.sav' }, @{ Ext = '.pack' }
        # ...plus the twelve WP17 Part A appended (TC-222 pins the same set with
        # mixed casing and the deliberate NON-additions).
        @{ Ext = '.z7' },   @{ Ext = '.esd' }
        @{ Ext = '.mpg' },  @{ Ext = '.mpeg' }, @{ Ext = '.m2ts' }
        @{ Ext = '.m4v' },  @{ Ext = '.wmv' },  @{ Ext = '.flv' }
        @{ Ext = '.heic' }, @{ Ext = '.heif' }
        @{ Ext = '.opus' }, @{ Ext = '.m4a' }
    ) {
        Test-ShouldCompress -FileName "file$Ext"            -CompressEnabled $true | Should -BeFalse
        Test-ShouldCompress -FileName "file$($Ext.ToUpper())" -CompressEnabled $true | Should -BeFalse
        # The EXTENSION decides, never the path (TC-002's property, kept).
        Test-ShouldCompress -FileName "C:\a$Ext\b\file.txt" -CompressEnabled $true | Should -BeTrue
    }

    It 'the LIST says compress for .docx .txt .xlsx .csv .log .bin (SR-004)' {
        # Re-scoped 2026-09-01 (WP17, Owner ruling Q7). This arm used to claim
        # these extensions compress BECAUSE SN-003 SAYS SO. SN-003's acceptance
        # line is an EXAMPLE of the need ("optionally compress stored data to
        # save more space"), not a ruling on those formats, so all this case can
        # honestly claim is what Test-ShouldCompress - THE LIST - answers. What
        # the COMPOSED decision does with them once the SR-081 probe exists is
        # TC-224's: above the floor, a .docx over incompressible bytes is stored
        # raw.
        foreach ($ext in '.docx', '.txt', '.xlsx', '.csv', '.log', '.bin') {
            Test-ShouldCompress -FileName "file$ext" -CompressEnabled $true |
                Should -BeTrue -Because "$ext is not on the already-compressed list"
        }
    }

    It 'declines every extension WP17 Part A added, in any casing, and still compresses .iso (TC-222)' {
        # TC-222. .z7 is the finding itself: file(1) reads '7-zip archive data',
        # and the production library holds 649 of them - 880 GB, 43% - that the
        # first pass was re-packing at -mx=9 for ~5%.
        foreach ($ext in '.z7', '.esd', '.mpg', '.mpeg', '.m2ts', '.m4v', '.wmv',
                         '.flv', '.heic', '.heif', '.opus', '.m4a') {
            foreach ($cased in $ext, $ext.ToUpperInvariant(),
                     ($ext.Substring(0, 2) + $ext.Substring(2).ToUpperInvariant())) {
                Test-ShouldCompress -FileName "file$cased" -CompressEnabled $true |
                    Should -BeFalse -Because "$cased is already-compressed content, whatever its casing"
            }
        }
        # The deliberate NON-additions, pinned so nobody 'completes' the list:
        # .iso is a filesystem CONTAINER, not compressed content, and adding it
        # would be the false-'already compressed' error the defect review names.
        # .mca is unconfirmed; .bin/.dng/.pdf are plausible but unproven - and
        # they are exactly what the SR-081 probe is for.
        foreach ($ext in '.iso', '.mca', '.bin', '.dng', '.pdf') {
            Test-ShouldCompress -FileName "file$ext" -CompressEnabled $true |
                Should -BeTrue -Because "$ext was deliberately NOT added by WP17 Part A"
        }
        # And CompressEnabled=false still dominates the list for both classes.
        Test-ShouldCompress -FileName 'file.z7'  -CompressEnabled $false | Should -BeFalse
        Test-ShouldCompress -FileName 'file.iso' -CompressEnabled $false | Should -BeFalse
    }

    It 'is defined in exactly one place, and README quotes that definition (SR-004)' {
        $commonPath = Join-Path $repo 'Modules\FileBackup.Common.psm1'
        $enginePath = Join-Path $repo 'Modules\FileBackup.Engine.psm1'
        # One definition site.
        @(Select-String -LiteralPath $commonPath -Pattern '^\$script:NonCompressibleExtensions\s*=').Count | Should -Be 1
        @(Select-String -LiteralPath $enginePath -Pattern 'NonCompressibleExtensions').Count | Should -Be 0

        # ...and the README table is the same set, so the documentation cannot drift.
        $live = @((Get-FileBackupDefaults).NonCompressibleExtensions) | Sort-Object
        $readme = Get-Content -LiteralPath (Join-Path $repo 'README.md') -Raw
        $block = [regex]::Match($readme, '(?s)### Already-compressed extensions.*?```\r?\n(.*?)```').Groups[1].Value
        $documented = @([regex]::Matches($block, '\.[a-z0-9]+') | ForEach-Object { $_.Value }) | Sort-Object
        ($documented -join ' ') | Should -Be ($live -join ' ')
    }
}

Describe 'Backup capacity preflight refuses before mutating (SR-052)' {
    # TC-100. The shortfall is induced by STUBBING the free-space probe, so the
    # test needs no full volume and stays deterministic. The arithmetic itself
    # (Get-BackupCapacityDemand) is asserted directly, because that is the part
    # a wrong estimate would silently break. The migration component is gone
    # with the migration itself (SR-061).
    BeforeAll {
        function New-CapacityStore {
            param([string]$Root, [bool]$Compress = $false)
            $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
            $cfg = Join-Path $Root 'c.xml'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
            [IO.File]::WriteAllText((Join-Path $src 'seed.txt'), ('SEED ' * 100))
            Invoke-FormBackup -Cfg $cfg | Out-Null
            return [pscustomobject]@{ Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg }
        }
    }

    It 'refuses the set and writes nothing when the estimate exceeds free space (SR-052, SR-013)' {
        $s = New-CapacityStore -Root (Join-Path $TestDrive 'tc100-refuse')
        [IO.File]::WriteAllText((Join-Path $s.Src 'big.txt'), ('X' * 200000))

        $beforeData  = @(Get-DataFile -Root $s.Bkp | ForEach-Object { "$($_.Name)|$($_.Length)" }) | Sort-Object
        $beforeState = Get-Content -LiteralPath (Join-Path $s.Bkp 'FileBackupState.json') -Raw
        $beforeChg   = @(Get-ChildItem -LiteralPath $s.Chg -Recurse -File | ForEach-Object { $_.FullName }) | Sort-Object

        $failed = $null
        try {
            InModuleScope FileBackup.Engine -Parameters @{ Set = $s } {
                param($Set)
                # The volume reports one byte free; everything else is real.
                Mock Get-FreeSpaceBytes { return 1L }
                $cfgSet = [pscustomobject]@{ Name = 'S'; SourcePath = $Set.Src; BackupPath = $Set.Bkp
                    ChangePath = $Set.Chg; HashRecalcFreq = 'A'; CompressEnabled = $false }
                $ok = $true
                Invoke-BackupSet -Set $cfgSet -Deps @{ '7z' = $null; 'ffprobe' = $null; 'xxhash' = $true } `
                    -OverallSuccess ([ref]$ok) -LogPaths (New-Object System.Collections.Generic.List[string])
            }
        } catch {
            $failed = $_.Exception.Message
        }

        $failed | Should -Not -BeNullOrEmpty
        $failed | Should -Match 'Not enough free space on the backup volume'
        $failed | Should -Match 'Required: \d+ byte\(s\), Free: 1 byte\(s\)'

        # Nothing was written: no data file changed or appeared, the run state is
        # untouched, and no staging folder was orphaned for the SR-017 guard.
        (@(Get-DataFile -Root $s.Bkp | ForEach-Object { "$($_.Name)|$($_.Length)" }) | Sort-Object) -join ',' |
            Should -Be ($beforeData -join ',')
        Get-Content -LiteralPath (Join-Path $s.Bkp 'FileBackupState.json') -Raw | Should -Be $beforeState
        (@(Get-ChildItem -LiteralPath $s.Chg -Recurse -File | ForEach-Object { $_.FullName }) | Sort-Object) -join ',' |
            Should -Be ($beforeChg -join ',')
        Test-Path -LiteralPath (Join-Path $s.Chg 'Temp') | Should -BeFalse
    }

    It 'fails the SET (status 1), not the whole invocation as a usage error (SR-052, SR-014)' {
        # A per-set refusal is status 1: other configured sets may still have run.
        # OBSERVED at the process boundary (WP5 review, finding m1): asserting on
        # the in-process throw alone never proved the entry point's status.
        #
        # The shortfall is genuine and needs no stub. SR-061 deleted the step-5.5
        # migration component this used to inflate, so it is induced on the
        # component that remains: an EVICTION. A removed row's bytes are moved to
        # staging, sized from the BACKUP row's Length - but ONLY when the change
        # root is on a different volume, because a same-volume move is a rename
        # and correctly costs nothing. So the change root gets its own drive via
        # subst, the way the integration harness makes volumes. That also makes
        # this the only unit-level coverage of the SameVolume=$false arm.
        $free = @('X', 'Y', 'W', 'V', 'U') |
                Where-Object { $_ -notin (Get-PSDrive -PSProvider FileSystem).Name } |
                Select-Object -First 1
        if (-not $free) { Set-ItResult -Skipped -Because 'no free drive letter for the second volume'; return }

        $root = Join-Path $TestDrive 'tc100-status'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chgHost = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src, $chgHost -Force | Out-Null
        $substOut = & cmd.exe /c "subst ${free}: `"$chgHost`"" 2>&1
        if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because "subst failed: $substOut"; return }
        try {
            $chg = "${free}:\"
            $cfg = Join-Path $root 'c.xml'
            New-FormConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
            [IO.File]::WriteAllText((Join-Path $src 'seed.txt'), ('SEED ' * 100))
            # A second file keeps the source non-empty when seed.txt goes, so the
            # refusal under test is the capacity one and not the delete-all guard.
            [IO.File]::WriteAllText((Join-Path $src 'keep.txt'), ('KEEP ' * 50))
            Invoke-FormBackup -Cfg $cfg | Out-Null

            $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
            foreach ($row in $rows) {
                if ($row.RelativePath -eq 'seed.txt') { $row.Length = [string]([long]::MaxValue / 4) }
            }
            Set-ManifestRows -Folder $bkp -Rows $rows
            Remove-Item -LiteralPath (Join-Path $src 'seed.txt') -Force

            Invoke-FormBackupExitCode -Cfg $cfg | Should -Be 1
            (Invoke-FormBackup -Cfg $cfg) | Should -Match 'Not enough free space'
        } finally {
            & cmd.exe /c "subst ${free}: /D" 2>&1 | Out-Null
        }

        # ...and the same refusal is a terminating error in process.
        $demand = Get-BackupCapacityDemand -NewOrChanged @([pscustomobject]@{ RelativePath = 'big.txt'
                        xxH2Hash = 'DEADBEEF'; Length = [long]::MaxValue / 4 }) `
                    -RemovedFromSource @() -BackupDb @() -SameVolume $true
        { Assert-BackupCapacity -BackupPath $TestDrive -ChangePath $TestDrive -BackupBytes $demand.BackupBytes -Log { param($m, $l) } } |
            Should -Throw -ExpectedMessage '*Not enough free space*'
    }

    It 'sums both demands when the backup and change roots share one volume (SR-052)' {
        # WP5 review, finding M2. Two demands that each fit but together do not
        # must refuse when they compete for the same bytes — checking them
        # separately passed the pair.
        $bkp = Join-Path $TestDrive 'tc100-same\bkp'
        $chg = Join-Path $TestDrive 'tc100-same\chg'
        New-Item -ItemType Directory -Path $bkp, $chg -Force | Out-Null
        (Get-VolumeIdentity -Path $bkp) | Should -Be (Get-VolumeIdentity -Path $chg)

        $free = Get-FreeSpaceBytes -Path $bkp
        $each = [long]($free * 0.6)          # each demand is 60% of the SAME free space
        { Assert-BackupCapacity -BackupPath $bkp -ChangePath $chg -BackupBytes $each -ChangeBytes $each -Log { param($m, $l) } } |
            Should -Throw -ExpectedMessage '*Not enough free space*'
        # Each alone still fits, so the refusal is the SUM and nothing else.
        { Assert-BackupCapacity -BackupPath $bkp -ChangePath $chg -BackupBytes $each -Log { param($m, $l) } } |
            Should -Not -Throw
    }

    It 'lets a run that fits proceed unchanged (SR-052)' {
        $s = New-CapacityStore -Root (Join-Path $TestDrive 'tc100-fits')
        [IO.File]::WriteAllText((Join-Path $s.Src 'more.txt'), ('MORE ' * 100))
        Invoke-FormBackupExitCode -Cfg $s.Cfg | Should -Be 0
        @(Import-Csv -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'more.txt') |
            Should -Not -BeNullOrEmpty
    }

    It 'counts only NEW deduplicated content on the backup volume (SR-052)' {
        # DataPath populated: a real held row carries one; a BLANK row's key is
        # deliberately NOT held (its bytes are gone and the SR-053 heal will
        # copy them — see the WP7 'budgets heal copies' pin).
        $held = @([pscustomobject]@{ RelativePath = 'a.txt'; DataPath = 'a.txt'; xxH2Hash = 'H1'; Length = 1000L })
        $new  = @(
            [pscustomobject]@{ RelativePath = 'b.txt'; xxH2Hash = 'H1'; Length = 1000L }   # dedup: already held
            [pscustomobject]@{ RelativePath = 'c.txt'; xxH2Hash = 'H2'; Length = 500L }
            [pscustomobject]@{ RelativePath = 'd.txt'; xxH2Hash = 'H2'; Length = 500L }    # dedup: same new key
        )
        $d = Get-BackupCapacityDemand -NewOrChanged $new -RemovedFromSource @() -BackupDb $held -SameVolume $true
        $d.BackupBytes | Should -Be 500
        $d.ChangeBytes | Should -Be 0 -Because 'on one volume, staging is a rename'
    }

    It 'counts staging bytes only when the change root is on another volume (SR-052)' {
        $held = @([pscustomobject]@{ RelativePath = 'a.txt'; DataPath = 'a.txt'; xxH2Hash = 'H1'; Length = 1000L })
        $new  = @([pscustomobject]@{ RelativePath = 'a.txt'; xxH2Hash = 'H9'; Length = 2000L })   # a.txt modified
        (Get-BackupCapacityDemand -NewOrChanged $new -RemovedFromSource @() -BackupDb $held -SameVolume $true).ChangeBytes |
            Should -Be 0
        $cross = Get-BackupCapacityDemand -NewOrChanged $new -RemovedFromSource @() -BackupDb $held -SameVolume $false
        $cross.BackupBytes | Should -Be 2000
        $cross.ChangeBytes | Should -Be 1000 -Because 'the superseded version must be COPIED across the volume boundary'
    }

}

Describe 'Free space is measured the same way on both platforms (SR-052, SR-023)' {
    # TC-101, Windows half. The Linux half (a rooted POSIX path in the container,
    # and the SR-023 restore check firing there for the first time) runs in the
    # Docker CI job.
    It 'returns a plausible non-zero value for a drive-qualified Windows path (SR-052)' {
        $free = Get-FreeSpaceBytes -Path $TestDrive
        $free | Should -Not -BeNullOrEmpty
        $free | Should -BeGreaterThan 0
        $free | Should -BeOfType [long]
    }

    It 'measures a path that does not exist yet, via its nearest existing ancestor (SR-052)' {
        $future = Join-Path $TestDrive 'does\not\exist\yet'
        Get-FreeSpaceBytes -Path $future | Should -BeGreaterThan 0
    }

    It 'never throws for an unresolvable path, it answers $null (SR-052)' {
        $answer = $null
        { $answer = Get-FreeSpaceBytes -Path '\\?\NoSuchVolume{0000}\nope' } | Should -Not -Throw
        $answer | Should -BeNullOrEmpty
    }

    It 'tells two volumes apart and one volume from itself (SR-052)' {
        $a = Get-VolumeIdentity -Path $TestDrive
        $a | Should -Not -BeNullOrEmpty
        Get-VolumeIdentity -Path (Join-Path $TestDrive 'sub\deeper') | Should -Be $a
    }

    It 'answers a MOUNT POINT from the mount table, longest prefix wins (SR-052)' {
        # WP5 review, finding M2. On Unix [DriveInfo]::new($p).Name is the
        # IDENTITY function — it echoes the path handed to it, so '/backup' and
        # '/backup/sub' read as DIFFERENT volumes and every same-volume decision
        # was wrong off Windows. The identity now comes from GetDrives(), which
        # reads the real mount table on Linux; the longest mount point that
        # prefixes the path on a separator boundary is the answer. Windows
        # exercises the same matcher (its mount table is the drive roots), and
        # the Linux confirmation is TC-101's Docker half.
        $identity = Get-VolumeIdentity -Path $TestDrive
        $mounts = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name })
        $mounts | Should -Contain $identity -Because 'the identity is a real mount point, never the path itself'
        $identity | Should -Not -Be ([IO.Path]::GetFullPath($TestDrive)) -Because 'that was the Unix defect'

        # A sibling whose name merely STARTS with the mount point is not in it.
        $deep = Join-Path $TestDrive 'a\b\c\d'
        New-Item -ItemType Directory -Path $deep -Force | Out-Null
        Get-VolumeIdentity -Path $deep | Should -Be $identity
        # The longest match is chosen: no mount point longer than the answer
        # also prefixes the path.
        foreach ($m in $mounts) {
            if ($m.Length -gt $identity.Length -and
                ([IO.Path]::GetFullPath($deep)).StartsWith($m.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, 'OrdinalIgnoreCase')) {
                throw "A longer mount point '$m' also prefixes '$deep' but was not chosen."
            }
        }
    }

    It 'no longer resolves the restore target through Split-Path -Qualifier (SR-023, SR-052)' {
        # The regression pin for the Linux half: the mechanism that could not
        # resolve a rooted POSIX path must be gone from the restore kit.
        $text = Get-Content -LiteralPath (Join-Path $repo 'Reconstruct.ps1') -Raw
        $text | Should -Not -Match '\$drive\s*=\s*Get-PSDrive -Name \(Split-Path'
        $text | Should -Match 'Get-FreeSpaceBytes -Path \$TargetRoot'
    }
}
