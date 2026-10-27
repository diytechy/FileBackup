param([Parameter(Mandatory)][string]$StoreDir)
# Experiment D: the residue an interrupted prune leaves ('<object>.fbprune.tmp',
# Copy-ReHomedDataFile, Engine.psm1:2560) in the destination folder - here a
# truncated copy, as a kill mid-copy leaves it - while the intact original is
# still in the snapshot being pruned. Restore the destination snapshot.
$ErrorActionPreference = 'Stop'
$work = "$StoreDir-D"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
Copy-Item -LiteralPath $StoreDir -Destination $work -Recurse
$snaps = @(Get-ChildItem -LiteralPath (Join-Path $work 'changes') -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name)
$older = $snaps[0].FullName; $newer = $snaps[1].FullName
$orig = Get-ChildItem -LiteralPath $newer -File | Where-Object Name -like '*_*.7z' | Select-Object -First 1
"original object in newer snapshot: $($orig.Name) ($($orig.Length) bytes)"
$bytes = [IO.File]::ReadAllBytes($orig.FullName)
$half = New-Object byte[] ([int]($bytes.Length / 2)); [Array]::Copy($bytes, $half, $half.Length)
[IO.File]::WriteAllBytes((Join-Path $older ($orig.Name + '.fbprune.tmp')), $half)
$t = Join-Path $work 'restoreD'
& pwsh -NoProfile -File (Join-Path $older 'RECONSTRUCT.ps1') -TargetRoot $t -NonInteractive -ExitCode *> (Join-Path $work 'restoreD.out')
"PS restore of the older snapshot: exit $LASTEXITCODE"
Get-Content (Join-Path $t 'RECONSTRUCT.log') | Select-String 'f02|INCOMPLETE' | ForEach-Object { $_.Line }
