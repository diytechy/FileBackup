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

Describe 'Test-IsInfrastructureFile' {
    It 'flags root-level infrastructure files' {
        $root = Join-Path $TestDrive 'bk'; New-Item -ItemType Directory -Path $root | Out-Null
        # DIRECTORIES.csv (SR-065) is load-bearing on this list: Get-DataFile
        # filters through here, so prune's unreferenced-data rail, the SR-064
        # orphan audit and Optimize-ChangeFolders would all treat the sidecar as
        # a stray data file without it.
        foreach ($n in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll','DIRECTORIES.csv','DIRECTORIES.csv.tmp') {
            $p = Join-Path $root $n; Set-Content -LiteralPath $p -Value 'x'
            Test-IsInfrastructureFile -Root $root -FullPath $p | Should -BeTrue
        }
    }
    It 'does NOT flag nested files that share the name (B6)' {
        $root = Join-Path $TestDrive 'bk2'; New-Item -ItemType Directory -Path (Join-Path $root 'sub') -Force | Out-Null
        foreach ($n in 'MANIFEST.csv', 'MANIFEST.csv.meta', 'DIRECTORIES.csv') {
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

Describe 'The source walk and the retired source-side record (plan R3, C6)' {
    It 'treats a root MANIFEST.csv as user data when SourceStatePath points elsewhere' {
        $source = Join-Path $TestDrive 'external-state-source'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.txt') -Value 'sample'
        Set-Content -LiteralPath (Join-Path $source 'MANIFEST.csv') -Value 'user-owned data'
        $walk = Get-SourceFileList -SourcePath $source -ExcludeOldSourceRecord $false
        @($walk.Files | ForEach-Object RelativePath) | Sort-Object | Should -Be @('MANIFEST.csv', 'sample.txt')
    }

    It 'keeps the old in-source record out of the backup, but not a nested file of that name (C6, B6)' {
        $source = Join-Path $TestDrive 'in-source-record'
        New-Item -ItemType Directory -Path (Join-Path $source 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'MANIFEST.csv') -Value 'old record'
        Set-Content -LiteralPath (Join-Path $source 'sub\MANIFEST.csv') -Value 'user data'
        $walk = Get-SourceFileList -SourcePath $source -ExcludeOldSourceRecord $true
        # '/'-separated on every host (plan C44, L7).
        @($walk.Files | ForEach-Object RelativePath) | Should -Be @('sub/MANIFEST.csv')
    }

    It 'neither creates nor refuses a SourceStatePath, which is no longer written' {
        $source = Join-Path $TestDrive 'nested-state-source'
        New-Item -ItemType Directory -Path $source | Out-Null
        $set = [pscustomobject]@{
            Name = 'OldState'; SourcePath = $source; SourceStatePath = (Join-Path $source '.state')
            StorePath = (Join-Path $TestDrive 'nested-state-store')
        }
        $paths = Resolve-BackupSetPaths -Set $set
        $paths.SrcStatePath | Should -Be (Join-Path $source '.state')
        Test-Path -LiteralPath (Join-Path $source '.state') | Should -BeFalse
    }
}

Describe 'The store-layout check refuses an old backup, not the engine''s own folders (SR-014, plan C44 S2)' {
    BeforeAll {
        function New-LayoutStore {
            param([string]$Name, [string]$Child)
            $root = Join-Path $TestDrive $Name
            $src = Join-Path $root 'src'; $store = Join-Path $root 'store'
            New-Item -ItemType Directory -Path $src, (Join-Path $store 'CurrentBackup'), (Join-Path $store $Child) -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
            Set-Content -LiteralPath (Join-Path (Join-Path $store $Child) 'MANIFEST.csv') -Value '"DataPath","RelativePath"'
            return [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        }
    }

    It 'accepts a store holding a leftover <Child> with a MANIFEST.csv, for a run and read-only (plan C44, S2)' -ForEach @(
        @{ Child = 'BackupHistory/Building_2026_01_01_10_00_00' }
        @{ Child = 'BackupHistory/Pruning_2026_01_01_10_00_00' }
    ) {
        # A run killed before the snapshot rename leaves Building_<date>; a
        # prune whose delete failed leaves Pruning_<name>. Each holds the
        # manifest it was given, and the next run or prune must finish it.
        $set = New-LayoutStore -Name ('ok-' + ($Child -replace '\W', '')) -Child $Child
        { Resolve-BackupSetPaths -Set $set } | Should -Not -Throw
        { Resolve-BackupSetPaths -Set $set -ReadOnly } | Should -Not -Throw
    }

    It 'still refuses a store holding an old-layout backup folder (a <Child> with a MANIFEST.csv) (plan C44, L2, S2)' -ForEach @(
        @{ Child = 'backup' }
        @{ Child = 'Backup_2026' }
        @{ Child = 'Latest' }
        @{ Child = 'Snapshot_2026_01_01_10_00_00' }
        @{ Child = 'Building_2026_01_01_10_00_00' }
        @{ Child = 'Pruning_2026_01_01_10_00_00' }
    ) {
        $set = New-LayoutStore -Name ('old-' + $Child) -Child $Child
        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage "*holds '$Child', a folder with a MANIFEST.csv*old-layout*"
        { Resolve-BackupSetPaths -Set $set -ReadOnly } | Should -Throw -ExpectedMessage '*old-layout*'
    }

    It 'refuses an old store whose backup folder was named CurrentBackup: a <Marker> (C44 review, finding 2)' -ForEach @(
        @{ Marker = 'path sidecar in CurrentBackup' }
        @{ Marker = 'kit older than revision 16 in CurrentBackup' }
        @{ Marker = 'change folder of snapshots beside CurrentBackup' }
        @{ Marker = 'old-named snapshots in BackupHistory' }
    ) {
        $root = Join-Path $TestDrive ('old-latest-' + ($Marker -replace '\W', ''))
        $src = Join-Path $root 'src'; $store = Join-Path $root 'store'; $latest = Join-Path $store 'CurrentBackup'
        New-Item -ItemType Directory -Path $src, $latest -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
        switch -Wildcard ($Marker) {
            'path sidecar*' { Set-Content -LiteralPath (Join-Path $latest 'RECONSTRUCT.paths.json') -Value '{}' }
            'kit older*'    { Set-Content -LiteralPath (Join-Path $latest 'RECONSTRUCT.ps1') -Value '# KitRevision: 15' }
            'change folder*' { New-Item -ItemType Directory -Path (Join-Path $store 'changes\Snapshot_2026_01_01_10_00_00') -Force | Out-Null }
            'old-named*'     { New-Item -ItemType Directory -Path (Join-Path $store 'BackupHistory\Snapshot_2026_01_01_10_00_00') -Force | Out-Null }
        }
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage '*old-layout*'
        { Resolve-BackupSetPaths -Set $set -ReadOnly } | Should -Throw -ExpectedMessage '*old-layout*'
    }

    It 'refuses a StorePath that is itself an old backup folder, and one with snapshots but no CurrentBackup (plan C44, S2, C26)' {
        $root = Join-Path $TestDrive 'old-self'
        $src = Join-Path $root 'src'; $store = Join-Path $root 'store'
        New-Item -ItemType Directory -Path $src, $store -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
        Set-Content -LiteralPath (Join-Path $store 'MANIFEST.csv') -Value '"DataPath","RelativePath"'
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage '*holds a MANIFEST.csv of its own*'

        $lost = Join-Path $root 'lost'
        New-Item -ItemType Directory -Path (Join-Path $lost 'BackupHistory/2026_01_01_10_00_00') -Force | Out-Null
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $lost }
        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage "*holds snapshots but no 'CurrentBackup' folder*"
        Test-Path -LiteralPath (Join-Path $lost 'CurrentBackup') | Should -BeFalse -Because 'no fresh full backup starts beside the snapshots'
    }

    It 'refuses a store with a CurrentBackup but no BackupHistory, for a run and read-only, and changes nothing (plan L10, S15)' {
        $root = Join-Path $TestDrive 'no-history'
        $src = Join-Path $root 'src'; $store = Join-Path $root 'store'
        New-Item -ItemType Directory -Path $src, (Join-Path $store 'CurrentBackup') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        $history = Join-Path $store 'BackupHistory'
        { Resolve-BackupSetPaths -Set $set } | Should -Throw -ExpectedMessage "*'CurrentBackup' folder but no 'BackupHistory' folder*create an empty folder at '$history'*"
        { Resolve-BackupSetPaths -Set $set -ReadOnly } | Should -Throw -ExpectedMessage "*no 'BackupHistory' folder*"
        Test-Path -LiteralPath $history | Should -BeFalse -Because 'the engine never makes the history of an existing store'
    }

    It 'lets the run go on once the user creates the empty BackupHistory the refusal names (plan L10)' {
        $root = Join-Path $TestDrive 'history-remade'
        $src = Join-Path $root 'src'; $store = Join-Path $root 'store'
        New-Item -ItemType Directory -Path $src, (Join-Path $store 'CurrentBackup'), (Join-Path $store 'BackupHistory') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        { Resolve-BackupSetPaths -Set $set } | Should -Not -Throw
        { Resolve-BackupSetPaths -Set $set -ReadOnly } | Should -Not -Throw
    }

    It 'gives a new store both folders, and treats an empty BackupHistory with no CurrentBackup as still new (plan S14)' {
        $root = Join-Path $TestDrive 'new-store'
        $src = Join-Path $root 'src'; $store = Join-Path $root 'store'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'a'
        $set = [pscustomobject]@{ Name = 'L'; SourcePath = $src; StorePath = $store }
        Resolve-BackupSetPaths -Set $set | Out-Null
        Test-Path -LiteralPath (Join-Path $store 'BackupHistory') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $store 'CurrentBackup') -PathType Container | Should -BeTrue

        # A run cut short between the two folders: history first, so this is new.
        Remove-Item -LiteralPath (Join-Path $store 'CurrentBackup') -Force
        { Resolve-BackupSetPaths -Set $set } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $store 'CurrentBackup') -PathType Container | Should -BeTrue
    }

    It 'counts a dated folder as a snapshot only inside BackupHistory (plan S12)' {
        $root = Join-Path $TestDrive 'dated-top'
        $store = Join-Path $root 'store'
        New-Item -ItemType Directory -Path (Join-Path $store '2026_01_01_10_00_00'), (Join-Path $store 'BackupHistory') -Force | Out-Null
        @(Get-PoolSnapshotFolder -ChangeRoot $store) | Should -BeNullOrEmpty
        New-Item -ItemType Directory -Path (Join-Path $store 'BackupHistory\2026_01_01_10_00_00') -Force | Out-Null
        @(Get-PoolSnapshotFolder -ChangeRoot $store).Name | Should -Be '2026_01_01_10_00_00'
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
        $changes = Join-Path $TestDrive 'json-store'
        $backup = Join-Path $changes 'CurrentBackup'
        $config = Join-Path $TestDrive 'FileBackup.json'
        $log = Join-Path $TestDrive 'logs\global.log'
        New-Item -ItemType Directory -Path $source | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'sample.txt') -Value 'container config'
        @{
            ConfigVersion = 3
            BackupSets = @(@{
                Name = 'JSON'; SourcePath = $source; StorePath = $changes
                HashRecalcFreq = 'N'; CompressEnabled = $false
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
        '{"ConfigVersion":3}' | Set-Content -LiteralPath $config -Encoding UTF8

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
        $result.ConfigVersion | Should -Be 3
        $result.Sets.Count | Should -Be 1
    }

    It 'accepts shared-corpus fixture <Name> (SR-042)' -ForEach $configCorpus.Accepted {
        $path = New-FixtureConfig -Json $Json
        $result = Import-BackupConfiguration -Path $path
        $result.ConfigVersion | Should -Be 3
        $result.Sets.Count | Should -BeGreaterThan 0
    }

    It 'wraps a single bare BackupSets object, as the published schema''s anyOf allows (SR-042)' {
        $path = New-FixtureConfig -Json '{"ConfigVersion":3,"BackupSets":{"Name":"bare","SourcePath":"s","StorePath":"st","HashRecalcFreq":"N","CompressEnabled":false}}'
        $result = Import-BackupConfiguration -Path $path
        $result.Sets.Count | Should -Be 1
        $result.Sets[0].Name | Should -Be 'bare'
    }

    It 'accepts an integral-valued ConfigVersion number (JSON has one number type: 3.0 IS 3) (SR-042)' {
        $path = New-FixtureConfig -Json '{"ConfigVersion":3.0,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st","HashRecalcFreq":"N","CompressEnabled":false}]}'
        (Import-BackupConfiguration -Path $path).ConfigVersion | Should -Be 3
    }

    It 'materializes SourceStatePath and AllowEmptySource defaults, and upper-cases HashRecalcFreq, when omitted (SR-042)' {
        $path = Join-Path $TestDrive 'minimal.json'
        [ordered]@{
            ConfigVersion = 3
            BackupSets    = @(
                [ordered]@{
                    Name = 'S'; SourcePath = 'C:\src'; StorePath = 'C:\store'
                    HashRecalcFreq = 'n'; CompressEnabled = $true
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
            Name = 'TestSet'; SourcePath = 'C:\src'; StorePath = 'C:\store'
            HashRecalcFreq = 'A'; CompressEnabled = $true
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $path

        $result = Import-BackupConfiguration -Path $path
        $result.ConfigVersion | Should -BeNullOrEmpty
        $result.Sets.Count | Should -Be 1
        $result.Sets[0].Name | Should -Be 'TestSet'
        $result.Sets[0].SourceStatePath | Should -Be 'C:\src'
        $result.Sets[0].AllowEmptySource | Should -BeFalse
        # The two roots every engine step takes are derived from the one key
        # (plan C44, S1): the latest state, and the store itself.
        $result.Sets[0].StorePath  | Should -Be 'C:\store'
        $result.Sets[0].BackupPath | Should -Be 'C:\store\CurrentBackup'
        $result.Sets[0].ChangePath | Should -Be 'C:\store'
    }

    It 'refuses a CLIXML set that still names BackupPath or ChangePath, by name, as JSON does (plan C44, L1)' {
        foreach ($retired in @(
                [ordered]@{ BackupPath = 'C:\bkp'; ChangePath = 'C:\chg' },
                [ordered]@{ StorePath = 'C:\store'; BackupPath = 'C:\bkp' },
                [ordered]@{ StorePath = 'C:\store'; ChangePath = 'C:\chg' })) {
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.xml')
            $set = [ordered]@{ Name = 'Old'; SourcePath = 'C:\src'; HashRecalcFreq = 'A'; CompressEnabled = $false }
            foreach ($k in $retired.Keys) { $set[$k] = $retired[$k] }
            @{ Secrets = $null; BackupSets = @([pscustomobject]$set) } | Export-Clixml -LiteralPath $path
            { Import-BackupConfiguration -Path $path } |
                Should -Throw -ExpectedMessage '*BackupPath and ChangePath were replaced in ConfigVersion 3 by StorePath*new, empty folder*'
        }
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

    It 'refuses a quoted "false" for AllowEmptySource rather than coercing it TRUE (SR-042)' {
        # The reviewer's reproduction: [bool]'false' is $true in PowerShell, so
        # before this check the run silently emptied the backup root and exited 0.
        $path = New-DefectiveConfig -Json '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st","HashRecalcFreq":"N","CompressEnabled":false,"AllowEmptySource":"false"}]}'
        # -Match (regex), not -ExpectedMessage (wildcard): [0] is a character
        # class to a wildcard pattern, so it would not pin the JSON path.
        $err = { Import-BackupConfiguration -Path $path } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match '\$\.BackupSets\[0\]\.AllowEmptySource .* JSON boolean'
    }

    It 'names the offending set by its real index, not a literal [?] (SR-042)' {
        $good = '{"Name":"a","SourcePath":"s","StorePath":"st","HashRecalcFreq":"N","CompressEnabled":true}'
        $bad  = '{"Name":"b","SourcePath":"s","StorePath":"st2","HashRecalcFreq":"N","CompressEnabled":"false"}'
        $path = New-DefectiveConfig -Json "{`"ConfigVersion`":3,`"BackupSets`":[$good,$bad]}"
        $err = { Import-BackupConfiguration -Path $path } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match '\$\.BackupSets\[1\]\.CompressEnabled'
    }
}

Describe 'Config v2 contract (SR-063, LLR-063)' {
    BeforeAll {
        function New-V2Json {
            param([string]$Json)
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.json')
            [IO.File]::WriteAllText($path, $Json)
            return $path
        }
        function New-V2Clixml {
            param([hashtable]$SetOverrides = @{})
            $set = [ordered]@{
                Name = 'S'; SourcePath = 'C:\src'; StorePath = 'C:\store'
                HashRecalcFreq = 'A'; CompressEnabled = $false
            }
            foreach ($k in $SetOverrides.Keys) { $set[$k] = $SetOverrides[$k] }
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.xml')
            @{ Secrets = $null; BackupSets = @([pscustomobject]$set) } | Export-Clixml -LiteralPath $path
            return $path
        }
    }

    It 'refuses ConfigVersion 1 as TOO OLD, naming the v2 change (SR-063, TC-126)' {
        $path = New-V2Json -Json '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":false}]}'
        { Import-BackupConfiguration -Path $path } |
            Should -Throw -ExpectedMessage '*declares version 1*too old*PreserveFolderTree*ConfigVersion to 3*'
    }

    It 'refuses ConfigVersion 2 as TOO OLD, naming the StorePath change (SR-063, plan C44 L1)' {
        $path = New-V2Json -Json '{"ConfigVersion":2,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":false}]}'
        { Import-BackupConfiguration -Path $path } |
            Should -Throw -ExpectedMessage '*declares version 2*too old*BackupPath and ChangePath with StorePath*ConfigVersion to 3*'
    }

    It 'refuses a JSON PreserveFolderTree with the NAMED removal diagnostic, not the generic unknown-key message (SR-063, TC-125)' {
        $path = New-V2Json -Json '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st","HashRecalcFreq":"N","CompressEnabled":false,"PreserveFolderTree":false}]}'
        $err = { Import-BackupConfiguration -Path $path } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'PreserveFolderTree was removed in ConfigVersion 2: storage is always content-addressed'
        $err.Exception.Message | Should -Not -Match 'unrecognized key'
    }

    It 'refuses a CLIXML PreserveFolderTree with the SAME named diagnostic — silent divergence is the failure class WP9 kills (SR-063, TC-126)' {
        # CLIXML is exempt from the closed schema, so without the named check a
        # legacy config would keep SAYING "mirror the tree" while the engine
        # content-addresses everything (work order §9 Q3).
        $path = New-V2Clixml -SetOverrides @{ PreserveFolderTree = $true }
        { Import-BackupConfiguration -Path $path } |
            Should -Throw -ExpectedMessage '*PreserveFolderTree was removed in ConfigVersion 2*'
    }

    It 'accepts BrowseView off/index, defaults it OFF, and defaults ViewPath to <StorePath>/View (SR-063, TC-127, plan C44 L3)' {
        $result = Import-BackupConfiguration -Path (New-V2Clixml)
        $result.Sets[0].BrowseView | Should -Be 'off'
        $result.Sets[0].ViewPath   | Should -Be 'C:\store\View'

        $result = Import-BackupConfiguration -Path (New-V2Clixml -SetOverrides @{ BrowseView = 'index'; ViewPath = 'C:\elsewhere\view' })
        $result.Sets[0].BrowseView | Should -Be 'index'
        $result.Sets[0].ViewPath   | Should -Be 'C:\elsewhere\view'
    }

    It 'refuses BrowseView ''link'' BY NAME (reserved) and anything else by vocabulary, in CLIXML too (SR-063, TC-127)' {
        { Import-BackupConfiguration -Path (New-V2Clixml -SetOverrides @{ BrowseView = 'link' }) } |
            Should -Throw -ExpectedMessage '*BrowseView*link*reserved*'
        { Import-BackupConfiguration -Path (New-V2Clixml -SetOverrides @{ BrowseView = 'sideways' }) } |
            Should -Throw -ExpectedMessage '*invalid BrowseView*'
    }

    It 'refuses a ViewPath inside the store, except at exactly <StorePath>/View, at path resolution (SR-063, TC-128, plan C44 L3)' {
        $root = Join-Path $TestDrive 'tc128-contain'
        $src = Join-Path $root 'src'; $chg = Join-Path $root 'chg'; $bkp = Join-Path $chg 'CurrentBackup'
        New-Item -ItemType Directory -Path $src, $bkp, $chg, (Join-Path $chg 'BackupHistory') -Force | Out-Null
        $mk = { param($vp) [pscustomobject]@{
            Name = 'S'; SourcePath = $src; StorePath = $chg
            SourceStatePath = ''; BrowseView = 'index'; ViewPath = $vp } }
        # Inside CurrentBackup, or CurrentBackup itself.
        { Resolve-BackupSetPaths -Set (& $mk (Join-Path $bkp 'view')) } |
            Should -Throw -ExpectedMessage '*must lie outside the store*'
        { Resolve-BackupSetPaths -Set (& $mk $bkp) } |
            Should -Throw -ExpectedMessage '*IS the store*'
        # Inside the store anywhere but its one View folder: a snapshot, a run
        # folder, or a folder of another name.
        { Resolve-BackupSetPaths -Set (& $mk (Join-Path $chg 'elsewhere')) } |
            Should -Throw -ExpectedMessage '*must lie outside the store*'
        { Resolve-BackupSetPaths -Set (& $mk (Join-Path $chg 'BackupHistory/2026_01_01_00_00_00')) } |
            Should -Throw -ExpectedMessage '*must lie outside the store*'
        { Resolve-BackupSetPaths -Set (& $mk (Join-Path $chg 'View\deeper')) } |
            Should -Throw -ExpectedMessage '*must lie outside the store*'
        # Exactly <StorePath>/View is the store's own view folder, and accepted.
        (Resolve-BackupSetPaths -Set (& $mk (Join-Path $chg 'View'))).ViewPath |
            Should -Be ([IO.Path]::GetFullPath((Join-Path $chg 'View')))
        # BrowseView off validates nothing: the same contained path is inert.
        $offSet = & $mk (Join-Path $bkp 'view'); $offSet.BrowseView = 'off'
        { Resolve-BackupSetPaths -Set $offSet } | Should -Not -Throw
    }

    It 'refuses a ViewPath that CONTAINS a storage root or the source tree (SR-063, TC-128, WP9 review MAJ-1)' {
        # The rail shipped one-directional: it caught "view inside an owned
        # path" and missed "view CONTAINING one", which is the destructive
        # direction - the view root is wiped on every refresh, so a ViewPath
        # naming an ancestor of BackupPath deleted the whole store and one
        # naming SourcePath deleted the user's files, on a run that reported
        # success. Both reproduced on 2026-08-25 before this arm existed.
        $root = Join-Path $TestDrive 'tc128-ancestor'
        $store = Join-Path $root 'store'
        $src = Join-Path $root 'src'; $chg = Join-Path $store 'chg'; $bkp = Join-Path $chg 'CurrentBackup'
        $state = Join-Path $root 'state'
        New-Item -ItemType Directory -Path $src, $bkp, $chg, (Join-Path $chg 'BackupHistory'), $state -Force | Out-Null
        $mk = { param($vp) [pscustomobject]@{
            Name = 'S'; SourcePath = $src; StorePath = $chg
            SourceStatePath = $state; BrowseView = 'index'; ViewPath = $vp } }

        # ancestor of the store (and so of CurrentBackup)
        { Resolve-BackupSetPaths -Set (& $mk $store) } |
            Should -Throw -ExpectedMessage '*CONTAINS the store*'
        # the store itself
        { Resolve-BackupSetPaths -Set (& $mk $chg) } |
            Should -Throw -ExpectedMessage '*the store*WIPED*'
        # ancestor of everything, storage and source alike
        { Resolve-BackupSetPaths -Set (& $mk $root) } |
            Should -Throw -ExpectedMessage '*CONTAINS*'
        # IS the source tree, and IS the source-state cache
        { Resolve-BackupSetPaths -Set (& $mk $src) } |
            Should -Throw -ExpectedMessage '*IS the source tree*'
        { Resolve-BackupSetPaths -Set (& $mk $state) } |
            Should -Throw -ExpectedMessage '*IS the source tree*'
        # A sibling whose name merely shares a prefix is NOT a container:
        # the check must compare path COMPONENTS, not raw string prefixes.
        { Resolve-BackupSetPaths -Set (& $mk ($src + '-sibling')) } |
            Should -Not -Throw -Because 'src-sibling neither contains nor sits inside src'
        # and the legitimate shape still resolves
        (Resolve-BackupSetPaths -Set (& $mk (Join-Path $root 'view'))).ViewPath |
            Should -Be ([IO.Path]::GetFullPath((Join-Path $root 'view')))
    }

    It 'refuses a ViewPath on a different volume; the default <StorePath>/View resolves (SR-063, TC-128)' {
        $free = @('X', 'Y', 'W', 'V', 'U') |
                Where-Object { $_ -notin (Get-PSDrive -PSProvider FileSystem).Name } |
                Select-Object -First 1
        if (-not $free) { Set-ItResult -Skipped -Because 'no free drive letter for subst'; return }
        $root = Join-Path $TestDrive 'tc128-volume'
        $src = Join-Path $root 'src'; $chg = Join-Path $root 'chg'; $bkp = Join-Path $chg 'CurrentBackup'
        $other = Join-Path $root 'othervol'
        New-Item -ItemType Directory -Path $src, $bkp, $chg, (Join-Path $chg 'BackupHistory'), $other -Force | Out-Null
        $substOut = & cmd.exe /c "subst ${free}: `"$other`"" 2>&1
        if ($LASTEXITCODE -ne 0) { Set-ItResult -Skipped -Because "subst failed: $substOut"; return }
        try {
            $set = [pscustomobject]@{
                Name = 'S'; SourcePath = $src; StorePath = $chg
                SourceStatePath = ''; BrowseView = 'index'; ViewPath = "${free}:\view"
            }
            { Resolve-BackupSetPaths -Set $set } |
                Should -Throw -ExpectedMessage '*must be on the backup volume*'
        } finally {
            & cmd.exe /c "subst ${free}: /D" 2>&1 | Out-Null
        }

        # The materialized default is always legal: <StorePath>/View, inside
        # the store on its volume (plan C44, L3).
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; StorePath = $chg
            SourceStatePath = ''; BrowseView = 'index'; ViewPath = ''
        }
        (Resolve-BackupSetPaths -Set $set).ViewPath | Should -Be (Join-Path (Resolve-Path -LiteralPath $chg).Path 'View')
    }
}
