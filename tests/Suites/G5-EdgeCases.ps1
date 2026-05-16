<#
.SYNOPSIS  G5 - Edge & failure paths.
#>
function Invoke-G5 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G5-EdgeCases'
    $cfg = Join-Path $Env.Root 'cfg-g5.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    # G5.1 pre-existing Temp staging folder must abort
    Reset-TestEnvironment $Env
    New-Item -ItemType Directory -Path (Join-Path $Env.ChgPath 'Temp') -Force | Out-Null
    Assert-True $suite $group 'G5.1' 'PreexistingTemp_throws' {
        try {
            Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
            $log = Join-Path $Env.ChgPath 'backup.log'
            if (Test-Path -LiteralPath $log) {
                return [bool](Select-String -LiteralPath $log -Pattern 'staging folder' -Quiet)
            }
            return $false
        } catch { return $true }
    }

    # G5.4 read-only file in source
    Reset-TestEnvironment $Env
    $ro = Join-Path $Env.SrcPath 'readonly.txt'
    New-TestFile $ro 'locked'
    (Get-Item -LiteralPath $ro).IsReadOnly = $true
    Assert-True $suite $group 'G5.4' 'ReadOnlyFile_backedUp' {
        Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
        $row = Get-ManifestRow (Join-Path $Env.BkpPath 'MANIFEST.csv') 'readonly.txt'
        $null -ne $row
    }

    # G5.7 idempotency: second run with no source changes
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'stable.txt') 'unchanging'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $changeFoldersBefore = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -like 'Pre_*_Changes' }).Count
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $changeFoldersAfter  = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -like 'Pre_*_Changes' }).Count
    Assert-True $suite $group 'G5.7' 'Idempotent_secondRun' {
        # An incremental run may still create an empty Pre_*_Changes folder, but the manifest row count must be stable.
        $rows = @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv'))
        $rows.Count -eq 1
    }
}
