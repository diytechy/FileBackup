# Repro: a restore started from the backup root's kit (it loads the bundled
# System.IO.Hashing.dll) makes the next scheduled backup fail at step 3.
# Store lives under %TEMP%; nothing is written into the repository.
$ErrorActionPreference = 'Stop'
$repo  = 'C:\Projects\FileBackup'
$base  = Join-Path $env:TEMP ('fb-rbb-' + [guid]::NewGuid().ToString('N'))
$src   = Join-Path $base 'src'
$store = Join-Path $base 'store'
New-Item -ItemType Directory -Path $src, $store | Out-Null
Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'hello one'
$cfg = Join-Path $base 'cfg.json'
@{
    ConfigVersion = 2
    BackupSets = @(@{ Name = 'T'; SourcePath = $src; BackupPath = (Join-Path $store 'backup'); ChangePath = (Join-Path $store 'changes')
                      HashRecalcFreq = 'N'; CompressEnabled = $false })
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfg

pwsh -NoProfile -File (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive -ExitCode | Out-Null
"run 1 exit: $LASTEXITCODE"

$bkp = Join-Path $store 'backup'
# What RECONSTRUCT.ps1 does first: import the bundled Common, hash (loads the bundled DLL).
$job = Start-Job -ScriptBlock {
    param($b)
    Import-Module (Join-Path $b 'FileBackup.Common.psm1') -Force
    [void](Get-FileXxHash -FilePath (Join-Path $b 'MANIFEST.csv'))
    Start-Sleep -Seconds 60
} -ArgumentList $bkp
Start-Sleep -Seconds 8

Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'hello two'
pwsh -NoProfile -File (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive -ExitCode | Out-Null
"run 2 (restore process alive) exit: $LASTEXITCODE"
Get-Content -LiteralPath (Join-Path $store 'changes\backup.log') | Select-String -Pattern 'did not finish|ERROR' | ForEach-Object { "  log: $($_.Line)" }

Stop-Job $job; Remove-Job $job -Force
Start-Sleep -Seconds 1
pwsh -NoProfile -File (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive -ExitCode | Out-Null
"run 3 (restore process gone) exit: $LASTEXITCODE"
try { Remove-Item -LiteralPath $base -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
