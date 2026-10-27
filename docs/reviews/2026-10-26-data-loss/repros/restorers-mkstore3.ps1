param([Parameter(Mandatory)][string]$Root, [string]$StoreDirName = 'store', [switch]$Compress)
# Three runs: run1 (state A), change f01 (run2 -> Snapshot_1), change f02 (run3 -> Snapshot_2).
# f02's first version is named by Snapshot_1 and Snapshot_2 and so moves into
# Snapshot_2 (the newest snapshot naming it, C23): restoring Snapshot_1 needs a sibling snapshot.
$ErrorActionPreference = 'Stop'
$fb = Join-Path $PSScriptRoot '..\fb-head\FileBackup.ps1'
if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
$src = Join-Path $Root 'src'; $null = New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force
1..12 | ForEach-Object { Set-Content -LiteralPath (Join-Path $src ("f{0:D2}.txt" -f $_)) -Value (("line $_ " * 4000)) -NoNewline }
Set-Content -LiteralPath (Join-Path $src 'sub\a.txt') -Value ('alpha ' * 5000) -NoNewline
$store = Join-Path $Root $StoreDirName
$cfg = [ordered]@{
    ConfigVersion = 2
    Tools = [ordered]@{ SevenZipPath = 'C:\Program Files\7-Zip\7z.exe' }
    BackupSets = @([ordered]@{
        Name = 'T'; SourcePath = $src
        BackupPath = (Join-Path $store 'backup'); ChangePath = (Join-Path $store 'changes')
        HashRecalcFreq = 'N'; CompressEnabled = [bool]$Compress
    })
}
$cfgPath = Join-Path $Root 'cfg.json'
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
function Invoke-Run([string]$Tag) {
    & pwsh -NoProfile -File $fb -ConfigPath $cfgPath -NoMail -NonInteractive -GlobalLogPath (Join-Path $Root 'g.log') *> (Join-Path $Root "$Tag.out")
    "$Tag exit $LASTEXITCODE"
}
Invoke-Run 'run1'; Start-Sleep -Seconds 2
Set-Content -LiteralPath (Join-Path $src 'f01.txt') -Value ('changed one ' * 3000) -NoNewline
Invoke-Run 'run2'; Start-Sleep -Seconds 2
Set-Content -LiteralPath (Join-Path $src 'f02.txt') -Value ('changed two ' * 3000) -NoNewline
Invoke-Run 'run3'
Get-ChildItem -LiteralPath $store -Recurse -File | Where-Object { $_.Name -match '_' -and $_.Name -notmatch 'RECONSTRUCT|System|FileBackup' } |
    Select-Object @{n='P';e={$_.FullName.Substring($Root.Length)}} | Format-Table -AutoSize | Out-String -Width 200
