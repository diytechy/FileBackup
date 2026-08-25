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
