<#
.SYNOPSIS
    Regenerates the committed golden fixtures the bash restore variant (bash-v1)
    tests against, using the REAL PowerShell engine so the fixtures can never
    drift from the on-disk contract.

.DESCRIPTION
    Produces two fixture sets under -OutRoot (default: tests/fixtures):

      hash-conformance/   Tiny golden files (+ a deterministic 1 MiB binary and a
                          unicode-named file) and expected-hashes.csv holding each
                          file's Get-FileXxHash value. Proves SR-030: the bash
                          hasher's output must equal these bytes exactly.

      bash-restore/<mode>/  For each of the four storage modes, a small backup set
                          produced by a fixed 3-run timeline (deterministic via
                          -BackupTime + fixed content + fixed mtimes). Each mode
                          holds:
                            backup/    the backup root (latest MANIFEST.csv + data)
                            changes/   the Snapshot_<date> point-in-time folders
                            expected/  one <origin>.tsv per restore origin (root +
                                       each snapshot): "posixRelativePath<TAB>hash"
                                       read from that origin's own MANIFEST.csv —
                                       the independent oracle reconstruct.sh must
                                       reproduce (a restored file's xxh128sum must
                                       equal the recorded content hash = byte-exact).

    The timeline exercises: dedup (shared content), a modified file (point-in-time
    v1 vs v2), a delete then identical re-add (yields a blank-DataPath row that
    recovers by (hash,length)), a 0-byte file, unicode / bracketed / comma-bearing
    names, a nested user file named MANIFEST.csv (B6), and — in the +Compress
    modes — .7z-stored rows.

    Committed fixtures are STRIPPED of the deployed restore-kit artifacts
    (RECONSTRUCT.ps1/.bat, reconstruct.sh, FileBackup.Common.psm1,
    System.IO.Hashing.dll) and the
    per-run backup.log, keeping only MANIFEST.csv + data + Snapshot_* + the tiny
    RECONSTRUCT.paths.json sidecar (kept so the "ignore an unresolvable Windows-path
    sidecar on Linux" path is exercised locally). -Fresh keeps everything — that is
    the real, unstripped engine output the CI cross-artifact interop job restores.

.PARAMETER OutRoot
    Where to write the fixtures. Default: <repo>/tests/fixtures.

.PARAMETER Fresh
    Emit a full, unstripped backup set (kit files + logs intact) — used by the CI
    windows->ubuntu interop job. Implies -SkipHashConformance unless overridden.

.PARAMETER Modes
    Storage-mode combos to build. Default: all four.

.NOTES
    Windows / PowerShell 7+ only (it drives the real engine). The fixtures it
    writes are consumed on Linux by tests/bash/*.bats. SR-030/SR-031/SR-032.
#>
[CmdletBinding()]
param(
    [string]$OutRoot,
    [switch]$Fresh,
    [string[]]$Modes = @('Mirror', 'Mirror+Compress', 'HashAddressed', 'HashAddressed+Compress'),
    [switch]$SkipHashConformance
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force

if (-not $OutRoot) { $OutRoot = Join-Path $repo 'tests\fixtures' }
$backupScript = Join-Path $repo 'FileBackup.ps1'

# Deterministic clock: each run's -BackupTime; the snapshot for run N is named by
# run N-1's completion date (persisted), so these three drive two dated snapshots.
$T1 = [datetime]'2024-01-01T09:00:00'
$T2 = [datetime]'2024-01-02T09:00:00'
$T3 = [datetime]'2024-01-03T09:00:00'
$MtimeBase = [datetime]'2024-01-01T08:00:00'   # fixed source mtimes => stable manifests

function New-Utf8File {
    param([string]$Path, [string]$Content, [datetime]$Mtime = $MtimeBase)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    (Get-Item -LiteralPath $Path).LastWriteTime = $Mtime
}

function New-DeterministicBinary {
    param([string]$Path, [int]$Size, [int]$Seed = 0, [datetime]$Mtime = $MtimeBase)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bytes = [byte[]]::new($Size)
    for ($i = 0; $i -lt $Size; $i++) { $bytes[$i] = [byte](($i * 37 + $Seed * 101 + 11) -band 0xFF) }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
    (Get-Item -LiteralPath $Path).LastWriteTime = $Mtime
}

function Write-FixtureConfig {
    param([string]$ConfigPath, [string]$Src, [string]$Bkp, [string]$Chg, [bool]$Compress, [bool]$ContentAddressed)
    $set = [pscustomobject]@{
        Name               = 'FixtureSet'
        SourcePath         = $Src
        BackupPath         = $Bkp
        ChangePath         = $Chg
        HashRecalcFreq     = 'A'
        CompressEnabled    = $Compress
        PreserveFolderTree = -not $ContentAddressed
    }
    @{ Secrets = [pscustomobject]@{ ToEmail = $null; FromEmail = $null; SmtpServer = $null; SmtpPort = 0; Credential = $null }
       BackupSets = @($set) } | Export-Clixml -LiteralPath $ConfigPath
}

function Invoke-FixtureBackup {
    param([string]$ConfigPath, [datetime]$When)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & $backupScript -ConfigPath $ConfigPath -NoMail -NonInteractive -AutoInstallDeps -BackupTime $When *>&1 |
            Out-Null
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "FileBackup.ps1 exited $LASTEXITCODE" }
    } finally { $ErrorActionPreference = $old }
}

function Set-SourceTimelineStep {
    param([string]$Src, [int]$Step)
    # Step 1: the full initial tree. Steps 2/3 mutate it in place.
    switch ($Step) {
        1 {
            New-Utf8File (Join-Path $Src 'hello.txt')            "hello world`n"
            New-Utf8File (Join-Path $Src 'dir/dup_a.txt')        "shared-bytes`n"
            New-Utf8File (Join-Path $Src 'dir/dup_b.txt')        "shared-bytes`n"     # duplicate content
            New-Utf8File (Join-Path $Src 'empty.dat')            ''                   # 0 bytes
            New-Utf8File (Join-Path $Src ('caf' + [char]0x00E9 + '-na' + [char]0x00EF + 've.txt')) "unicode name`n"
            New-Utf8File (Join-Path $Src '[b] (p).txt')          "bracket paren`n"
            New-Utf8File (Join-Path $Src 'with,comma.txt')       "comma name`n"       # comma => CSV quoting
            New-Utf8File (Join-Path $Src 'recur.txt')            "recurring content`n"
            New-DeterministicBinary (Join-Path $Src 'data.bin')  96 -Seed 7
            New-Utf8File (Join-Path $Src 'sub/MANIFEST.csv')     "nested not-infra`n" # B6 nested infra-named
        }
        2 {
            New-Utf8File (Join-Path $Src 'hello.txt') "hello world v2`n" -Mtime $MtimeBase.AddDays(1)  # modify
            Remove-Item -LiteralPath (Join-Path $Src 'recur.txt') -Force                               # delete
            Remove-Item -LiteralPath (Join-Path $Src 'data.bin') -Force                                # delete
        }
        3 {
            New-Utf8File (Join-Path $Src 'recur.txt')   "recurring content`n" -Mtime $MtimeBase        # re-add identical
            New-Utf8File (Join-Path $Src 'newfile.txt') "brand new`n" -Mtime $MtimeBase.AddDays(2)     # add
        }
    }
}

function Write-ExpectedTsv {
    param([string]$ManifestPath, [string]$OutFile)
    $rows = Import-Csv -LiteralPath $ManifestPath
    $lines = foreach ($r in $rows) {
        if ([string]::IsNullOrEmpty($r.RelativePath)) { continue }
        $posix = $r.RelativePath -replace '\\', '/'
        "$posix`t$($r.xxH2Hash)"
    }
    $dir = [System.IO.Path]::GetDirectoryName($OutFile)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($OutFile, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

$KitArtifacts = @('RECONSTRUCT.ps1', 'RECONSTRUCT.bat', 'reconstruct.sh', 'FileBackup.Common.psm1', 'System.IO.Hashing.dll')

function Remove-KitBloat {
    param([string]$Folder)
    # Strip the deployed restore kit + logs from a committed fixture,
    # keeping MANIFEST.csv, data files, Snapshot_* and the tiny path sidecar.
    Get-ChildItem -LiteralPath $Folder -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in $KitArtifacts -or $_.Name -eq 'backup.log' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    # Normalize every RECONSTRUCT.paths.json to a STABLE, deliberately unresolvable
    # Windows path (the real one carries a random temp GUID => fixture churn). The
    # sidecar is kept so tests prove reconstruct.sh ignores a Windows-path sidecar
    # on Linux and relies on --backup-root/--change-root / auto-detection instead.
    Get-ChildItem -LiteralPath $Folder -Recurse -File -Filter 'RECONSTRUCT.paths.json' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $stable = @{ BackupRoot = 'C:\Backups\FileBackupFixture\backup'
                         ChangeRoot = 'C:\Backups\FileBackupFixture\backup\changes' } | ConvertTo-Json
            [System.IO.File]::WriteAllText($_.FullName, $stable, [System.Text.UTF8Encoding]::new($false))
        }
}

function Get-ModeFlags {
    param([string]$Mode)
    @{ Compress = $Mode -like '*Compress*'; ContentAddressed = $Mode -like 'HashAddressed*' }
}

# --- Build bash-restore fixtures -------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ("fbfix_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    foreach ($mode in $Modes) {
        $flags = Get-ModeFlags $mode
        $modeSafe = $mode -replace '\+', '_'
        Write-Host "=== bash-restore fixture: $mode ===" -ForegroundColor Cyan

        $src = Join-Path $work "$modeSafe\src"
        $bkp = Join-Path $work "$modeSafe\backup"
        $chg = Join-Path $work "$modeSafe\backup\changes"   # nested: enables Linux grandparent auto-detect too
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $cfg = Join-Path $work "$modeSafe\config.xml"
        Write-FixtureConfig -ConfigPath $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $flags.Compress -ContentAddressed $flags.ContentAddressed

        Set-SourceTimelineStep -Src $src -Step 1; Invoke-FixtureBackup -ConfigPath $cfg -When $T1
        Set-SourceTimelineStep -Src $src -Step 2; Invoke-FixtureBackup -ConfigPath $cfg -When $T2
        Set-SourceTimelineStep -Src $src -Step 3; Invoke-FixtureBackup -ConfigPath $cfg -When $T3

        # Publish backup + changes into the fixture output tree.
        $destMode = Join-Path $OutRoot "bash-restore\$modeSafe"
        if (Test-Path -LiteralPath $destMode) { Remove-Item -LiteralPath $destMode -Recurse -Force }
        New-Item -ItemType Directory -Path $destMode -Force | Out-Null
        Copy-Item -LiteralPath $bkp -Destination (Join-Path $destMode 'backup') -Recurse -Force

        # Expected oracle: one TSV per restore origin (root + each snapshot).
        $destBackup = Join-Path $destMode 'backup'
        $destChanges = Join-Path $destBackup 'changes'
        Write-ExpectedTsv -ManifestPath (Join-Path $destBackup 'MANIFEST.csv') -OutFile (Join-Path $destMode 'expected\root.tsv')
        $snapCount = 0
        if (Test-Path -LiteralPath $destChanges) {
            Get-ChildItem -LiteralPath $destChanges -Directory | Where-Object { $_.Name -like 'Snapshot_*' } | ForEach-Object {
                Write-ExpectedTsv -ManifestPath (Join-Path $_.FullName 'MANIFEST.csv') -OutFile (Join-Path $destMode "expected\$($_.Name).tsv")
                $snapCount++
            }
        }

        if (-not $Fresh) { Remove-KitBloat -Folder $destBackup }

        # Report blank-DataPath coverage (the hash-recovery path).
        $blank = 0
        Get-ChildItem -LiteralPath $destBackup -Recurse -Filter 'MANIFEST.csv' | ForEach-Object {
            $blank += (Import-Csv -LiteralPath $_.FullName | Where-Object { $_.RelativePath -and -not $_.DataPath }).Count
        }
        Write-Host ("    snapshots={0}  blank-DataPath-rows={1}" -f $snapCount, $blank) -ForegroundColor DarkGray
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Build hash-conformance fixtures ---------------------------------------
if (-not $SkipHashConformance -and -not $Fresh) {
    Write-Host "=== hash-conformance fixtures ===" -ForegroundColor Cyan
    $hc = Join-Path $OutRoot 'hash-conformance'
    if (Test-Path -LiteralPath $hc) { Remove-Item -LiteralPath $hc -Recurse -Force }
    New-Item -ItemType Directory -Path $hc -Force | Out-Null

    New-Utf8File (Join-Path $hc 'empty.dat') ''
    New-Utf8File (Join-Path $hc 'one-byte.dat') 'A'
    New-Utf8File (Join-Path $hc 'text.txt') "The quick brown fox jumps over the lazy dog`n"
    New-Utf8File (Join-Path $hc ('u' + [char]0x00E9 + '-unicode-' + [char]0x00E5 + '.txt')) "unicode content`n"
    # >1 MiB, spans multiple read buffers (SR-030 explicitly requires binary >1 MiB).
    New-DeterministicBinary (Join-Path $hc 'binary-1MiB.bin') (1048576 + 17) -Seed 3

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('FileName,xxH2Hash')
    Get-ChildItem -LiteralPath $hc -File | Sort-Object Name | ForEach-Object {
        $h = Get-FileXxHash -FilePath $_.FullName
        $name = $_.Name
        if ($name -match '[",]') { $name = '"' + ($name -replace '"', '""') + '"' }
        $lines.Add("$name,$h")
    }
    [System.IO.File]::WriteAllText((Join-Path $hc 'expected-hashes.csv'), (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "    wrote $($lines.Count - 1) golden hashes" -ForegroundColor DarkGray
}

Write-Host "Fixtures written under $OutRoot" -ForegroundColor Green
