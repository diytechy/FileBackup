<#
.SYNOPSIS  G4 - SanitizeBackupDatabase / config migration.
.NOTES     Always runs - changes config between two backup runs.
#>
function Invoke-G4 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G4-Sanitization'
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'

    # Seed in Mirror, Compress=Off
    Reset-TestEnvironment $Env
    $cfgMirror = Join-Path $Env.Root 'cfg-g4-mirror.xml'
    Write-TestConfig $cfgMirror $Env.SrcPath $Env.BkpPath $Env.ChgPath $false $false
    New-TestFile (Join-Path $Env.SrcPath 'doc.txt')      'document content'
    New-TestFile (Join-Path $Env.SrcPath 'sub\img.bin')  'binary blob'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfgMirror | Out-Null

    Assert-True $suite $group 'G4.1' 'AfterMirror_filesAtOriginalPath' {
        (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'doc.txt')) -and
        (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'sub\img.bin'))
    }

    # Migrate to HashAddressed
    $cfgHash = Join-Path $Env.Root 'cfg-g4-hash.xml'
    Write-TestConfig $cfgHash $Env.SrcPath $Env.BkpPath $Env.ChgPath $false $true
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfgHash | Out-Null

    Assert-True $suite $group 'G4.1' 'AfterMigrate_originalNamesGone' {
        # In hash-addressed mode files should NOT live at the original paths anymore.
        -not (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'doc.txt'))
    }
    Assert-True $suite $group 'G4.1' 'AfterMigrate_manifestStoredAsHash' {
        $row = Get-ManifestRow $manifest 'doc.txt'
        $row -and $row.StoredAsHashSize -eq 'Hash'
    }
}
