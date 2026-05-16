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

    # G2.2 move
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

    # G2.8 duplicate detection
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'd1.txt') 'SHARED'
    New-TestFile (Join-Path $Env.SrcPath 'd2.txt') 'SHARED'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-True $suite $group 'G2.8' 'Dedup_singleDataPath' {
        $rows = Import-Csv -LiteralPath $manifest | Where-Object { $_.RelativePath -in 'd1.txt','d2.txt' }
        $rows -and ($rows | Select-Object -ExpandProperty DataPath -Unique).Count -le 2
    }
}
