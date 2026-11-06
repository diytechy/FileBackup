<#
.SYNOPSIS
Exercises both independent native-metadata recovery routes on a small real store.
#>
[CmdletBinding()]
param([string]$ScratchRoot = 'D:\FileBackupBuild\tmp', [switch]$WithWsl)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'Modules/FileBackup.Common.psm1') -Force
$run = Join-Path $ScratchRoot ('recovery-contract-' + [guid]::NewGuid().ToString('N'))
$store = Join-Path $run 'store'
$latest = Join-Path $store 'CurrentBackup'
New-Item -ItemType Directory -Force $latest,(Join-Path $store 'BackupHistory') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'recovery/Reconstruct.ps1') -Destination (Join-Path $latest 'RECONSTRUCT.ps1')
Copy-Item -LiteralPath (Join-Path $repo 'recovery/reconstruct.sh') -Destination $latest
Copy-Item -LiteralPath (Join-Path $repo 'bash/reconstruct.sh') -Destination (Join-Path $latest 'reconstruct-core.sh')
Copy-Item -LiteralPath (Join-Path $repo 'Modules/FileBackup.Common.psm1') -Destination $latest
Copy-Item -LiteralPath (Get-XxHashDllPath) -Destination $latest
foreach ($name in 'path-keys.tsv','path-keys.awk','THIRD-PARTY-NOTICES.txt') { Copy-Item -LiteralPath (Join-Path $repo "recovery/$name") -Destination $latest }
$inventory = Get-ChildItem -LiteralPath $latest -File | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.Name }
[IO.File]::WriteAllText((Join-Path $latest 'KIT.sha256'), ($inventory -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
$source = Join-Path $run 'payload.txt'
[IO.File]::WriteAllText($source, 'independent native recovery payload')
$hash = Get-FileXxHash -FilePath $source
$length = (Get-Item -LiteralPath $source).Length
$name = Get-HashSizeFileName -Hash $hash -Length $length -Extension '.txt'
$shard = Join-Path $latest $name.Substring(0,2).ToLowerInvariant()
New-Item -ItemType Directory -Force $shard | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $shard $name)
$rows = foreach ($relative in 'nested/u[é],file.txt','duplicate.txt','kapı.txt','kapi.txt','İ.txt','i.txt') {
    [pscustomobject]@{DataPath=$name;RelativePath=$relative;Length="$length";LastWriteTimeStr='2026-11-06T10:00:00.0000000Z';xxH2Hash=$hash;Compressed='No';StoredAsHashSize='Hash';Duplicate='';MediaMBPerSec=''}
}
$rows | Export-Csv -LiteralPath (Join-Path $latest 'MANIFEST.csv') -NoTypeInformation
$dirs = @(
    # 'nested' is implied by its file path; both readers must accept this link target.
    [pscustomobject]@{RelativePath='empty';Attributes='';EntryKind='Directory';LinkTarget=''},
    [pscustomobject]@{RelativePath='relative-link';Attributes='';EntryKind='FolderLink';LinkTarget='nested'}
)
$dirs | Export-Csv -LiteralPath (Join-Path $latest 'DIRECTORIES.csv') -NoTypeInformation
$psTarget = Join-Path $run 'powershell'
& pwsh -NoProfile -File (Join-Path $latest 'RECONSTRUCT.ps1') -TargetRoot $psTarget -NonInteractive -ExitCode
if ($LASTEXITCODE -ne 0) { throw "PowerShell recovery failed: $LASTEXITCODE" }
foreach ($relative in $rows.RelativePath) {
    if ((Get-FileXxHash -FilePath (Join-Path $psTarget $relative)) -ne $hash) { throw "PowerShell byte mismatch: $relative" }
}
if (-not (Test-Path -LiteralPath (Join-Path $psTarget 'empty') -PathType Container)) { throw 'Empty directory was not restored.' }
if ($WithWsl) {
    $linuxRoot = '/mnt/' + $run.Substring(0,1).ToLowerInvariant() + $run.Substring(2).Replace('\','/')
    & wsl -d Ubuntu -- bash "$linuxRoot/store/CurrentBackup/reconstruct.sh" --target-root "$linuxRoot/bash"
    if ($LASTEXITCODE -ne 0) { throw "bash recovery failed: $LASTEXITCODE" }
    foreach ($relative in $rows.RelativePath) {
        if ((Get-FileXxHash -FilePath (Join-Path (Join-Path $run 'bash') $relative)) -ne $hash) { throw "bash byte mismatch: $relative" }
    }
    & wsl -d Ubuntu -- test -L "$linuxRoot/bash/relative-link"
    if ($LASTEXITCODE -ne 0) { throw 'bash did not recreate the relative directory link.' }
}
# Required sidecar damage must be incomplete, without losing independent files.
Remove-Item -LiteralPath (Join-Path $latest 'DIRECTORIES.csv')
& pwsh -NoProfile -File (Join-Path $latest 'RECONSTRUCT.ps1') -TargetRoot (Join-Path $run 'missing-metadata') -NonInteractive -ExitCode
if ($LASTEXITCODE -ne 1) { throw 'Missing native metadata did not report incomplete.' }
Write-Output "Native recovery contract fixtures passed; inspect $run"
