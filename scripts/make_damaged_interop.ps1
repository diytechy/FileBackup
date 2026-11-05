<#
.SYNOPSIS
    Builds the TC-110 damaged-store interop fixtures and records the
    PowerShell restorer's verdicts for the Linux half to compare against.

.DESCRIPTION
    Takes the FRESH HashAddressed backup produced by gen_bash_fixtures.ps1
    -Fresh (kit intact) and derives two damaged stores under <OutRoot>/damage:

      heal/  — one data file's bytes replaced by same-length WRONG bytes,
               with a good copy parked elsewhere in the pool: the kit-rev-6
               verify-after-write must heal it (exit 0, byte-exact, warning
               logged).
      gone/  — the same damage with NO surviving copy: exit 1, row named.

    Each store is then restored HERE with its own deployed RECONSTRUCT.ps1
    -NonInteractive -ExitCode, and the observed exit code plus the xxHash128
    of every restored file are written to <OutRoot>/damage/expected.tsv.
    tests/bash/verify_damage_interop.sh restores the same stores on Linux
    and demands identical exit codes and identical bytes (SR-056, SR-031).
#>
# Implements: SR-056, SR-031 (TC-110)
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutRoot)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force

# A whole store (plan C44): CurrentBackup, its objects in shard folders, and the
# snapshots beside it. Each damaged copy is a store of its own.
$src = Join-Path $OutRoot 'bash-restore\HashAddressed\store'
$srcLatest = Join-Path $src 'CurrentBackup'
if (-not (Test-Path -LiteralPath $srcLatest -PathType Container)) {
    throw "Fresh HashAddressed store not found at '$src' — run scripts/gen_bash_fixtures.ps1 -Fresh -OutRoot $OutRoot first."
}
$damageRoot = Join-Path $OutRoot 'damage'
Remove-Item -LiteralPath $damageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $damageRoot -Force | Out-Null

# Pick a raw (Compressed=No) row whose DataPath resolves — the damage target.
$rows = @(Import-Csv -LiteralPath (Join-Path $srcLatest 'MANIFEST.csv'))
$victim = $rows | Where-Object {
    $_.Compressed -eq 'No' -and $_.DataPath -and
    (Test-Path -LiteralPath (Get-StoredObjectPath -Folder $srcLatest -Name $_.DataPath -Sharded) -PathType Leaf) -and
    [long]$_.Length -gt 0
} | Select-Object -First 1
if (-not $victim) { throw 'No raw resolvable row found to damage.' }

$results = New-Object System.Collections.Generic.List[string]
foreach ($shape in 'heal', 'gone') {
    $store = Join-Path $damageRoot $shape
    Copy-Item -LiteralPath $src -Destination $store -Recurse -Force
    $latest = Join-Path $store 'CurrentBackup'
    $data = Get-StoredObjectPath -Folder $latest -Name $victim.DataPath -Sharded
    if ($shape -eq 'heal') {
        # Good copy parked in the pool under an unrelated name (found only by
        # the content scan), then damage.
        Copy-Item -LiteralPath $data -Destination (Join-Path $latest 'interop-spare.bin')
    } else {
        # 'gone' must be REALLY gone: a snapshot may hold another copy of these bytes —
        # delete every pool file whose raw (hash,length) matches the victim,
        # except the victim's own data file (which gets corrupted below).
        $victimData = (Resolve-Path -LiteralPath $data).Path
        foreach ($f in @(Get-ChildItem -LiteralPath $store -File -Recurse -Force)) {
            if ($f.FullName -eq $victimData -or $f.Length -ne [long]$victim.Length) { continue }
            try { $match = (Get-FileXxHash -FilePath $f.FullName) -eq $victim.xxH2Hash } catch { $match = $false }
            if ($match) { Remove-Item -LiteralPath $f.FullName -Force }
        }
    }
    $bytes = [IO.File]::ReadAllBytes((Get-StoredObjectPath -Folder $srcLatest -Name $victim.DataPath -Sharded))
    $bytes[0] = $bytes[0] -bxor 0xFF          # same length, wrong bytes
    [IO.File]::WriteAllBytes($data, $bytes)

    # Restore with the store's own deployed kit and record the verdict.
    $target = Join-Path $damageRoot "restored-$shape"
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $latest 'RECONSTRUCT.ps1') `
        -TargetRoot $target -NonInteractive -ExitCode *>&1 | Out-Null
    $code = $LASTEXITCODE
    $results.Add("exit`t$shape`t$code")
    if (Test-Path -LiteralPath $target) {
        foreach ($f in @(Get-ChildItem -LiteralPath $target -File -Recurse -Force |
                         Where-Object Name -ne 'RECONSTRUCT.log')) {
            $rel = $f.FullName.Substring($target.Length).TrimStart('\', '/').Replace('\', '/')
            $results.Add("file`t$shape`t$rel`t$(Get-FileXxHash -FilePath $f.FullName)")
        }
        Remove-Item -LiteralPath $target -Recurse -Force   # only the verdicts travel
    }
    Write-Host "damage[$shape]: PowerShell restorer exit $code"
}
[IO.File]::WriteAllLines((Join-Path $damageRoot 'expected.tsv'), $results)
Write-Host "Wrote $(Join-Path $damageRoot 'expected.tsv') ($($results.Count) lines)."
if ((@($results | Where-Object { $_ -eq "exit`theal`t0" }).Count -ne 1) -or
    (@($results | Where-Object { $_ -eq "exit`tgone`t1" }).Count -ne 1)) {
    throw 'PowerShell verdicts are not the expected heal=0 / gone=1 — do not ship these fixtures.'
}
