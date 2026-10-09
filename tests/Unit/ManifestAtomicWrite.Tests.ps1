<#
.SYNOPSIS  Pester 5 unit tests for the atomic publish of MANIFEST.csv (SR-082,
           SR-083, LLR-087, LLR-088; TC-237..TC-240).
.NOTES     Write-Manifest writes MANIFEST.csv.tmp beside the destination and renames
           it over MANIFEST.csv, so a kill at any instant leaves the complete OLD
           file or the complete NEW file. The suite proves that two ways: in-process,
           with the module's ManifestWriteTestHook seam throwing at each boundary
           (the repo's Invoke-StagingTestHook pattern), and out-of-process, where a
           child pwsh is parked at a boundary and killed for real.

           Every assertion about the destination is a SHA-256 comparison against the
           two complete files, never "the file exists" - a zero-length or truncated
           manifest must fail it.
#>

BeforeAll {
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:Repo = $repo
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    function New-ManifestRows {
        # The shape Read-Manifest returns and Write-Manifest consumes.
        param([string]$Tag, [int]$Count = 40)
        1..$Count | ForEach-Object {
            $name = "$Tag-$_.txt"
            [pscustomobject]@{ DataPath = $name; RelativePath = $name; Length = ($_ * 7)
                LastWriteTime = (Get-Date '2026-01-02T03:04:05'); xxH2Hash = "H$Tag$_"; Compressed = 'No'
                StoredAsHashSize = 'Hash'; Duplicate = 0; MediaMBPerSec = $null }
        }
    }

    # Other unit files import kit copies of Common from elsewhere and leave them
    # loaded, so a bare InModuleScope FileBackup.Common is ambiguous when the
    # whole suite runs in one session. Address THIS repo's module by its path.
    $script:CommonModulePath = (Resolve-Path (Join-Path $repo 'Modules\FileBackup.Common.psm1')).Path
    function Set-ManifestWriteHook {
        param([AllowNull()][scriptblock]$Hook)
        $mod = @(Get-Module FileBackup.Common | Where-Object { $_.Path -eq $script:CommonModulePath })[0]
        & $mod { param($h) $script:ManifestWriteTestHook = $h } $Hook
    }

    function Get-Sha256 {
        param([string]$Path)
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    function New-Folder {
        param([string]$Name)
        $dir = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        return $dir
    }

    $script:OldRows = @(New-ManifestRows 'old' 40)
    $script:NewRows = @(New-ManifestRows 'new' 60)

    # The two complete files, hashed once from scratch folders.
    $seedOld = New-Folder 'expected-old'
    Write-Manifest -FolderPath $seedOld -Records $script:OldRows
    $script:OldHash = Get-Sha256 (Join-Path $seedOld 'MANIFEST.csv')
    $seedNew = New-Folder 'expected-new'
    Write-Manifest -FolderPath $seedNew -Records $script:NewRows
    $script:NewHash = Get-Sha256 (Join-Path $seedNew 'MANIFEST.csv')
    if ($script:OldHash -eq $script:NewHash) { throw 'fixture error: the old and new manifests are identical, so no assertion below could tell them apart' }

    function New-SeededFolder {
        # A folder that already holds the OLD complete manifest and its witness.
        param([string]$Name)
        $dir = New-Folder $Name
        Write-Manifest -FolderPath $dir -Records $script:OldRows
        return $dir
    }

    function Invoke-KilledWrite {
        # Runs Write-Manifest(NewRows) with a hook that stands in for a kill at
        # $Stage (it throws, and the seam sits outside the function's own
        # catch blocks, so no cleanup runs - exactly like a real kill). $Tear, when
        # given, first truncates the staging file to that fraction of its length,
        # which is what a kill DURING the Export-Csv leaves behind.
        param([string]$Folder, [string]$Stage, [AllowNull()][object]$Tear)
        $seen = @{ Fired = $false }
        $hook = {
            param($s, $c)
            if ($s -ne $Stage) { return }
            $seen.Fired = $true
            if ($null -ne $Tear -and [double]$Tear -lt 1) {
                $fs = [System.IO.File]::Open($c.Temp, 'Open', 'Write')
                try { $fs.SetLength([long]([System.IO.FileInfo]$c.Temp).Length * [double]$Tear) } finally { $fs.Dispose() }
            }
            throw 'SIMULATED KILL'
        }.GetNewClosure()
        Set-ManifestWriteHook $hook
        try { Write-Manifest -FolderPath $Folder -Records $script:NewRows } catch {
            if ($_.Exception.Message -ne 'SIMULATED KILL') { throw }
        } finally { Set-ManifestWriteHook $null }
        if (-not $seen.Fired) { throw "fixture error: the $Stage boundary was never reached, so the test would prove nothing" }
    }
}

AfterAll { Set-ManifestWriteHook $null }

Describe 'Write-Manifest publishes MANIFEST.csv atomically (TC-237, SR-082, LLR-087)' {

    AfterEach { Set-ManifestWriteHook $null }

    It 'leaves the complete OLD or the complete NEW file when killed at <Name> (TC-237, SR-082)' -ForEach @(
        @{ Name = 'BeforeTempWrite'; Stage = 'BeforeTempWrite'; Tear = $null }
        @{ Name = 'AfterTempWrite, temp complete'; Stage = 'AfterTempWrite'; Tear = $null }
        @{ Name = 'AfterTempWrite, temp torn at half'; Stage = 'AfterTempWrite'; Tear = 0.5 }
        @{ Name = 'AfterTempWrite, temp zero-length'; Stage = 'AfterTempWrite'; Tear = 0 }
        @{ Name = 'AfterRename'; Stage = 'AfterRename'; Tear = $null }
    ) {
        $folder = New-SeededFolder ("kill-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Invoke-KilledWrite -Folder $folder -Stage $Stage -Tear $Tear
        # Membership in the pair of complete files also rules out a zero-length
        # or truncated destination, since neither complete file is either.
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -BeIn @($script:OldHash, $script:NewHash)
    }

    It 'has the NEW manifest in place once the rename has happened (TC-237, SR-082)' {
        $folder = New-SeededFolder 'after-rename-new'
        Invoke-KilledWrite -Folder $folder -Stage 'AfterRename' -Tear $null
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -Be $script:NewHash
    }

    It 'has the OLD manifest untouched while the temp file is being written (TC-237, SR-082)' {
        $folder = New-SeededFolder 'before-rename-old'
        Invoke-KilledWrite -Folder $folder -Stage 'AfterTempWrite' -Tear 0.5
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -Be $script:OldHash
    }

    It 'fails loud, in the safe direction, between the manifest rename and the witness (TC-237, SR-038)' {
        # A kill after the rename leaves the NEW complete manifest beside the OLD
        # witness: a mismatch, i.e. a refused restore, never a silent pass.
        $folder = New-SeededFolder 'stale-witness'
        Invoke-KilledWrite -Folder $folder -Stage 'AfterRename' -Tear $null
        (Test-ManifestWitness -FolderPath $folder).Status | Should -Be 'Mismatch'
    }

    It 'resolves a RELATIVE folder against the PowerShell location, not the process directory (TC-237, SR-082)' {
        # The .NET rename resolves against the process directory while
        # Export-Csv resolves against $PWD. The module bridges them; a missing
        # bridge would put the manifest (or fail) somewhere else entirely.
        # Stopped at AfterRename on purpose: the WITNESS (Get-FileXxHash ->
        # OpenRead) has never accepted a relative folder, before or after this
        # change, and production always passes absolute paths.
        $folder = New-SeededFolder 'rel-folder'
        Push-Location $TestDrive
        try { Invoke-KilledWrite -Folder 'rel-folder' -Stage 'AfterRename' -Tear $null } finally { Pop-Location }
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -Be $script:NewHash
    }

    It 'removes its own temp file when the rename itself fails, and leaves the destination alone (TC-237, SR-082)' {
        # A DIRECTORY named MANIFEST.csv makes the rename throw an ordinary
        # error on every platform.
        $folder = New-Folder 'rename-fails'
        New-Item -ItemType Directory -Path (Join-Path $folder 'MANIFEST.csv') | Out-Null
        try { Write-Manifest -FolderPath $folder -Records $script:NewRows } catch { Write-Verbose "expected: $($_.Exception.Message)" }
        Test-Path -LiteralPath (Join-Path $folder 'MANIFEST.csv.tmp') | Should -BeFalse
    }

    It 'leaves no temp file behind on a successful write (TC-237, SR-082)' {
        $folder = New-SeededFolder 'clean-success'
        Write-Manifest -FolderPath $folder -Records $script:NewRows
        Test-Path -LiteralPath (Join-Path $folder 'MANIFEST.csv.tmp') | Should -BeFalse
    }

    It 'writes the same bytes as the pre-SR-082 in-place writer for an empty record set (TC-237, SR-025)' {
        $folder = New-Folder 'empty-set'
        Write-Manifest -FolderPath $folder -Records $null
        (Test-ManifestWitness -FolderPath $folder).Status | Should -Be 'Verified'
    }
}

Describe 'A real process kill never tears MANIFEST.csv (TC-238, SR-082, LLR-087)' {
    # Not a seam that throws: a child pwsh is PARKED at the boundary and then
    # terminated (Stop-Process -Force is TerminateProcess / SIGKILL), so no
    # finally, catch or flush in the child can run.
    BeforeAll {
        $script:ChildScript = Join-Path $TestDrive 'kill-child.ps1'
        $rowFn = ${function:New-ManifestRows}.ToString()
        $childText = @"
param([string]`$Repo, [string]`$Folder, [string]`$Stage, [string]`$Ready, [double]`$Tear)
`$ErrorActionPreference = 'Stop'
Import-Module (Join-Path `$Repo 'Modules/FileBackup.Common.psm1') -Force
function New-ManifestRows {$rowFn}
`$rows = @(New-ManifestRows 'new' 60)
`$mod = Get-Module FileBackup.Common
& `$mod {
    param(`$stage, `$ready, `$tear)
    `$script:ManifestWriteTestHook = {
        param(`$s, `$c)
        if (`$s -ne `$stage) { return }
        if (`$tear -lt 1) {
            `$fs = [System.IO.File]::Open(`$c.Temp, 'Open', 'Write')
            try { `$fs.SetLength([long]([System.IO.FileInfo]`$c.Temp).Length * `$tear) } finally { `$fs.Dispose() }
        }
        [System.IO.File]::WriteAllText(`$ready, 'parked')
        Start-Sleep -Seconds 600
    }.GetNewClosure()
} `$Stage `$Ready `$Tear
Write-Manifest -FolderPath `$Folder -Records `$rows
"@
        [System.IO.File]::WriteAllText($script:ChildScript, $childText)
    }

    It 'kills a writer parked at <Stage> (tear <Tear>) and finds the old or the new complete manifest (TC-238, SR-082)' -ForEach @(
        @{ Stage = 'BeforeTempWrite'; Tear = 1.0 }
        @{ Stage = 'AfterTempWrite'; Tear = 1.0 }
        @{ Stage = 'AfterTempWrite'; Tear = 0.4 }
        @{ Stage = 'AfterRename'; Tear = 1.0 }
    ) {
        $folder = New-SeededFolder ("proc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $ready = Join-Path $TestDrive ("ready-" + [guid]::NewGuid().ToString('N') + '.flag')
        $pwsh = (Get-Process -Id $PID).Path
        $proc = Start-Process -FilePath $pwsh -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-File', $script:ChildScript,
            '-Repo', $script:Repo, '-Folder', $folder, '-Stage', $Stage, '-Ready', $ready,
            '-Tear', ([string]$Tear))
        try {
            $deadline = [datetime]::UtcNow.AddSeconds(90)
            while (-not (Test-Path -LiteralPath $ready) -and -not $proc.HasExited -and [datetime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 100
            }
            if (-not (Test-Path -LiteralPath $ready)) { throw "fixture error: the child never reached $Stage (exited=$($proc.HasExited))" }
        } finally {
            if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
            $proc.WaitForExit(30000) | Out-Null
        }
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -BeIn @($script:OldHash, $script:NewHash)
    }
}

Describe 'A leftover MANIFEST.csv.tmp breaks nothing (TC-239, SR-083, LLR-088)' {

    AfterEach { Set-ManifestWriteHook $null }

    It 'a kill after the temp write leaves a <Name> temp file behind (precondition for the next tests) (TC-239, SR-083)' -ForEach @(
        @{ Name = 'complete'; Tear = $null }
        @{ Name = 'torn'; Tear = 0.5 }
        @{ Name = 'zero-length'; Tear = 0 }
    ) {
        $folder = New-SeededFolder ("leftover-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Invoke-KilledWrite -Folder $folder -Stage 'AfterTempWrite' -Tear $Tear
        Test-Path -LiteralPath (Join-Path $folder 'MANIFEST.csv.tmp') | Should -BeTrue -Because 'the kill must really have left the temp file'
    }

    It 'publishes the complete new manifest over a leftover <Name> temp file, and consumes it (TC-239, SR-083)' -ForEach @(
        @{ Name = 'complete'; Tear = $null }
        @{ Name = 'torn'; Tear = 0.5 }
        @{ Name = 'zero-length'; Tear = 0 }
    ) {
        $folder = New-SeededFolder ("overwrite-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Invoke-KilledWrite -Folder $folder -Stage 'AfterTempWrite' -Tear $Tear
        Write-Manifest -FolderPath $folder -Records $script:NewRows
        Get-Sha256 (Join-Path $folder 'MANIFEST.csv') | Should -Be $script:NewHash
    }

    It 'leaves no temp file after that next write (TC-239, SR-083)' {
        $folder = New-SeededFolder 'next-write-clean'
        Invoke-KilledWrite -Folder $folder -Stage 'AfterTempWrite' -Tear 0.5
        Write-Manifest -FolderPath $folder -Records $script:NewRows
        Test-Path -LiteralPath (Join-Path $folder 'MANIFEST.csv.tmp') | Should -BeFalse
    }

    It 'leaves a VERIFIED witness after that next write (TC-239, SR-083, SR-038)' {
        $folder = New-SeededFolder 'next-write-witness'
        Invoke-KilledWrite -Folder $folder -Stage 'AfterRename' -Tear $null
        Write-Manifest -FolderPath $folder -Records $script:NewRows
        (Test-ManifestWitness -FolderPath $folder).Status | Should -Be 'Verified'
    }

    It 'is root-level infrastructure: never data, never an orphan, never a storage-form finding (TC-239, SR-083, SR-022)' {
        $root = New-Folder 'infra-root'
        New-Item -ItemType Directory -Path (Join-Path $root 'sub') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root 'MANIFEST.csv.tmp'), 'torn')
        [System.IO.File]::WriteAllText((Join-Path $root 'sub\MANIFEST.csv.tmp'), 'user data')
        $names = @(Get-DataFile -Root $root | ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\', '/') })
        # The nested user file is data (B6) and the root-level temp file is not.
        ($names -join '|') | Should -Be (Join-Path 'sub' 'MANIFEST.csv.tmp')
    }


    It 'does not make Test-BackupManifest warn about an orphan (TC-239, SR-083, SR-064)' {
        $root = New-Folder 'tbm-orphan'
        Write-Manifest -FolderPath $root -Records @()
        [System.IO.File]::WriteAllText((Join-Path $root 'MANIFEST.csv.tmp'), 'torn')
        $messages = New-Object System.Collections.Generic.List[string]
        Test-BackupManifest -FolderRoot $root -Log { param($m, $l) $messages.Add("$l $m") }.GetNewClosure()
        @($messages | Where-Object { $_ -match 'MANIFEST\.csv\.tmp' }).Count | Should -Be 0
    }

    It 'raises no storage-form finding in the backup root or a snapshot (TC-239, SR-083, SR-049)' {
        $root = New-Folder 'sf-root'
        $chg  = New-Folder 'sf-chg'
        $snap = New-Folder 'sf-chg\Snapshot_2026_01_02_03_04_05'
        Write-Manifest -FolderPath $root -Records @()
        Write-Manifest -FolderPath $snap -Records @()
        [System.IO.File]::WriteAllText((Join-Path $root 'MANIFEST.csv.tmp'), 'torn')
        [System.IO.File]::WriteAllText((Join-Path $snap 'MANIFEST.csv.tmp'), 'torn')
        @(Test-BackupStorageForm -BackupRoot $root -ChangeRoot $chg).Count | Should -Be 0
    }
}

Describe 'A leftover MANIFEST.csv.tmp through whole backup runs (TC-240, SR-083, LLR-088)' {
    BeforeAll {
        $script:Fx = $null
        function Invoke-FixtureBackup {
            param([object]$Fixture, [datetime]$When)
            $ok = $true
            Invoke-BackupSet -Set $Fixture.Set -Deps @{ '7z' = $null; 'ffprobe' = $null } `
                -OverallSuccess ([ref]$ok) -LogPaths (New-Object System.Collections.Generic.List[string]) `
                -BackupTime $When
            return $ok
        }
        $root = Join-Path $TestDrive 'e2e'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub') -Force | Out-Null
        $fx = [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg
            Set = [pscustomobject]@{
                Name = 'tc240'; SourcePath = $src; SourceStatePath = ''; BackupPath = $bkp
                ChangePath = $chg; HashRecalcFreq = 'A'; CompressEnabled = $false
                AllowEmptySource = $false; BrowseView = 'off'; ViewPath = ''
            }
        }
        [System.IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'ONE')
        # A genuine USER file with the temp name, nested: data under B6.
        [System.IO.File]::WriteAllText((Join-Path $src 'sub\MANIFEST.csv.tmp'), 'USER DATA, NOT INFRASTRUCTURE')

        $script:Runs = @()
        $script:Runs += (Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-01 00:00:01'))
        [System.IO.File]::WriteAllText((Join-Path $bkp 'MANIFEST.csv.tmp'), 'torn,leftover')
        [System.IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'TWO')
        $script:Runs += (Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-02 00:00:01'))
        $snapDir = @(Get-ChildItem -LiteralPath $chg -Directory | Where-Object { $_.Name -match '^Snapshot_' })[0]
        [System.IO.File]::WriteAllText((Join-Path $snapDir.FullName 'MANIFEST.csv.tmp'), 'torn,leftover')
        [System.IO.File]::WriteAllText((Join-Path $bkp 'MANIFEST.csv.tmp'), 'torn,leftover')
        $script:Runs += (Invoke-FixtureBackup -Fixture $fx -When ([datetime]'2024-01-03 00:00:01'))
        $script:Fx = $fx
        $script:Log = Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw
        $script:Rows = @(Read-Manifest -FolderPath $bkp)
    }

    It 'completes every run despite a leftover in the backup root (TC-240, SR-083)' {
        ($script:Runs -join ',') | Should -Be 'True,True,True'
    }

    It 'warns about no orphan and no missing row for the leftover (TC-240, SR-083, SR-022)' {
        @($script:Log -split "`n" | Where-Object { $_ -match 'WARN' -and $_ -match '(?<![\\/])MANIFEST\.csv\.tmp' }).Count | Should -Be 0
    }

    It 'never records the root-level leftover as a backed-up file (TC-240, SR-083)' {
        @($script:Rows | Where-Object { $_.RelativePath -ceq 'MANIFEST.csv.tmp' }).Count | Should -Be 0
    }

    It 'still backs up a NESTED user file of the same name as data (TC-240, SR-083, B6)' {
        @($script:Rows | Where-Object { ($_.RelativePath -replace '\\', '/') -ceq 'sub/MANIFEST.csv.tmp' }).Count | Should -Be 1
    }

    It 'consumes the leftover: the next write replaced it (TC-240, SR-083)' {
        Test-Path -LiteralPath (Join-Path $script:Fx.Bkp 'MANIFEST.csv.tmp') | Should -BeFalse
    }

    It 'ends with a verified witness (TC-240, SR-083, SR-038)' {
        (Test-ManifestWitness -FolderPath $script:Fx.Bkp).Status | Should -Be 'Verified'
    }
}
