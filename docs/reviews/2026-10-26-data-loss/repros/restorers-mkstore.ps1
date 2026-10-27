param([Parameter(Mandatory)][string]$Root, [switch]$Compress)
# Builds a store with the HEAD export: run 1, change one file, run 2 (-> one snapshot).
$ErrorActionPreference = 'Stop'
$fb = Join-Path $PSScriptRoot '..\fb-head\FileBackup.ps1'
if (Test-Path $Root) { Remove-Item $Root -Recurse -Force }
$src = Join-Path $Root 'src'; $null = New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force
1..12 | ForEach-Object { Set-Content -LiteralPath (Join-Path $src ("f{0:D2}.txt" -f $_)) -Value (("line $_ " * 4000)) -NoNewline }
Set-Content -LiteralPath (Join-Path $src 'sub\a.txt') -Value ('alpha ' * 5000) -NoNewline
$cfg = [ordered]@{
    ConfigVersion = 2
    Tools = [ordered]@{ SevenZipPath = 'C:\Program Files\7-Zip\7z.exe' }
    BackupSets = @([ordered]@{
        Name = 'T'; SourcePath = $src
        BackupPath = (Join-Path $Root 'store\backup'); ChangePath = (Join-Path $Root 'store\changes')
        HashRecalcFreq = 'N'; CompressEnabled = [bool]$Compress
    })
}
$cfgPath = Join-Path $Root 'cfg.json'
$cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
& pwsh -NoProfile -File $fb -ConfigPath $cfgPath -NoMail -NonInteractive -GlobalLogPath (Join-Path $Root 'g.log') *> (Join-Path $Root 'run1.out')
"run1 exit $LASTEXITCODE"
Start-Sleep -Seconds 2
Set-Content -LiteralPath (Join-Path $src 'f01.txt') -Value ('changed ' * 3000) -NoNewline
& pwsh -NoProfile -File $fb -ConfigPath $cfgPath -NoMail -NonInteractive -GlobalLogPath (Join-Path $Root 'g.log') *> (Join-Path $Root 'run2.out')
"run2 exit $LASTEXITCODE"
Get-ChildItem -LiteralPath (Join-Path $Root 'store') -Recurse -File | Select-Object @{n='P';e={$_.FullName.Substring($Root.Length)}}, Length | Format-Table -AutoSize | Out-String -Width 200
