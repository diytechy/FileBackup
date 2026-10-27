param([Parameter(Mandatory)][string]$StoreDir)
# Experiment C: a sibling snapshot that cannot be listed (stands in for an ACL /
# uid problem on a copied store or a directory the drive cannot read). Restoring
# the older snapshot needs an object that lives in it.
$ErrorActionPreference = 'Stop'
$work = "$StoreDir-C"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
Copy-Item -LiteralPath $StoreDir -Destination $work -Recurse
$snaps = @(Get-ChildItem -LiteralPath (Join-Path $work 'changes') -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name)
$older = $snaps[0].FullName; $newer = $snaps[1].FullName
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls $newer /deny "${me}:(RD)" | Out-Null
try {
    $t = Join-Path $work 'restoreC'
    & pwsh -NoProfile -File (Join-Path $older 'RECONSTRUCT.ps1') -TargetRoot $t -NonInteractive -ExitCode *> (Join-Path $work 'restoreC.out')
    "PS restore exit $LASTEXITCODE"
    Get-Content (Join-Path $t 'RECONSTRUCT.log') | Select-String 'WARN|ERROR|INCOMPLETE' | ForEach-Object { $_.Line }
} finally {
    & icacls $newer /remove:d "$me" | Out-Null
}
