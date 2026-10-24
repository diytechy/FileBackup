<#
.SYNOPSIS  G8 - Real-volume-only scenarios.
.NOTES     Skipped under Subst / VHDX backends.

           G8.3-G8.5 (TC-194, the SR-075 stale-staging reclaim on exFAT) were
           removed with that machinery: the bounded backup run keeps no staging
           folder to reclaim (docs/plans/bounded-run-loop.md).
#>

function Invoke-G8 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G8-RealVolume'

    if ($Env.Backend -ne 'RealUSB') {
        Add-TestResult $suite $group 'G8.0' 'BackendNotRealUSB' 'SKIP' "Current backend: $($Env.Backend)"
        return
    }

    $cfg = Join-Path $env:TEMP 'cfg-g8.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress

    # G8.1 capacity sanity. (The original one-liner ended in
    # `Measure-Object | ForEach-Object Count -eq 0`, which binds 'Count' as a
    # METHOD name on the always-emitted GenericMeasureInfo and threw — so this
    # arm could never pass under the only backend that runs it.)
    Assert-True $suite $group 'G8.1' 'VolumesPresent_andLabeled' {
        $missing = @(@($Env.SrcPath, $Env.BkpPath, $Env.ChgPath, $Env.ReconPath) |
            Where-Object { -not (Test-Path -LiteralPath $_) })
        $missing.Count -eq 0
    }

    # G8.2 single-pass backup on real disks
    New-TestFile (Join-Path $Env.SrcPath 'real.txt') 'real-volume content'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G8.2' 'RealBackup_rowPresent' (Join-Path $Env.BkpPath 'MANIFEST.csv') 'real.txt' $true
}
