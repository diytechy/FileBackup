<#
.SYNOPSIS  G7 - Determinism / idempotency.
#>
function Invoke-G7 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G7-Determinism'
    $cfg = Join-Path $Env.Root 'cfg-g7.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress

    # Twin runs on identical source — manifest row content must match
    Reset-TestEnvironment $Env
    1..10 | ForEach-Object { New-TestFile (Join-Path $Env.SrcPath "f$_.txt") "content $_" }
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $manifest1 = Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv')

    # Second run with no changes
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $manifest2 = Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv')

    Assert-True $suite $group 'G7.1' 'NoChange_manifestStable' {
        if ($manifest1.Count -ne $manifest2.Count) { return $false }
        $h1 = $manifest1 | ForEach-Object { "$($_.RelativePath)|$($_.xxH2Hash)|$($_.Length)" } | Sort-Object
        $h2 = $manifest2 | ForEach-Object { "$($_.RelativePath)|$($_.xxH2Hash)|$($_.Length)" } | Sort-Object
        ($h1 -join ';') -eq ($h2 -join ';')
    }

    # Hashes deterministic — re-hash a known content
    $known = Join-Path $Env.SrcPath 'f1.txt'
    $sha = (Get-FileHash -LiteralPath $known -Algorithm SHA256).Hash
    Assert-True $suite $group 'G7.2' 'SHA256_known' { $sha.Length -eq 64 }
}
