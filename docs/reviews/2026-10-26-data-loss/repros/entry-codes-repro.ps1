# Repro: entry-point exit codes for a missing required tool, and for retention
# when the SOURCE is offline. Store under %TEMP%; repo untouched.
$ErrorActionPreference = 'Stop'
$repo  = 'C:\Projects\FileBackup'
$fb    = Join-Path $repo 'FileBackup.ps1'
$base  = Join-Path $env:TEMP ('fb-ecr-' + [guid]::NewGuid().ToString('N'))
$src   = Join-Path $base 'src'
$store = Join-Path $base 'store'
New-Item -ItemType Directory -Path $src, $store | Out-Null
Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
function Write-Cfg([string]$Seven, [bool]$Compress, [string]$Source) {
    $c = @{ ConfigVersion = 2
            BackupSets = @(@{ Name = 'T'; SourcePath = $Source; BackupPath = (Join-Path $store 'backup'); ChangePath = (Join-Path $store 'changes')
                              HashRecalcFreq = 'N'; CompressEnabled = $Compress }) }
    if ($Seven) { $c.Tools = @{ SevenZipPath = $Seven } }
    $c | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $base 'cfg.json')
}
$cfg = Join-Path $base 'cfg.json'
Write-Cfg -Seven 'C:\Program Files\7-Zip\7z.exe' -Compress $true -Source $src
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -BackupTime '2026-01-01T01:00:00' *> $null
"backup, tools present: exit $LASTEXITCODE"
Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'b'
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -BackupTime '2026-01-02T01:00:00' *> $null
"backup 2: exit $LASTEXITCODE"

Write-Cfg -Seven 'C:\nowhere\7z.exe' -Compress $true -Source $src
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode *> $null
"backup, 7-Zip missing (plan section 6 says 2): exit $LASTEXITCODE"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Verify *> $null
"verify, 7-Zip missing (1 means 'findings'): exit $LASTEXITCODE"

Write-Cfg -Seven 'C:\Program Files\7-Zip\7z.exe' -Compress $true -Source (Join-Path $base 'offline-source')
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Snapshots *> $null
"snapshots, source offline: exit $LASTEXITCODE"
$snap = (Get-ChildItem -LiteralPath (Join-Path $store 'changes') -Directory | Where-Object Name -like 'Snapshot_*' | Select-Object -First 1).Name
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Prune -Snapshot $snap *> $null
"prune, source offline (1 means 'batch incomplete, no data lost'): exit $LASTEXITCODE"
"snapshot still there: $(Test-Path -LiteralPath (Join-Path $store "changes\$snap"))"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Verify *> $null
"verify, source offline: exit $LASTEXITCODE"
try { Remove-Item -LiteralPath $base -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
