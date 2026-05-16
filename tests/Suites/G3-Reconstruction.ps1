<#
.SYNOPSIS  G3 - Reconstruction roundtrip.
#>
function Invoke-G3 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G3-Reconstruction'
    $cfg = Join-Path $Env.Root 'cfg-g3.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress ($Mode -eq 'HashAddressed')

    Reset-TestEnvironment $Env
    $srcFiles = @(
        @{ Rel='r1.txt';            Content='one' },
        @{ Rel='sub\r2.txt';        Content='two' },
        @{ Rel='deep\a\b\c\r3.bin'; Content=([string]([char[]](65..90) -join '')) }
    )
    foreach ($f in $srcFiles) {
        New-TestFile (Join-Path $Env.SrcPath $f.Rel) $f.Content
    }
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null

    # G3.1 reconstruct from backup root
    $reconScript = Join-Path $Env.BkpPath 'RECONSTRUCT.ps1'
    Assert-True $suite $group 'G3.1' 'ReconScript_exists' { Test-Path -LiteralPath $reconScript }

    if (Test-Path -LiteralPath $reconScript) {
        Invoke-Reconstruct -ReconstructScript $reconScript -TargetRoot $Env.ReconPath
        foreach ($f in $srcFiles) {
            $expected = Join-Path $Env.SrcPath   $f.Rel
            $actual   = Join-Path $Env.ReconPath $f.Rel
            Assert-FilesByteEqual $suite $group ('G3.1-'+$f.Rel) ('Roundtrip_'+$f.Rel) $expected $actual
        }
    }

    # G3.5 hash-fallback - blank a DataPath, ensure file still recovers
    $bkpManifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    if (Test-Path -LiteralPath $bkpManifest) {
        $rows = Import-Csv -LiteralPath $bkpManifest
        if ($rows.Count -gt 0) {
            $target = $rows[0]
            $origDataPath = $target.DataPath
            $target.DataPath = ''
            $rows | Export-Csv -LiteralPath $bkpManifest -NoTypeInformation

            Get-ChildItem -LiteralPath $Env.ReconPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Invoke-Reconstruct -ReconstructScript $reconScript -TargetRoot $Env.ReconPath

            Assert-True $suite $group 'G3.5' 'HashFallback_recoveredFile' {
                Test-Path -LiteralPath (Join-Path $Env.ReconPath $target.RelativePath) -PathType Leaf
            }

            # restore
            $target.DataPath = $origDataPath
            $rows | Export-Csv -LiteralPath $bkpManifest -NoTypeInformation
        }
    }

    # G3.6 target = subpath of backup must throw
    Assert-True $suite $group 'G3.6' 'BadTarget_rejected' {
        try {
            & $reconScript -TargetRoot (Join-Path $Env.BkpPath 'inside') 2>&1 | Out-Null
            return $false  # should have thrown
        } catch { return $true }
    }
}
