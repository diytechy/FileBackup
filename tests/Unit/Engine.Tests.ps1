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
        foreach ($n in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll') {
            $p = Join-Path $root $n; Set-Content -LiteralPath $p -Value 'x'
            Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeTrue
        }
    }
    It 'does NOT flag nested files that share the name (B6)' {
        $root = Join-Path $TestDrive 'bk2'; New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        foreach ($n in 'MANIFEST.csv', 'MANIFEST.csv.meta') {
            $p = Join-Path $root "sub\$n"; Set-Content -LiteralPath $p -Value 'x'
            Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeFalse
        }
    }
    It 'does NOT flag ordinary data files' {
        $root = Join-Path $TestDrive 'bk3'; New-Item -ItemType Directory -Path $root | Out-Null
        $p = Join-Path $root 'photo.jpg'; Set-Content -LiteralPath $p -Value 'x'
        Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeFalse
    }
}

Describe 'External source state' {
    It 'keeps the cache outside the source and treats a root MANIFEST.csv as user data' {
        $source = Join-Path $TestDrive 'external-state-source'
        $state = Join-Path $TestDrive 'external-state-cache'
        New-Item -ItemType Directory -Path $source,$state | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.txt') -Value 'sample'
        Set-Content -LiteralPath (Join-Path $source 'MANIFEST.csv') -Value 'user-owned data'

        $rows = @(Update-SourceManifest -SourcePath $source -ManifestFolderPath $state)

        $rows.Count | Should -Be 2
        $rows.RelativePath | Should -Contain 'MANIFEST.csv'
        Test-Path -LiteralPath (Join-Path $state 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $source 'MANIFEST.csv') -Raw).Trim() | Should -Be 'user-owned data'
    }

    It 'rejects a state cache nested inside the source tree' {
        $source = Join-Path $TestDrive 'nested-state-source'
        $backup = Join-Path $TestDrive 'nested-state-backup'
        $changes = Join-Path $TestDrive 'nested-state-changes'
        New-Item -ItemType Directory -Path $source | Out-Null
        $set = [pscustomobject]@{
            Name = 'UnsafeState'
            SourcePath = $source
            SourceStatePath = (Join-Path $source '.state')
            BackupPath = $backup
            ChangePath = $changes
        }

        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage '*must not be inside SourcePath*'
    }
}

Describe 'Resolve-OptionalTool non-interactive (SR-016, SR-020)' {
    # If -NonInteractive blocked on Read-Host these tests would hang, never pass.
    It 'returns null for a missing tool without prompting (SR-016)' {
        Resolve-OptionalTool -Name 'Bogus' -Path 'Z:\does\not\exist\bogus.exe' -NonInteractive 3>$null |
            Should -BeNullOrEmpty
    }
    It 'returns the path when the tool exists (SR-020)' {
        $f = New-TemporaryFile
        try { Resolve-OptionalTool -Name 'Present' -Path $f.FullName -NonInteractive | Should -Be $f.FullName }
        finally { Remove-Item -LiteralPath $f.FullName -Force }
    }
    It 'fails closed when a selected feature requires the missing tool (SR-020)' {
        { Resolve-OptionalTool -Name 'RequiredBogus' -Path 'Z:\does\not\exist\bogus.exe' -Required -NonInteractive 3>$null } |
            Should -Throw -ExpectedMessage '*required*not found*'
    }
}

Describe 'FileBackup.ps1 entry point (SR-018)' {
    It 'throws a clear error when the config file does not exist (SR-018)' {
        $entry = Join-Path $repo 'FileBackup.ps1'
        { & $entry -ConfigPath (Join-Path $TestDrive 'no-such-config.xml') -NoMail -NonInteractive } |
            Should -Throw -ExpectedMessage '*not found*'
    }

    It 'accepts the JSON configuration format used by the container' {
        $entry = Join-Path $repo 'FileBackup.ps1'
        $source = Join-Path $TestDrive 'json-source'
        $backup = Join-Path $TestDrive 'json-backup'
        $changes = Join-Path $TestDrive 'json-changes'
        $config = Join-Path $TestDrive 'FileBackup.json'
        $log = Join-Path $TestDrive 'logs\global.log'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.txt') -Value 'container config'
        @{
            BackupSets = @(@{
                Name = 'JSON'; SourcePath = $source; BackupPath = $backup; ChangePath = $changes
                HashRecalcFreq = 'N'; CompressEnabled = $false; PreserveFolderTree = $false
            })
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8

        { & $entry -ConfigPath $config -GlobalLogPath $log -NoMail -NonInteractive *>&1 | Out-Null } |
            Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $backup 'MANIFEST.csv') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $log -PathType Leaf | Should -BeTrue
    }

    It 'rejects a JSON configuration with no backup sets' {
        $entry = Join-Path $repo 'FileBackup.ps1'
        $config = Join-Path $TestDrive 'empty.json'
        '{}' | Set-Content -LiteralPath $config -Encoding UTF8

        { & $entry -ConfigPath $config -NoMail -NonInteractive } |
            Should -Throw -ExpectedMessage '*at least one BackupSets entry*'
    }
}

Describe 'Configuration loader accepts the documented contract (SR-042)' {
    It 'accepts container/FileBackup.example.json (ConfigVersion added in-memory if the checked-in file predates WP2 Phase D) (SR-042)' {
        $exampleObj = Get-Content -Raw (Join-Path $repo 'container\FileBackup.example.json') | ConvertFrom-Json
        if ($exampleObj.PSObject.Properties.Name -notcontains 'ConfigVersion') {
            $exampleObj | Add-Member -NotePropertyName ConfigVersion -NotePropertyValue 1
        }
        $path = Join-Path $TestDrive 'example.json'
        $exampleObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Import-BackupConfiguration -Path $path
        $result.ConfigVersion | Should -Be 1
        $result.Sets.Count | Should -Be 1
    }

    It 'materializes SourceStatePath and AllowEmptySource defaults, and upper-cases HashRecalcFreq, when omitted (SR-042)' {
        $path = Join-Path $TestDrive 'minimal.json'
        [ordered]@{
            ConfigVersion = 1
            BackupSets    = @(
                [ordered]@{
                    Name = 'S'; SourcePath = 'C:\src'; BackupPath = 'C:\bkp'; ChangePath = 'C:\chg'
                    HashRecalcFreq = 'n'; CompressEnabled = $true; PreserveFolderTree = $false
                }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Import-BackupConfiguration -Path $path
        $result.Sets[0].SourceStatePath  | Should -Be 'C:\src'
        $result.Sets[0].AllowEmptySource | Should -BeFalse
        $result.Sets[0].HashRecalcFreq   | Should -Be 'N'
    }

    It 'loads a CLIXML config the same shape as tests/Common/Harness.ps1 writes, unversioned (SR-042)' {
        $path = Join-Path $TestDrive 'clixml-config.xml'
        $set = [pscustomobject]@{
            Name = 'TestSet'; SourcePath = 'C:\src'; BackupPath = 'C:\bkp'; ChangePath = 'C:\chg'
            HashRecalcFreq = 'A'; CompressEnabled = $true; PreserveFolderTree = $false
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $path

        $result = Import-BackupConfiguration -Path $path
        $result.ConfigVersion | Should -BeNullOrEmpty
        $result.Sets.Count | Should -Be 1
        $result.Sets[0].Name | Should -Be 'TestSet'
        $result.Sets[0].SourceStatePath | Should -Be 'C:\src'
        $result.Sets[0].AllowEmptySource | Should -BeFalse
    }
}

Describe 'Configuration loader fails loudly and names the key (SR-042)' {
    BeforeAll {
        function New-DefectiveConfig {
            param([string]$Json)
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
            $Json | Set-Content -LiteralPath $path -Encoding UTF8
            return $path
        }
        $validSet = '"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true,"PreserveFolderTree":false'
    }

    It 'rejects a missing ConfigVersion' {
        $path = New-DefectiveConfig "{`"BackupSets`":[{$validSet}]}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*ConfigVersion*missing*'
    }

    It 'rejects a ConfigVersion above the highest supported' {
        $path = New-DefectiveConfig "{`"ConfigVersion`":2,`"BackupSets`":[{$validSet}]}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*declares version 2*supports up to 1*'
    }

    It 'rejects an unrecognized top-level key' {
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$validSet}],`"Bogus`":1}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*$.Bogus*unrecognized key*'
    }

    It 'rejects an unrecognized per-set key (typo AllowEmptySources) instead of silently ignoring it' {
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$validSet,`"AllowEmptySources`":true}]}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*AllowEmptySources*unrecognized key*'
    }

    It 'rejects a quoted "false" for CompressEnabled instead of coercing it true' {
        $badSet = '"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":"false","PreserveFolderTree":false'
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$badSet}]}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*CompressEnabled*JSON boolean*'
    }

    It 'preserves the existing invalid-HashRecalcFreq wording' {
        $badSet = '"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"Q","CompressEnabled":true,"PreserveFolderTree":false'
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$badSet}]}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*invalid HashRecalcFreq*'
    }

    It 'preserves the existing empty-BackupSets wording' {
        $path = New-DefectiveConfig '{"ConfigVersion":1,"BackupSets":[]}'
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*at least one BackupSets entry*'
    }

    It 'rejects a non-integer Secrets.SmtpPort' {
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$validSet}],`"Secrets`":{`"SmtpPort`":`"abc`"}}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*Secrets.SmtpPort*integer*'
    }

    It 'rejects Secrets.Credential in JSON by name (JSON cannot carry a PSCredential)' {
        $path = New-DefectiveConfig "{`"ConfigVersion`":1,`"BackupSets`":[{$validSet}],`"Secrets`":{`"Credential`":`"x`"}}"
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*Secrets.Credential*PSCredential*'
    }

    It 'rejects a file that is not valid JSON' {
        $path = New-DefectiveConfig 'not json at all'
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage '*not valid JSON*'
    }
}
