# Repro: -Action Verify -RepairStorage moves objects while another process holds
# the store's OS lock (Temp.lock). Store under %TEMP%; repo untouched.
$ErrorActionPreference = 'Stop'
$repo  = 'C:\Projects\FileBackup'
$fb    = Join-Path $repo 'FileBackup.ps1'
$base  = Join-Path $env:TEMP ('fb-vlr-' + [guid]::NewGuid().ToString('N'))
$src   = Join-Path $base 'src'
$store = Join-Path $base 'store'
$bkp   = Join-Path $store 'backup'
$chg   = Join-Path $store 'changes'
New-Item -ItemType Directory -Path $src, $store | Out-Null
$cfg = Join-Path $base 'cfg.json'
@{
    ConfigVersion = 2
    BackupSets = @(@{ Name = 'T'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
                      HashRecalcFreq = 'N'; CompressEnabled = $false })
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfg
function Invoke-Run([string]$When) { pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -BackupTime $When | Out-Null; $LASTEXITCODE }
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value 'f one'
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g one'
"run1: $(Invoke-Run '2026-01-01T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g two'
"run2: $(Invoke-Run '2026-01-02T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value 'f two'
"run3: $(Invoke-Run '2026-01-03T01:00:00')"
$snaps = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name)
# The precondition R10 says older stores have: the same object in two folders.
$obj = Get-ChildItem -LiteralPath $snaps[1].FullName -File | Where-Object Name -match '^[2-9A-HJ-NP-Za-km-z]{22}_' | Select-Object -First 1
Copy-Item -LiteralPath $obj.FullName -Destination $snaps[0].FullName
"duplicate placed: $($obj.Name) in $($snaps[0].Name) and $($snaps[1].Name)"

# Another FileBackup (a backup or prune) holds the OS lock.
$lock = Join-Path $chg 'Temp.lock'
$job = Start-Job -ScriptBlock { return
    param($p)
    $s = [System.IO.FileStream]::new($p, 'OpenOrCreate', 'Read', 'None')
    Start-Sleep -Seconds 60
    $s.Dispose()
} -ArgumentList $lock
Start-Sleep -Seconds 6
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Verify -RepairStorage -WhatIf | Out-Null
"verify -RepairStorage -WhatIf, no lock held: exit $LASTEXITCODE"
Get-Content -LiteralPath (Join-Path $base 'Backup_Global.log') | Select-String 'moved|Refusing|Moved' | ForEach-Object { "  log: $($_.Line)" }
"Verify folder now holds: " + ((Get-ChildItem -LiteralPath (Join-Path $chg 'Verify') -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($chg.Length) }) -join ', ')
Stop-Job $job; Remove-Job $job -Force
try { Remove-Item -LiteralPath $base -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
