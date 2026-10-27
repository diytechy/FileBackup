$ErrorActionPreference = 'Stop'
Import-Module "C:\Projects\FileBackup\Modules\FileBackup.Common.psm1" -Force
$src = Get-XxHashDllPath
$dir = Join-Path $PSScriptRoot 'kit'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$dst = Join-Path $dir 'System.IO.Hashing.dll'
Copy-Item -LiteralPath $src -Destination $dst -Force
# Child process loads the bundled copy, as RECONSTRUCT.ps1 run from the backup root would, and stays alive.
$child = Start-Process pwsh -ArgumentList '-NoProfile','-Command',"Add-Type -Path '$dst'; [System.IO.Hashing.XxHash128] | Out-Null; Start-Sleep 20" -PassThru -WindowStyle Hidden
Start-Sleep 6
try { Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop; "COPY-OVER-LOADED: succeeded" } catch { "COPY-OVER-LOADED: FAILED - $($_.Exception.Message)" }
$child | Stop-Process -Force
