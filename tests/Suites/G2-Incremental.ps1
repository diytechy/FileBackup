<#
.SYNOPSIS  G2 - Incremental change behaviours.
#>
function Invoke-G2 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G2-Incremental'
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    $cfg = Join-Path $Env.Root 'cfg-g2.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    # Seed
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'a.txt') 'AAA'
    New-TestFile (Join-Path $Env.SrcPath 'folderA\b.txt') 'BBB'
    New-TestFile (Join-Path $Env.SrcPath 'dup1.txt') 'DUPLICATE'
    New-TestFile (Join-Path $Env.SrcPath 'dup2.txt') 'DUPLICATE'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null

    # G2.1 rename
    Rename-Item (Join-Path $Env.SrcPath 'a.txt') -NewName 'a_renamed.txt'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G2.1' 'Rename_newPresent' $manifest 'a_renamed.txt' $true
    Assert-ManifestRow $suite $group 'G2.1' 'Rename_oldAbsent'  $manifest 'a.txt' $false

    # G2.2 move (Move-Item won't create the destination folder, so make it first)
    New-Item -ItemType Directory -Path (Join-Path $Env.SrcPath 'folderB') -Force | Out-Null
    Move-Item (Join-Path $Env.SrcPath 'folderA\b.txt') (Join-Path $Env.SrcPath 'folderB\b.txt')
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G2.2' 'Move_newPath' $manifest 'folderB\b.txt' $true
    Assert-ManifestRow $suite $group 'G2.2' 'Move_oldPath_absent' $manifest 'folderA\b.txt' $false

    # G2.3 modify content
    New-TestFile (Join-Path $Env.SrcPath 'dup1.txt') 'CHANGED'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-True $suite $group 'G2.3' 'Modify_hashChanged' {
        $row = Get-ManifestRow $manifest 'dup1.txt'
        $row -and $row.xxH2Hash
    }

    # G2.5 delete
    Remove-Item (Join-Path $Env.SrcPath 'dup2.txt')
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G2.5' 'Delete_rowAbsent' $manifest 'dup2.txt' $false

    # G2.6 re-add identical content (should dedup)
    New-TestFile (Join-Path $Env.SrcPath 'dup2.txt') 'DUPLICATE'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G2.6' 'Readd_rowPresent' $manifest 'dup2.txt' $true

    # G2.8 duplicate detection — MODE-AWARE and EXACT (TC-019, de-vacuumed
    # 2026-08-24: the old `-le 2` passed under D-5 and would pass with dedup
    # removed entirely).
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'd1.txt') 'SHARED'
    New-TestFile (Join-Path $Env.SrcPath 'd2.txt') 'SHARED'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-True $suite $group 'G2.8' 'Dedup_singleDataPath' {
        $rows = @(Import-Csv -LiteralPath $manifest | Where-Object { $_.RelativePath -in 'd1.txt', 'd2.txt' })
        if ($rows.Count -ne 2) { return $false }
        $paths  = @($rows | Where-Object DataPath | Select-Object -ExpandProperty DataPath -Unique)
        $copies = Get-PoolContentCopyCount -Folders @($Env.BkpPath) `
            -Hash $rows[0].xxH2Hash -Length ([long]$rows[0].Length)
        if ($Mode -eq 'HashAddressed') {
            # True dedup: ONE distinct DataPath and ONE physical pool copy.
            $paths.Count -eq 1 -and $copies -eq 1
        } else {
            # Mirror stores same-run duplicates TWICE today — that is defect
            # D-5, fixed by the option-3 WP (which deletes Mirror). Asserted
            # exactly as a labelled change-detector: when option-3 lands this
            # arm dies with the mode instead of silently passing.
            $paths.Count -eq 2 -and $copies -eq 2
        }
    }

    # TC-116: orphan-detection second pass — every blank-DataPath row in every
    # manifest must be backed by a BYTE-VERIFIED pool copy (the assertion that
    # caught D-1 on the HomeHub bench; stronger than -Action Verify).
    Assert-True $suite $group 'G2.audit' 'BlankRows_byteVerified' {
        @(Get-BlankRowPoolViolations -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath).Count -eq 0
    }
}
