<#
.SYNOPSIS
    Demonstration: drive a scripted backup timeline (create / modify / remove /
    re-add / no-op) and emit a legible, timestamped narrative report — source
    events, the backup run's outcome, an immediate restore-and-byte-compare
    verification, then point-in-time reconstruction of every snapshot.

.DESCRIPTION
    A Demonstration artifact (process.md §4 verification methods), not a gate
    test: the gate suites assert; this shows the same machinery in motion in a
    form a human can read end-to-end. Everything it prints is measured from the
    real engine — each "verify" line is an actual RECONSTRUCT.ps1 run followed
    by an xxHash128 byte-compare of every file.

    Work area is created under %TEMP%\FileBackupDemo (never the repo); the
    report is written there as TimelineReport.md and echoed to the console.

.PARAMETER Compress
    Enable 7-Zip compression for the demo backup set.

.PARAMETER ReportPath
    Where to write the Markdown report (default: <work area>\TimelineReport.md).

.NOTES
    Implements: (demonstration tooling — exercises SR-005/SR-010/SR-028/SR-029
    visibly; verification of those SRs lives in the gated test suites.)
#>
[CmdletBinding()]
param(
    [switch]$Compress,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$repo  = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$entry = Join-Path $repo 'FileBackup.ps1'
Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force

$work = Join-Path ([IO.Path]::GetTempPath()) ("FileBackupDemo\" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$src  = Join-Path $work 'source'
$bkp  = Join-Path $work 'backup'
$chg  = Join-Path $work 'changes'
$cfg  = Join-Path $work 'config.xml'
New-Item -ItemType Directory -Path $src -Force | Out-Null
if (-not $ReportPath) { $ReportPath = Join-Path $work 'TimelineReport.md' }

$set = [pscustomobject]@{
    Name = 'Demo'; SourcePath = $src; BackupPath = $bkp; ChangePath = $chg
    HashRecalcFreq = 'A'; CompressEnabled = [bool]$Compress
}
@{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg

$md = [System.Text.StringBuilder]::new()
function Out-Line([string]$Text = '') { [void]$md.AppendLine($Text); Write-Host $Text }

# ---- tree state helpers (root MANIFEST.csv is engine bookkeeping, not data) ----
function Get-TreeState([string]$Dir) {
    $state = @{}
    if (Test-Path -LiteralPath $Dir) {
        foreach ($f in Get-ChildItem -LiteralPath $Dir -File -Recurse) {
            $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $Dir).Path.Length).TrimStart('\','/')
            if ($rel -in 'MANIFEST.csv','RECONSTRUCT.log') { continue }
            $state[$rel] = Get-FileXxHash -FilePath $f.FullName
        }
    }
    return $state
}
function Compare-TreeToState([string]$Dir, [hashtable]$Expected) {
    $actual = Get-TreeState $Dir
    $problems = @()
    foreach ($rel in $Expected.Keys) {
        if (-not $actual.ContainsKey($rel))         { $problems += "missing: $rel" }
        elseif ($actual[$rel] -ne $Expected[$rel])  { $problems += "wrong bytes: $rel" }
    }
    foreach ($rel in $actual.Keys) {
        if (-not $Expected.ContainsKey($rel))       { $problems += "unexpected: $rel" }
    }
    return ,$problems
}
function Invoke-Restore([string]$From, [string]$Target, [hashtable]$Expected) {
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    $err = $null
    try { & (Join-Path $From 'RECONSTRUCT.ps1') -TargetRoot $Target *>&1 | Out-Null }
    catch { $err = $_.Exception.Message }
    if ($err) { return @("restore FAILED loudly: $err") }
    return (Compare-TreeToState $Target $Expected)
}

# ---- one timeline step: describe events, run the backup, verify latest ----------
$script:runNo = 0
$script:states = [ordered]@{}   # snapshot-folder-name-or-'latest' -> expected tree state
function Invoke-TimelineRun([datetime]$When, [string[]]$Events) {
    $script:runNo++
    $before = @(Get-ChildItem -LiteralPath $chg -Directory -ErrorAction SilentlyContinue |
                Where-Object Name -match '^Snapshot_' | ForEach-Object Name)
    $t0 = Get-Date
    & $entry -ConfigPath $cfg -NoMail -NonInteractive -BackupTime $When *>&1 | Out-Null
    $elapsed = '{0:N1}s' -f ((Get-Date) - $t0).TotalSeconds
    $after = @(Get-ChildItem -LiteralPath $chg -Directory -ErrorAction SilentlyContinue |
               Where-Object Name -match '^Snapshot_' | ForEach-Object Name)
    $newSnap = @($after | Where-Object { $_ -notin $before })

    Out-Line ''
    Out-Line ("## Run $script:runNo — backup dated {0}" -f $When.ToString('yyyy-MM-dd HH:mm:ss'))
    Out-Line ''
    Out-Line 'Source events since the previous run:'
    foreach ($e in $Events) { Out-Line "  - $e" }
    $rows = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv'))
    $snapTxt = if ($newSnap.Count) { "``$($newSnap -join ', ')`` (preserves the pre-run state)" } else { '*none*' }
    Out-Line ("Backup completed in {0}: manifest now lists **{1} file(s)**; snapshot created: {2}" -f $elapsed, $rows.Count, $snapTxt)

    # Verify the run: restore the live backup and byte-compare against the source.
    $expectNow = Get-TreeState $src
    $problems = Invoke-Restore $bkp (Join-Path $work "verify-run$script:runNo") $expectNow
    $verdict = if ($problems.Count -eq 0) { "**PASS** ($($expectNow.Count)/$($expectNow.Count) files byte-identical)" }
               else { '**FAIL** — ' + ($problems -join '; ') }
    Out-Line "Verification (restore latest, xxHash128-compare every file): $verdict"

    # Remember what each new snapshot must reproduce (= state before this run),
    # and keep 'latest' pointing at the current source state.
    foreach ($s in $newSnap) { $script:states[$s] = $script:prevState }
    $script:prevState = $expectNow
    if ($problems.Count) { $script:anyFail = $true }
}

# =============================== the timeline ===============================
$script:anyFail = $false
$script:prevState = @{}
$title = "content-addressed$(if ($Compress) {'+Compress'})"
Out-Line "# FileBackup timeline demonstration — $title"
Out-Line ''
Out-Line ("Generated {0} by scripts/demo_timeline.ps1. Every verification below is a real" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Out-Line 'RECONSTRUCT.ps1 run followed by an xxHash128 byte-compare of every file.'
Out-Line ''
Out-Line "Work area: $work"

[IO.File]::WriteAllText((Join-Path $src 'alpha.txt'), 'alpha v1')
$rng = [byte[]]::new(1024); [Random]::new(42).NextBytes($rng)
[IO.File]::WriteAllBytes((Join-Path $src 'beta.bin'), $rng)
New-Item -ItemType Directory -Path (Join-Path $src 'notes') | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'notes\readme.md'), '# demo notes')
Invoke-TimelineRun ([datetime]'2024-01-01 09:00:00') @(
    'created alpha.txt ("alpha v1")',
    'created beta.bin (1,024 random bytes)',
    'created notes\readme.md')

[IO.File]::WriteAllText((Join-Path $src 'alpha.txt'), 'alpha v2 — edited')
Invoke-TimelineRun ([datetime]'2024-02-01 09:00:00') @(
    'MODIFIED alpha.txt ("alpha v1" -> "alpha v2 — edited")')

Remove-Item -LiteralPath (Join-Path $src 'beta.bin')
Invoke-TimelineRun ([datetime]'2024-03-01 09:00:00') @(
    'REMOVED beta.bin')

[IO.File]::WriteAllBytes((Join-Path $src 'beta.bin'), $rng)
Invoke-TimelineRun ([datetime]'2024-04-01 09:00:00') @(
    'RE-ADDED beta.bin (identical 1,024 bytes — dedup will reuse the preserved copy)')

Invoke-TimelineRun ([datetime]'2024-05-01 09:00:00') @(
    '(no changes — manifest-identical run)')

# ================== point-in-time reconstruction verification ==================
Out-Line ''
Out-Line '## Point-in-time reconstruction (every snapshot, byte-exact)'
Out-Line ''
$i = 0
foreach ($snap in $script:states.Keys) {
    $i++
    $expected = $script:states[$snap]
    $problems = Invoke-Restore (Join-Path $chg $snap) (Join-Path $work "rollback$i") $expected
    $files = ($expected.Keys | Sort-Object) -join ', '
    $verdict = if ($problems.Count -eq 0) { '**PASS**' } else { '**FAIL** — ' + ($problems -join '; ') }
    Out-Line ("- ``{0}`` -> expected state: [{1}] -> {2}" -f $snap, $files, $verdict)
    if ($problems.Count) { $script:anyFail = $true }
}

Out-Line ''
Out-Line ("**Overall: {0}** — {1} runs, {2} snapshots, every state restored and byte-compared." -f `
    $(if ($script:anyFail) {'FAIL'} else {'PASS'}), $script:runNo, $script:states.Count)

[IO.File]::WriteAllText($ReportPath, $md.ToString())
Write-Host ''
Write-Host "Report written to: $ReportPath"
if ($script:anyFail) { exit 1 }
exit 0
