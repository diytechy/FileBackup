# Repro: -RepairStorage renames an object, then is killed before that folder's
# manifest is rewritten. Store under %TEMP%; repo untouched. The kill is the
# Common manifest-write test seam throwing (as the suite stands in for a kill).
$ErrorActionPreference = 'Stop'
$repo  = 'C:\Projects\FileBackup'
$fb    = Join-Path $repo 'FileBackup.ps1'
$base  = Join-Path $env:TEMP ('fb-rkr-' + [guid]::NewGuid().ToString('N'))
$src   = Join-Path $base 'src'
$store = Join-Path $base 'store'
$bkp   = Join-Path $store 'backup'
$chg   = Join-Path $store 'changes'
New-Item -ItemType Directory -Path $src, $store | Out-Null
$cfg = Join-Path $base 'cfg.json'
@{ ConfigVersion = 2
   BackupSets = @(@{ Name = 'T'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg; HashRecalcFreq = 'N'; CompressEnabled = $false }) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfg
function Invoke-Run([string]$When) { pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -BackupTime $When | Out-Null; $LASTEXITCODE }
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value 'f one'
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g one'
"run1: $(Invoke-Run '2026-01-01T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g two'
"run2: $(Invoke-Run '2026-01-02T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value 'f two'
"run3: $(Invoke-Run '2026-01-03T01:00:00')"

Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
$snaps = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name)
$T = $snaps[1].FullName
# Precondition an older engine could leave (what -RepairStorage exists for): a
# row whose object name and Compressed column claim the archive form over raw bytes.
$rows = @(Read-Manifest -FolderPath $T)
$row  = $rows | Where-Object RelativePath -eq 'f.txt'
$old  = $row.DataPath
Rename-Item -LiteralPath (Join-Path $T $old) -NewName "$old.7z"
$row.DataPath = "$old.7z"; $row.Compressed = 'Yes'
Write-Manifest -FolderPath $T -Records $rows
"precondition: pool problems = $(@(Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg).Count); form findings = " +
    ((@(Test-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg) | ForEach-Object Class) -join ',')

$log = { param([string]$m, [string]$l = 'INFO') }
& (Get-Module FileBackup.Common) { $script:ManifestWriteTestHook = { param($stage, $ctx) if ($stage -eq 'BeforeTempWrite') { throw 'killed' } } }
try { Repair-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg -Log $log | Out-Null } catch { "repair killed: $($_.Exception.Message)" }
& (Get-Module FileBackup.Common) { $script:ManifestWriteTestHook = $null }
"files in T now: " + ((Get-ChildItem -LiteralPath $T -File | Where-Object Name -match '^[2-9A-HJ-NP-Za-km-z]{22}_' | ForEach-Object Name) -join ', ') + "; T row names '$((Read-Manifest -FolderPath $T | Where-Object RelativePath -eq 'f.txt').DataPath)'"
"pool problems after the kill:"
Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg | ForEach-Object { "  [$($_.Kind)] BytesSurvive=$($_.BytesSurvive) $($_.Message)" }
"re-run repair:"
$r = Repair-BackupStorageForm -BackupRoot $bkp -ChangeRoot $chg -Log $log
"  repaired $($r.Repaired); skipped classes: " + ((@($r.Skipped) | ForEach-Object Class) -join ',')
"pool problems after re-running repair: $(@(Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg).Count)"
"a backup run: $(Invoke-Run '2026-01-04T01:00:00'); pool problems after it: $(@(Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg).Count)"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Prune -Snapshot $snaps[0].Name -WhatIf | Out-Null
"prune -WhatIf of $($snaps[0].Name): exit $LASTEXITCODE"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Verify | Out-Null
"verify: exit $LASTEXITCODE"
Get-Content -LiteralPath (Join-Path $base 'Backup_Global.log') | Select-String '\[(PoolUnresolvable|DanglingDataPath|Unreferenced)\]' | ForEach-Object { "  log: $($_.Line.Substring(0, [Math]::Min(220, $_.Line.Length)))" }
$target = Join-Path $base 'restore-T'
pwsh -NoProfile -File (Join-Path $T 'RECONSTRUCT.ps1') -TargetRoot $target -NonInteractive -ExitCode 2>&1 | Out-Null
"restore of T with its own kit: exit $LASTEXITCODE; f.txt = '$((Get-Content -LiteralPath (Join-Path $target 'f.txt') -ErrorAction SilentlyContinue))'"
try { Remove-Item -LiteralPath $base -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
