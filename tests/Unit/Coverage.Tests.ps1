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
              [bool]$Compress = $false, [string]$Name = 'S')
        $set = [pscustomobject]@{
            Name = $Name; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
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
        param([string]$Root, [bool]$Compress = $false,
              [bool]$SuffixNamedUserFiles = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        [IO.File]::WriteAllText((Join-Path $src 'keep.txt'),  'KEEP ' * 40)
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'), 'VERSION-ONE ' * 40)
        [IO.File]::WriteAllText((Join-Path $src 'gone.txt'),  'DOOMED ' * 40)
        # B6: a NESTED file named like infrastructure is user data and must
        # travel through prune like any other content.
        [IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv'), 'nested,not,infrastructure' * 5)
        # WP4 review finding H1: a genuine user file whose name ends in the
        # prune mechanism's staging suffix. Mirror stored it at its verbatim
        # path, so a bare-suffix sweep destroyed it in every folder at once
        # (root-level AND nested, because the sweep recursed). The committed
        # sweep must stay name-precise even now that pool objects are
        # hash-named.
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

    function Set-SnapshotBlankRowForm {
        <#
        .SYNOPSIS
            Makes a snapshot's blank-DataPath rows claim a form the pool copy
            does not have, re-stamping the SR-038 witness so the store fails the
            way the test means to rather than exiting 3.
        .NOTES
            Constructed rather than produced by a CompressEnabled flip: SR-061
            deleted the layout migration that used to re-form the backup root
            while snapshots kept their form.
        #>
        param([string]$Folder, [string]$Compressed)
        $rows = @(Import-Csv -LiteralPath (Join-Path $Folder 'MANIFEST.csv'))
        $touched = 0
        foreach ($row in $rows) {
            if ([string]::IsNullOrWhiteSpace($row.DataPath)) { $row.Compressed = $Compressed; $touched++ }
        }
        if ($touched -eq 0) { throw "fixture: no blank-DataPath row in '$Folder'" }
        $rows | Export-Csv -LiteralPath (Join-Path $Folder 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $Folder | Out-Null
    }

    # --- WP9 step 1: the D-1 / D-5 timelines (TC-118, TC-119) ---------------
    . (Join-Path $repo 'tests\Common\PoolAudit.ps1')

    function New-BorrowTimeline {
        <#
        .SYNOPSIS
            The D-1 shape exactly as the HomeHub bench produced it: ONE owner,
            a later cross-run duplicate that borrows the owner's DataPath, then
            an ordinary edit of one of the holders.

        .PARAMETER Copies
            Total holders of the shared content: 1 owner + (Copies - 1)
            borrowers, all of the borrowers arriving in run 2.

        .PARAMETER Edit
            Which holder run 3 edits away from the shared content - the owner
            (the path whose DataPath the others adopted) or the first borrower.

        .NOTES
            The owner must be the ONLY PRIOR copy for the borrow to form at
            all. A second copy in the SAME run as the owner MASKS D-1 - the
            borrower's adopted DataPath may then name the untouched sibling,
            and even when it names the edited file the surviving sibling keeps
            the content alive. That is why the bench drill only saw this once
            cycle 10 introduced a twin of a single-copy file, and it is why the
            D-5 timeline below is kept separate rather than folded in. Copies
            greater than 2 add further run-2 borrowers, which is a different
            axis: they never mask the defect because they adopt the same
            single prior object.
        #>
        param(
            [string]$Root,
            [bool]$Compress = $false,
            [ValidateRange(2, 9)][int]$Copies = 2,
            [ValidateSet('owner', 'borrower')][string]$Edit = 'owner'
        )
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        $one = 'SHARED-CONTENT-ONE ' * 60
        $two = 'OWNER-CONTENT-TWO '  * 60

        $ownerRel = 'a.bin'
        $borrowerRels = @(for ($i = 1; $i -lt $Copies; $i++) {
            if ($i -eq 1) { 'sub\twin.bin' } else { "sub\twin$i.bin" }
        })

        # run1 - the owner is the only holder of this content.
        [IO.File]::WriteAllText((Join-Path $src $ownerRel), $one)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        & $run ([datetime]'2024-01-01 00:00:01')

        # run2 - identical copies arrive LATER, so they are matched against the
        # PRIOR backup and adopt the owner's DataPath verbatim, writing no
        # bytes of their own. That is the borrow D-1 needs.
        foreach ($rel in $borrowerRels) { [IO.File]::WriteAllText((Join-Path $src $rel), $one) }
        & $run ([datetime]'2024-02-02 00:00:02')      # => Snapshot_2024_01_01_00_00_01

        # run3 - an ORDINARY edit of one holder. Under the deleted Mirror layout
        # the destination was that path's own data file, overwriting the bytes
        # the other holders still claimed (D-1); content addressing writes a NEW
        # object instead, and this timeline is what proves they survive.
        $editedRel = if ($Edit -eq 'owner') { $ownerRel } else { $borrowerRels[0] }
        [IO.File]::WriteAllText((Join-Path $src $editedRel), $two)
        & $run ([datetime]'2024-03-03 00:00:03')      # => Snapshot_2024_02_02_00_00_02

        $allRels = @($ownerRel) + $borrowerRels
        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; One = $one; Two = $two
            AllRels = $allRels
            EditedRel = $editedRel
            UnchangedRels = @($allRels | Where-Object { $_ -ne $editedRel })
            SnapAfterRun1 = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
            SnapAfterRun2 = Join-Path $chg 'Snapshot_2024_02_02_00_00_02'
        }
    }

    function New-SameRunDuplicateStore {
        <#
        .SYNOPSIS
            The D-5 shape: two identical files FIRST SEEN IN ONE RUN, where the
            dedup lookup consults only the prior backup and so finds nothing.
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $one = 'SAME-RUN-DUPLICATE ' * 60
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'sub\b.bin'), $one)
        & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime ([datetime]'2024-01-01 00:00:01') *>&1 | Out-Null
        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; One = $one
            Log = Join-Path $chg 'backup.log'
        }
    }

    # --- WP9 step 4: exact-survival timelines (SR-059, LLR-059) --------------

    function New-FrozenClaimTimeline {
        <#
        .SYNOPSIS
            The frozen-claim shape (SR-057 x SR-059): a duplicate pair whose
            second member lives in a directory that later becomes unreadable
            (Deny ACE), then an ordinary edit of the only WALKABLE holder.
            After that run the frozen row is the ONLY live claim on the shared
            object - a claim the source-based survival test cannot see,
            because the frozen file is exactly the one the walk could not
            visit.
        .NOTES
            The fixture owns the Deny ACE lifecycle: applied before run 2 and
            removed in a finally immediately after it (the freeze has already
            happened by then), so no failure path can strand an ACE that
            breaks TestDrive cleanup (review 2026-08-25, nit n2). Callers
            must still prove the ACE actually bit - see the non-vacuity guard
            in the It (review MAJ-1).
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'locked') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        $one = 'FROZEN-SHARED-ONE ' * 60
        $two = 'EDITED-AWAY-TWO '   * 60

        # run1 - the pair shares one object; the walkable file is the owner.
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'locked\pair.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        & $run ([datetime]'2024-01-01 00:00:01')

        # run2 - the directory becomes unenumerable (SR-057: rows under it
        # freeze, the set fails loudly) while the only walkable holder edits
        # away from the shared content.
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $two)
        $denied = Join-Path $src 'locked'
        icacls $denied /deny "${env:USERNAME}:(OI)(CI)(R)" | Out-Null
        try {
            & $run ([datetime]'2024-02-02 00:00:02')  # => Snapshot_2024_01_01_00_00_01
        } finally {
            icacls $denied /remove:d "${env:USERNAME}" | Out-Null
        }

        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; One = $one; Two = $two
            PreEditSnap = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        }
    }

    function New-EvictSupersedeTimeline {
        <#
        .SYNOPSIS
            Work-order risk R4: supersession and eviction share one object in
            ONE run - a duplicate pair where the same run deletes one member
            and edits the other. Exactly one staged copy must land in the
            snapshot, whichever loop reaches the object first.
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        $one = 'EVICT-AND-SUPERSEDE ' * 60
        $two = 'MOVED-ON-CONTENT '    * 60

        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'sub\b.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        & $run ([datetime]'2024-01-01 00:00:01')

        Remove-Item -LiteralPath (Join-Path $src 'sub\b.bin') -Force
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $two)
        & $run ([datetime]'2024-02-02 00:00:02')      # => Snapshot_2024_01_01_00_00_01

        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; One = $one; Two = $two
            Snap = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        }
    }

    function New-MemberRemovedTimeline {
        <#
        .SYNOPSIS
            TC-135: one member of a dedup group is DELETED while the others
            live on - the owner (the borrowed-from path) by default, a
            borrower with -RemoveBorrower. B9's eviction refcount must keep
            the shared object in the pool for the survivors, and the snapshot
            must still restore the removed path's bytes.

        .PARAMETER Copies
            Total holders of the shared content: 1 owner + (Copies - 1)
            borrowers. copies=3 leaves TWO survivors after the removal, so an
            eviction that consulted only "is there one other claim" is not
            enough to pass by accident.
        #>
        param(
            [string]$Root,
            [bool]$Compress = $false,
            [switch]$RemoveBorrower,
            [ValidateRange(2, 9)][int]$Copies = 2
        )
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        $run = { param([datetime]$d) & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $d *>&1 | Out-Null }

        $one = 'MEMBER-REMOVED-SHARED ' * 60

        $ownerRel = 'a.bin'
        $borrowerRels = @(for ($i = 1; $i -lt $Copies; $i++) {
            if ($i -eq 1) { 'sub\twin.bin' } else { "sub\twin$i.bin" }
        })

        # run1 - the owner is the only holder; run2 - the twins borrow the
        # owner's object; run3 - one member is deleted, the others live.
        [IO.File]::WriteAllText((Join-Path $src $ownerRel), $one)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        & $run ([datetime]'2024-01-01 00:00:01')
        foreach ($rel in $borrowerRels) { [IO.File]::WriteAllText((Join-Path $src $rel), $one) }
        & $run ([datetime]'2024-02-02 00:00:02')      # => Snapshot_2024_01_01_00_00_01
        $removedRel = if ($RemoveBorrower) { $borrowerRels[0] } else { $ownerRel }
        $allRels    = @($ownerRel) + $borrowerRels
        Remove-Item -LiteralPath (Join-Path $src $removedRel) -Force
        & $run ([datetime]'2024-03-03 00:00:03')      # => Snapshot_2024_02_02_00_00_02

        return [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; One = $one
            AllRels = $allRels
            RemovedRel = $removedRel
            SurvivorRels = @($allRels | Where-Object { $_ -ne $removedRel })
            SnapAfterRun2 = Join-Path $chg 'Snapshot_2024_02_02_00_00_02'
        }
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
            HashRecalcFreq='A'; CompressEnabled=$false }
        $goodSet = [pscustomobject]@{ Name='Good'; SourcePath=$good; BackupPath=$bkp; ChangePath=$chg
            HashRecalcFreq='A'; CompressEnabled=$false }
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
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $root = Join-Path $TestDrive ("pit\" + ($Mode -replace '\W', ''))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src, $root -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress

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

        # Destroy doomed.txt's only data source (its content-addressed pool object).
        $doomedData = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                        Where-Object RelativePath -eq 'doomed.txt')[0].DataPath
        Remove-Item -LiteralPath (Join-Path $bkp $doomedData) -Force
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

Describe 'Hash recovery of a nested infra-named pool file (SR-022, SR-010)' {
    # 2026-07-03 bash-v1 finding (human-approved fix): Find-DataFileByHash applied
    # the infrastructure-name skip RECURSIVELY, so a NESTED pool file named like
    # infrastructure (B6) was invisible to hash recovery. The contract
    # (AGENTS.md §3) is root-level-only; the skip is an optimization, not a
    # correctness mechanism: recovery matches on (xxH2Hash, Length). The engine
    # no longer produces nested pool files (hash names are flat at the root),
    # so the legacy-store shape is CONSTRUCTED — the restorer deliberately
    # still serves legacy stores (work-order R1), where it occurs naturally.
    It 'recovers a blanked row whose only copy is a NESTED infra-named pool file (B6, TC-058)' {
        $root = Join-Path $TestDrive 'nestedinfra'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg

        [IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv'), 'NESTED-USER-DATA')
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v1')
        Invoke-FB $cfg                                            # run1 (no snapshot)
        [IO.File]::WriteAllText((Join-Path $src 'other.txt'), 'v2')
        Invoke-FB $cfg                                            # run2 ⇒ Snapshot of state-1

        # Construct the legacy shape: the content's pool object renamed to a
        # NESTED infrastructure name inside the backup root, its row blanked
        # (witness re-stamped) — hash recovery is the only way back, and it
        # must scan past the nested name because the skip is root-level-only.
        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        $nested = @($rows | Where-Object RelativePath -eq 'sub\MANIFEST.csv')[0]
        New-Item -ItemType Directory -Path (Join-Path $bkp 'sub') -Force | Out-Null
        Move-Item -LiteralPath (Join-Path $bkp $nested.DataPath) -Destination (Join-Path $bkp 'sub\MANIFEST.csv') -Force
        $nested.DataPath = ''
        $rows | Export-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $bkp | Out-Null

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

        # Destroy one row's only data source (its content-addressed pool object).
        $lostData = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'lost.txt')[0].DataPath
        Remove-Item -LiteralPath (Join-Path $bkp $lostData) -Force
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
        $aData = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                   Where-Object RelativePath -eq 'a.txt')[0].DataPath
        Remove-Item -LiteralPath (Join-Path $bkp $aData) -Force
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
        $aData = $rows[0].DataPath
        $rows[0].DataPath = ''
        $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
        Write-ManifestWitness -FolderPath $bkp | Out-Null
        # The candidate must NOT carry the row's own bytes: since kit revision 5
        # a raw match under a '.7z' name recovers WITHOUT 7-Zip (TC-107), so
        # the dependency failure needs genuinely different candidate bytes.
        Remove-Item -LiteralPath (Join-Path $bkp $aData) -Force
        [IO.File]::WriteAllText((Join-Path $bkp 'a.7z'), 'OTHER BYTES ENTIRELY')

        Invoke-ReconProcess (Join-Path $bkp 'RECONSTRUCT.ps1') `
            @('-TargetRoot', (Join-Path $root 'r'), '-SevenZipPath', (Join-Path $root 'no-7z.exe')) |
            Should -Be 4
    }

    It 'still THROWS with the existing wording when called in-process (SR-040)' {
        # The -ExitCode switch is opt-in precisely so every in-process caller and
        # the six Should -Throw assertions keep working unchanged.
        $root = Join-Path $TestDrive 'x-inproc'
        $bkp = New-ExitCodeOrigin $root
        $aData = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                   Where-Object RelativePath -eq 'a.txt')[0].DataPath
        Remove-Item -LiteralPath (Join-Path $bkp $aData) -Force
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
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg

        # Run 1: four files, two of which this run will supersede/remove.
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'),  'OLD-SUPERSEDED')
        [IO.File]::WriteAllText((Join-Path $src 'gone.txt'),   'OLD-REMOVED')
        [IO.File]::WriteAllText((Join-Path $src 'super2.txt'), 'OLD-SUPERSEDED-2')
        [IO.File]::WriteAllText((Join-Path $src 'gone2.txt'),  'OLD-REMOVED-2')
        Invoke-FB $cfg
        # Resolve every pool object BEFORE run 2 replaces the rows: the loops
        # move these hash-named objects, and the assertions below read them.
        $r1data = @{}
        foreach ($row in @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))) {
            $r1data[$row.RelativePath] = $row.DataPath
        }

        # Set up run 2: supersede one file (Save-SupersededData, the step-11.5
        # post-evict position — this is that arm's failure-aggregation
        # coverage, step-4 review MIN-2) and remove another
        # (Move-RemovedFilesToStaging), so BOTH loops have work.
        [IO.File]::WriteAllText((Join-Path $src 'super.txt'),  'NEW-CONTENT')
        [IO.File]::WriteAllText((Join-Path $src 'super2.txt'), 'NEW-CONTENT-2')
        Remove-Item -LiteralPath (Join-Path $src 'gone.txt')  -Force
        Remove-Item -LiteralPath (Join-Path $src 'gone2.txt') -Force

        # Hold TWO pool objects open with no sharing, so their moves fail —
        # one in each loop. FileShare::None makes Move-Item throw exactly the way
        # a real locked file (AV scanner, open handle) does.
        $lock1 = [IO.File]::Open((Join-Path $bkp $r1data['super.txt']), 'Open', 'Read', 'None')
        $lock2 = [IO.File]::Open((Join-Path $bkp $r1data['gone.txt']),  'Open', 'Read', 'None')
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
        [IO.File]::ReadAllText((Join-Path $snap $r1data['super2.txt'])) | Should -Be 'OLD-SUPERSEDED-2'
        [IO.File]::ReadAllText((Join-Path $snap $r1data['gone2.txt']))  | Should -Be 'OLD-REMOVED-2'

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
        # (ConfigVersion, Name, HashRecalcFreq, CompressEnabled) is kept
        # exactly as checked in.
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

    It 'declares the shipped example, the README block, and the smoke config all at ConfigVersion 2 (the loader''s current version)' {
        $exampleObj = Get-Content -LiteralPath (Join-Path $repo 'container\FileBackup.example.json') -Raw | ConvertFrom-Json
        $exampleObj.ConfigVersion | Should -Be 2

        $readme = Get-Content -LiteralPath (Join-Path $repo 'README.md') -Raw
        if ($readme -match '(?s)```json\r?\n(\{.*?"BackupSets".*?\})\r?\n```') {
            $readmeObj = $Matches[1] | ConvertFrom-Json
            $readmeObj.ConfigVersion | Should -Be 2
        } else {
            throw "Could not locate the README JSON config block to check its ConfigVersion."
        }

        $invokeContainerSrc = Get-Content -LiteralPath (Join-Path $repo 'scripts\Invoke-Container.ps1') -Raw
        $invokeContainerSrc | Should -Match 'ConfigVersion\s*=\s*2'
    }
}

Describe 'Entry-point status codes (SR-043)' {
    BeforeAll {
        function New-JsonBackupConfig {
            param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg, [string]$Name = 'S')
            [ordered]@{
                ConfigVersion = 2
                BackupSets    = @(
                    [ordered]@{
                        Name = $Name; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
                        HashRecalcFreq = 'A'; CompressEnabled = $false
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
        [IO.File]::WriteAllText($badCfg, '{"ConfigVersion":2,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":"false"}]}')

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
            ConfigVersion = 2
            BackupSets    = @(
                [ordered]@{ Name = 'A'; SourcePath = $srcA; BackupPath = $bkpA; ChangePath = (Join-Path $root 'chgA'); HashRecalcFreq = 'A'; CompressEnabled = $false }
                [ordered]@{ Name = 'B'; SourcePath = $srcB; BackupPath = $bkpB; ChangePath = (Join-Path $root 'chgB'); HashRecalcFreq = 'A'; CompressEnabled = $false }
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
                  [string]$Hash, [string]$Compressed = 'No', [string]$StoredAs = 'Hash')
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
                # those (B6), so re-homing onto one would hide the bytes. Only
                # a LEGACY path-addressed row can produce such a name (a hash
                # name structurally cannot), so the row is constructed as
                # 'Original': prune still serves legacy stores (SR-061 refuses
                # only Backup), and this guard is why the re-home refusal
                # survives WP9 step 5.
                $plan   = Get-SnapshotPrunePlan -BackupRoot $e.Bkp -ChangeRoot $e.Chg -Name $e.Newest
                $item   = $plan.Items.ToArray()[0]
                $folder = Join-Path $e.Chg $e.Newest
                Rename-Item -LiteralPath (Join-Path $folder $item.SourceDataPath) -NewName 'backup.log'
                $rows = @(Read-Manifest -FolderPath $folder)
                $row  = @($rows | Where-Object { $_.DataPath -eq $item.SourceDataPath })[0]
                $row.DataPath = 'backup.log'; $row.RelativePath = 'backup.log'
                $row.StoredAsHashSize = 'Original'
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
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if ($Compress -and -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because "no 7-Zip at '$sevenZip' for the compressed modes"
            return
        }
        $root = Join-Path $TestDrive ('tc081-' + $Mode.Replace('+', '-'))
        $env  = New-PruneTimeline -Root $root -Compress $Compress

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
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
        if ($Compress -and -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because "no 7-Zip at '$sevenZip' for the compressed modes"
            return
        }
        $root = Join-Path $TestDrive ('tc086-' + $Mode.Replace('+', '-'))
        $env  = New-PruneTimeline -Root $root -Compress $Compress
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
            # The user files' POOL OBJECTS. Hash-named since WP9 step 5, so a
            # bare-suffix sweep cannot even see them by name any more — these
            # resolved paths prove the bytes survive regardless of naming.
            $rows = @(Import-Csv -LiteralPath (Join-Path $Env.Bkp 'MANIFEST.csv') |
                      Where-Object { $_.RelativePath -in 'notes.fbprune.tmp', 'sub\notes.fbprune.tmp' })
            return @($rows | ForEach-Object { Join-Path $Env.Bkp $_.DataPath } | Select-Object -Unique)
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
        $keepData = @(Import-Csv -LiteralPath (Join-Path $env.Bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'keep.txt')[0].DataPath
        $residue = Join-Path $env.Bkp ($keepData + '.fbprune.tmp')  # unreferenced: real residue
        Copy-Item -LiteralPath (Join-Path $env.Bkp $keepData) -Destination $residue

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
        $keepData = @(Import-Csv -LiteralPath (Join-Path $env.Bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'keep.txt')[0].DataPath
        $staged  = (Join-Path $env.Bkp $keepData) + '.fbprune.tmp'
        Copy-Item -LiteralPath (Join-Path $env.Bkp $keepData) -Destination $staged
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
        $keepData = @(Import-Csv -LiteralPath (Join-Path $env.Bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'keep.txt')[0].DataPath
        $staged = (Join-Path $env.Bkp $keepData) + '.fbprune.tmp'
        Copy-Item -LiteralPath (Join-Path $env.Bkp $keepData) -Destination $staged
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

    It 'exposes -Action Backup|Prune|Snapshots|Verify|View (default Backup) and -Snapshot as a string list' {
        $cmd = Get-Command $entry
        $action = $cmd.Parameters['Action']
        $action | Should -Not -BeNullOrEmpty
        $validate = @($action.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0]
        # WP5 extended the ONE dispatch with Verify (SR-049), WP9 with View
        # (SR-062); neither adds a parallel one.
        $validate.ValidValues | Should -Be @('Backup', 'Prune', 'Snapshots', 'Verify', 'View')
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

Describe 'WP8 portable names and raw-candidate recovery (SR-055, SR-050)' {
    BeforeAll {
        function Invoke-FBWp8 {
            param([string]$Cfg)
            $out = & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Cfg `
                        -NoMail -NonInteractive -ExitCode 2>&1
            return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
        }
    }

    It 'classifies portability per name component (SR-055)' {
        if ($IsWindows) {
            # '\' separates on Windows; brackets, parens, spaces, Unicode are fine.
            Test-PortableRelativePath -RelativePath 'sub folder\ok [1] (2).txt' | Should -BeNullOrEmpty
        }
        Test-PortableRelativePath -RelativePath 'колокол.txt' | Should -BeNullOrEmpty
        Test-PortableRelativePath -RelativePath 'quote"name.txt' | Should -Match 'no Windows file name'
        Test-PortableRelativePath -RelativePath ("newline`nname.txt") | Should -Match 'control character'
        Test-PortableRelativePath -RelativePath 'pipe|name.txt' | Should -Match 'no Windows file name'
        Test-PortableRelativePath -RelativePath 'trailing.' | Should -Match 'dot or space'
        Test-PortableRelativePath -RelativePath 'sub/trailing ' | Should -Match 'dot or space'
        # WP9 step 8b (TC-117): reserved device names, with or without an
        # extension, any case, in any component — and near-misses stay legal.
        Test-PortableRelativePath -RelativePath 'NUL' | Should -Match 'reserved device name'
        Test-PortableRelativePath -RelativePath 'nul.txt' | Should -Match 'reserved device name'
        Test-PortableRelativePath -RelativePath 'sub\CON.tar.gz' | Should -Match 'reserved device name'
        Test-PortableRelativePath -RelativePath 'Com3.log' | Should -Match 'reserved device name'
        Test-PortableRelativePath -RelativePath 'LPT9' | Should -Match 'reserved device name'
        Test-PortableRelativePath -RelativePath 'CONSOLE.txt' | Should -BeNullOrEmpty
        Test-PortableRelativePath -RelativePath 'COM10.txt' | Should -BeNullOrEmpty
        Test-PortableRelativePath -RelativePath 'nullable.cs' | Should -BeNullOrEmpty
        # The reserved-name rule holds on the POSIX arm too: a Linux source
        # holding NUL.txt starts failing loudly (the disclosed consequence).
        Test-PortableRelativePath -RelativePath 'sub/NUL.txt' -TreatAsPosix $true | Should -Match 'reserved device name'

        # The Linux arm, asserted via the -TreatAsPosix seam (WP8 review,
        # minor 1): '\' in a component is a NAME character on a POSIX host and
        # a path separator to the Windows restorer — refused; and on POSIX only
        # '/' separates, so 'sub\file' is ONE component there.
        Test-PortableRelativePath -RelativePath 'a\b.txt' -TreatAsPosix $true | Should -Match 'path separator on Windows'
        Test-PortableRelativePath -RelativePath 'sub/a.txt' -TreatAsPosix $true | Should -BeNullOrEmpty
        Test-PortableRelativePath -RelativePath 'sub\a.txt' -TreatAsPosix $false | Should -BeNullOrEmpty
    }

    It 'skips a non-portable name loudly, fails the set, backs up the rest, and freezes the prior row (SR-055)' {
        $root = Join-Path $TestDrive 'wp8-names'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'good.txt'), ('GOOD ' * 40))
        Invoke-FB $cfg

        # A prior-stored row under a non-portable name (a store written before
        # the guard existed, e.g. on Linux) whose source file is still there:
        # frozen, never evicted, never re-processed. The trailing-dot shape is
        # the one Windows can host via the \\?\ prefix, so the whole scenario
        # runs on this platform.
        $goodRow = @(Read-Manifest -FolderPath $bkp | Where-Object RelativePath -eq 'good.txt')[0]
        # The frozen row shares good.txt's content-addressed object (dedup-legal
        # and what a pre-guard Linux-written CA store would really hold; an
        # 'Original' row would instead trip the SR-061 legacy-store refusal).
        $badRow = [pscustomobject]@{
            DataPath = $goodRow.DataPath; RelativePath = 'bad.'; Length = $goodRow.Length
            LastWriteTime = $goodRow.LastWriteTime; xxH2Hash = $goodRow.xxH2Hash
            Compressed = $goodRow.Compressed; StoredAsHashSize = 'Hash'; Duplicate = ''; MediaMBPerSec = ''
        }
        Write-Manifest -FolderPath $bkp -Records (@(Read-Manifest -FolderPath $bkp) + $badRow)
        [IO.File]::WriteAllText("\\?\$src\bad.", ('GOOD ' * 40))
        [IO.File]::WriteAllText((Join-Path $src 'also-good.txt'), ('ALSO ' * 40))

        $run = Invoke-FBWp8 -Cfg $cfg
        $run.Code | Should -Be 1 -Because 'a skipped file is a loud failure, never a silent omission'
        $run.Output | Should -Match "Skipping 'bad\.'"

        $after = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        @($after | Where-Object RelativePath -eq 'also-good.txt').Count | Should -Be 1 -Because 'the rest of the set still backs up'
        @($after | Where-Object RelativePath -eq 'bad.').Count | Should -Be 1 -Because 'the prior row is frozen, not evicted'
        Test-Path -LiteralPath (Join-Path $bkp $goodRow.DataPath) | Should -BeTrue -Because 'the frozen row''s shared object stays in the pool'
    }

    It 'hash-recovers a raw .7z-named candidate with no 7-Zip installed (SR-050, kit revision 5)' {
        $root = Join-Path $TestDrive 'wp8-raw7z'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        # A genuine user file NAMED .7z whose bytes are raw — SR-004 stores an
        # already-compressed extension verbatim, so the pool candidate is a raw
        # file under a '.7z' name. Testing its own bytes needs no 7-Zip.
        [IO.File]::WriteAllText((Join-Path $src 'payload.7z'), ('NOT AN ARCHIVE ' * 30))
        Invoke-FB $cfg

        $rows = @(Read-Manifest -FolderPath $bkp)
        @($rows | Where-Object RelativePath -eq 'payload.7z')[0].DataPath = ''
        Write-Manifest -FolderPath $bkp -Records $rows

        $target = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target -SevenZipPath 'Z:\no\such\7z.exe' *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'payload.7z')) |
            Should -Be ('NOT AN ARCHIVE ' * 30) -Because 'raw bytes under a .7z name need no 7-Zip to recover'
    }
}

Describe 'WP7 storage self-healing and retention unblock (SR-053, SR-054, SR-046)' {
    BeforeAll {
        function Invoke-FBArgs {
            # Child process so the SR-040 exit code is observable.
            param([string]$Cfg, [string[]]$Arguments)
            $out = & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Cfg `
                        -NoMail -NonInteractive -ExitCode @Arguments 2>&1
            return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
        }
    }

    It 'treats a blank-DataPath root row as changed so the diff can heal it (SR-053)' {
        # Pure-diff pin: metadata equality must not hide a row whose bytes are gone.
        $row = { param($rel, $data) [pscustomobject]@{
            RelativePath = $rel; Length = 10; LastWriteTime = '2026-01-01 00:00:00'
            xxH2Hash = 'ABCD'; DataPath = $data } }
        $src = @(& $row 'a.txt' 'ignored')
        # .Count direct — @() around a List reached via a PSObject property
        # throws on PS 7.5 (see the step-8 note in Invoke-BackupSet).
        $diff = Compare-SourceToBackup -SourceDb $src -BackupDb @(& $row 'a.txt' '')
        $diff.NewOrChanged.Count | Should -Be 1 -Because 'a blank DataPath is damage to heal, not an unchanged row'
        $diff = Compare-SourceToBackup -SourceDb $src -BackupDb @(& $row 'a.txt' 'a.txt')
        $diff.NewOrChanged.Count | Should -Be 0
    }

    It 'heals an externally deleted data file from the still-matching source, and never adopts the blank row (SR-053)' {
        $root = Join-Path $TestDrive 'wp7-heal'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'unique.txt'), ('IRREPLACEABLE ' * 30))
        Invoke-FB $cfg

        # The verified initiating class: something outside FileBackup (AV
        # quarantine, cloud dehydration, a tidying operator) deletes the data
        # file inside the backup root. The source is untouched.
        $uniqueData = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                        Where-Object RelativePath -eq 'unique.txt')[0].DataPath
        Remove-Item -LiteralPath (Join-Path $bkp $uniqueData) -Force
        # R5 shape in the same run: a NEW source file with the same content
        # must not adopt the blanked row.
        Copy-Item -LiteralPath (Join-Path $src 'unique.txt') -Destination (Join-Path $src 'copy.txt')

        Invoke-FBArgs -Cfg $cfg -Arguments @() | ForEach-Object { $_.Code | Should -Be 0 }

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        foreach ($rel in 'unique.txt', 'copy.txt') {
            $r = @($rows | Where-Object RelativePath -eq $rel)[0]
            $r.DataPath | Should -Not -BeNullOrEmpty -Because "the $rel row must point at real bytes again"
            Test-Path -LiteralPath (Join-Path $bkp $r.DataPath) | Should -BeTrue
        }
        $target = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'unique.txt')) | Should -Be ('IRREPLACEABLE ' * 30)
        [IO.File]::ReadAllText((Join-Path $target 'copy.txt'))   | Should -Be ('IRREPLACEABLE ' * 30)
    }

    It 'verify reports PoolUnresolvable, exit 1, when a row''s bytes are gone from the pool entirely (SR-054)' {
        $root = Join-Path $TestDrive 'wp7-poolgone'
        $env  = New-PruneTimeline -Root $root
        # Kill the LAST copies of gone.txt's content: eviction parked its bytes
        # in the newest snapshot; the oldest snapshot's row reaches them only
        # by hash. The parked object is hash-named, so resolve its name from
        # the snapshot manifests before deleting every physical copy.
        $goneData = @(Get-ChildItem -LiteralPath $env.Chg -Directory |
                      Where-Object Name -match '^Snapshot_' |
                      ForEach-Object { Import-Csv -LiteralPath (Join-Path $_.FullName 'MANIFEST.csv') } |
                      Where-Object { $_.RelativePath -eq 'gone.txt' -and $_.DataPath } |
                      Select-Object -ExpandProperty DataPath -Unique)
        foreach ($dp in $goneData) {
            Get-ChildItem -LiteralPath $env.Chg -Recurse -File -Filter ([IO.Path]::GetFileName($dp)) | Remove-Item -Force
        }

        $run = Invoke-FBArgs -Cfg $env.Cfg -Arguments @('-Action', 'Verify')
        $run.Code | Should -Be 1 -Because 'a store with unrestorable rows must not verify clean'
        $lines = $run.Output -split "`r?`n"
        $start = [array]::IndexOf($lines, '[')
        $end   = [array]::IndexOf($lines, ']')
        $doc = @(($lines[$start..$end] -join "`n") | ConvertFrom-Json)
        @($doc | Where-Object Class -eq 'PoolUnresolvable') | Should -Not -BeNullOrEmpty
    }

    It 'budgets heal copies in the capacity preflight (SR-052, SR-053)' {
        # WP7 review, required change 1: a blank row's key must not read as
        # "already held" — the heal WILL copy those bytes, and the preflight
        # must refuse before mutation, not fail mid-copy on a full volume.
        $mk = { param($rel, $data) [pscustomobject]@{
            RelativePath = $rel; DataPath = $data; Length = 500
            LastWriteTime = '2026-01-01 00:00:00'; xxH2Hash = 'AB12' } }
        $demand = Get-BackupCapacityDemand -NewOrChanged @(& $mk 'big.bin' 'ignored') `
            -RemovedFromSource @() -BackupDb @(& $mk 'big.bin' '') -SameVolume $true
        $demand.BackupBytes | Should -Be 500 -Because 'a blank row holds no bytes; the heal will copy them'
        $demand = Get-BackupCapacityDemand -NewOrChanged @(& $mk 'big.bin' 'ignored') `
            -RemovedFromSource @() -BackupDb @(& $mk 'big.bin' 'big.bin') -SameVolume $true
        $demand.BackupBytes | Should -Be 0 -Because 'a non-blank row genuinely holds the bytes'
    }

    It 'verify tells a missing named file with surviving bytes apart from true loss (SR-054)' {
        # WP7 review, required change 2: a row whose named file is gone while
        # the CONTENT survives elsewhere restores via the revision-4+ fallback
        # and heals next run — reporting it PoolUnresolvable handed the wrapper
        # a false data-loss alarm.
        $root = Join-Path $TestDrive 'wp7-classes'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('SHARED ' * 40))
        Invoke-FB $cfg

        # A second physical copy of the same content under its own row.
        # ('Hash', not the legacy 'Original': Verify would otherwise add a
        # LegacyStoredForm finding this test is not about.)
        $rowA = @(Read-Manifest -FolderPath $bkp | Where-Object RelativePath -eq 'a.txt')[0]
        Copy-Item -LiteralPath (Join-Path $bkp $rowA.DataPath) -Destination (Join-Path $bkp 'spare.bin')
        $spare = [pscustomobject]@{
            DataPath = 'spare.bin'; RelativePath = 'spare.src'; Length = $rowA.Length
            LastWriteTime = $rowA.LastWriteTime; xxH2Hash = $rowA.xxH2Hash
            Compressed = 'No'; StoredAsHashSize = 'Hash'; Duplicate = ''; MediaMBPerSec = ''
        }
        Write-Manifest -FolderPath $bkp -Records (@(Read-Manifest -FolderPath $bkp) + $spare)
        [IO.File]::Delete((Join-Path $bkp $rowA.DataPath))

        $parse = {
            param($output)
            $lines = $output -split "`r?`n"
            $start = [array]::IndexOf($lines, '[')
            $end   = [array]::IndexOf($lines, ']')
            return @(($lines[$start..$end] -join "`n") | ConvertFrom-Json)
        }
        $run = Invoke-FBArgs -Cfg $cfg -Arguments @('-Action', 'Verify')
        $run.Code | Should -Be 1
        $doc = & $parse $run.Output
        @($doc | Where-Object Class -eq 'PoolDataPathMissing') | Should -Not -BeNullOrEmpty
        @($doc | Where-Object Class -eq 'PoolUnresolvable') |
            Should -BeNullOrEmpty -Because 'the bytes survive as spare.bin; nothing is lost'

        [IO.File]::Delete((Join-Path $bkp 'spare.bin'))
        $run = Invoke-FBArgs -Cfg $cfg -Arguments @('-Action', 'Verify')
        $run.Code | Should -Be 1
        @((& $parse $run.Output) | Where-Object Class -eq 'PoolUnresolvable') |
            Should -Not -BeNullOrEmpty -Because 'now the content is truly gone from the pool'
    }

    It 'prunes a compression-flipped store whose kits are revision 2 or newer (SR-046 as amended)' {
        $root = Join-Path $TestDrive 'wp7-flip'
        $env  = New-PruneTimeline -Root $root -Compress $true
        # The form disagreement retention has to cope with. It is CONSTRUCTED:
        # SR-061 deleted the layout migration, so flipping CompressEnabled no
        # longer re-forms the root while snapshots keep their form - a
        # disagreement now comes only from damage or tampering. The rail still
        # has to hold for such a store, which is what this pins.
        Set-SnapshotBlankRowForm -Folder (Join-Path $env.Chg $env.Oldest) -Compressed 'No'

        $run = Invoke-FBArgs -Cfg $env.Cfg -Arguments @('-Action', 'Prune', '-Snapshot', $env.Newest)
        $run.Code | Should -Be 0 -Because 'revision-2+ kits decide form from the file they locate (SR-050); the rail premise is gone'
        Test-Path -LiteralPath (Join-Path $env.Chg $env.Newest) | Should -BeFalse

        # The surviving snapshot still restores byte-exact across the flip.
        $target = Join-Path $root 'restored'
        & (Join-Path (Join-Path $env.Chg $env.Oldest) 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'gone.txt')) | Should -Be ('DOOMED ' * 40)
    }

    It 'still refuses the form disagreement for a folder carrying a pre-revision-2 kit (SR-046)' {
        $root = Join-Path $TestDrive 'wp7-oldkit'
        $env  = New-PruneTimeline -Root $root -Compress $true
        Set-SnapshotBlankRowForm -Folder (Join-Path $env.Chg $env.Oldest) -Compressed 'No'

        # Regress the OLDEST snapshot's kit marker to revision 1: that kit
        # genuinely branches on the row, so its rows' form disagreement is real.
        $kit = Join-Path (Join-Path $env.Chg $env.Oldest) 'RECONSTRUCT.ps1'
        [IO.File]::WriteAllText($kit, ([IO.File]::ReadAllText($kit) -replace '# KitRevision: \d+', '# KitRevision: 1'))

        $run = Invoke-FBArgs -Cfg $env.Cfg -Arguments @('-Action', 'Prune', '-Snapshot', $env.Newest)
        $run.Code | Should -Be 2 -Because 'a pre-revision-2 kit restores the wrong form; pruning into that store stays refused'
        $run.Output | Should -Match 'form-mismatch'
        $run.Output | Should -Match 'RefreshKits' -Because 'the refusal must name the remedy'
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

    It 'backs up a source file named like ROOT-LEVEL infrastructure as ordinary data (SR-022, SR-058)' {
        # Pre-WP9, Mirror had to REFUSE this file: its mirror-path destination
        # was the real index at the backup root. Content addressing stores it
        # at a hash name that structurally cannot collide with infrastructure
        # (the TC-123 grammar), so the refusal class is gone and the file is
        # simply backed up and restored like any other data.
        $root = Join-Path $TestDrive 'wg-infra'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $state = Join-Path $root 'state'; $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        # External SourceStatePath: EVERY source file is user data, including a
        # root-level MANIFEST.csv (the container's default arrangement).
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
            SourceStatePath = $state
            HashRecalcFreq = 'A'; CompressEnabled = $false
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg
        [IO.File]::WriteAllText((Join-Path $src 'MANIFEST.csv'), 'user,data,that,is,not,an,index')
        [IO.File]::WriteAllText((Join-Path $src 'ok.txt'), ('FINE ' * 40))

        Invoke-FBExit -Cfg $cfg | Should -Be 0 -Because 'a hash-named object cannot collide with the index, so nothing is refused'

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        @($rows | Where-Object RelativePath -eq 'ok.txt').Count | Should -Be 1
        $mrow = @($rows | Where-Object RelativePath -eq 'MANIFEST.csv')
        $mrow.Count | Should -Be 1
        $mrow[0].DataPath | Should -Not -Be 'MANIFEST.csv' -Because 'the object must never sit at the index name'
        # Restore returns the USER'S bytes at that name, not the engine index.
        $t = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t 'MANIFEST.csv')) | Should -Be 'user,data,that,is,not,an,index'
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

    It 'keys no RelativePath map off a literal case-insensitive hashtable (SR-034)' {
        # Independent review of 83cc5f1, required change 1: the F3 conversion
        # missed Save-SupersededData, so on Linux a case-differing pair could
        # skip staging superseded bytes. Pin the CLASS: a literal @{} whose
        # fill is keyed by .RelativePath must be New-RelativePathMap instead.
        $repoRoot = Split-Path $entry
        foreach ($rel in 'Modules/FileBackup.Engine.psm1', 'Modules/FileBackup.Common.psm1', 'Reconstruct.ps1', 'FileBackup.ps1') {
            $lines = [IO.File]::ReadAllLines((Join-Path $repoRoot $rel))
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -notmatch '=\s*@\{\}') { continue }
                $window = $lines[$i..([Math]::Min($i + 3, $lines.Count - 1))] -join "`n"
                $window | Should -Not -Match '\.RelativePath\]\s*=' `
                    -Because "$rel line $($i + 1) fills a literal case-insensitive hashtable with RelativePath keys; use New-RelativePathMap (SR-034)"
            }
        }
    }

    It 'hash-recovers a row whose named data file is gone but whose bytes survive in the pool (SR-031, SR-010)' {
        $root = Join-Path $TestDrive 'wg-hint'
        $env  = New-PruneTimeline -Root $root
        # The Optimize crash window: the file a row NAMES is gone while
        # byte-identical content survives elsewhere in the pool. Renaming the
        # root object reproduces exactly that shape.
        $keepData = @(Import-Csv -LiteralPath (Join-Path $env.Bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'keep.txt')[0].DataPath
        Move-Item -LiteralPath (Join-Path $env.Bkp $keepData) -Destination (Join-Path $env.Bkp 'keep.survives')

        $target = Join-Path $root 'restored'
        & (Join-Path $env.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'keep.txt')) |
            Should -Be ('KEEP ' * 40) -Because 'DataPath is a locator hint; (hash,length) is the content authority'
    }
}

# ---------------------------------------------------------------------------
# WP9 step 1 — D-1 / D-5 repros (TC-118, TC-119, SR-059, SR-060).
#
# The step-1 CHANGE-DETECTOR Describe (asserting both defects reproduce on
# Mirror — the proof the contract blocks test something real) was deleted with
# the mode at WP9 step 5, exactly as its own marker directed; commits e302593
# and 9a1da7d hold the recorded asymmetry evidence.
# ---------------------------------------------------------------------------

Describe 'Shared content survives an edit by one holder (D-1, SR-059, TC-118)' {
    # The full TC-118 matrix: edit={owner,borrower} x copies={2,3} x
    # compress={on,off}. copies=2 is the bench shape (one owner, one borrower);
    # copies=3 adds a second run-2 borrower so the edited row is not the last
    # claim on the object - the case where a naive "is anyone else still using
    # it" check can go wrong in the other direction and evict too eagerly.
    It 'keeps every other holder restorable when the <Edit> of <Copies> copies is edited (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false; Edit = 'owner';    Copies = 2 }
        @{ Mode = 'Compress'; Compress = $true;  Edit = 'owner';    Copies = 2 }
        @{ Mode = 'Plain';    Compress = $false; Edit = 'borrower'; Copies = 2 }
        @{ Mode = 'Compress'; Compress = $true;  Edit = 'borrower'; Copies = 2 }
        @{ Mode = 'Plain';    Compress = $false; Edit = 'owner';    Copies = 3 }
        @{ Mode = 'Compress'; Compress = $true;  Edit = 'owner';    Copies = 3 }
        @{ Mode = 'Plain';    Compress = $false; Edit = 'borrower'; Copies = 3 }
        @{ Mode = 'Compress'; Compress = $true;  Edit = 'borrower'; Copies = 3 }
    ) {
        $root = Join-Path $TestDrive ('d1\' + $Edit + $Copies + '\' + ($Mode -replace '\W', ''))
        $t = New-BorrowTimeline -Root $root -Compress $Compress -Copies $Copies -Edit $Edit

        # (1) Store level: no row claims bytes that are not there. This is the
        # detector D-1 needed and nothing had - the borrowed file is PRESENT
        # after the edit, so no blank-row or Test-Path check sees it.
        @(Get-ClaimedRowViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty
        @(Get-BlankRowPoolViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty

        # (2) Latest state: the edited holder moved on, every other holder
        # still restores the original content.
        $latest = Join-Path $root 'r-latest'
        & (Join-Path $t.Bkp 'RECONSTRUCT.ps1') -TargetRoot $latest *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $latest $t.EditedRel)) | Should -Be $t.Two
        foreach ($rel in $t.UnchangedRels) {
            [IO.File]::ReadAllText((Join-Path $latest $rel)) | Should -Be $t.One
        }

        # (3) Still exactly one physical object per content: the surviving
        # holders share the original object (no per-borrower fork), and the
        # edit added exactly one new object.
        $rows = @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv'))
        foreach ($rel in @($t.EditedRel) + $t.UnchangedRels) {
            $row = @($rows | Where-Object RelativePath -eq $rel)
            $row.Count | Should -Be 1 -Because "'$rel' must have exactly one live row"
            Get-PoolContentCopyCount -Folders @($t.Bkp) -Hash $row[0].xxH2Hash -Length ([long]$row[0].Length) |
                Should -Be 1 -Because 'content addressing stores each distinct content once'
        }
        @($rows | Where-Object RelativePath -in $t.UnchangedRels |
                  Select-Object -ExpandProperty DataPath -Unique).Count |
            Should -Be 1 -Because 'the unedited holders still share the ONE original object'

        # (4) Point in time: the snapshot of the pre-edit state gives the
        # ORIGINAL content for every holder.
        $pre = Join-Path $root 'r-pre-edit'
        & (Join-Path $t.SnapAfterRun2 'RECONSTRUCT.ps1') -TargetRoot $pre *>&1 | Out-Null
        foreach ($rel in $t.AllRels) {
            [IO.File]::ReadAllText((Join-Path $pre $rel)) | Should -Be $t.One
        }
    }
}

Describe 'The pool is immutable and every name is justified (SR-059, TC-122)' {
    # The census TC-122 asks for, and the other half of SR-059: an object no
    # live row happens to claim is still held to the naming contract, because
    # hash recovery (SR-050) would hand it to any row asking for those bytes.
    It 'never changes the content at a claimed DataPath across <Runs> runs (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false; Runs = 3 }
        @{ Mode = 'Compress'; Compress = $true;  Runs = 3 }
        @{ Mode = 'Plain';    Compress = $false; Runs = 5 }
        @{ Mode = 'Compress'; Compress = $true;  Runs = 5 }
    ) {
        $root = Join-Path $TestDrive ('tc122\' + $Runs + '\' + ($Mode -replace '\W', ''))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src, (Join-Path $src 'sub') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress

        $gen1 = 'CENSUS-GENERATION-ONE ' * 60
        $gen2 = 'CENSUS-GENERATION-TWO ' * 60

        # One mutation per run, each a shape that has produced a real defect:
        # seed, a LATER duplicate that borrows (D-1's setup), the owner editing
        # away, the last live claim on the shared content going, and the old
        # content returning under a new name (re-adoption after eviction).
        $mutate = @(
            { [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $gen1)
              [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY') }
            { [IO.File]::WriteAllText((Join-Path $src 'sub\twin.bin'), $gen1) }
            { [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $gen2) }
            { Remove-Item -LiteralPath (Join-Path $src 'sub\twin.bin') -Force }
            { [IO.File]::WriteAllText((Join-Path $src 'sub\again.bin'), $gen1) }
        )

        # The census records each object's PROVEN CONTENT, not its raw bytes:
        # a .7z re-created for identical content is not byte-identical (7-Zip
        # stores the member name and time), and re-creating an evicted object
        # is legitimate. What SR-059 forbids is the CONTENT at a claimed path
        # changing - so that is what is compared.
        $contentKey = {
            param([string]$Path, [string]$WantHash)
            $raw = Get-FileXxHash -FilePath $Path
            $len = (Get-Item -LiteralPath $Path -Force).Length
            if ($raw -eq $WantHash) { return "$raw|$len" }
            $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
            if ($sevenZip -and (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $sevenZip -Archive $Path -DestinationFile $tmp
                    return "$(Get-FileXxHash -FilePath $tmp)|$((Get-Item -LiteralPath $tmp -Force).Length)"
                } catch {
                    Write-Verbose "TC-122: '$Path' is neither the claimed raw content nor expandable: $($_.Exception.Message)"
                } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            }
            return "$raw|$len"
        }

        $census = @{}
        for ($i = 0; $i -lt $Runs; $i++) {
            & $mutate[$i]
            & $entry -ConfigPath $cfg -NoMail -NonInteractive `
                -BackupTime ([datetime]'2024-01-01 00:00:01').AddDays($i) *>&1 | Out-Null

            foreach ($folder in (Get-PoolFolderList -BackupRoot $bkp -ChangeRoot $chg)) {
                $manifest = Join-Path $folder 'MANIFEST.csv'
                if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
                foreach ($row in @(Import-Csv -LiteralPath $manifest | Where-Object DataPath)) {
                    $full = Join-Path $folder $row.DataPath
                    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
                    $now = & $contentKey $full $row.xxH2Hash
                    if ($census.ContainsKey($full)) {
                        $now | Should -Be $census[$full] `
                            -Because "the content at '$full' changed under a live claim by run $($i + 1)"
                    }
                    $census[$full] = $now
                }
            }

            @(Get-ClaimedRowViolations -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty
            @(Get-UnjustifiedPoolNames -BackupRoot $bkp -ChangeRoot $chg)  | Should -BeNullOrEmpty
        }

        # The census must have SEEN several objects across several folders, or
        # every assertion above is vacuous.
        $census.Count | Should -BeGreaterThan 2
    }

    It 'reports a pool object whose name its own content does not justify (non-vacuity)' {
        # The audit above is only worth its green if it can go red. Tamper a
        # COPY of a real store - never the store the other arms just proved.
        $root = Join-Path $TestDrive 'tc122-nonvacuity'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), 'NON-VACUITY ' * 60)
        & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime ([datetime]'2024-01-01 00:00:01') *>&1 | Out-Null

        $copy = Join-Path $root 'bkp-copy'
        Copy-Item -LiteralPath $bkp -Destination $copy -Recurse -Force
        @(Get-UnjustifiedPoolNames -BackupRoot $copy -ChangeRoot (Join-Path $root 'no-such-chg')) |
            Should -BeNullOrEmpty -Because 'an untouched copy of a real store is clean'

        $object = @(Get-ChildItem -LiteralPath $copy -File -Force |
                    Where-Object { $_.Name -notmatch '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)' })[0]
        $object | Should -Not -BeNullOrEmpty
        [IO.File]::WriteAllText($object.FullName, 'DIFFERENT BYTES UNDER THE SAME NAME')

        @(Get-UnjustifiedPoolNames -BackupRoot $copy -ChangeRoot (Join-Path $root 'no-such-chg')) |
            Should -Not -BeNullOrEmpty -Because 'the name now encodes a (hash,length) the bytes do not produce'
    }
}

Describe 'Same-run duplicates are stored once (D-5, SR-060, TC-119)' {
    It 'writes ONE physical object for content first seen in one run (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        $root = Join-Path $TestDrive ('d5\' + ($Mode -replace '\W', ''))
        $t = New-SameRunDuplicateStore -Root $root -Compress $Compress

        $rows = @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv') |
                  Where-Object { $_.RelativePath -in 'a.bin', 'sub\b.bin' })
        $rows.Count | Should -Be 2
        @($rows | Select-Object -ExpandProperty DataPath -Unique).Count |
            Should -Be 1 -Because 'identical content resolves to one physical object, whenever it was first seen'
        Get-PoolContentCopyCount -Folders @($t.Bkp) -Hash $rows[0].xxH2Hash -Length ([long]$rows[0].Length) |
            Should -Be 1 -Because 'the pool holds exactly one copy of the shared bytes'

        # SR-060 asks for ONE copy/compress OPERATION, not just one resulting
        # file - and under content addressing those are different claims: a
        # second write lands on the same name with the same bytes, so every
        # assertion above passes identically with the intra-run memo disabled.
        # That blindness was real (WP9 review, MAJ-2): the memo could be
        # deleted outright and the whole 405-test suite stayed green while
        # every duplicate was silently re-copied - D-5's cost defect returning
        # unnoticed. The engine now logs one line per PHYSICAL write; count it.
        $writes = @(Get-Content -LiteralPath $t.Log |
                    Where-Object { $_ -match ([regex]::Escape("hash=$($rows[0].xxH2Hash) len=$($rows[0].Length)")) -and
                                   $_ -match 'Stored object' })
        $writes.Count | Should -Be 1 -Because 'the second member must adopt the memo, not re-copy the same bytes'
    }
}

Describe 'An unreadable owner does not fail its whole content group (WP9 review MIN-1)' {
    # Owner election picks ONE member's file as the source for the group's
    # single stored object. Before this fix that was the ONLY source tried, so
    # one unreadable file left every one of its content twins unbacked-up - and
    # the error named the twin rather than the file that could not be read.
    # Every member of a (hash,length) group holds identical bytes by
    # definition, so any member can supply them.
    #
    # Driven at Invoke-BackupFileGroup rather than end-to-end on purpose: an
    # exclusive lock taken before a run also blocks HASHING, so the set would
    # fail at the source walk and never reach the copy branch. Removing the
    # owner's file after the group is built reaches it deterministically, and
    # is the same shape as a file that vanishes mid-run.
    It 'stores the shared content from a readable member (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true  }
    ) {
        $root = Join-Path $TestDrive ('min1\' + ($Mode -replace '\W', ''))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub'), $bkp -Force | Out-Null
        $shared = 'UNREADABLE-OWNER-SHARED ' * 60
        # 'a.bin' is shorter than 'sub\twin.bin', so it is the elected owner.
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), $shared)
        [IO.File]::WriteAllText((Join-Path $src 'sub\twin.bin'), $shared)
        $hash = Get-FileXxHash -FilePath (Join-Path $src 'a.bin')
        $len  = (Get-Item -LiteralPath (Join-Path $src 'a.bin')).Length

        $group = @('a.bin', 'sub\twin.bin') | ForEach-Object {
            [pscustomobject]@{
                RelativePath = $_; Length = $len; xxH2Hash = $hash
                LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
            }
        }
        # The owner becomes unreadable AFTER hashing - the copy branch's problem.
        Remove-Item -LiteralPath (Join-Path $src 'a.bin') -Force

        $map = @{}; $changed = 0; $ok = $true; $lines = New-Object System.Collections.Generic.List[string]
        $log = { param($m, $l = 'INFO') $lines.Add("[$l] $m") }
        Invoke-BackupFileGroup -Group $group -SrcPath $src -BkpPath $bkp `
            -CompressEnabled $Compress -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath `
            -BackupDb @() -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) `
            -Log $log -OverallSuccess ([ref]$ok)

        $ok | Should -BeTrue -Because 'a readable member supplied the bytes'
        $map.Keys | Should -HaveCount 2
        $map['a.bin'].DataPath | Should -Be $map['sub\twin.bin'].DataPath

        # The bytes really are the group's content, proven from disk.
        $stored = Join-Path $bkp $map['sub\twin.bin'].DataPath
        Test-Path -LiteralPath $stored | Should -BeTrue
        if ($Compress) {
            $tmp = Join-Path $root 'expanded.bin'
            Expand-FileWithSevenZip -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath -Archive $stored -DestinationFile $tmp
            Get-FileXxHash -FilePath $tmp | Should -Be $hash
        } else {
            Get-FileXxHash -FilePath $stored | Should -Be $hash
        }

        # And the diagnostic names the file that could not be read, not a twin.
        @($lines | Where-Object { $_ -match 'Could not read' -and $_ -match 'a\.bin' }) |
            Should -Not -BeNullOrEmpty -Because 'the WARN must name the unreadable OWNER'
    }
}

Describe 'A snapshot can never exist without its restore kit (F8, SR-028, WP9 step 8)' {
    It 'stages the kit BEFORE the publish rename: a crash at the rename leaves a complete Temp and NO snapshot' {
        # The old order was rename-then-copy, so a crash in the window left a
        # valid, published snapshot with no restore kit. Now the rename IS the
        # last mutation: a Snapshot_* folder structurally cannot exist without
        # its kit. Driven through Invoke-BackupSet directly (the entry point
        # re-imports the module, which would tear down the mock).
        $root = Join-Path $TestDrive 'f8'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $set = [pscustomobject]@{
            Name = 'F8'; SourcePath = $src; SourceStatePath = ''; BackupPath = $bkp; ChangePath = $chg
            HashRecalcFreq = 'A'; CompressEnabled = $false; AllowEmptySource = $false
            BrowseView = 'off'; ViewPath = ''
        }
        $deps = @{ '7z' = $null; 'ffprobe' = $null }
        $ok = $true; $logs = New-Object System.Collections.Generic.List[string]

        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'ONE')
        Invoke-BackupSet -Set $set -Deps $deps -OverallSuccess ([ref]$ok) -LogPaths $logs -BackupTime ([datetime]'2024-01-01 00:00:01')
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'TWO')

        Mock -ModuleName FileBackup.Engine Rename-Item { throw 'INJECTED: crash at the publish rename' }
        { Invoke-BackupSet -Set $set -Deps $deps -OverallSuccess ([ref]$ok) -LogPaths $logs -BackupTime ([datetime]'2024-02-02 00:00:02') } |
            Should -Throw -ExpectedMessage '*INJECTED*'

        @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -match '^Snapshot_') |
            Should -BeNullOrEmpty -Because 'nothing was published; the crash hit the publish itself'
        $temp = Join-Path $chg 'Temp'
        Test-Path -LiteralPath $temp -PathType Container | Should -BeTrue -Because 'the unpublished snapshot stays as Temp for the SR-017 guard'
        foreach ($artifact in 'RECONSTRUCT.ps1', 'RECONSTRUCT.bat', 'reconstruct.sh', 'FileBackup.Common.psm1', 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json') {
            Test-Path -LiteralPath (Join-Path $temp $artifact) -PathType Leaf |
                Should -BeTrue -Because "the kit ('$artifact') must be staged BEFORE the rename"
        }
        Test-Path -LiteralPath (Join-Path $temp 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
    }
}

Describe 'A directory squatting on a copy destination is refused (step-4 review n6)' {
    It 'Copy-SourceFileToBackup returns the error string instead of silently copying INTO the directory' {
        $root = Join-Path $TestDrive 'n6'
        New-Item -ItemType Directory -Path (Join-Path $root 'dest.bin') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $root 'src.bin'), 'PAYLOAD')
        $result = Copy-SourceFileToBackup -SourceFilePath (Join-Path $root 'src.bin') `
            -BackupFilePath (Join-Path $root 'dest.bin') -ShouldCompress:$false
        $result | Should -Match 'is a directory'
        @(Get-ChildItem -LiteralPath (Join-Path $root 'dest.bin')) |
            Should -BeNullOrEmpty -Because 'nothing may be copied INTO the squatting directory'
    }
}

Describe 'The unreferenced-data audit is linear (SR-064, LLR-062, TC-132)' {
    It 'scales linearly from 1k to 4k rows and still catches the orphan and the missing file' {
        function New-AuditStore {
            param([string]$Root, [int]$Count)
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            $rows = for ($i = 0; $i -lt $Count; $i++) {
                $name = 'obj{0:D5}.bin' -f $i
                [IO.File]::WriteAllText((Join-Path $Root $name), "payload $i")
                [pscustomobject]@{
                    DataPath = $name; RelativePath = "file$i.bin"; Length = 9
                    LastWriteTime = [datetime]'2024-01-01'; xxH2Hash = 'ABCD'
                    Compressed = 'No'; StoredAsHashSize = 'Hash'; Duplicate = ''; MediaMBPerSec = ''
                }
            }
            Write-Manifest -FolderPath $Root -Records @($rows)
            return $Root
        }
        $log = { param($m, $l) }

        $small = New-AuditStore -Root (Join-Path $TestDrive 'tc132\small') -Count 1000
        $big   = New-AuditStore -Root (Join-Path $TestDrive 'tc132\big')   -Count 4000
        [void](Test-BackupManifest -FolderRoot $small -Log $log)   # warm-up (module JIT, FS cache)
        $tSmall = (Measure-Command { Test-BackupManifest -FolderRoot $small -Log $log | Out-Null }).TotalMilliseconds
        $tBig   = (Measure-Command { Test-BackupManifest -FolderRoot $big   -Log $log | Out-Null }).TotalMilliseconds

        # Linear scales ~4x here; the old per-file Where-Object re-pipe scaled
        # ~16x. The bound is generous against noisy hosts, and still separates
        # the two shapes decisively (TC-132's behavioral/timing proof).
        ($tBig / [math]::Max($tSmall, 1)) | Should -BeLessThan 10 -Because "1k took ${tSmall}ms, 4k took ${tBig}ms"

        # The behavioral half at scale: one orphan file and one missing-file
        # row are both still reported.
        $store = New-AuditStore -Root (Join-Path $TestDrive 'tc132\beh') -Count 50
        [IO.File]::WriteAllText((Join-Path $store 'orphan.bin'), 'NO ROW NAMES ME')
        $rows = @(Read-Manifest -FolderPath $store)
        Remove-Item -LiteralPath (Join-Path $store $rows[0].DataPath) -Force
        $lines = New-Object System.Collections.Generic.List[string]
        $healed = @(Test-BackupManifest -FolderRoot $store -Log { param($m, $l) $lines.Add($m) })
        @($lines | Where-Object { $_ -match 'exists in backup folder but not in DB: orphan\.bin' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match 'Datapath missing in backup DB' }).Count | Should -Be 1
        @($healed | Where-Object { -not $_.DataPath }).Count | Should -Be 1
    }
}

Describe 'Manifest writes are canonical (WP9 step-8 fold: deterministic bytes)' {
    It 'a manifest-identical run rewrites MANIFEST.csv byte-identically, rows in ordinal order' {
        # Step 7's viewstamp work caught the drift: fresh rows carried $null
        # in optional columns while adopted rows carried Import-Csv's '', and
        # Export-Csv quotes the two differently - so a NO-OP run changed the
        # manifest's bytes. Canonicalization at step 12 kills the class.
        $root = Join-Path $TestDrive 'canon'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'zz'), (Join-Path $src 'aa') -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'zz\deep.txt'), 'DEEP')
        [IO.File]::WriteAllText((Join-Path $src 'aa\first.txt'), 'FIRST')
        [IO.File]::WriteAllText((Join-Path $src 'root.txt'), 'ROOT')
        Invoke-FB $cfg
        $bytes1 = Get-Content -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -Raw
        Invoke-FB $cfg
        $bytes2 = Get-Content -LiteralPath (Join-Path $bkp 'MANIFEST.csv') -Raw
        $bytes2 | Should -Be $bytes1 -Because 'a manifest-identical run must not churn a single byte of the index'

        $rels = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Select-Object -ExpandProperty RelativePath)
        $rels.Count | Should -Be 3
        for ($i = 1; $i -lt $rels.Count; $i++) {
            [string]::CompareOrdinal($rels[$i - 1], $rels[$i]) | Should -BeLessOrEqual 0 -Because 'rows are written in ordinal RelativePath order'
        }
    }
}

Describe 'Every stored row is content-addressed (SR-058, TC-121)' {
    It 'names every DataPath by the hash grammar and stamps StoredAsHashSize=Hash (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        $root = Join-Path $TestDrive ('tc121\' + $Mode)
        $t = New-SameRunDuplicateStore -Root $root -Compress $Compress
        foreach ($row in @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv'))) {
            $row.StoredAsHashSize | Should -Be 'Hash'
            $row.DataPath | Should -Not -BeNullOrEmpty
        }
        @(Get-HashNameGrammarViolations -BackupRoot $t.Bkp) |
            Should -BeNullOrEmpty -Because 'no configuration selects any other layout (SR-058)'
    }
}

# ---------------------------------------------------------------------------
# WP9 step 4 — the exact survival test (SR-059, LLR-059).
#
# In the content-addressed modes Save-SupersededData now runs AFTER the
# copy/evict steps and asks the exact question — does any row of the FINAL
# manifest still claim the old object — instead of predicting survival from
# the source walk. The frozen-claim It is the distinguisher: it fails on the
# source-based test (which moves out an object a frozen row still claims) and
# passes on the exact one. The other two Its pin behavior that must hold under
# BOTH orders, so the reorder cannot regress it.
# ---------------------------------------------------------------------------

Describe 'Preservation consults the FINAL manifest, not the source walk (SR-059, LLR-059)' {
    It 'keeps the pool object a FROZEN row still claims when the last walkable holder edits away (SR-057, TC-118 frozen-claim arm, <Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        $root = Join-Path $TestDrive ('frz\' + ($Mode -replace '\W', ''))
        $t = New-FrozenClaimTimeline -Root $root -Compress $Compress

        # (0) Non-vacuity guard (review 2026-08-25, MAJ-1): if the Deny ACE
        # does not bite (privileged CI identity, silent icacls failure), this
        # timeline degenerates to an ordinary edit and every assertion below
        # passes without testing SR-059 at all. Prove SR-057 actually froze
        # the pair before trusting anything else.
        (Get-Content -LiteralPath (Join-Path $t.Chg 'backup.log') -Raw) |
            Should -Match 'Cannot enumerate' -Because 'the fixture is vacuous unless SR-057 actually fired'

        # (1) The distinguisher: the frozen row's DataPath must still hold
        # its bytes. The source-based test could not see this claim - the
        # frozen file is exactly the one the walk could not visit - and
        # moved the object into the snapshot, leaving the live row
        # pointing at nothing.
        @(Get-ClaimedRowViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty
        @(Get-BlankRowPoolViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty

        # (2) Latest state: the edit landed; the frozen path still restores.
        $latest = Join-Path $root 'r-latest'
        & (Join-Path $t.Bkp 'RECONSTRUCT.ps1') -TargetRoot $latest *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $latest 'a.bin'))           | Should -Be $t.Two
        [IO.File]::ReadAllText((Join-Path $latest 'locked\pair.bin')) | Should -Be $t.One

        # (3) Point in time: the pre-edit snapshot reproduces the shared
        # content for both paths (hash-recovered from the live pool).
        $pre = Join-Path $root 'r-pre'
        & (Join-Path $t.PreEditSnap 'RECONSTRUCT.ps1') -TargetRoot $pre *>&1 | Out-Null
        foreach ($rel in 'a.bin', 'locked\pair.bin') {
            [IO.File]::ReadAllText((Join-Path $pre $rel)) | Should -Be $t.One
        }
    }

    It 'parks exactly one staged copy when eviction and supersession share content in one run (R4, TC-118 arm, <Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        $root = Join-Path $TestDrive ('r4\' + ($Mode -replace '\W', ''))
        $t = New-EvictSupersedeTimeline -Root $root -Compress $Compress

        @(Get-ClaimedRowViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty
        @(Get-BlankRowPoolViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty

        # The old object left the pool (no final row claims it) and exactly
        # ONE copy landed in the snapshot - whichever loop moved it, the
        # other found it already gone.
        $snapRow = @(Import-Csv -LiteralPath (Join-Path $t.Snap 'MANIFEST.csv') |
                     Where-Object RelativePath -eq 'a.bin')[0]
        Get-PoolContentCopyCount -Folders @($t.Bkp)  -Hash $snapRow.xxH2Hash -Length ([long]$snapRow.Length) |
            Should -Be 0 -Because 'nothing in the final manifest claims the superseded content'
        Get-PoolContentCopyCount -Folders @($t.Snap) -Hash $snapRow.xxH2Hash -Length ([long]$snapRow.Length) |
            Should -Be 1 -Because 'exactly one parked copy serves both loops; zero would be the R4 missed-bytes failure'

        $latest = Join-Path $root 'r-latest'
        & (Join-Path $t.Bkp 'RECONSTRUCT.ps1') -TargetRoot $latest *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $latest 'a.bin')) | Should -Be $t.Two
        Test-Path -LiteralPath (Join-Path $latest 'sub\b.bin') | Should -BeFalse

        $pre = Join-Path $root 'r-pre'
        & (Join-Path $t.Snap 'RECONSTRUCT.ps1') -TargetRoot $pre *>&1 | Out-Null
        foreach ($rel in 'a.bin', 'sub\b.bin') {
            [IO.File]::ReadAllText((Join-Path $pre $rel)) | Should -Be $t.One
        }
    }

    It 'keeps the old object in the pool when the replacement copy FAILS (TC-118 failed-copy arm, <Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        # The severest exactness win (review 2026-08-25, MIN-1; red-first
        # proven by the reviewer's pre-change probe): a failed step-10 copy
        # leaves the OLD row live in the final manifest, so the exact test
        # keeps its object. The source-based test moved it out - the new
        # content is in the source, the old is not - and the live root then
        # failed to restore with content-missing.
        $root = Join-Path $TestDrive ('fcpy\' + ($Mode -replace '\W', ''))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress

        $one = 'FAILED-COPY-OLD ' * 60
        $two = 'FAILED-COPY-NEW ' * 60
        [IO.File]::WriteAllText((Join-Path $src 'f.bin'), $one)
        [IO.File]::WriteAllText((Join-Path $src 'steady.txt'), 'STEADY')
        & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime ([datetime]'2024-01-01 00:00:01') *>&1 | Out-Null

        # Pre-create and lock the NEW content's destination so step 10's copy
        # fails exactly the way a real locked file (AV hold) does.
        [IO.File]::WriteAllText((Join-Path $src 'f.bin'), $two)
        $probe = Join-Path $src 'f.bin'
        $destName = Get-HashSizeFileName -HashHex (Get-FileXxHash -FilePath $probe) `
            -Length (Get-Item -LiteralPath $probe).Length `
            -Extension $(if ($Compress) { '.7z' } else { '.bin' })
        $blockPath = Join-Path $bkp $destName
        [IO.File]::WriteAllText($blockPath, 'BLOCKER')
        $lock = [IO.File]::Open($blockPath, 'Open', 'Read', 'None')
        try {
            # Child process so the exit code is observable.
            & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 1 -Because 'a failed copy must fail the set loudly (SR-014)'
        } finally {
            $lock.Dispose()
        }
        Remove-Item -LiteralPath $blockPath -Force

        (Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw) |
            Should -Match 'Failed to copy/compress' -Because 'the fixture is vacuous unless the copy actually failed'

        # The old row is still live, so its object must still be in the pool.
        @(Get-ClaimedRowViolations -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty
        @(Get-BlankRowPoolViolations -BackupRoot $bkp -ChangeRoot $chg) | Should -BeNullOrEmpty

        $latest = Join-Path $root 'r-latest'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $latest *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $latest 'f.bin')) |
            Should -Be $one -Because 'the backup could not take the new bytes, so it must still restore the old ones'
    }
}

Describe 'One dedup member deleted while the others live (B9, SR-006, TC-135)' {
    It 'keeps the shared object when the <Removed> of <Copies> copies is deleted, and the snapshot restores it (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false; RemoveBorrower = $false; Removed = 'owner';    Copies = 2 }
        @{ Mode = 'Plain';    Compress = $false; RemoveBorrower = $true;  Removed = 'borrower'; Copies = 2 }
        @{ Mode = 'Compress'; Compress = $true;  RemoveBorrower = $false; Removed = 'owner';    Copies = 2 }
        @{ Mode = 'Compress'; Compress = $true;  RemoveBorrower = $true;  Removed = 'borrower'; Copies = 2 }
        @{ Mode = 'Plain';    Compress = $false; RemoveBorrower = $false; Removed = 'owner';    Copies = 3 }
        @{ Mode = 'Plain';    Compress = $false; RemoveBorrower = $true;  Removed = 'borrower'; Copies = 3 }
        @{ Mode = 'Compress'; Compress = $true;  RemoveBorrower = $false; Removed = 'owner';    Copies = 3 }
        @{ Mode = 'Compress'; Compress = $true;  RemoveBorrower = $true;  Removed = 'borrower'; Copies = 3 }
    ) {
        $root = Join-Path $TestDrive ('tc135\' + $Removed + $Copies + '\' + ($Mode -replace '\W', ''))
        $t = New-MemberRemovedTimeline -Root $root -Compress $Compress -RemoveBorrower:$RemoveBorrower -Copies $Copies

        @(Get-ClaimedRowViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty
        @(Get-BlankRowPoolViolations -BackupRoot $t.Bkp -ChangeRoot $t.Chg) | Should -BeNullOrEmpty

        # B9: evicting the removed member's row must NOT take the object the
        # survivors still claim - and with copies=3 two of them still do.
        $rows = @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv') |
                  Where-Object RelativePath -in $t.SurvivorRels)
        $rows.Count | Should -Be $t.SurvivorRels.Count
        @($rows | Select-Object -ExpandProperty DataPath -Unique).Count |
            Should -Be 1 -Because 'the survivors share the one object the removed member also used'
        Get-PoolContentCopyCount -Folders @($t.Bkp) -Hash $rows[0].xxH2Hash -Length ([long]$rows[0].Length) |
            Should -Be 1 -Because 'the survivors still claim the object, so eviction must leave it in the pool'

        $latest = Join-Path $root 'r-latest'
        & (Join-Path $t.Bkp 'RECONSTRUCT.ps1') -TargetRoot $latest *>&1 | Out-Null
        foreach ($rel in $t.SurvivorRels) {
            [IO.File]::ReadAllText((Join-Path $latest $rel)) | Should -Be $t.One
        }
        Test-Path -LiteralPath (Join-Path $latest $t.RemovedRel) | Should -BeFalse

        $preRemove = Join-Path $root 'r-pre'
        & (Join-Path $t.SnapAfterRun2 'RECONSTRUCT.ps1') -TargetRoot $preRemove *>&1 | Out-Null
        foreach ($rel in $t.AllRels) {
            [IO.File]::ReadAllText((Join-Path $preRemove $rel)) | Should -Be $t.One
        }
    }
}

Describe 'One (hash,length) group elects one physical object (SR-060, TC-120)' {
    # Step 2's own proof. Members of a group can disagree about BOTH inputs to
    # the stored form - extension and compressibility - and content addressing
    # has room for only one object, so the owner decides and every row must
    # describe the object that was actually written.
    It 'stores one object for identical bytes under different extensions' {
        $root = Join-Path $TestDrive 'elect-ext'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        $body = 'SAME-BYTES-DIFFERENT-NAMES ' * 40
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), $body)
        [IO.File]::WriteAllText((Join-Path $src 'a.dat'), $body)
        Invoke-FB $cfg

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                  Where-Object { $_.RelativePath -in 'a.txt', 'a.dat' })
        $rows.Count | Should -Be 2
        $paths = @($rows | Select-Object -ExpandProperty DataPath -Unique)
        $paths.Count | Should -Be 1 -Because 'one (hash,length) means one physical object'
        # 'a.dat' and 'a.txt' are the same length, so the ORDINAL tie-break
        # elects 'a.dat' - and the stored object carries the owner's extension.
        $paths[0] | Should -BeLike '*.dat'
        Get-PoolContentCopyCount -Folders @($bkp) -Hash $rows[0].xxH2Hash -Length ([long]$rows[0].Length) |
            Should -Be 1

        $t = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        foreach ($rel in 'a.txt', 'a.dat') { [IO.File]::ReadAllText((Join-Path $t $rel)) | Should -Be $body }
    }

    It 'stores one object when the members disagree about compressibility' {
        $root = Join-Path $TestDrive 'elect-comp'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-FBConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true
        # Identical bytes under a compressible and a non-compressible extension:
        # Test-ShouldCompress says YES for .txt and NO for .jpg (SR-004).
        $body = 'MIXED-COMPRESSIBILITY ' * 40
        [IO.File]::WriteAllText((Join-Path $src 'x.txt'), $body)
        [IO.File]::WriteAllText((Join-Path $src 'x.jpg'), $body)
        Invoke-FB $cfg

        $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                  Where-Object { $_.RelativePath -in 'x.txt', 'x.jpg' })
        $rows.Count | Should -Be 2
        @($rows | Select-Object -ExpandProperty DataPath -Unique).Count | Should -Be 1
        # 'x.jpg' wins the ordinal tie-break, so the group is stored RAW and
        # EVERY row must say so - a row whose Compressed disagrees with the
        # object it names is the finding-B family (SR-049/SR-050).
        @($rows | Select-Object -ExpandProperty Compressed -Unique) | Should -Be 'No'
        Get-PoolContentCopyCount -Folders @($bkp) -Hash $rows[0].xxH2Hash -Length ([long]$rows[0].Length) |
            Should -Be 1

        # And -Action Verify must consider that store clean.
        $verify = & $entry -ConfigPath $cfg -NoMail -NonInteractive -Action Verify -ExitCode *>&1
        $LASTEXITCODE | Should -Be 0 -Because "the store is consistent: $verify"

        $t = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        foreach ($rel in 'x.txt', 'x.jpg') { [IO.File]::ReadAllText((Join-Path $t $rel)) | Should -Be $body }
    }
}

Describe 'A compression flip re-forms nothing already stored (SR-061, TC-124)' {
    # Replaces the deleted migration suites. The human ruled 2026-08-25 that
    # retroactive re-packing is not required in EITHER direction, so
    # CompressEnabled governs only content written after the flip. A mixed-form
    # store is normal - compression has always been per-file (SR-004) - and every
    # row's Compressed describes its OWN object, so nothing needs re-forming.
    It 'leaves existing objects untouched, applies the new setting to new content, and audits clean (<Flip>)' -ForEach @(
        @{ Flip = 'on-to-off'; Start = $true;  Then = $false }
        @{ Flip = 'off-to-on'; Start = $false; Then = $true  }
    ) {
        $root = Join-Path $TestDrive ('flip-' + $Flip)
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $cfgA = Join-Path $root 'a.xml'; $cfgB = Join-Path $root 'b.xml'
        New-FBConfig -Path $cfgA -Src $src -Bkp $bkp -Chg $chg -Compress $Start
        New-FBConfig -Path $cfgB -Src $src -Bkp $bkp -Chg $chg -Compress $Then 

        $before = 'STORED-UNDER-THE-FIRST-SETTING ' * 40
        [IO.File]::WriteAllText((Join-Path $src 'first.txt'), $before)
        Invoke-FB $cfgA

        $firstRow = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') |
                      Where-Object RelativePath -eq 'first.txt')[0]
        $firstObj = Join-Path $bkp $firstRow.DataPath
        $firstFingerprint = "$((Get-Item -LiteralPath $firstObj).Length)|$(Get-FileXxHash -FilePath $firstObj)"

        # Flip the setting and add new content.
        $after = 'WRITTEN-UNDER-THE-SECOND-SETTING ' * 40
        [IO.File]::WriteAllText((Join-Path $src 'second.txt'), $after)
        Invoke-FB $cfgB

        # (1) The pre-existing object is byte-identical, at the same path, with
        # the same Compressed claim: no re-forming happened.
        $rowsAfter = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
        $firstAfter = @($rowsAfter | Where-Object RelativePath -eq 'first.txt')[0]
        $firstAfter.DataPath   | Should -Be $firstRow.DataPath
        $firstAfter.Compressed | Should -Be $firstRow.Compressed
        Test-Path -LiteralPath $firstObj -PathType Leaf | Should -BeTrue
        "$((Get-Item -LiteralPath $firstObj).Length)|$(Get-FileXxHash -FilePath $firstObj)" |
            Should -Be $firstFingerprint -Because 'SR-061: nothing already stored is re-formed'

        # (2) New content follows the NEW setting, so the store is mixed-form.
        $secondAfter = @($rowsAfter | Where-Object RelativePath -eq 'second.txt')[0]
        $secondAfter.Compressed | Should -Be $(if ($Then) { 'Yes' } else { 'No' })

        # (3) A mixed-form store is NORMAL, not a finding.
        & $entry -ConfigPath $cfgB -NoMail -NonInteractive -Action Verify -ExitCode *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'a mixed-form store is well-formed: each row describes its own object'

        # (4) Everything still restores byte-exact.
        $t = Join-Path $root 'restored'
        & (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $t 'first.txt'))  | Should -Be $before
        [IO.File]::ReadAllText((Join-Path $t 'second.txt')) | Should -Be $after
    }
}
