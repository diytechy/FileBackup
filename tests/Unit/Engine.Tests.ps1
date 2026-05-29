<#
.SYNOPSIS  Pester 5 unit tests for FileBackup.Engine pure functions.
#>
BeforeAll {
    # $PSScriptRoot here is tests\Unit; repo root is two levels up.
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    function New-Row($rel, $len, $hash, $lwt) {
        [pscustomobject]@{ RelativePath = $rel; Length = $len; xxH2Hash = $hash; LastWriteTime = $lwt }
    }
}

Describe 'Test-HashRecalcDue' {
    BeforeAll { $now = Get-Date '2026-06-15T12:00:00' }

    It 'recalculates when never run before' {
        Test-HashRecalcDue -FreqCode 'W' -Now $now | Should -BeTrue
    }
    It 'A and E always recalc' {
        Test-HashRecalcDue -FreqCode 'A' -LastHashRun $now.AddMinutes(-1) -Now $now | Should -BeTrue
        Test-HashRecalcDue -FreqCode 'E' -LastHashRun $now.AddMinutes(-1) -Now $now | Should -BeTrue
    }
    It 'N never recalcs' {
        Test-HashRecalcDue -FreqCode 'N' -LastHashRun $now.AddYears(-10) -Now $now | Should -BeFalse
    }
    It 'D recalcs only on a new day' {
        Test-HashRecalcDue -FreqCode 'D' -LastHashRun $now.AddHours(-1) -Now $now | Should -BeFalse
        Test-HashRecalcDue -FreqCode 'D' -LastHashRun $now.AddDays(-1)  -Now $now | Should -BeTrue
    }
    It 'M recalcs only on a new month' {
        Test-HashRecalcDue -FreqCode 'M' -LastHashRun $now.AddDays(-5)    -Now $now | Should -BeFalse
        Test-HashRecalcDue -FreqCode 'M' -LastHashRun $now.AddMonths(-1)  -Now $now | Should -BeTrue
    }
    It 'Y recalcs only on a new year' {
        Test-HashRecalcDue -FreqCode 'Y' -LastHashRun $now.AddMonths(-1) -Now $now | Should -BeFalse
        Test-HashRecalcDue -FreqCode 'Y' -LastHashRun $now.AddYears(-1)  -Now $now | Should -BeTrue
    }
    It 'unknown code defaults to recalc' {
        Test-HashRecalcDue -FreqCode 'Q' -LastHashRun $now.AddYears(-1) -Now $now | Should -BeTrue
    }
}

Describe 'Compare-SourceToBackup' {
    BeforeAll { $t = Get-Date '2026-01-01' }

    It 'flags new files' {
        $src = @( (New-Row 'a' 1 'H' $t) )
        $diff = Compare-SourceToBackup -SourceDb $src -BackupDb @()
        $diff.NewOrChanged.Count | Should -Be 1
        $diff.RemovedFromSource.Count | Should -Be 0
    }
    It 'flags removed files' {
        $bkp = @( (New-Row 'gone' 1 'H' $t) )
        $diff = Compare-SourceToBackup -SourceDb @() -BackupDb $bkp
        $diff.RemovedFromSource.Count | Should -Be 1
    }
    It 'ignores unchanged files' {
        $row = New-Row 'same' 10 'H1' $t
        $diff = Compare-SourceToBackup -SourceDb @($row) -BackupDb @($row)
        $diff.NewOrChanged.Count | Should -Be 0
        $diff.RemovedFromSource.Count | Should -Be 0
    }
    It 'detects a content change (hash differs)' {
        $s = New-Row 'f' 10 'NEW' $t
        $b = New-Row 'f' 10 'OLD' $t
        $diff = Compare-SourceToBackup -SourceDb @($s) -BackupDb @($b)
        $diff.NewOrChanged.Count | Should -Be 1
    }
    It 'tolerates null inputs' {
        { Compare-SourceToBackup -SourceDb $null -BackupDb $null } | Should -Not -Throw
    }
}

Describe 'Test-IsInfrastructureFile' {
    It 'flags root-level infrastructure files' {
        $root = Join-Path $TestDrive 'bk'; New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($n in 'MANIFEST.csv','RECONSTRUCT.ps1','FileBackup.Common.psm1','System.IO.Hashing.dll') {
            $p = Join-Path $root $n; Set-Content -LiteralPath $p -Value 'x'
            Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeTrue
        }
    }
    It 'does NOT flag nested files that share the name (B6)' {
        $root = Join-Path $TestDrive 'bk2'; New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        $p = Join-Path $root 'sub\MANIFEST.csv'; Set-Content -LiteralPath $p -Value 'x'
        Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeFalse
    }
    It 'does NOT flag ordinary data files' {
        $root = Join-Path $TestDrive 'bk3'; New-Item -ItemType Directory -Path $root | Out-Null
        $p = Join-Path $root 'photo.jpg'; Set-Content -LiteralPath $p -Value 'x'
        Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeFalse
    }
}
