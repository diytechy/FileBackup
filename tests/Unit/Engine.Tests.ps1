<#
.SYNOPSIS  Pester 5 unit tests for FileBackup.Engine pure functions.
#>

# Discovery-time (so the fixtures can drive -ForEach): the ONE shared
# configuration-fixture corpus (SR-042). tests/Unit/Coverage.Tests.ps1's TC-077
# reads the same file, so the published schema and the runtime validator are
# pinned against a single list that cannot be hand-copied out of sync.
. (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'tests\Common\ConfigFixtures.ps1')
$configCorpus = Get-ConfigFixtureCorpus

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
        # A real backup row always carries a DataPath (the manifest schema);
        # WP7 treats a BLANK one as damage to heal, so the unchanged case must
        # be modeled with the column populated.
        $bkpRow = $row | Select-Object *
        $bkpRow | Add-Member -NotePropertyName DataPath -NotePropertyValue 'same' -Force
        $diff = Compare-SourceToBackup -SourceDb @($row) -BackupDb @($bkpRow)
        $diff.NewOrChanged.Count | Should -Be 0
        $diff.RemovedFromSource.Count | Should -Be 0

        # WP7 (SR-053): the same metadata with a BLANK DataPath is not
        # "unchanged" — it re-enters the diff so the run can heal it.
        $bkpRow.DataPath = ''
        (Compare-SourceToBackup -SourceDb @($row) -BackupDb @($bkpRow)).NewOrChanged.Count | Should -Be 1
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
            ConfigVersion = 1
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
        '{"ConfigVersion":1}' | Set-Content -LiteralPath $config -Encoding UTF8

        { & $entry -ConfigPath $config -NoMail -NonInteractive } |
            Should -Throw -ExpectedMessage '*at least one BackupSets entry*'
    }

    It 'rejects a JSON configuration with no ConfigVersion (SR-042; the version check runs before the BackupSets check, first in document order)' {
        $entry = Join-Path $repo 'FileBackup.ps1'
        $config = Join-Path $TestDrive 'no-version.json'
        '{}' | Set-Content -LiteralPath $config -Encoding UTF8

        { & $entry -ConfigPath $config -NoMail -NonInteractive } |
            Should -Throw -ExpectedMessage '*ConfigVersion*missing*'
    }
}

Describe 'Configuration loader accepts the documented contract (SR-042)' {
    BeforeAll {
        function New-FixtureConfig {
            param([string]$Json)
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
            [IO.File]::WriteAllText($path, $Json)
            return $path
        }
    }

    It 'accepts the checked-in container/FileBackup.example.json verbatim (SR-042)' {
        # Verbatim: no in-memory patching. If the shipped example ever stops
        # satisfying the contract it demonstrates, this fails -- which is the
        # whole point of the fixture.
        $result = Import-BackupConfiguration -Path (Join-Path $repo 'container\FileBackup.example.json')
        $result.ConfigVersion | Should -Be 1
        $result.Sets.Count | Should -Be 1
    }

    It 'accepts shared-corpus fixture <Name> (SR-042)' -ForEach $configCorpus.Accepted {
        $path = New-FixtureConfig -Json $Json
        $result = Import-BackupConfiguration -Path $path
        $result.ConfigVersion | Should -Be 1
        $result.Sets.Count | Should -BeGreaterThan 0
    }

    It 'wraps a single bare BackupSets object, as the published schema''s anyOf allows (SR-042)' {
        $path = New-FixtureConfig -Json '{"ConfigVersion":1,"BackupSets":{"Name":"bare","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":false,"PreserveFolderTree":false}}'
        $result = Import-BackupConfiguration -Path $path
        $result.Sets.Count | Should -Be 1
        $result.Sets[0].Name | Should -Be 'bare'
    }

    It 'accepts an integral-valued ConfigVersion number (JSON has one number type: 1.0 IS 1) (SR-042)' {
        $path = New-FixtureConfig -Json '{"ConfigVersion":1.0,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":false,"PreserveFolderTree":false}]}'
        (Import-BackupConfiguration -Path $path).ConfigVersion | Should -Be 1
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
            [IO.File]::WriteAllText($path, $Json)
            return $path
        }
    }

    # One list, one place: the same corpus TC-074 accepts from and TC-077 runs
    # the published JSON schema against.
    It 'rejects shared-corpus fixture <Name>, naming the key (SR-042)' -ForEach $configCorpus.Rejected {
        $path = New-DefectiveConfig -Json $Json
        { Import-BackupConfiguration -Path $path } | Should -Throw -ExpectedMessage $Message
    }

    It 'refuses a quoted "false" for AllowEmptySource rather than coercing it TRUE and disarming the SR-036 delete-all refusal (SR-042)' {
        # The reviewer's reproduction: [bool]'false' is $true in PowerShell, so
        # before this check the run silently emptied the backup root and exited 0.
        $path = New-DefectiveConfig -Json '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":false,"PreserveFolderTree":false,"AllowEmptySource":"false"}]}'
        # -Match (regex), not -ExpectedMessage (wildcard): [0] is a character
        # class to a wildcard pattern, so it would not pin the JSON path.
        $err = { Import-BackupConfiguration -Path $path } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match '\$\.BackupSets\[0\]\.AllowEmptySource .* JSON boolean'
    }

    It 'names the offending set by its real index, not a literal [?] (SR-042)' {
        $good = '{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true,"PreserveFolderTree":false}'
        $bad  = '{"Name":"b","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":"false","PreserveFolderTree":false}'
        $path = New-DefectiveConfig -Json "{`"ConfigVersion`":1,`"BackupSets`":[$good,$bad]}"
        $err = { Import-BackupConfiguration -Path $path } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match '\$\.BackupSets\[1\]\.CompressEnabled'
    }
}
