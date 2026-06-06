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
}
