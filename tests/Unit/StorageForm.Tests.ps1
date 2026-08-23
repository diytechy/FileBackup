<#
.SYNOPSIS  WP5 storage-form trust: repro + verification/repair coverage
           (SR-049, SR-050, SR-051, SR-052).
.NOTES     TC-091..TC-096, TC-098, TC-100, TC-101 (Windows half).
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
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $false, [bool]$ContentAddressed = $false)
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
            PreserveFolderTree = (-not $ContentAddressed)
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

    function New-MalformedStore {
        <#
        .SYNOPSIS
            A real Mirror backup of four files, then each row bent into one of
            TC-091's four malformed shapes. The bytes are ground truth; only the
            manifest and the data-file NAMES are tampered with.

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

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        foreach ($row in $rows) {
            $current = Join-Path $bkp $row.DataPath
            switch ($row.RelativePath) {
                'a.txt' {
                    Move-Item -LiteralPath $current -Destination (Join-Path $bkp 'a.txt.7z') -Force
                    $row.DataPath = 'a.txt.7z'; $row.Compressed = 'Yes'
                }
                'b.txt' {
                    # Real archive bytes parked under the raw name (shape b).
                    $tmp = Join-Path $Root 'b.7z'
                    Compress-FileWithSevenZip -SevenZipPath $script:sevenZip -SourceFile $current -Destination7z $tmp
                    Copy-Item -LiteralPath $tmp -Destination $current -Force
                    Remove-Item -LiteralPath $tmp -Force
                    $row.Compressed = 'No'
                }
                'c.txt' {
                    Move-Item -LiteralPath $current -Destination (Join-Path $bkp 'c.txt.7z') -Force
                    $row.DataPath = 'c.txt.7z'; $row.Compressed = 'No'
                }
                'd.txt' {
                    Remove-Item -LiteralPath $current -Force
                }
            }
        }
        Set-ManifestRows -Folder $bkp -Rows $rows
        return [pscustomobject]@{ Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg }
    }

    function New-FlipTimeline {
        <#
        .SYNOPSIS
            TC-092's no-tampering repro: a snapshot whose blank-DataPath row
            carries the form the pool no longer holds, produced only by turning
            compression on (or off) between two ordinary runs.

        .DESCRIPTION
            run1 (StartCompressed)      -> a.txt + b.txt stored in that form
            run2 (StartCompressed)      -> b.txt superseded => Snapshot_D1, whose
                                           a.txt row is blanked by Optimize and
                                           keeps run1's Compressed value
            run3 (-not StartCompressed) -> Sync migrates the BACKUP ROOT ONLY, so
                                           the only surviving copy of a.txt's
                                           bytes now has the opposite form
        #>
        param([string]$Root, [bool]$StartCompressed, [bool]$ContentAddressed)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $cfgA = Join-Path $Root 'a.xml'; $cfgB = Join-Path $Root 'b.xml'
        New-FormConfig -Path $cfgA -Src $src -Bkp $bkp -Chg $chg -Compress $StartCompressed        -ContentAddressed $ContentAddressed
        New-FormConfig -Path $cfgB -Src $src -Bkp $bkp -Chg $chg -Compress (-not $StartCompressed) -ContentAddressed $ContentAddressed

        $aPath = Join-Path $src 'a.txt'
        [IO.File]::WriteAllText($aPath, ('THE-ORIGINAL-BYTES ' * 200))
        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'v1')
        Invoke-FormBackup -Cfg $cfgA -At ([datetime]'2024-01-01 00:00:01') | Out-Null

        [IO.File]::WriteAllText((Join-Path $src 'b.txt'), 'v2')
        Invoke-FormBackup -Cfg $cfgA -At ([datetime]'2024-02-02 00:00:02') | Out-Null

        Invoke-FormBackup -Cfg $cfgB -At ([datetime]'2024-03-03 00:00:03') | Out-Null

        $snap = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' })[0]
        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Snapshot = $snap.FullName
            Original = $aPath
        }
    }
}

Describe 'Sync-BackupStorageLayout trusts metadata over bytes (SR-049)' {
    # TC-091 — REPRO-FIRST. The first two cases pin the DEFECT (they pass on the
    # pre-WP5 code and are the evidence that finding C is real); the third is the
    # requirement and is red until SR-049's verification action exists.
    BeforeAll {
        $script:store = New-MalformedStore -Root (Join-Path $TestDrive 'tc091')
    }

    It 'leaves every malformed row byte-identical and still reports the set successful (SR-049)' {
        $before = Get-TreeFingerprint -Folder $store.Bkp
        Invoke-FormBackup -Cfg $store.Cfg | Out-Null
        # The migration decision compares manifest metadata with configuration and
        # never with the bytes, so nothing about these rows looks wrong to it.
        $rows = @(Import-Csv -LiteralPath (Join-Path $store.Bkp 'MANIFEST.csv'))
        ($rows | Where-Object RelativePath -eq 'a.txt').Compressed | Should -Be 'Yes'
        ($rows | Where-Object RelativePath -eq 'b.txt').Compressed | Should -Be 'No'
        ($rows | Where-Object RelativePath -eq 'c.txt').DataPath   | Should -Be 'c.txt.7z'
        # Infrastructure (manifest, witness, run state, kit) is rewritten by every
        # run; the DATA files are what must be byte-identical. Get-DataFile applies
        # exactly the SR-022 root-level-only rule the engine itself uses.
        $after = Get-TreeFingerprint -Folder $store.Bkp
        foreach ($f in @(Get-DataFile -Root $store.Bkp)) {
            $after[$f.FullName] | Should -Be $before[$f.FullName] -Because "data file '$($f.Name)' must be untouched"
        }
    }

    It 'swallows a failed transformation of a Compressed=Yes-over-raw row into a log line (SR-049)' {
        $root = Join-Path $TestDrive 'tc091c'
        $s = New-MalformedStore -Root $root
        # Config now says "do not compress", so the a.txt row (Compressed=Yes over
        # RAW bytes) is selected for transformation; Expand-FileWithSevenZip throws
        # on bytes that are not an archive.
        New-FormConfig -Path $s.Cfg -Src $s.Src -Bkp $s.Bkp -Chg $s.Chg -Compress $false
        $log = Invoke-FormBackup -Cfg $s.Cfg
        $log | Should -Match "Failed to decompress 'a\.txt\.7z'"
        # ...and the set is nevertheless reported as successful (shape c): the
        # ERROR is logged, the row is skipped by `continue`, and the run finishes.
        $log | Should -Match "Backup set 'S' completed"
        $log | Should -Not -Match "Backup set 'S' failed"
    }

    It 'reports one finding per malformed row with its class (SR-049)' -Skip {
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
    It 'restores a snapshot byte-exact after compression is turned <Flip> (mode <Mode>) (SR-050)' -ForEach @(
        @{ Flip = 'on';  StartCompressed = $false; Mode = 'Mirror';        ContentAddressed = $false }
        @{ Flip = 'off'; StartCompressed = $true;  Mode = 'Mirror';        ContentAddressed = $false }
        @{ Flip = 'on';  StartCompressed = $false; Mode = 'HashAddressed'; ContentAddressed = $true  }
        @{ Flip = 'off'; StartCompressed = $true;  Mode = 'HashAddressed'; ContentAddressed = $true  }
    ) {
        $t = New-FlipTimeline -Root (Join-Path $TestDrive "tc092-$Flip-$Mode") `
                -StartCompressed $StartCompressed -ContentAddressed $ContentAddressed
        $target = Join-Path $TestDrive "tc092-$Flip-$Mode-out"
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

    It 'still reports an unexpandable, unmatching .7z candidate as a HOST failure (SR-040, SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-host') -DataName 'x.txt.7z' `
                -Compressed 'Yes' -Corrupt
        $target = Join-Path $TestDrive 'tc098-host-out'
        { & (Join-Path $s.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null } |
            Should -Throw -ExpectedMessage '*0 content-missing, 1 host*'
    }

    It 'still reports genuinely absent content as the CONTENT class (SR-040, SR-050)' {
        $s = New-BlankRowStore -Root (Join-Path $TestDrive 'tc098-content') -DataName 'x.txt' -Compressed 'No'
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'x.txt') -Force
        $target = Join-Path $TestDrive 'tc098-content-out'
        { & (Join-Path $s.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null } |
            Should -Throw -ExpectedMessage '*1 content-missing, 0 host*'
    }
}
