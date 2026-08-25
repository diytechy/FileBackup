<#
.SYNOPSIS  G9 - Dated-snapshot rollback over a controlled timeline.
.NOTES     Invoked by Run-All.ps1. Verifies SR-005 (snapshot lifecycle/naming),
           SR-010 (point-in-time restore), SR-028 (mixed content + delta storage)
           across the 4 storage modes, using injected backup dates (-BackupTime)
           so each snapshot has a distinct, predictable name.
#>
function Invoke-G9 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G9-Rollback'
    $cfg = Join-Path $Env.Root 'cfg-g9.xml'

    Reset-TestEnvironment $Env
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    $D1 = [datetime]'2024-01-01 00:00:01'
    $D2 = [datetime]'2024-02-02 00:00:02'
    $D3 = [datetime]'2024-03-03 00:00:03'
    $D4 = [datetime]'2024-04-04 00:00:04'
    function SnapName([datetime]$d) { 'Snapshot_' + $d.ToString('yyyy_MM_dd_HH_mm_ss') }

    $S = $Env.SrcPath
    # ---- run1 @D1 : initial mixed-content tree (state1) — no snapshot (first run) ----
    New-TestFile (Join-Path $S 'a.txt') 'A1'
    New-TestFile (Join-Path $S 'dup1.txt') 'SHARED'
    New-TestFile (Join-Path $S 'dup2.txt') 'SHARED'          # duplicate content
    New-RandomBinaryFile (Join-Path $S 'keep.bin') 2048
    New-TestFile (Join-Path $S 'pic.jpg') 'pretend-jpeg'     # already-compressed extension
    New-TestFile (Join-Path $S 'orig.txt') 'RENAMEME'        # will be renamed at run3
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D1 | Out-Null
    $keepHash = (Get-FileHash -LiteralPath (Join-Path $S 'keep.bin') -Algorithm SHA256).Hash

    # ---- run2 @D2 : modify a.txt, delete dup2.txt, add new.txt (state2) ⇒ Snapshot(D1) ----
    New-TestFile (Join-Path $S 'a.txt') 'A2'
    Remove-Item -LiteralPath (Join-Path $S 'dup2.txt') -Force
    New-TestFile (Join-Path $S 'new.txt') 'NEW'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D2 | Out-Null

    # ---- run3 @D3 : modify a.txt again + rename orig.txt -> renamed.txt (state3) ⇒ Snapshot(D2) ----
    New-TestFile (Join-Path $S 'a.txt') 'A3'
    Move-Item -LiteralPath (Join-Path $S 'orig.txt') -Destination (Join-Path $S 'renamed.txt')
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D3 | Out-Null

    # ---- run4 @D4 : no-op (state4 == state3) ⇒ NO snapshot ----
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D4 | Out-Null

    # ---- Lifecycle (SR-005): snapshots for D1 & D2 exist; none for D3 (no-op run4) ----
    $snapD1 = Join-Path $Env.ChgPath (SnapName $D1)
    $snapD2 = Join-Path $Env.ChgPath (SnapName $D2)
    $snapD3 = Join-Path $Env.ChgPath (SnapName $D3)
    Assert-True $suite $group 'G9.1' 'Snapshot_D1_exists' { Test-Path -LiteralPath (Join-Path $snapD1 'MANIFEST.csv') }
    Assert-True $suite $group 'G9.1' 'Snapshot_D2_exists' { Test-Path -LiteralPath (Join-Path $snapD2 'MANIFEST.csv') }
    Assert-True $suite $group 'G9.2' 'NoSnapshot_for_noop' { -not (Test-Path -LiteralPath $snapD3) }

    # ---- Helper: reconstruct a folder to a fresh target, return its path ----
    function Restore([string]$ReconFolder, [string]$TargetName) {
        $target = Join-Path $Env.Root $TargetName
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Invoke-Reconstruct -ReconstructScript (Join-Path $ReconFolder 'RECONSTRUCT.ps1') -TargetRoot $target
        return $target
    }
    function TextEq([string]$Path, [string]$Expected) {
        (Test-Path -LiteralPath $Path) -and ([IO.File]::ReadAllText($Path) -eq $Expected)
    }

    # ---- Rollback to state1 (Snapshot D1): a=A1, dup2 present, keep.bin intact, new.txt absent ----
    $r1 = Restore $snapD1 'g9-r1'
    Assert-True $suite $group 'G9.3' 'State1_a_is_A1'        { TextEq (Join-Path $r1 'a.txt') 'A1' }
    Assert-True $suite $group 'G9.3' 'State1_dup2_present'   { TextEq (Join-Path $r1 'dup2.txt') 'SHARED' }
    Assert-True $suite $group 'G9.3' 'State1_new_absent'     { -not (Test-Path -LiteralPath (Join-Path $r1 'new.txt')) }
    Assert-True $suite $group 'G9.3' 'State1_keepbin_bytes'  {
        (Test-Path -LiteralPath (Join-Path $r1 'keep.bin')) -and
        (Get-FileHash -LiteralPath (Join-Path $r1 'keep.bin') -Algorithm SHA256).Hash -eq $keepHash
    }
    Assert-True $suite $group 'G9.3' 'State1_pic_present'     { TextEq (Join-Path $r1 'pic.jpg') 'pretend-jpeg' }
    Assert-True $suite $group 'G9.3' 'State1_orig_present'    { TextEq (Join-Path $r1 'orig.txt') 'RENAMEME' }
    Assert-True $suite $group 'G9.3' 'State1_renamed_absent'  { -not (Test-Path -LiteralPath (Join-Path $r1 'renamed.txt')) }

    # ---- Rollback to state2 (Snapshot D2): a=A2, dup2 deleted, new.txt present ----
    $r2 = Restore $snapD2 'g9-r2'
    Assert-True $suite $group 'G9.4' 'State2_a_is_A2'      { TextEq (Join-Path $r2 'a.txt') 'A2' }
    Assert-True $suite $group 'G9.4' 'State2_dup2_absent'  { -not (Test-Path -LiteralPath (Join-Path $r2 'dup2.txt')) }
    Assert-True $suite $group 'G9.4' 'State2_new_present'  { TextEq (Join-Path $r2 'new.txt') 'NEW' }
    # Rename happens at run3, so state2 still has the pre-rename path.
    Assert-True $suite $group 'G9.4' 'State2_orig_present'   { TextEq (Join-Path $r2 'orig.txt') 'RENAMEME' }
    Assert-True $suite $group 'G9.4' 'State2_renamed_absent' { -not (Test-Path -LiteralPath (Join-Path $r2 'renamed.txt')) }

    # ---- Latest from the backup root: a=A3, rename applied (state3/4) ----
    $r0 = Restore $Env.BkpPath 'g9-r0'
    Assert-True $suite $group 'G9.5' 'Latest_a_is_A3'        { TextEq (Join-Path $r0 'a.txt') 'A3' }
    Assert-True $suite $group 'G9.5' 'Latest_dup1_present'   { TextEq (Join-Path $r0 'dup1.txt') 'SHARED' }
    Assert-True $suite $group 'G9.5' 'Latest_renamed_present'{ TextEq (Join-Path $r0 'renamed.txt') 'RENAMEME' }
    Assert-True $suite $group 'G9.5' 'Latest_orig_absent'    { -not (Test-Path -LiteralPath (Join-Path $r0 'orig.txt')) }

    # TC-116: orphan-detection second pass over the full rollback timeline —
    # every blank-DataPath row in every manifest backed by a BYTE-VERIFIED
    # pool copy (the assertion that caught D-1; see PoolAudit.ps1).
    Assert-True $suite $group 'G9.audit' 'BlankRows_byteVerified' {
        @(Get-BlankRowPoolViolations -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath).Count -eq 0
    }
}

function Get-G9PhysicalCopyCount {
    <#
    .SYNOPSIS
        Counts the physical copies of one content (hash,length) across the whole
        store — the dedup property TC-049/TC-082 assert on quiescent states.
    #>
    param([pscustomobject]$Env, [string]$Hash, [long]$Length)
    # Counted through the physical content index, not by hashing raw files: in
    # the compressed modes the stored file is a .7z whose own bytes hash to
    # something else entirely, so only the index knows which files ARE the
    # content. The index lists one entry per data file that exists on disk.
    $snapshots = @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath | ForEach-Object { $_.FullName })
    $index = Get-BackupContentIndex -BackupRoot $Env.BkpPath -SnapshotFolder $snapshots
    $key = "$Hash|$Length"
    if (-not $index.Map.ContainsKey($key)) { return 0 }
    return $index.Map[$key].Count
}

function Invoke-G9Prune {
    <#
    .SYNOPSIS  G9 (part 2) - snapshot retention over the same dated timeline.
    .NOTES     TC-090 (prune at every timeline position) and TC-082 (TC-049's
               adversarial delete/re-add/delete cycle extended with prunes).
               SR-045/SR-046: removing a snapshot must re-home the content only
               it physically holds, and must never refuse the newest or the last.
    #>
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G9-Rollback'

    function SnapName([datetime]$d) { 'Snapshot_' + $d.ToString('yyyy_MM_dd_HH_mm_ss') }
    function RestoreTo([pscustomobject]$Env, [string]$ReconFolder, [string]$TargetName) {
        $target = Join-Path $Env.Root $TargetName
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Invoke-Reconstruct -ReconstructScript (Join-Path $ReconFolder 'RECONSTRUCT.ps1') -TargetRoot $target
        return $target
    }
    function TextAt([string]$Path, [string]$Expected) {
        (Test-Path -LiteralPath $Path) -and ([IO.File]::ReadAllText($Path) -eq $Expected)
    }

    # ================= TC-090: prune at every timeline position =================
    Reset-TestEnvironment $Env
    $cfg = Join-Path $Env.Root 'cfg-g9p.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')
    $S = $Env.SrcPath
    $D = @([datetime]'2025-01-01 00:00:01', [datetime]'2025-02-02 00:00:02', [datetime]'2025-03-03 00:00:03',
           [datetime]'2025-04-04 00:00:04', [datetime]'2025-05-05 00:00:05')

    New-TestFile (Join-Path $S 'a.txt') 'A1'
    New-TestFile (Join-Path $S 'sub\MANIFEST.csv') 'NESTED-NOT-INFRASTRUCTURE'   # B6
    New-RandomBinaryFile (Join-Path $S 'keep.bin') 2048
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D[0] | Out-Null
    foreach ($i in 1..4) {
        New-TestFile (Join-Path $S 'a.txt') ('A' + ($i + 1))
        Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime $D[$i] | Out-Null
    }
    # Snapshots exist for D1..D4 (each named by the superseded run's date); the
    # live backup root is state5.
    $snaps = @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath | ForEach-Object { $_.Name })
    Assert-True $suite $group 'G9.6' 'Prune_timeline_has_four_snapshots' { $snaps.Count -eq 4 }

    # -- oldest: nothing else can only-reach its content, so zero bytes copied --
    $oldest = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $snaps[0])
    Assert-True $suite $group 'G9.6' 'Prune_oldest_succeeds'   { $oldest[0].Status -eq 'Pruned' -and $oldest[0].Code -eq 0 }
    Assert-True $suite $group 'G9.6' 'Prune_oldest_copies_zero'{ $oldest[0].BytesReHomed -eq 0 }
    Assert-True $suite $group 'G9.6' 'Prune_oldest_folder_gone'{ -not (Test-Path -LiteralPath (Join-Path $Env.ChgPath $snaps[0])) }

    # -- newest: it parks the superseded bytes, so this is the expensive case --
    $newest = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $snaps[3])
    Assert-True $suite $group 'G9.7' 'Prune_newest_succeeds'  { $newest[0].Status -eq 'Pruned' -and $newest[0].Code -eq 0 }
    Assert-True $suite $group 'G9.7' 'Prune_newest_not_refused' { $newest[0].Refusals.Count -eq 0 }

    # -- middle --
    $middle = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $snaps[1])
    Assert-True $suite $group 'G9.8' 'Prune_middle_succeeds' { $middle[0].Status -eq 'Pruned' }

    # Every state that is left still restores byte-exact, and the nested
    # infrastructure-named user file survives every re-home (B6).
    $survivor = Join-Path $Env.ChgPath $snaps[2]
    $r3 = RestoreTo $Env $survivor 'g9p-r3'
    Assert-True $suite $group 'G9.8' 'Prune_survivor_state_restores' { TextAt (Join-Path $r3 'a.txt') 'A3' }
    Assert-True $suite $group 'G9.8' 'Prune_survivor_nested_manifest' { TextAt (Join-Path $r3 'sub\MANIFEST.csv') 'NESTED-NOT-INFRASTRUCTURE' }
    $r0 = RestoreTo $Env $Env.BkpPath 'g9p-r0'
    Assert-True $suite $group 'G9.8' 'Prune_latest_state_restores' { TextAt (Join-Path $r0 'a.txt') 'A5' }

    # -- the sole remaining snapshot: retention to zero is legitimate --
    $last = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $snaps[2])
    Assert-True $suite $group 'G9.9' 'Prune_last_succeeds' { $last[0].Status -eq 'Pruned' }
    Assert-True $suite $group 'G9.9' 'Prune_no_snapshots_left' { @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath).Count -eq 0 }
    $r0b = RestoreTo $Env $Env.BkpPath 'g9p-r0b'
    Assert-True $suite $group 'G9.9' 'Prune_latest_still_restores' { TextAt (Join-Path $r0b 'a.txt') 'A5' }
    Assert-True $suite $group 'G9.9' 'Prune_latest_keeps_binary' {
        (Test-Path -LiteralPath (Join-Path $r0b 'keep.bin')) -and
        (Get-Item -LiteralPath (Join-Path $r0b 'keep.bin')).Length -eq 2048
    }

    # ============ TC-082: TC-049's cycle, extended with prunes =================
    Reset-TestEnvironment $Env
    $cfg2 = Join-Path $Env.Root 'cfg-g9c.xml'
    Write-TestConfig $cfg2 $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')
    $C = 'CYCLE-CONTENT ' + ('data ' * 50)
    New-TestFile (Join-Path $S 'steady.txt') 'STEADY'
    New-TestFile (Join-Path $S 'f.txt') $C
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg2 -BackupTime $D[0] | Out-Null
    Remove-Item -LiteralPath (Join-Path $S 'f.txt') -Force
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg2 -BackupTime $D[1] | Out-Null
    New-TestFile (Join-Path $S 'f.txt') $C                       # reintroduced, identical
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg2 -BackupTime $D[2] | Out-Null
    Remove-Item -LiteralPath (Join-Path $S 'f.txt') -Force
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg2 -BackupTime $D[3] | Out-Null

    $probe = Join-Path $Env.Root 'g9c-probe.tmp'
    New-TestFile $probe $C
    $cHash = Get-FileXxHash -FilePath $probe
    $cLen  = (Get-Item -LiteralPath $probe).Length
    Remove-Item -LiteralPath $probe -Force
    Assert-True $suite $group 'G9.10' 'Cycle_one_copy_before_prune' {
        (Get-G9PhysicalCopyCount -Env $Env -Hash $cHash -Length $cLen) -eq 1
    }

    # Prune the snapshot that physically holds the single copy: the content must
    # be re-homed, not lost, and the store must go back to exactly one copy.
    $cycleSnaps = @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath | ForEach-Object { $_.Name })
    $keeper = $null
    foreach ($name in $cycleSnaps) {
        $plan = Get-SnapshotPrunePlan -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $name
        if ($plan.Items.Count -gt 0) { $keeper = $name; break }
    }
    Assert-True $suite $group 'G9.10' 'Cycle_keeper_snapshot_identified' { $null -ne $keeper }
    if ($keeper) {
        $pruned = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $keeper)
        Assert-True $suite $group 'G9.10' 'Cycle_prune_keeper_succeeds' { $pruned[0].Status -eq 'Pruned' }
        Assert-True $suite $group 'G9.10' 'Cycle_one_copy_after_prune' {
            (Get-G9PhysicalCopyCount -Env $Env -Hash $cHash -Length $cLen) -eq 1
        }
        foreach ($name in @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath | ForEach-Object { $_.Name })) {
            # The expectation comes from that snapshot's OWN manifest, never
            # from the restore output being judged: reading it back from the
            # target made the assertion self-fulfilling, so losing f.txt passed
            # vacuously (WP4 review, finding M2).
            $expectF = @(Read-Manifest -FolderPath (Join-Path $Env.ChgPath $name) |
                         Where-Object { $_.RelativePath -eq 'f.txt' }).Count -gt 0
            $t = RestoreTo $Env (Join-Path $Env.ChgPath $name) ('g9c-' + $name)
            Assert-True $suite $group 'G9.10' ("Cycle_state_restores_" + $name) {
                (TextAt (Join-Path $t 'steady.txt') 'STEADY') -and
                $(if ($expectF) { TextAt (Join-Path $t 'f.txt') $C }
                  else { -not (Test-Path -LiteralPath (Join-Path $t 'f.txt')) })
            }
        }
    }

    # Oldest-first retention copies nothing: the cheap policy stays cheap.
    $remaining = @(Get-PoolSnapshotFolder -ChangeRoot $Env.ChgPath | ForEach-Object { $_.Name })
    if ($remaining.Count -gt 0) {
        $oldestPlan = Get-SnapshotPrunePlan -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $remaining[0]
        $oldestRun  = @(Remove-BackupSnapshot -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath -Name $remaining[0])
        Assert-True $suite $group 'G9.11' 'Cycle_oldest_first_copies_zero' {
            $oldestPlan.BytesReHomed -eq 0 -and $oldestRun[0].Status -eq 'Pruned'
        }
    }
    $rLatest = RestoreTo $Env $Env.BkpPath 'g9c-latest'
    Assert-True $suite $group 'G9.11' 'Cycle_latest_restores_after_prunes' {
        (TextAt (Join-Path $rLatest 'steady.txt') 'STEADY') -and
        (-not (Test-Path -LiteralPath (Join-Path $rLatest 'f.txt')))
    }

    # TC-116: the second pass must also hold AFTER pruning — a prune that
    # orphaned a blank row would be invisible to every default check.
    Assert-True $suite $group 'G9P.audit' 'BlankRows_byteVerified_postPrune' {
        @(Get-BlankRowPoolViolations -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath).Count -eq 0
    }
}
