<#
.SYNOPSIS
    Regression tests for fail-before-mutation backup safety gates.
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    $script:entry = Join-Path $repo 'FileBackup.ps1'

    function New-SafetyConfig {
        param(
            [string]$Path,
            [string]$Source,
            [string]$Backup,
            [string]$Changes,
            [bool]$AllowEmptySource = $false
        )
        $set = [pscustomobject]@{
            Name = 'Safety'; SourcePath = $Source; BackupPath = $Backup; ChangePath = $Changes
            HashRecalcFreq = 'A'; CompressEnabled = $false
            AllowEmptySource = $AllowEmptySource
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function Invoke-SafetyBackup {
        param([string]$Config)
        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Config -NoMail -NonInteractive *>&1 | Out-Null
        return $LASTEXITCODE
    }

    function Get-StoredText {
        # Storage is content-addressed: a row's bytes live at the hash-named
        # pool object its manifest DataPath names, never at its RelativePath.
        param([string]$Backup, [string]$RelativePath)
        $row = @(Import-Csv -LiteralPath (Join-Path $Backup 'MANIFEST.csv') |
                    Where-Object RelativePath -eq $RelativePath)[0]
        return [IO.File]::ReadAllText((Join-Path $Backup $row.DataPath))
    }

    function Get-SnapshotText {
        # A snapshot row resolves through its content name, anywhere in the
        # pool (bounded-run-loop plan section 7): its own folder, then the
        # backup root.
        param([string]$Snapshot, [string]$Backup, [string]$RelativePath)
        $row = @(Import-Csv -LiteralPath (Join-Path $Snapshot 'MANIFEST.csv') |
                    Where-Object RelativePath -eq $RelativePath)[0]
        $prefix = Get-HashSizeFileName -HashHex $row.xxH2Hash -Length ([long]$row.Length) -Extension ''
        foreach ($folder in $Snapshot, $Backup) {
            $hit = @(Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Name.StartsWith($prefix, [StringComparison]::Ordinal) })
            if ($hit.Count -gt 0) { return [IO.File]::ReadAllText($hit[0].FullName) }
        }
        return $null
    }
}

Describe 'Backup history safety: corner cases warn, and the prior state stays restorable (SR-035, SR-036, plan R1, review 2026-10-26 C2)' {
    It 'dates the prior state by the manifest file when LastBackupRun is missing, and keeps it as a snapshot (SR-035)' {
        $root = Join-Path $TestDrive 'missing-state'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'OLD')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        Remove-Item -LiteralPath (Join-Path $bkp 'FileBackupState.json') -Force
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'NEW')

        (Invoke-SafetyBackup $cfg) | Should -Be 0
        (Get-StoredText -Backup $bkp -RelativePath 'f.txt') | Should -Be 'NEW'
        $snap = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -Match '^Snapshot_')
        $snap.Count | Should -Be 1
        (Get-SnapshotText -Snapshot $snap[0].FullName -Backup $bkp -RelativePath 'f.txt') | Should -Be 'OLD'
        Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw | Should -Match 'No usable LastBackupRun'
    }

    It 'sets a malformed state file aside instead of treating the store as new (SR-035)' {
        $root = Join-Path $TestDrive 'bad-state'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'OLD')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        [IO.File]::WriteAllText((Join-Path $bkp 'FileBackupState.json'), '{broken')
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'NEW')
        (Invoke-SafetyBackup $cfg) | Should -Be 0
        @(Get-ChildItem -LiteralPath $bkp -Filter 'FileBackupState.json.unreadable-*').Count | Should -Be 1
        (Get-StoredText -Backup $bkp -RelativePath 'f.txt') | Should -Be 'NEW'
        $snap = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -Match '^Snapshot_')
        (Get-SnapshotText -Snapshot $snap[0].FullName -Backup $bkp -RelativePath 'f.txt') | Should -Be 'OLD'
    }

    It 'stops with 4 when the source is empty at the start of a run, leaving the latest state as it was (SR-036, review 2026-10-26 C2)' {
        $root = Join-Path $TestDrive 'empty-source'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        # AllowEmptySource is accepted and ignored: it does not let an empty
        # source through (a set meant to be empty is removed from the config).
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg -AllowEmptySource $true
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'KEEP')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        Remove-Item -LiteralPath (Join-Path $src 'f.txt') -Force
        (Invoke-SafetyBackup $cfg) | Should -Be 4
        @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv')).Count | Should -Be 1 -Because 'the latest state still lists the file'
        (Get-StoredText -Backup $bkp -RelativePath 'f.txt') | Should -Be 'KEEP'
        Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw | Should -Match 'remove the set from the configuration'
    }
}
