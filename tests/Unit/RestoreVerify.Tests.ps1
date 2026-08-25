<#
.SYNOPSIS  Kit-revision-6 restore surface: locator exit-code honesty (D-3),
           verify-after-write (D-2), non-interactive parity, hidden/dot capture
           probes (SR-040, SR-056, SR-016, SR-057).
.NOTES     TC-108, TC-111, TC-114, TC-115 (Windows half; TC-109/TC-112 are the
           bats twins). These drive real backup runs and real restores, so they
           also exercise the engine I/O shells. Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry = Join-Path $repo 'FileBackup.ps1'
    $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath

    function New-RVConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $false)
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
            PreserveFolderTree = $true
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function New-RVStore {
        <#
        .SYNOPSIS
            A real Mirror backup of two known files under $Root, returning the
            paths a tampering test needs. The deployed RECONSTRUCT.ps1 is the
            restorer under test (copied verbatim from the repo at backup time).
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path $src, $bkp, $chg -Force | Out-Null
        # b.txt is large and repetitive so a Compress-mode store reliably stores
        # it as a .7z archive (the compression decision is per-file).
        Set-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'ALPHA-CONTENT' -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'b.txt') -Value ('BETA-CONTENT-X' * 4000) -NoNewline
        $cfg = Join-Path $Root 'cfg.xml'
        New-RVConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
        [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg
            Manifest = Join-Path $bkp 'MANIFEST.csv'
            Recon    = Join-Path $bkp 'RECONSTRUCT.ps1'
        }
    }

    function Set-ManifestRows {
        # Rewrite a folder's MANIFEST.csv and re-stamp its SR-038 witness so the
        # tampered store fails the way the test means to exercise, not exit 3.
        param([string]$Folder, [object[]]$Rows)
        $Rows | Export-Csv -LiteralPath (Join-Path $Folder 'MANIFEST.csv') -NoTypeInformation
        Write-ManifestWitness -FolderPath $Folder | Out-Null
    }

    function Invoke-ReconstructExitCode {
        # Child process so RECONSTRUCT.ps1's -ExitCode `exit` is observable at
        # the process boundary — the same numbers reconstruct.sh returns.
        param([string]$Recon, [string]$TargetRoot, [string[]]$Extra = @())
        & (Get-Process -Id $PID).Path -NoProfile -File $Recon -TargetRoot $TargetRoot -ExitCode @Extra *>&1 |
            Out-File -LiteralPath (Join-Path (Split-Path $TargetRoot -Parent) 'recon-out.txt')
        return $LASTEXITCODE
    }
}

Describe 'Locator exit-code honesty — a bad pool candidate is data damage, not a host problem (SR-040, D-3)' {
    # TC-111. The locator is only ever called when the row's own file is blank
    # or missing, so no candidate it inspects is the row's own file: an
    # unexpandable archive there proves nothing about this host (kit rev 6).

    It 'an unrelated unexpandable .7z in the pool yields ContentMissing / exit 1, naming the candidate (TC-111)' {
        $root = Join-Path $TestDrive 'd3-content'
        $s = New-RVStore -Root $root
        # Blank a.txt's DataPath and remove its bytes: recovery must scan a pool
        # whose only .7z is garbage — under the old code that flipped "your
        # bytes are gone" (1) into "fix this host" (4).
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $a = $rows | Where-Object RelativePath -eq 'a.txt'
        $a.DataPath = ''
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Force
        [IO.File]::WriteAllBytes((Join-Path $s.Bkp 'noise.7z'), [byte[]](1..64))
        Set-ManifestRows -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 1
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[ContentMissing\]'
        $log | Should -Match 'could not be expanded'
        $log | Should -Match 'noise\.7z'
        $log | Should -Not -Match '\[CandidateError\]'
        # Salvage semantics: the healthy row still restored.
        Get-Content -LiteralPath (Join-Path $t 'b.txt') -Raw | Should -Be ('BETA-CONTENT-X' * 4000)
    }

    It 'a candidate that cannot be READ is a host condition: StorageUnreadable / exit 4 (TC-111)' {
        $root = Join-Path $TestDrive 'd3-locked'
        $s = New-RVStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $a = $rows | Where-Object RelativePath -eq 'a.txt'
        $a.DataPath = ''
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Force
        Set-ManifestRows -Folder $s.Bkp -Rows $rows
        # A same-length candidate the locator must hash — held open with no
        # sharing, so the read throws (I/O/lock class, not data damage).
        $locked = Join-Path $s.Bkp 'noise.bin'
        [IO.File]::WriteAllText($locked, 'X' * [int]$a.Length)
        $h = [IO.File]::Open($locked, 'Open', 'Read', 'None')
        try {
            $t = Join-Path $root 't'
            $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
            $code | Should -Be 4
            $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
            $log | Should -Match '\[StorageUnreadable\]'
            $log | Should -Match 'could not be read'
        } finally { $h.Dispose() }
    }

    It 'a no-7-Zip unreadable candidate records exactly ONE cause (TC-111, folded nit)' {
        $root = Join-Path $TestDrive 'd3-no7z'
        $s = New-RVStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $a = $rows | Where-Object RelativePath -eq 'a.txt'
        $a.DataPath = ''
        Remove-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Force
        Set-ManifestRows -Folder $s.Bkp -Rows $rows
        # A same-length .7z-named candidate, locked: with no 7-Zip the raw test
        # throws — 7-Zip could not have helped read a file that cannot be read,
        # so DependencyMissing must NOT also be recorded for it.
        $locked = Join-Path $s.Bkp 'noise.7z'
        [IO.File]::WriteAllText($locked, 'X' * [int]$a.Length)
        $h = [IO.File]::Open($locked, 'Open', 'Read', 'None')
        try {
            $t = Join-Path $root 't'
            $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t `
                -Extra @('-SevenZipPath', (Join-Path $root 'no-such-7z.exe'))
            $code | Should -Be 4
            $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
            $log | Should -Match '\[StorageUnreadable\]'
            $log | Should -Not -Match 'DependencyMissing'
        } finally { $h.Dispose() }
    }

    It "a row's OWN archive failing to expand is still host class / exit 4 (TC-111 non-regression)" {
        $root = Join-Path $TestDrive 'd3-own'
        $s = New-RVStore -Root $root -Compress $true
        # Replace b.txt's own stored archive with garbage: the row resolves
        # through its own DataPath, so this failure is about THIS host's ability
        # to extract it — CandidateError, exit 4, unchanged by D-3.
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $b = $rows | Where-Object RelativePath -eq 'b.txt'
        $b.DataPath | Should -Match '\.7z$'
        [IO.File]::WriteAllBytes((Join-Path $s.Bkp $b.DataPath), [byte[]](5..99))
        Write-ManifestWitness -FolderPath $s.Bkp | Out-Null

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 4
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[CandidateError\]'
    }

    It 'a genuine host failure alongside a content failure still reports 4 (SR-040 precedence, TC-111)' {
        $root = Join-Path $TestDrive 'd3-mixed'
        $s = New-RVStore -Root $root -Compress $true
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $a = $rows | Where-Object RelativePath -eq 'a.txt'
        $b = $rows | Where-Object RelativePath -eq 'b.txt'
        # a.txt: content class — bytes gone from every pool folder (a first
        # backup writes no snapshot, so the backup root is the whole pool).
        $aData = $a.DataPath
        $a.DataPath = ''
        Remove-Item -LiteralPath (Join-Path $s.Bkp $aData) -Force
        # b.txt: host class — its own archive is garbage.
        $b.DataPath | Should -Match '\.7z$'
        [IO.File]::WriteAllBytes((Join-Path $s.Bkp $b.DataPath), [byte[]](5..99))
        Set-ManifestRows -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 4
        (Get-Content -LiteralPath (Join-Path $root 'recon-out.txt') -Raw) |
            Should -Match '1 content-missing, 1 host'
    }
}

Describe 'Restore verifies the bytes it wrote (SR-056, D-2)' {
    # TC-108. Before kit revision 6 both restorers trusted a resolvable
    # DataPath: wrong payload, a same-length bit-flip, even truncation
    # restored with exit 0.

    It 'heals a wrong-payload data file from a surviving pool copy: exit 0, byte-exact, warning logged (TC-108)' {
        $root = Join-Path $TestDrive 'd2-heal'
        $s = New-RVStore -Root $root
        # A good copy survives elsewhere in the pool under an unrelated name;
        # the row's own data file carries same-length wrong bytes.
        Copy-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Destination (Join-Path $s.Bkp 'spare.bin')
        Set-Content -LiteralPath (Join-Path $s.Bkp 'a.txt') -Value 'WRONG-CONTENT' -NoNewline

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'a.txt') -Raw | Should -Be 'ALPHA-CONTENT'
        # A silent heal that leaves no trace is not acceptable: the warning and
        # the recovery must both be in the log.
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[ContentMismatch\]'
        $log | Should -Match 'after a verify mismatch'
    }

    It 'a same-length bit-flip with no surviving copy fails loudly naming the row: exit 1 (TC-108)' {
        $root = Join-Path $TestDrive 'd2-flip'
        $s = New-RVStore -Root $root
        $bytes = [IO.File]::ReadAllBytes((Join-Path $s.Bkp 'a.txt'))
        $bytes[-1] = $bytes[-1] -bxor 0xFF
        [IO.File]::WriteAllBytes((Join-Path $s.Bkp 'a.txt'), $bytes)

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $root 'recon-out.txt') -Raw) |
            Should -Match '1 content-missing, 0 host'
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[ContentMismatch\].*a\.txt'
        # The bad bytes were deleted, not left where good ones were asked for;
        # every other row still restored (SR-029 salvage).
        Test-Path (Join-Path $t 'a.txt') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $t 'b.txt') -Raw | Should -Be ('BETA-CONTENT-X' * 4000)
    }

    It 'truncation is caught by the length check before any hashing (TC-108)' {
        $root = Join-Path $TestDrive 'd2-trunc'
        $s = New-RVStore -Root $root
        Set-Content -LiteralPath (Join-Path $s.Bkp 'a.txt') -Value 'ALPHA' -NoNewline

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 1
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[ContentMismatch\]'
        $log | Should -Match 'got \(not hashed\)/5'
    }

    It "a valid archive with the WRONG payload at the row's own DataPath is healed from a pool copy (TC-108 archive arm)" {
        $root = Join-Path $TestDrive 'd2-arch'
        $s = New-RVStore -Root $root -Compress $true
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $b = $rows | Where-Object RelativePath -eq 'b.txt'
        $b.DataPath | Should -Match '\.7z$'
        # Keep a good pool copy under an unrelated name, then repack the row's
        # own archive with DIFFERENT bytes — a corrupt container exits 4, so
        # the wrong-payload arm needs a genuinely valid archive (plan §6.1).
        Copy-Item -LiteralPath (Join-Path $s.Bkp $b.DataPath) -Destination (Join-Path $s.Bkp 'spare.7z')
        $work = Join-Path $root 'repack'
        New-Item -ItemType Directory -Path $work | Out-Null
        [IO.File]::WriteAllText((Join-Path $work 'b.txt'), ('OTHER-PAYLOAD-' * 4000))
        Compress-FileWithSevenZip -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath `
            -SourceFile (Join-Path $work 'b.txt') -Destination7z (Join-Path $work 'wrong.7z')
        Move-Item -LiteralPath (Join-Path $work 'wrong.7z') -Destination (Join-Path $s.Bkp $b.DataPath) -Force

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'b.txt') -Raw | Should -Be ('BETA-CONTENT-X' * 4000)
        $log = Get-Content -LiteralPath (Join-Path $t 'RECONSTRUCT.log') -Raw
        $log | Should -Match '\[ContentMismatch\]'
    }
}

Describe 'Hidden and dot-prefixed entries are captured and located (SR-057, TC-114)' {
    # Site-specific probes for the D-4 -Force sweep; the end-to-end capture
    # across all four modes is suite case G5.8 (TC-113).

    It 'no Get-ChildItem in the maintained surface lacks -Force — the anti-regression guard (TC-114)' {
        # The only cheap defense against enumeration site #10 arriving later
        # without -Force. AST-based so a line-wrapped call cannot dodge a grep.
        $offenders = foreach ($f in 'Modules\FileBackup.Engine.psm1', 'Modules\FileBackup.Common.psm1',
                                     'Reconstruct.ps1', 'FileBackup.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $f), [ref]$null, [ref]$null)
            $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                                    $n.GetCommandName() -eq 'Get-ChildItem' }, $true)
            foreach ($cmd in $calls) {
                $hasForce = @($cmd.CommandElements | Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Force' })
                if (-not $hasForce) { "${f}:$($cmd.Extent.StartLineNumber)" }
            }
        }
        $offenders | Should -BeNullOrEmpty
    }

    It 'a DOT-NAMED pool data file is found by (hash,length) recovery (TC-114)' {
        # Hash-addressed short names can begin with a dot — the exact shape
        # that broke the 2026-08-23 CI artifact upload.
        $root = Join-Path $TestDrive 'd4-dotpool'
        $s = New-RVStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        ($rows | Where-Object RelativePath -eq 'a.txt').DataPath = ''
        Move-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Destination (Join-Path $s.Bkp '.pool-copy.bin')
        Set-ManifestRows -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'a.txt') -Raw | Should -Be 'ALPHA-CONTENT'
    }

    It 'a pool data file carrying the Windows HIDDEN attribute is found by (hash,length) recovery (TC-114)' {
        $root = Join-Path $TestDrive 'd4-hidpool'
        $s = New-RVStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        ($rows | Where-Object RelativePath -eq 'a.txt').DataPath = ''
        $pool = Join-Path $s.Bkp 'pool-copy.bin'
        Move-Item -LiteralPath (Join-Path $s.Bkp 'a.txt') -Destination $pool
        (Get-Item -LiteralPath $pool -Force).Attributes = ((Get-Item -LiteralPath $pool -Force).Attributes -bor [IO.FileAttributes]::Hidden)
        Set-ManifestRows -Folder $s.Bkp -Rows $rows

        $t = Join-Path $root 't'
        $code = Invoke-ReconstructExitCode -Recon $s.Recon -TargetRoot $t
        $code | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'a.txt') -Raw | Should -Be 'ALPHA-CONTENT'
    }

    It 'Expand-FileWithSevenZip picks up a payload 7-Zip restored with the Hidden attribute (TC-114)' {
        $root = Join-Path $TestDrive 'd4-hidzip'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $srcFile = Join-Path $root 'payload.txt'
        [IO.File]::WriteAllText($srcFile, 'HIDDEN-PAYLOAD')
        (Get-Item -LiteralPath $srcFile -Force).Attributes = ((Get-Item -LiteralPath $srcFile -Force).Attributes -bor [IO.FileAttributes]::Hidden)
        $archive = Join-Path $root 'payload.7z'
        Compress-FileWithSevenZip -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath `
            -SourceFile $srcFile -Destination7z $archive
        $dest = Join-Path $root 'out.txt'
        # Before -Force this threw "No file extracted" when 7-Zip restored the
        # Hidden attribute on the extracted temp file.
        Expand-FileWithSevenZip -SevenZipPath (Get-FileBackupDefaults).SevenZipDefaultPath `
            -Archive $archive -DestinationFile $dest
        Get-Content -LiteralPath $dest -Raw -Force | Should -Be 'HIDDEN-PAYLOAD'
    }

    It 'a HIDDEN Snapshot_* folder is still part of the pool (Get-PoolSnapshotFolder, TC-114)' {
        $chg = Join-Path $TestDrive 'd4-hidsnap'
        $snap = Join-Path $chg 'Snapshot_2024_01_01_00_00_01'
        New-Item -ItemType Directory -Path $snap -Force | Out-Null
        (Get-Item -LiteralPath $snap -Force).Attributes = ((Get-Item -LiteralPath $snap -Force).Attributes -bor [IO.FileAttributes]::Hidden)
        @(Get-PoolSnapshotFolder -ChangeRoot $chg).Name | Should -Contain 'Snapshot_2024_01_01_00_00_01'
    }
}

Describe 'Non-interactive TargetRoot parity (SR-016, TC-115)' {
    # Before kit revision 6, RECONSTRUCT.ps1 without -TargetRoot fell back to
    # Read-Host — a scripted restore hung, while reconstruct.sh died loudly
    # with usage. The twins now agree; the interactive prompt is kept for hand
    # use (that arm is manual — asserting on a live Read-Host is not automatable).

    It '-NonInteractive with no -TargetRoot exits 2 with usage and never blocks (TC-115)' {
        $root = Join-Path $TestDrive 'ni-guard'
        $s = New-RVStore -Root $root
        $out = & (Get-Process -Id $PID).Path -NoProfile -File $s.Recon -NonInteractive -ExitCode *>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $out | Should -Match 'Usage: RECONSTRUCT\.ps1'
        $out | Should -Match '-TargetRoot is required'
    }

    It 'with -TargetRoot given, -NonInteractive changes nothing (TC-115)' {
        $root = Join-Path $TestDrive 'ni-ok'
        $s = New-RVStore -Root $root
        $t = Join-Path $root 't'
        & (Get-Process -Id $PID).Path -NoProfile -File $s.Recon -TargetRoot $t -NonInteractive -ExitCode *>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Get-Content -LiteralPath (Join-Path $t 'a.txt') -Raw | Should -Be 'ALPHA-CONTENT'
    }
}
