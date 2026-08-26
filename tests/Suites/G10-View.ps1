<#
.SYNOPSIS  G10 - the browse view over a real timeline (SR-062; TC-129, TC-130,
           TC-131, TC-133 integration arms; the unit battery is
           tests/Unit/View.Tests.ps1).
.NOTES     The subst env's BkpPath is a bare drive root, and a view must lie
           OUTSIDE the backup root on the SAME volume - impossible when the
           root owns the whole drive. So this suite nests its roots one level
           down (X:\bkp etc.), which is also the realistic deployment shape.
#>
function Invoke-G10 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G10-View'

    Reset-TestEnvironment $Env
    $S   = Join-Path $Env.SrcPath 'src'
    $bkp = Join-Path $Env.BkpPath 'bkp'
    $chg = Join-Path $Env.ChgPath 'chg'
    $view = "$bkp" + '_View'
    New-Item -ItemType Directory -Path $S -Force | Out-Null
    $cfg = Join-Path $Env.Root 'cfg-g10.xml'
    Write-TestConfig $cfg $S $bkp $chg $Compress -BrowseView 'index'

    # ---- a 3-run timeline: add, edit, delete -------------------------------
    New-TestFile (Join-Path $S 'doc.txt') 'ONE'
    New-TestFile (Join-Path $S 'sub\nested.txt') 'NESTED'
    New-TestFile (Join-Path $S 'dup1.bin') 'SAME-BYTES'
    New-TestFile (Join-Path $S 'sub\dup2.bin') 'SAME-BYTES'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2024-01-01 00:00:01') | Out-Null
    New-TestFile (Join-Path $S 'doc.txt') 'TWO'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2024-02-02 00:00:02') | Out-Null
    Remove-Item -LiteralPath (Join-Path $S 'sub\nested.txt') -Force
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2024-03-03 00:00:03') | Out-Null

    $manifest = Join-Path $bkp 'MANIFEST.csv'
    $rows = @(Import-Csv -LiteralPath $manifest)

    # G10.1 (TC-129): the TSV mirrors the manifest exactly - every logical
    # path, including both dedup siblings.
    Assert-True $suite $group 'G10.1' 'Tsv_mirrors_manifest' {
        $tsvRel = @(Get-Content -LiteralPath (Join-Path $view 'INDEX.tsv') | Select-Object -Skip 1 |
                    ForEach-Object { ($_ -split "`t")[0] })
        $tsvRel.Count -eq $rows.Count -and
        @($rows | Where-Object { $tsvRel -notcontains $_.RelativePath }).Count -eq 0
    }
    Assert-True $suite $group 'G10.1' 'Both_dedup_siblings_listed' {
        $tsv = Get-Content -LiteralPath (Join-Path $view 'INDEX.tsv') -Raw
        $tsv -match [regex]::Escape('dup1.bin') -and $tsv -match [regex]::Escape('dup2.bin')
    }
    # G10.2 (TC-129): one page per folder; a sampled href on the sub page
    # decodes and resolves to that row's real pool object.
    Assert-True $suite $group 'G10.2' 'Page_per_folder' {
        (Test-Path -LiteralPath (Join-Path $view 'INDEX.html') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $view 'sub\INDEX.html') -PathType Leaf)
    }
    Assert-True $suite $group 'G10.2' 'Href_resolves_to_pool_object' {
        $page = Join-Path $view 'sub\INDEX.html'
        $html = Get-Content -LiteralPath $page -Raw
        $ok = $true; $found = 0
        foreach ($m in [regex]::Matches($html, 'href="([^"]+)"')) {
            $h = $m.Groups[1].Value
            if ($h -like '*INDEX.html') { continue }
            $found++
            $full = [IO.Path]::GetFullPath((Join-Path (Split-Path $page -Parent) ([Uri]::UnescapeDataString($h) -replace '/', '\')))
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $ok = $false }
        }
        $ok -and $found -gt 0
    }
    # G10.3 (TC-131): the deleted row's entry is GONE (regeneration drops
    # stale entries) and the stamp is present (written last).
    Assert-True $suite $group 'G10.3' 'Removed_row_dropped' {
        (Get-Content -LiteralPath (Join-Path $view 'INDEX.tsv') -Raw) -notmatch [regex]::Escape('nested.txt')
    }
    Assert-True $suite $group 'G10.3' 'Viewstamp_present' {
        Test-Path -LiteralPath (Join-Path $view '.viewstamp') -PathType Leaf
    }
    # G10.4 (TC-130): the view is invisible - the store verifies clean and the
    # pool audits hold with the view sitting beside the root.
    Assert-True $suite $group 'G10.4' 'Verify_clean_with_view' {
        @(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg).Count -eq 0
    }
    Assert-True $suite $group 'G10.4' 'ClaimedRows_clean_with_view' {
        @(Get-ClaimedRowViolations -BackupRoot $bkp -ChangeRoot $chg).Count -eq 0
    }
    # G10.5 (TC-133): snapshots hold no view artifacts.
    Assert-True $suite $group 'G10.5' 'Snapshots_view_free' {
        $bad = 0
        foreach ($snap in @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -match '^Snapshot_')) {
            $bad += @(Get-ChildItem -LiteralPath $snap.FullName -Recurse -Force |
                      Where-Object { $_.Name -in 'INDEX.html', 'INDEX.tsv', '.viewstamp' }).Count
        }
        $bad -eq 0
    }
}
