param([Parameter(Mandatory)][string]$Root, [int]$KeepBytes = 700)
# Experiment A: a snapshot manifest whose tail reads as NULs (what NTFS shows for
# a file whose size reached the disk but whose data did not), then restore it.
$ErrorActionPreference = 'Stop'
$work = "$Root-A"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
Copy-Item -LiteralPath $Root -Destination $work -Recurse
$snap = Get-ChildItem -LiteralPath (Join-Path $work 'store\changes') -Directory | Where-Object Name -like 'Snapshot_*' | Select-Object -First 1
$m = Join-Path $snap.FullName 'MANIFEST.csv'
$bytes = [IO.File]::ReadAllBytes($m)
"manifest bytes $($bytes.Length), rows " + ((Get-Content -LiteralPath $m).Count - 1)
for ($i = $KeepBytes; $i -lt $bytes.Length; $i++) { $bytes[$i] = 0 }
[IO.File]::WriteAllBytes($m, $bytes)
$t = Join-Path $work 'restore'
& pwsh -NoProfile -File (Join-Path $snap.FullName 'RECONSTRUCT.ps1') -TargetRoot $t -NonInteractive -ExitCode *> (Join-Path $work 'restoreA.out')
"PS restore exit $LASTEXITCODE"
"files restored: " + (@(Get-ChildItem -LiteralPath $t -Recurse -File | Where-Object Name -ne 'RECONSTRUCT.log').Count) + " of 13"
Get-Content (Join-Path $t 'RECONSTRUCT.log') | Select-Object -Last 6
