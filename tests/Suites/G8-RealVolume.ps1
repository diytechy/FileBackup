<#
.SYNOPSIS  G8 - Real-volume-only scenarios.
.NOTES     Skipped under Subst / VHDX backends.
#>
function Invoke-G8 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G8-RealVolume'

    if ($Env.Backend -ne 'RealUSB') {
        Add-TestResult $suite $group 'G8.0' 'BackendNotRealUSB' 'SKIP' "Current backend: $($Env.Backend)"
        return
    }

    $cfg = Join-Path $env:TEMP 'cfg-g8.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    # G8.1 capacity sanity
    Assert-True $suite $group 'G8.1' 'VolumesPresent_andLabeled' {
        @($Env.SrcPath, $Env.BkpPath, $Env.ChgPath, $Env.ReconPath) | ForEach-Object { Test-Path $_ } |
            Where-Object { -not $_ } | Measure-Object | ForEach-Object Count -eq 0
    }

    # G8.2 single-pass backup on real disks
    New-TestFile (Join-Path $Env.SrcPath 'real.txt') 'real-volume content'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G8.2' 'RealBackup_rowPresent' (Join-Path $Env.BkpPath 'MANIFEST.csv') 'real.txt' $true
}
