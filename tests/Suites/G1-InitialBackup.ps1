<#
.SYNOPSIS  G1 - Initial-backup behaviours.
.NOTES     Invoked by Run-All.ps1. Expects $Env (backend), $BackupScript, $Mode, $Compress.
#>
function Invoke-G1 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G1-InitialBackup'

    # ---- G1.1 Empty source ----
    Reset-TestEnvironment $Env
    $cfg = Join-Path $Env.Root 'cfg-g1.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    Assert-True $suite $group 'G1.1' 'EmptySource_completes' {
        try { Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null; $true }
        catch { $script:G1_1_err = $_.Exception.Message; $false }
    }

    # ---- G1.2 Single file ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'single.txt') 'Hello'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.2' 'Single_present' (Join-Path $Env.BkpPath 'MANIFEST.csv') 'single.txt' $true

    # ---- G1.3 Many small files ----
    Reset-TestEnvironment $Env
    1..200 | ForEach-Object {
        New-TestFile (Join-Path $Env.SrcPath ("bulk\f{0:000}.txt" -f $_)) ("payload $_")
    }
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    Assert-True $suite $group 'G1.3' 'BulkFiles_200rows' {
        if (-not (Test-Path -LiteralPath $manifest)) { return $false }
        @(Import-Csv -LiteralPath $manifest).Count -ge 200
    }

    # ---- G1.5 Source contains a literal MANIFEST.csv at a sub-path (regression for B6) ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'sub\MANIFEST.csv') 'fake,manifest,row'
    New-TestFile (Join-Path $Env.SrcPath 'sub\other.txt')    'real payload'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    # NOTE: today FileBackup.ps1 filters by Name only — this assertion exposes bug B6.
    Assert-ManifestRow $suite $group 'G1.5' 'NestedManifest_preserved' $manifest 'sub\MANIFEST.csv' $true

    # ---- G1.6 Unicode filenames ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'Δοκιμή.txt') 'unicode-greek'
    New-TestFile (Join-Path $Env.SrcPath '测试.bin')   'unicode-chinese'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.6' 'Unicode_Greek'   $manifest 'Δοκιμή.txt' $true
    Assert-ManifestRow $suite $group 'G1.6' 'Unicode_Chinese' $manifest '测试.bin'  $true

    # ---- G1.8 Brackets/parentheses ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'folder[1]\file(2).txt') 'special-chars'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.8' 'SpecialChars_present' $manifest 'folder[1]\file(2).txt' $true
}
