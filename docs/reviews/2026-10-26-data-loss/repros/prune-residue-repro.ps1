# Repro: what a prune killed during a re-home copy leaves behind, and what it does
# to a restore of the destination snapshot. Store under %TEMP%; repo untouched.
$ErrorActionPreference = 'Stop'
$repo  = 'C:\Projects\FileBackup'
$fb    = Join-Path $repo 'FileBackup.ps1'
$base  = Join-Path $env:TEMP ('fb-prr-' + [guid]::NewGuid().ToString('N'))
$src   = Join-Path $base 'src'
$store = Join-Path $base 'store'
$bkp   = Join-Path $store 'backup'
$chg   = Join-Path $store 'changes'
New-Item -ItemType Directory -Path $src, $store | Out-Null
$cfg = Join-Path $base 'cfg.json'
@{
    ConfigVersion = 2
    Tools = @{ SevenZipPath = 'C:\Program Files\7-Zip\7z.exe' }
    BackupSets = @(@{ Name = 'T'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
                      HashRecalcFreq = 'N'; CompressEnabled = $true })
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $cfg
function Invoke-Run([string]$When) {
    pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -BackupTime $When | Out-Null
    return $LASTEXITCODE
}
$k  = (1..20000 | ForEach-Object { "line $_ of the first version of f, compressible text" }) -join "`n"
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value $k
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g one'
"run1: $(Invoke-Run '2026-01-01T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'g.txt') -Value 'g two'
"run2: $(Invoke-Run '2026-01-02T01:00:00')"
Set-Content -LiteralPath (Join-Path $src 'f.txt') -Value 'f second version'
"run3: $(Invoke-Run '2026-01-03T01:00:00')"
Get-ChildItem -LiteralPath $chg -Directory | ForEach-Object { "  $($_.Name): " + ((Get-ChildItem -LiteralPath $_.FullName -File | Where-Object Name -match '^[2-9A-HJ-NP-Za-km-z]{22}_' | ForEach-Object Name) -join ', ') }

$snaps = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -like 'Snapshot_*' | Sort-Object Name)
$S = $snaps[0].FullName; $T = $snaps[1].FullName
"prune dry run of $($snaps[1].Name):"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Snapshots | ForEach-Object { "  $_" }

$restoreS = {
    param([string]$Label)
    $target = Join-Path $base ('restore-' + [guid]::NewGuid().ToString('N'))
    pwsh -NoProfile -File (Join-Path $S 'RECONSTRUCT.ps1') -TargetRoot $target -NonInteractive -ExitCode 2>&1 | Out-Null
    $code = $LASTEXITCODE
    $log = Get-ChildItem -LiteralPath $target -Filter '*.log' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    "restore of $([IO.Path]::GetFileName($S)) [$Label]: exit $code"
    if ($log) { Get-Content -LiteralPath $log.FullName | Select-String 'WARN|resolved by name|CandidateError' | ForEach-Object { "  log: $($_.Line)" } }
}
& $restoreS 'before any prune'

# What a prune killed inside Copy-ReHomedDataFile leaves: the staging folder with
# its marker, and a partly written '<object>.fbprune.tmp' in the destination.
$obj = Get-ChildItem -LiteralPath $T -File | Where-Object Name -like '*.7z' | Select-Object -First 1
"object only in T: $($obj.Name) ($($obj.Length) bytes)"
New-Item -ItemType Directory -Path (Join-Path $chg 'Temp') | Out-Null
Set-Content -LiteralPath (Join-Path $chg 'Temp\PRUNE.inprogress') -Value $snaps[1].Name -Encoding UTF8
$bytes = [IO.File]::ReadAllBytes($obj.FullName)
[IO.File]::WriteAllBytes((Join-Path $S "$($obj.Name).fbprune.tmp"), $bytes[0..([int]($bytes.Length / 2))])

& $restoreS 'after a killed prune'
"prune again:"
pwsh -NoProfile -File $fb -ConfigPath $cfg -NoMail -NonInteractive -ExitCode -Action Prune -Snapshot $snaps[1].Name | Out-Null
"  prune exit: $LASTEXITCODE"
Get-Content -LiteralPath (Join-Path $base 'Backup_Global.log') | Select-String 'Refusing' | Select-Object -Last 1 | ForEach-Object { "  log: $($_.Line)" }
"backup run after the killed prune: $(Invoke-Run '2026-01-04T01:00:00')"
Get-Content -LiteralPath (Join-Path $chg 'backup.log') | Select-String 'Temp' | ForEach-Object { "  log: $($_.Line)" }
try { Remove-Item -LiteralPath $base -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
