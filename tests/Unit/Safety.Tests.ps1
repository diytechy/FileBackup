<#
.SYNOPSIS
    Regression tests for fail-before-mutation backup safety gates.
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
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
            HashRecalcFreq = 'A'; CompressEnabled = $false; PreserveFolderTree = $true
            AllowEmptySource = $AllowEmptySource
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function Invoke-SafetyBackup {
        param([string]$Config)
        & (Get-Process -Id $PID).Path -NoProfile -File $entry -ConfigPath $Config -NoMail -NonInteractive *>&1 | Out-Null
        return $LASTEXITCODE
    }
}

Describe 'Backup history safety gates' {
    It 'refuses to mutate an initialized backup when LastBackupRun state is missing' {
        $root = Join-Path $TestDrive 'missing-state'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'OLD')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        $manifestHash = (Get-FileHash -LiteralPath (Join-Path $bkp 'MANIFEST.csv')).Hash
        Remove-Item -LiteralPath (Join-Path $bkp 'FileBackupState.json') -Force
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'NEW')

        (Invoke-SafetyBackup $cfg) | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $bkp 'f.txt')) | Should -Be 'OLD'
        (Get-FileHash -LiteralPath (Join-Path $bkp 'MANIFEST.csv')).Hash | Should -Be $manifestHash
        @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -Match '^Snapshot_').Count | Should -Be 0
    }

    It 'refuses malformed state instead of treating it as a first backup' {
        $root = Join-Path $TestDrive 'bad-state'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'OLD')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        [IO.File]::WriteAllText((Join-Path $bkp 'FileBackupState.json'), '{broken')
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'NEW')
        (Invoke-SafetyBackup $cfg) | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $bkp 'f.txt')) | Should -Be 'OLD'
    }

    It 'blocks an unexpected empty source and permits an explicit delete-all override' {
        $root = Join-Path $TestDrive 'empty-source'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'config.xml'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'KEEP')
        (Invoke-SafetyBackup $cfg) | Should -Be 0

        Remove-Item -LiteralPath (Join-Path $src 'f.txt') -Force
        (Invoke-SafetyBackup $cfg) | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $bkp 'f.txt')) | Should -Be 'KEEP'
        @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv')).Count | Should -Be 1

        New-SafetyConfig -Path $cfg -Source $src -Backup $bkp -Changes $chg -AllowEmptySource $true
        (Invoke-SafetyBackup $cfg) | Should -Be 0
        @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv')).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object Name -Match '^Snapshot_').Count | Should -Be 1
    }
}
