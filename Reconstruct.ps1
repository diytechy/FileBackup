<#
.SYNOPSIS
    Reconstructs a source tree from MANIFEST.csv and the available data files.

.DESCRIPTION
    Deployed (by New-ReconstructScript) into the backup root and each change
    folder, alongside FileBackup.Common.psm1, System.IO.Hashing.dll, and a
    RECONSTRUCT.paths.json sidecar. Runs standalone — no repository required.

        * From the backup root: uses that folder's MANIFEST.csv only.
        * From a dated snapshot folder (name starts with "Snapshot_"): that
          snapshot's own manifest is the authoritative point-in-time state, with
          bytes resolved by hash from the backup root + sibling snapshots.

    When a row's DataPath is blank or its file is missing, the bytes are found
    through a name index built once per restore: every stored object is named
    by its own (hash, length) (SR-069), so listing the pool folders once
    resolves every such row. Only a row the index cannot resolve falls back to
    scanning the pool for a file whose length and xxHash128 match.

.NOTES
    Requires PowerShell 7+ (pwsh). Logs to RECONSTRUCT.log in the target root.
    Fails loudly (terminating error / non-zero exit) when any manifest row
    cannot be restored, after restoring everything recoverable (SR-029).

    Restore exit codes (SR-040 — the normative table lives in README
    "Restore exit codes"; reconstruct.sh returns the same numbers):

        0  Complete — every manifest row restored.
        1  Incomplete, CONTENT — the remaining rows' bytes are not in the pool,
           or nothing in the pool reproduces them (ContentMismatch: the written
           file disagreed with the row's Length/xxH2Hash — SR-056).
        2  Precondition / usage — nothing attempted (bad arguments, missing or
           unrecognizable manifest, target inside the backup, an unusable target
           path, missing required tool, insufficient capacity). Any terminating
           error this script did not classify lands here too: nothing was
           attempted, so it must not be reported as data loss (code 1). The
           header check and the store refusals run before the target folder
           and the log are created, so they leave the target exactly as they
           found it — as reconstruct.sh does. The later code-2 preflights
           (capacity, 7-Zip) run after target+log creation, identically in
           both restorers.
        3  Retired at kit revision 14; never returned. It was "manifest-witness
           verification failed". The kit no longer reads MANIFEST.csv.meta at
           all (bounded-run-loop R5), so a witness that is present, stale or
           garbage changes nothing.
        4  Incomplete, HOST — rows failed for reasons on this machine, not in
           the backup (unreadable search folder or candidate, 7-Zip unavailable
           for an archive candidate, extraction/copy I/O error on the row's OWN
           file, or a WriteMismatch — a hash-PROVEN pool source whose written
           destination disagrees: the backup holds the bytes, the write is
           broken). Retry after fixing the host. Since kit revision 6 a POOL
           candidate that fails to expand while 7-Zip passes its self-test is
           data damage (ContentMissing, 1) — only the restore loop raises
           CandidateError.

    Precedence when several apply: 2 > 4 > 1.

    Delivery: by default every failure is a TERMINATING ERROR (throw), which is
    what in-process callers and the test harness rely on. Pass -ExitCode (as
    RECONSTRUCT.cmd does) to exit the process with the table's code instead.
#>

# KitRevision: 14
# The revision of the restore kit bundled into a backup folder. Bumped whenever
# any kit-bundled file changes behaviour, so a snapshot can be asked which kit
# it carries (SR-049 reports it with every blank-row form finding, and
# -RefreshKits is the only way to retire an old one). Revision 2 was the first
# stamped revision and the first to decide a hash-recovered row's form from the
# FILE it located rather than the row's Compressed column (SR-050). Revision 3
# additionally tests every non-matching '.7z' candidate as RAW bytes, so a
# blank row for a genuine '.7z' SOURCE file is recoverable. Revision 4 honors
# the path sidecar only while the kit folder still lives inside the roots it
# records (a copied/moved store auto-detects instead of reading the original),
# falls back to (hash,length) pool recovery when a row's named data file is
# missing, maps '\' separators on non-Windows hosts, and keys the manifest
# dictionary case-sensitively there. Revision 5 tests a '.7z'-named recovery
# candidate's raw bytes even when 7-Zip is absent (raw needs no 7-Zip), so a
# restore that requires no actual decompression no longer exits 4 demanding
# 7-Zip. Revision 6 verifies EVERY written file against the row's
# (Length, xxH2Hash) — healing a mismatch from the pool once, else failing
# loudly as ContentMismatch (SR-056); reclassifies an unexpandable POOL
# candidate as content damage (exit 1) rather than a host problem, while a
# row's own file failing to extract stays exit 4; scans the pool with -Force
# so dot-named and Hidden data files are recoverable by (hash,length)
# (SR-057); and adds the -NonInteractive guard (usage + exit 2) in place of a
# blocking prompt (SR-016). Revision 7 REFUSES a legacy path-addressed store
# (SR-061: a DataPath carrying a path separator) as a precondition failure
# instead of restoring it - support for pre-content-addressed stores was
# withdrawn deliberately, not lost; stamps each restored file's
# LastWriteTimeStr from its own manifest row, which is what makes a
# deduplicated row keep its OWN timestamp instead of the pool object's
# (SR-066); and applies the DIRECTORIES.csv sidecar, recreating empty
# directories and re-applying folder attributes (SR-065). Revision 8 decides a
# row's stored form from the BYTES for a row resolved through its own DataPath
# too, not just for a hash-recovered one (SR-068): the Compressed column is no
# longer consulted for any correctness decision, only as an input to the
# capacity ESTIMATE, so a manifest whose column disagrees with its bytes can no
# longer produce a wrong restore. That narrows SR-040's host class by design
# (human-ratified 2026-08-26): a row's own object is exit 4 only when it is
# ARCHIVE-SHAPED and will not open; unsignatured bytes that reproduce neither
# form are content damage, exit 1, because no retry fixes them.
# Revision 9 - the base-57 name grammar (WP12) - CHANGED BEHAVIOUR BUT WAS
# NEVER EMITTED: this marker stayed at 8 and reconstruct.sh stayed at 6, so
# every store WP12 wrote reports the kit it carries as 8, and Get-BackupKit
# Revision (the only reader) has been naming the wrong kit ever since. The
# drift is corrected forward at revision 10 rather than back-dated, because
# the marker records what a BUNDLED kit does and a deployed copy cannot be
# rewritten (WP13, F-1). Revision 10 clears the read-only attribute on every
# restored file, so a write-protected store cannot hand its protection to
# the restored tree - a snapshot keeps its kit forever, so this half must
# ship BEFORE the store is ever marked, not with it. Its POSIX twin also
# stops assuming GNU coreutils (SR-071). Revisions 11 to 13 changed only the
# bundled FileBackup.Common.psm1 (AGENTS.md section 3).
# Revision 14 (2026-10-24): a row whose DataPath is blank or names a missing
# file is resolved through a NAME INDEX built once per restore - the top-level
# files of the origin, the backup root and every snapshot, keyed by the
# (hash, length) each SR-069 name carries - instead of a recursive scan that
# hashed the whole pool once per such row. An index hit is treated exactly like
# a DataPath file (form from its bytes, SR-068; written file verified, SR-056);
# the content scan remains only as the last resort for a row the index cannot
# resolve. The MANIFEST.csv.meta witness is no longer read at all, so exit 3,
# the 'unverified index' warning, -RequireWitness and the witness-version
# refusal are gone (bounded-run-loop R5/R6, section 7).
# Restoring a snapshot with its OWN older kit
# still carries the defects fixed after it.

param(
    [string]$TargetRoot,
    [string]$BackupRootOverride,
    [string]$ChangeRootOverride,
    [string]$SevenZipPath,
    # Report the SR-040 exit code as a process exit status instead of throwing.
    # Only process entry points pass this; in-process callers keep the throw.
    [switch]$ExitCode,
    # Automation safety (SR-016, kit revision 6): never prompt. A missing
    # -TargetRoot prints usage and exits 2 instead of blocking on Read-Host —
    # the behavior reconstruct.sh has always had (--target-root is required).
    # Redirected stdin triggers the same guard, so a scheduled run that forgot
    # the switch still fails loudly rather than hanging.
    [switch]$NonInteractive,
    # Never open a graphical folder picker even on a desktop session (SR-073);
    # the typed prompt is used instead. FILEBACKUP_NO_GUI=1 does the same, for
    # a caller that cannot add a switch.
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$here = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)

# Exit-code constants (SR-040). Named so the call sites read as classifications.
$EXIT_COMPLETE    = 0
$EXIT_CONTENT     = 1
$EXIT_PRECONDITION= 2
# 3 is retired (kit revision 14): it meant "manifest witness failed".
$EXIT_HOST        = 4

$logPath = $null

# Log lines produced BEFORE the target (and therefore RECONSTRUCT.log) exists.
# The manifest is checked before anything is written to the target, so any
# finding from that stage is held here and flushed once the log is opened.
$pendingLog = New-Object System.Collections.Generic.List[string]

function Add-ReconstructLog {
    <#
    .SYNOPSIS
        Appends one timestamped line to RECONSTRUCT.log, buffering it when the
        log does not exist yet (the manifest checks run before the target is
        created).
    #>
    # Implements: SR-040, LLR-040
    param([Parameter(Mandatory)][string]$Message)
    $line = "$(Get-Date -Format 'O') - $Message"
    if ($logPath) { $line | Out-File -LiteralPath $logPath -Append }
    else { $script:pendingLog.Add($line) }
}

# Set by Exit-Reconstruct so the top-level trap can tell a failure we already
# classified from an unexpected one.
$classified = $false

# Top-level error routing (SR-040). An unclassified terminating error — say a
# FILE occupying the target path making New-Item throw — used to escape and
# leave the process exit status at 1, which the table reserves for "content
# unrecoverable / data loss". Nothing was attempted in such a case, so it is a
# PRECONDITION failure (2), which is also what reconstruct.sh returns for the
# same causes. In-process callers still see the original terminating error.
trap {
    if ($classified) { break }      # our own throw: preserve its exact wording
    if ($ExitCode) {
        $msg = $_.Exception.Message
        if ($logPath) { "$(Get-Date -Format 'O') - ERROR: $msg" | Out-File -LiteralPath $logPath -Append }
        [Console]::Error.WriteLine("reconstruct: $msg")
        exit $EXIT_PRECONDITION
    }
    break
}

function Wait-BeforeClosing {
    <#
    .SYNOPSIS
        Holds a double-clicked window open so its outcome can be read (SR-072).
    .DESCRIPTION
        Fires ONLY when the target was obtained interactively - the one branch
        that has already proved a human is watching. The launcher deliberately
        does NOT pause: a `pause` in RECONSTRUCT.cmd would also fire for a
        console-attached automated caller that passes no arguments, and hang it
        without ever returning the exit code (2026-08-28 independent review,
        T6). Deciding here means the hold cannot reach automation at all.
    .PARAMETER Code
        The SR-040 code about to be returned, shown to the operator.
    #>
    # Implements: SR-072, LLR-072
    param([int]$Code)
    if (-not $script:InteractiveTarget) { return }
    if ([System.Console]::IsInputRedirected) { return }
    try {
        Write-Host ''
        Write-Host "Exited with code $Code."
        $null = Read-Host 'Press Enter to close'
    } catch {
        # No console to hold on to; ending quietly is correct.
        Write-Verbose "Could not hold the window open: $($_.Exception.Message)"
    }
}

function Exit-Reconstruct {
    <#
    .SYNOPSIS
        Ends the restore with one of the SR-040 exit codes, logging the reason.

    .DESCRIPTION
        The single failure exit of this script. Under -ExitCode it exits the
        process with the classified code; otherwise it throws, preserving the
        exact message wording that in-process callers assert on (see the
        "wording that must not change" list in the WP1 plan).

    .PARAMETER Code
        One of the SR-040 codes (see the script .NOTES).

    .PARAMETER Message
        The operator-facing reason. Wording is load-bearing — existing tests
        match on substrings of it.
    #>
    # Implements: SR-040, LLR-040
    param(
        [Parameter(Mandatory)][int]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    # A pre-mutation refusal (code 2) happens before the target — and its log —
    # exists, on purpose: the message goes to the console and the thrown error
    # instead of a log file we must not create.
    if ($logPath) {
        "$(Get-Date -Format 'O') - ERROR: $Message" | Out-File -LiteralPath $logPath -Append
    }
    $script:classified = $true
    if ($ExitCode) {
        [Console]::Error.WriteLine("reconstruct: $Message")
        Wait-BeforeClosing -Code $Code
        exit $Code
    }
    throw $Message
}

# ---- Load shared primitives (hashing, manifest I/O, 7-Zip, defaults) ----
$commonModule = Join-Path $here 'FileBackup.Common.psm1'
if (-not (Test-Path -LiteralPath $commonModule -PathType Leaf)) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "FileBackup.Common.psm1 not found next to Reconstruct.ps1 at '$here'. The backup folder is incomplete."
}
Import-Module $commonModule -Force
$Def = Get-FileBackupDefaults

$DatabaseFilename    = $Def.DatabaseFilename
$ReconstructLogName  = $Def.ReconstructLogName
$ChangeFolderPattern = '^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}'

$folderName = [System.IO.Path]::GetFileName($here)

# Cached by Test-SevenZipUsable: $null = not yet probed.
$script:sevenZipUsable = $null
function Test-SevenZipUsable {
    <#
    .SYNOPSIS
        Proves this HOST can run 7-Zip end-to-end: compresses a tiny probe
        file and expands it back. Cached for the process.

    .DESCRIPTION
        Separates "7-Zip ran and rejected that archive" (data damage,
        ContentMissing/exit 1) from "7-Zip cannot run or cannot write its
        output here" (broken binary, full temp dir — a HOST problem, exit 4).
        Without this split, a failing 7-Zip made the locator report intact
        pool bytes as gone — the one message a backup tool must never emit
        wrongly (2026-08-24 independent review, blocker 2).
    #>
    # Implements: SR-040, LLR-040
    param([string]$SevenZipPath)
    if ($null -ne $script:sevenZipUsable) { return $script:sevenZipUsable }
    $work = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    try {
        New-Item -ItemType Directory -Path $work | Out-Null
        $probe = Join-Path $work 'probe.txt'
        [IO.File]::WriteAllText($probe, 'selftest')
        Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $probe `
            -Destination7z (Join-Path $work 'probe.7z')
        Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive (Join-Path $work 'probe.7z') `
            -DestinationFile (Join-Path $work 'out.txt')
        $script:sevenZipUsable = ([IO.File]::ReadAllText((Join-Path $work 'out.txt')) -eq 'selftest')
    } catch {
        $script:sevenZipUsable = $false
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $script:sevenZipUsable
}

function Find-DataFileByHash {
    <#
    .SYNOPSIS
        Locates a data file matching the original (hash,length) and reports WHY
        it could not, so the caller can tell "your bytes are gone" from "fix this
        host and retry" (SR-040).

    .DESCRIPTION
        Uncompressed candidates are filtered by length then hashed; .7z
        candidates are decompressed to a temp file and hashed (their on-disk
        size/hash differ from the original), so recovery works for compressed
        backups too. The path returned for an archive is the ARCHIVE path — the
        caller extracts it.

        The infra-name skip is ROOT-LEVEL ONLY (SR-022 / AGENTS.md §3): a nested
        user file named like infrastructure is data (B6) and, in Mirror mode, may
        be the only physical copy of a blanked snapshot row. The skip is a scan
        optimization, never a correctness gate — matching is by (hash, length).

        The located file's FORM travels back with it (SR-050). The search has
        already PROVEN that form — an archive candidate only matches once it has
        been expanded and its payload hashed, a raw candidate only once the file
        itself hashed — so reporting it costs nothing, and it is the only field
        that describes the file actually found. The row's Compressed column
        describes a file in the ROW's own folder, which for a blank-DataPath row
        is not this file: consulting it here restores 7z container bytes under
        the original filename (exit 0) or expands raw bytes (exit 4).

        EVERY '.7z' candidate that does not yield the payload is additionally
        tested as raw bytes before it is dropped — whether it failed to expand
        (a '.7z' name over raw content, the finding-B family artifact) or
        expanded to something else (a genuine '.7z' SOURCE file stored raw,
        which really is an archive but whose payload is not this row's content).
        Free on the happy path, and the second case is otherwise unrecoverable.

    .OUTPUTS
        [pscustomobject] Path / Cause / Form / Detail, where Cause is one of:
          Found              — Path holds the data source; Form is 'Archive'
                               (extract it) or 'Raw' (copy it).
          ContentMissing     — the pool was searched cleanly; the bytes are gone.
                               Archive candidates that failed to EXPAND are named
                               in the Detail: this locator is only ever called
                               when the row's own file is blank or missing, so no
                               candidate it inspects is the row's own file — an
                               unexpandable archive here is data damage, and a
                               retry on this host cannot change the outcome
                               (kit revision 6; SR-040 amendment 2026-08-24).
          DependencyMissing  — an archive candidate was met with no usable 7-Zip.
          StorageUnreadable  — a search folder is absent or could not be read, or
                               a candidate's bytes could not be READ at all
                               (I/O error, lock, permission) — reading may
                               succeed on a healthy host, so exit 4 is honest.

        The two non-ContentMissing causes are HOST problems (exit 4): the
        backup may still hold the bytes, so a wrapper should retry rather than
        report data loss. They are only reported when the scan found nothing.
        The locator never returns CandidateError — that cause is raised only by
        the restore loop, for a row's OWN file failing to extract or copy.
    #>
    # Implements: SR-040, SR-050, LLR-040, LLR-050
    param([string]$Hash, [long]$Length, [string[]]$SearchFolders, [string]$SevenZipPath)

    $skip = '^(MANIFEST|RECONSTRUCT|DIRECTORIES|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    # Host-class problems met along the way, reported only if nothing matched — a
    # successful recovery must never be downgraded by an unrelated bad folder.
    $hostIssues = New-Object System.Collections.Generic.List[pscustomobject]
    # Archive candidates that failed to EXPAND. Not a host issue: no candidate
    # here is the row's own file, so an unexpandable archive proves nothing about
    # this host — it is damaged data, reported inside ContentMissing's detail.
    $failedExpand = New-Object System.Collections.Generic.List[string]

    foreach ($folder in $SearchFolders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                Detail = "Search folder '$folder' does not exist or is not a directory." })
            continue
        }
        $folderNorm = [System.IO.Path]::GetFullPath($folder).TrimEnd('\', '/')
        $enumErrors = $null
        # -Force (SR-057): hash-addressed short names can BEGIN WITH A DOT, and a
        # pool file carrying a Hidden attribute was invisible here — making its
        # content unrecoverable by (hash,length) until kit revision 6 (D-4).
        $candidates = Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable enumErrors |
            Where-Object {
                -not ($_.Name -match $skip -and
                      [System.IO.Path]::GetDirectoryName($_.FullName) -eq $folderNorm) -and
                -not (Test-IsVolumeRootPseudoPath -Root $folderNorm -FullPath $_.FullName)
            }
        # A store sitting at a volume ROOT carries 'System Volume Information',
        # which is unreadable by design. Counting that as a pool read failure
        # reported StorageUnreadable -> exit 4 against a wholly intact backup,
        # so it is filtered out before the honest failures are judged (SR-074).
        $realEnumErrors = @($enumErrors | Where-Object {
            $_.TargetObject -and -not (Test-IsVolumeRootPseudoPath -Root $folderNorm -FullPath "$($_.TargetObject)")
        })
        if ($realEnumErrors.Count -gt 0) {
            $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                Detail = "Search folder '$folder' could not be fully read: $($realEnumErrors[0].Exception.Message)" })
        }
        foreach ($f in $candidates) {
            if ($f.Extension -ieq '.7z') {
                if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                    # Its OWN bytes may still be the answer — a raw file under a
                    # '.7z' name, or a genuine '.7z' source stored verbatim —
                    # and testing that needs no 7-Zip at all (kit revision 5).
                    # Only a candidate whose raw bytes do NOT match still needs
                    # the dependency. A candidate that cannot be READ records
                    # exactly ONE cause (StorageUnreadable): 7-Zip could not
                    # have helped read a file that cannot be read (kit rev 6).
                    try {
                        if ($f.Length -eq $Length -and (Get-FileXxHash -FilePath $f.FullName) -eq $Hash) {
                            return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Form = 'Raw'; Detail = '' }
                        }
                    } catch {
                        $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                            Detail = "Candidate '$($f.FullName)' could not be read: $($_.Exception.Message)" })
                        continue
                    }
                    $hostIssues.Add([pscustomobject]@{ Cause = 'DependencyMissing'
                        Detail = "An archive candidate '$($f.FullName)' needs 7-Zip, which was not found at '$SevenZipPath'." })
                    continue
                }
                # Expanded on the restore target's volume, never in the system
                # temp folder (RAM in the container): see $script:ExpandScratch.
                $scratchBase = if ($script:ExpandScratch) { $script:ExpandScratch } else { [IO.Path]::GetTempPath() }
                $tmp = Join-Path $scratchBase ('.fbexpand-' + [IO.Path]::GetRandomFileName())
                $expandError = $null
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $f.FullName -DestinationFile $tmp
                    if ((Get-Item -LiteralPath $tmp).Length -eq $Length -and (Get-FileXxHash -FilePath $tmp) -eq $Hash) {
                        return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Form = 'Archive'; Detail = '' }
                    }
                } catch {
                    $expandError = $_.Exception.Message
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                # The candidate's OWN bytes may be the answer, whether or not it
                # expanded. A genuine '.7z' SOURCE file stored raw (SR-004
                # declines to re-compress one) expands SUCCESSFULLY — it really
                # is an archive — but its payload is not this row's content; the
                # file itself is. Dropping it there made a blank row for a real
                # '.7z' source unrecoverable while every checker called the store
                # clean (WP5 review, finding H2). Symmetric with the
                # failed-expand case, and free on the happy path.
                try {
                    if ($f.Length -eq $Length -and (Get-FileXxHash -FilePath $f.FullName) -eq $Hash) {
                        return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Form = 'Raw'; Detail = '' }
                    }
                } catch {
                    $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                        Detail = "Candidate '$($f.FullName)' could not be read: $($_.Exception.Message)" })
                }
                if ($expandError) {
                    if (Test-SevenZipUsable -SevenZipPath $SevenZipPath) {
                        # 7-Zip provably works here, so the archive itself is
                        # damaged — see $failedExpand above.
                        $failedExpand.Add("'$($f.FullName)': $expandError")
                    } else {
                        # 7-Zip cannot run/write on THIS host: the candidate is
                        # untested, not disproven. Exit-4 territory, with the
                        # precise remediation (2026-08-24 review, blocker 2).
                        $hostIssues.Add([pscustomobject]@{ Cause = 'DependencyMissing'
                            Detail = "7-Zip at '$SevenZipPath' is present but NOT usable on this host (self-test failed); archive candidate '$($f.FullName)' could not be tested: $expandError" })
                    }
                }
            } elseif ($f.Length -eq $Length) {
                try {
                    if ((Get-FileXxHash -FilePath $f.FullName) -eq $Hash) {
                        return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Form = 'Raw'; Detail = '' }
                    }
                } catch {
                    $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                        Detail = "Candidate '$($f.FullName)' could not be read: $($_.Exception.Message)" })
                }
            }
        }
    }

    # A missing dependency outranks the other: it is the one with a precise
    # remediation ("install 7-Zip"), so it is what the operator should be told.
    foreach ($preferred in 'DependencyMissing', 'StorageUnreadable') {
        $issue = $hostIssues | Where-Object { $_.Cause -eq $preferred } | Select-Object -First 1
        if ($issue) {
            return [pscustomobject]@{ Path = $null; Cause = $issue.Cause; Form = $null; Detail = $issue.Detail }
        }
    }
    $detail = "No file with (hash=$Hash, length=$Length) survives anywhere in the data pool."
    if ($failedExpand.Count -gt 0) {
        $detail += " $($failedExpand.Count) archive candidate(s) could not be expanded" +
            " (7-Zip passed its self-test on this host, so the archive itself is damaged): $($failedExpand[0])."
    }
    return [pscustomobject]@{
        Path   = $null
        Cause  = 'ContentMissing'
        Form   = $null
        Detail = $detail
    }
}

function New-StoredObjectNameIndex {
    <#
    .SYNOPSIS
        Lists the TOP-LEVEL files of each pool folder once and maps every
        stored-object name to the (hash, length) it carries (kit revision 14).

    .DESCRIPTION
        Every stored object is named "<hash22>_<len><ext>" from its own content
        (SR-069), and objects sit flat at the top of the backup root and of each
        Snapshot_* folder. So one listing answers "where are the bytes for this
        (hash, length)?" for every row of the restore. Before revision 14 each
        blank or stale row ran Find-DataFileByHash, which re-listed the whole
        pool recursively and hashed candidates FOR EACH ROW: rows x pool.

        Names are parsed only by ConvertFrom-HashSizeFileName, the one parser
        (AGENTS.md section 3). A name that does not parse - infrastructure, a
        pre-WP12 base-85 name, debris - is not an object and is ignored; the
        content scan still covers it as the last resort. A folder that does not
        exist or cannot be listed simply contributes nothing: the content scan
        is what reports an unreadable pool (StorageUnreadable, exit 4).

        A name is a CLAIM about the bytes, not proof. The caller treats a hit
        exactly like a DataPath file: its form comes from its bytes (SR-068)
        and the written file is verified against the row (SR-056).

        A name ending in '.fbprune.tmp' (compared ordinal, ignoring case) is
        never indexed: it is a prune's staged copy (Copy-ReHomedDataFile
        writes '<object>.fbprune.tmp' and publishes it by rename), and a prune
        killed mid-copy leaves a PARTIAL one beside the destination. Indexed,
        it was the first candidate of its key, a partial archive failed to
        expand, and the restore exited 4 with the intact original still in
        the pool (review 2026-10-26 A3). No object carries that suffix - an
        object's extension is one GetExtension segment - and the content scan
        still sees every file, so nothing is lost by skipping it. Nothing is
        deleted here by suffix (AGENTS.md section 3).

    .PARAMETER Folders
        Pool folders in candidate order: the restore origin first, then the
        backup root, then snapshots newest first. Duplicates are the caller's
        to remove.

    .OUTPUTS
        [hashtable] "<HASH32>:<length>" -> List[string] of full paths, in the
        order of -Folders.
    #>
    # Implements: SR-010, SR-069, LLR-069
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][string[]]$Folders = @())

    $index = @{}
    foreach ($folder in $Folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        # -Force (SR-057): a pool object carrying the Hidden attribute is still
        # an object. Top level only - objects never nest.
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)) {
            # A prune's staged copy, never an object (see .DESCRIPTION).
            if ($f.Name.EndsWith('.fbprune.tmp', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $parsed = ConvertFrom-HashSizeFileName -Name $f.Name
            if ($null -eq $parsed) { continue }
            $key  = "$($parsed.HashHex):$($parsed.Length)"
            $list = $index[$key]
            if ($null -eq $list) {
                $list = New-Object System.Collections.Generic.List[string]
                $index[$key] = $list
            }
            $list.Add($f.FullName)
        }
    }
    return $index
}

function Find-DataFileByName {
    <#
    .SYNOPSIS
        The first indexed object for a row's (hash, length) that still exists,
        or $null when the name index has no usable candidate (kit revision 14).

    .PARAMETER Index
        The table New-StoredObjectNameIndex built.

    .PARAMETER Hash
        The row's xxH2Hash, 32 hex digits (compared in upper case, as
        ConvertFrom-HashSizeFileName reports it).

    .PARAMETER Length
        The row's Length.

    .OUTPUTS
        [string] a full path, or $null.
    #>
    # Implements: SR-010, SR-069, LLR-069
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Index,
        [Parameter(Mandatory)][string]$Hash,
        [Parameter(Mandatory)][long]$Length
    )
    $list = $Index["$($Hash.ToUpperInvariant()):$Length"]
    if ($null -eq $list) { return $null }
    # Listed once at the start; a candidate can have gone since. The first that
    # is still there wins - it is verified after the write in any case.
    foreach ($candidate in $list) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

# ---- Resolve backup/change roots ----
$isChangeFolder = $folderName -match $ChangeFolderPattern

# Sidecar written by New-ReconstructScript takes precedence over auto-detection
# (B10) — but ONLY while this folder still lives inside the roots it records.
# The recorded absolute paths are meaningless for a store that was copied or
# moved (USB, another machine, a drive-letter change), and honoring them there
# either fails against a dead path or, worse, silently restores from the
# still-live ORIGINAL store instead of this copy. reconstruct.sh applies the
# same containment rule.
$sidecar = Join-Path $here 'RECONSTRUCT.paths.json'
if (-not $BackupRootOverride -and (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
    try {
        $paths = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json
        $hereIsInsideRecorded = foreach ($root in @($paths.BackupRoot, $paths.ChangeRoot)) {
            if ($root -and (Test-Path -LiteralPath $root -PathType Container)) {
                $r = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
                $h = [System.IO.Path]::GetFullPath($here).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
                if ($h.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { $true; break }
            }
        }
        if ($hereIsInsideRecorded) {
            if (-not $BackupRootOverride) { $BackupRootOverride = $paths.BackupRoot }
            if (-not $ChangeRootOverride) { $ChangeRootOverride = $paths.ChangeRoot }
        } else {
            Write-Warning "Path sidecar '$sidecar' records roots this folder no longer lives in (the store was likely copied or moved); using auto-detection."
        }
    } catch {
        Write-Warning "Could not read path sidecar '$sidecar'; falling back to auto-detection. $($_.Exception.Message)"
    }
}

if ($isChangeFolder) {
    $changeRoot = [System.IO.Path]::GetDirectoryName($here)
    $backupRoot = [System.IO.Path]::GetDirectoryName($changeRoot)
    # The one-mount layout (bounded-run-loop R8) keeps the backup root BESIDE
    # the change root (<store>/backup, <store>/changes), not above it. When the
    # parent holds no manifest, the one sibling that does is the backup root;
    # otherwise the name index would miss the latest state's objects and every
    # row naming one would fall to the content scan.
    if ($backupRoot -and -not (Test-Path -LiteralPath (Join-Path $backupRoot $DatabaseFilename) -PathType Leaf)) {
        $siblings = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force -ErrorAction SilentlyContinue |
                      Where-Object { $_.FullName -ne $changeRoot -and (Test-Path -LiteralPath (Join-Path $_.FullName $DatabaseFilename) -PathType Leaf) })
        if ($siblings.Count -eq 1) { $backupRoot = $siblings[0].FullName }
    }
} else {
    $backupRoot = $here
    $changeRoot = $null     # B10: no assumed CHANGES sibling; only used if known.
    # A latest-state restore needs the snapshots only for a row whose object
    # still sits in one (a move back that failed, plan C19). With no change root
    # recorded or given, the one folder inside or beside the backup root that
    # holds Snapshot_* folders is it - found, not assumed by name (B10). Every
    # restored file is verified, so a wrong guess can supply no wrong bytes.
    if (-not $ChangeRootOverride) {
        $parent = [System.IO.Path]::GetDirectoryName($here)
        $candidates = @(@(Get-ChildItem -LiteralPath $here -Directory -Force -ErrorAction SilentlyContinue) +
                        @(if ($parent) { Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $here } }) |
                        Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
                                         Where-Object Name -match $ChangeFolderPattern | Select-Object -First 1).Count -gt 0 })
        if ($candidates.Count -eq 1) { $changeRoot = $candidates[0].FullName }
    }
}

if ($BackupRootOverride) { $backupRoot = $BackupRootOverride }
if ($ChangeRootOverride) { $changeRoot = $ChangeRootOverride }

function Show-ReconstructUsage {
    <#
    .SYNOPSIS
        The usage text printed when a non-interactive run omits -TargetRoot,
        mirroring reconstruct.sh's usage() parameter-for-parameter so the twin
        restorers document the same surface.
    #>
    # Implements: SR-016, LLR-016
    return @'
Usage: RECONSTRUCT.ps1 -TargetRoot DIR [-BackupRootOverride DIR]
                       [-ChangeRootOverride DIR] [-SevenZipPath PATH]
                       [-NonInteractive] [-NoGui] [-ExitCode]

  -TargetRoot DIR          Where to rebuild the tree (must be OUTSIDE the backup).
  -BackupRootOverride DIR  Override the auto-detected backup root (the live data pool).
  -ChangeRootOverride DIR  Override the folder that holds the Snapshot_<date> siblings.
  -SevenZipPath PATH       Explicit 7z binary (else the configured default; needed
                           only when the backup has compressed rows).
  -NonInteractive          Never prompt: a missing -TargetRoot becomes this usage
                           text and exit 2 (reconstruct.sh's required --target-root
                           is the twin).
  -NoGui                   Never open a folder picker; use the typed prompt.
                           Also honoured as FILEBACKUP_NO_GUI=1.
  -ExitCode                Exit the process with the SR-040 code instead of throwing.

Exit: 0 complete; 1 incomplete, content unrecoverable; 2 usage/precondition;
      4 incomplete, host problem (retry after fixing this machine).
      Precedence: 2 > 4 > 1. (3, the manifest-witness refusal, is retired.)
'@
}

function Test-ShouldPromptGraphically {
    <#
    .SYNOPSIS
        Decides whether a missing -TargetRoot should be asked for with a folder
        picker, with a typed prompt, or not asked for at all (SR-073).

    .DESCRIPTION
        PURE: every signal is a parameter and nothing is read from the
        environment, so the whole decision matrix is unit-testable — a modal
        dialog can never be shown in a test. The I/O lives in
        Select-FolderInteractively.

        Returns one of three decisions:
          'None'   nothing may be asked; the caller must fail with usage/exit 2.
          'Text'   a console is present; use the typed prompt (today's behaviour).
          'Gui'    a desktop session is present and a picker is permitted.

    .PARAMETER NonInteractive
        The caller declared itself scripted.
    .PARAMETER InputRedirected
        stdin is not a console, so a prompt would read EOF or block.
    .PARAMETER UserInteractive
        The process has a station that can interact with a desktop. FALSE for a
        service, a Task Scheduler job set to run whether or not a user is logged
        on, and session-0 hosts.
    .PARAMETER NoGui
        The operator asked for no dialog.
    .PARAMETER IsWindowsHost
        WinForms exists only on Windows; other platforms use a native helper.
    .OUTPUTS
        [string] 'None' | 'Text' | 'Gui'
    #>
    # Implements: SR-016, SR-073, LLR-073
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [bool]$NonInteractive,
        [bool]$InputRedirected,
        [bool]$UserInteractive,
        [bool]$NoGui,
        [bool]$IsWindowsHost
    )
    # Automation must never block (SR-016/SN-011). The first two were already
    # guarded; UserInteractive is NEW at kit revision 10 and closes a hole that
    # HAS BEEN SHIPPING: a scheduled task started without -TargetRoot and
    # without -NonInteractive has neither switch nor redirected stdin, reached
    # Read-Host, and waited forever (2026-08-28 independent review, T7). There
    # is no console to type into and no desktop to show a dialog on, so the
    # honest answer is a usage failure, not a prompt nobody can answer.
    if ($NonInteractive -or $InputRedirected -or -not $UserInteractive) { return 'None' }
    if ($NoGui) { return 'Text' }
    return 'Gui'
}

function Select-FolderInteractively {
    <#
    .SYNOPSIS
        Opens a native folder picker and returns the chosen path, or $null when
        one is unavailable or the operator cancelled (SR-073).

    .DESCRIPTION
        The I/O shell for Test-ShouldPromptGraphically. Never throws: every
        failure is $null, and the caller falls back to the typed prompt, so a
        host without a usable dialog is never worse off than before.

        Windows uses WinForms. PowerShell 7.3+ runs STA on Windows, but 7.0-7.2
        defaulted to MTA and this kit lands on unknown machines — a rescue box,
        an old install — so ShowDialog is marshalled onto a dedicated STA thread
        whenever the current apartment is not STA. macOS uses osascript, which
        needs nothing installed; Linux tries zenity then kdialog.

    .PARAMETER Picker
        Test seam: a scriptblock returning a path, $null, or throwing. When
        supplied it replaces the platform dialog entirely, so the fallback paths
        are provable without a dialog ever appearing.
    .OUTPUTS
        [string] the chosen directory, or $null.
    #>
    # Implements: SR-073, LLR-073
    [CmdletBinding()]
    [OutputType([string])]
    param([scriptblock]$Picker)

    $prompt = 'Choose the folder to restore into (must be OUTSIDE the backup)'
    try {
        if ($Picker) { $chosen = & $Picker $prompt }
        elseif ($IsWindows) { $chosen = Invoke-WindowsFolderDialog -Description $prompt }
        elseif ($IsMacOS) {
            $chosen = & osascript -e "POSIX path of (choose folder with prompt ""$prompt"")" 2>$null
        }
        elseif (Get-Command zenity -ErrorAction SilentlyContinue) {
            $chosen = & zenity --file-selection --directory --title=$prompt 2>$null
        }
        elseif (Get-Command kdialog -ErrorAction SilentlyContinue) {
            $chosen = & kdialog --getexistingdirectory $HOME --title $prompt 2>$null
        }
        else { return $null }
    } catch {
        # A missing toolkit, a headless station, a COM failure: all mean 'no
        # dialog', never 'fail the restore'.
        return $null
    }
    $chosen = "$chosen".Trim()
    if (-not $chosen) { return $null }
    return $chosen.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Invoke-WindowsFolderDialog {
    <#
    .SYNOPSIS
        Shows the Windows folder browser, on an STA thread if this one is not.
    .PARAMETER Description
        The prompt shown in the dialog.
    .OUTPUTS
        [string] the selected path, or $null when cancelled/unavailable.
    #>
    # Implements: SR-073, LLR-073
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Description)

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $show = {
        param([string]$Prompt)
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $dialog.Description         = $Prompt
            $dialog.ShowNewFolderButton = $true
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.SelectedPath } else { $null }
        } finally { $dialog.Dispose() }
    }
    return (Invoke-OnStaThread -Script $show -Arguments @($Description))
}

function Invoke-OnStaThread {
    <#
    .SYNOPSIS
        Runs a scriptblock on a single-threaded-apartment thread and returns its
        result, or $null if it faulted.

    .DESCRIPTION
        Windows shell dialogs require STA. PowerShell 7.3+ is STA by default on
        Windows, but 7.0-7.2 defaulted to MTA and this kit lands on unknown
        machines, so the MTA case has to work.

        It must NOT be done with a raw System.Threading.Thread: a PowerShell
        scriptblock invoked on a bare .NET thread has no Runspace and throws
        'There is no Runspace available to run scripts in this thread' - as an
        UNHANDLED exception on a background thread, which terminates the whole
        process rather than merely failing to return (2026-08-28 independent
        review, T3; reproduced). A runspace created with ApartmentState = STA is
        the supported route: PowerShell owns the thread and marshals the result.

        Separated from the dialog so the marshalling itself is testable with a
        harmless scriptblock - the dialog can never be shown in a test, which is
        exactly why the broken version survived review of the code around it.

    .PARAMETER Script
        The scriptblock to run.
    .PARAMETER Arguments
        Positional arguments for it.
    .OUTPUTS
        The scriptblock's last output object, or $null when it wrote an error.
    #>
    # Implements: SR-073, LLR-073
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [object[]]$Arguments = @()
    )
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        return (& $Script @Arguments)
    }
    $runspace = $null
    $shell    = $null
    try {
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
        $runspace.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $runspace.Open()
        $shell = [powershell]::Create()
        $shell.Runspace = $runspace
        $null = $shell.AddScript($Script.ToString())
        foreach ($arg in $Arguments) { $null = $shell.AddArgument($arg) }
        $out = $shell.Invoke()
        if ($shell.Streams.Error.Count -gt 0) { return $null }
        return ($out | Select-Object -Last 1)
    } finally {
        if ($shell)    { $shell.Dispose() }
        if ($runspace) { $runspace.Dispose() }
    }
}

# Set when -TargetRoot came from a picker or a typed prompt rather than the
# command line: the only case in which this script holds its window open.
$script:InteractiveTarget = $false

if (-not $TargetRoot) {
    $askMode = Test-ShouldPromptGraphically `
        -NonInteractive  ([bool]$NonInteractive) `
        -InputRedirected ([System.Console]::IsInputRedirected) `
        -UserInteractive ([System.Environment]::UserInteractive) `
        -NoGui           ([bool]$NoGui -or '1' -eq $env:FILEBACKUP_NO_GUI) `
        -IsWindowsHost   ([bool]$IsWindows)

    if ($askMode -eq 'None') {
        # Automation must never block (SR-016): fail loudly with usage — the
        # exact behavior of reconstruct.sh's required --target-root.
        $why = if ($NonInteractive -or [System.Console]::IsInputRedirected) {
            '-TargetRoot is required (non-interactive run; no prompt).'
        } else {
            # Kit revision 10 (SR-073): NO console and NO desktop. This used to
            # fall through to Read-Host and wait forever — a scheduled task set
            # to run whether or not a user is logged on has neither switch nor
            # redirected stdin, so it hung instead of failing (2026-08-28
            # independent review, T7). There is nobody to answer a prompt here.
            '-TargetRoot is required (no interactive console or desktop session; no prompt).'
        }
        Write-Host (Show-ReconstructUsage)
        if ($NonInteractive -and -not $ExitCode) {
            # -NonInteractive DECLARES a scripted caller: deliver the SR-040
            # code at the process boundary even without -ExitCode, so a
            # scheduled `pwsh -File` invocation reads 2 (usage), not the
            # throw path's 1 — the code reserved for data loss (2026-08-24
            # review, minor 8). No in-process caller passes -NonInteractive.
            $script:classified = $true
            [Console]::Error.WriteLine("reconstruct: $why")
            exit $EXIT_PRECONDITION
        }
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message $why
    }

    if ($askMode -eq 'Gui') {
        # Cancel, or no usable dialog, falls through to the typed prompt below:
        # a desktop operator is never left worse off than before the picker.
        $picked = Select-FolderInteractively
        if ($picked) { $TargetRoot = $picked; $script:InteractiveTarget = $true }
    }

    if (-not $TargetRoot) {
        $TargetRoot = Read-Host 'Enter target folder to reconstruct into'
        if ($TargetRoot) { $script:InteractiveTarget = $true }
    }
}

# Reject a target inside the backup/change root (SR-009). Compare normalized full
# paths with a trailing separator so a prefix-sharing sibling (e.g. 'bkp' vs
# 'bkp-restore') is allowed and bracket/wildcard chars are treated literally —
# '-like' would mishandle both.
function Resolve-PathPhysically {
    <#
    .SYNOPSIS
        A path with its reparse points (junctions, symlinks) resolved, for the
        SR-009 containment test.

    .DESCRIPTION
        GetFullPath alone is LEXICAL: it normalises separators and '..' but
        never follows a junction, so a target under one was judged by where it
        is NAMED rather than where it LANDS. With 'C:\outside\link' a junction
        to the backup root, '-TargetRoot C:\outside\link\restore' compared as
        outside and the restore then wrote INTO the backup (2026-08-28
        independent review, T1; recorded before that as D-7/F-3, the divergence
        from the bash twin, which has always resolved links via realpath).

        The target usually does not exist yet, so the deepest EXISTING ancestor
        is resolved and the remaining tail re-appended - a path that does not
        exist cannot contain a reparse point. Mirrors canon() in reconstruct.sh.
    .OUTPUTS
        [string] the physical path; the lexical one when nothing can be resolved.
    #>
    # Implements: SR-009, LLR-079
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $tail = ''
    $cur  = $full
    while ($cur) {
        if (Test-Path -LiteralPath $cur) {
            try {
                $item = Get-Item -LiteralPath $cur -Force -ErrorAction Stop
                # ResolveLinkTarget(final:$true) walks a chain of links; it
                # returns $null when the item is not a link at all.
                $resolved = $null
                if ($item.LinkTarget) {
                    $resolved = [System.IO.Directory]::ResolveLinkTarget($cur, $true)
                }
                $base = if ($resolved) { $resolved.FullName } else { $item.FullName }
            } catch {
                $base = $cur
            }
            if ($tail) { return [System.IO.Path]::GetFullPath((Join-Path $base $tail)) }
            return [System.IO.Path]::GetFullPath($base)
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $leaf = [System.IO.Path]::GetFileName($cur)
        $tail = if ($tail) { Join-Path $leaf $tail } else { $leaf }
        $cur  = $parent
    }
    return $full
}

function Test-PathIsInside {
    <#
    .SYNOPSIS
        True when Child is Parent or sits underneath it, compared PHYSICALLY
        (SR-009).
    .DESCRIPTION
        Both sides are resolved through Resolve-PathPhysically first, so a
        junction cannot present an inside path as an outside one. The trailing
        separator keeps a prefix-sharing sibling ('bkp' vs 'bkp-restore')
        outside, and StartsWith rather than -like means bracket and wildcard
        characters are treated literally.
    #>
    # Implements: SR-009, LLR-079
    param([string]$Child, [string]$Parent)
    $c = (Resolve-PathPhysically -Path $Child).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $p = (Resolve-PathPhysically -Path $Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $c.StartsWith($p, [System.StringComparison]::OrdinalIgnoreCase)
}
if (Test-PathIsInside -Child $TargetRoot -Parent $backupRoot) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message 'TargetRoot must be outside the backup root.'
}
if ($changeRoot -and (Test-Path -LiteralPath $changeRoot -PathType Container) -and (Test-PathIsInside -Child $TargetRoot -Parent $changeRoot)) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message 'TargetRoot must be outside the change folder root.'
}

function Read-RawManifest {
    <#
    .SYNOPSIS
        Reads the restore origin's MANIFEST.csv after proving it is one: it
        exists and its header is a FileBackup manifest header.

    .DESCRIPTION
        Runs BEFORE the target folder, the log, and the capacity pre-check
        exist, so a refusal leaves the target byte-for-byte untouched - not
        even a RECONSTRUCT.log - exactly as reconstruct.sh does. An
        unrecognizable header is exit 2: this is not a manifest at all (the
        corrupt-file guard, matching reconstruct.sh's wording).

        Kit revision 14 reads NO MANIFEST.csv.meta witness (bounded-run-loop
        R5). One that is present, stale or garbage is ignored; there is no
        exit 3 and no 'unverified index' warning any more. A snapshot's
        manifest is written once and never rewritten (R6); a damaged row is
        caught where it matters, when every written file is verified against
        its row (SR-056).

    .PARAMETER Folder
        The restore origin (backup root or Snapshot_<date> folder).
    #>
    # Implements: SR-040, LLR-040
    param([string]$Folder)

    $path = Join-Path $Folder $DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "MANIFEST.csv not found in restore origin '$Folder'. The backup folder is incomplete."
    }

    # Header-shape guard (mirrors reconstruct.sh): a legitimately empty backup
    # still carries the full header row, so this only rejects a corrupt or
    # wrong file.
    $header = ("$(Get-Content -LiteralPath $path -TotalCount 1)").TrimStart([char]0xFEFF)
    if ($header -notmatch 'RelativePath' -or $header -notmatch 'xxH2Hash') {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "'$path' is not a FileBackup manifest (unexpected header). Corrupt or wrong file."
    }

    Import-Csv -LiteralPath $path
}

# ---- Build main dictionary (SR-010 authority rule) ----
# From a dated snapshot folder, that snapshot's OWN manifest is the sole
# point-in-time authority (no newer manifest is overlaid). From the backup root,
# the live backup manifest is the latest state. In both cases the bytes are
# resolved later from the data pool by hash where a DataPath is blank.
# New-RelativePathMap: case-sensitive keys on Linux, where case-differing
# manifest rows are distinct ordinary files (SR-034).
$main = New-RelativePathMap
$haveSnapshotTree = $changeRoot -and (Test-Path -LiteralPath $changeRoot -PathType Container)
$authorityFolder  = if ($isChangeFolder) { $here } else { $backupRoot }

foreach ($row in (Read-RawManifest -Folder $authorityFolder)) {
    if (-not $row.RelativePath) { continue }
    $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $authorityFolder -Force
    $main[$row.RelativePath] = $row
}

# ---- Pre-WP12 store: refused, not restored (SR-061 / SR-069) ----
# Support for WRITING a pre-content-addressed store went at WP9; kit revision 7
# withdrew READING it too, and kit revision 9 (WP12) extends the same refusal to
# a pre-WP12 CONTENT-ADDRESSED store, whose objects carry the old base-85,
# space-separated names. Refused as a PRECONDITION before the target exists -
# nothing attempted, nothing written.
#
# TWO markers, because neither is complete alone:
#   1. StoredAsHashSize='Original'  - a pre-content-addressed store (WP9).
#   2. A DataPath in a RETIRED grammar - a path separator (pre-WP9
#      path-addressed), or a space at index 16 (the pre-WP12 base-85
#      "<hash16> <len10><ext>" form).
# Until kit revision 14 a third marker read the format Version out of the
# MANIFEST.csv.meta witness. The kit no longer reads the witness at all
# (bounded-run-loop R5), so that marker went with it.
#
# Marker 2 is a POSITIVE test, NOT "does not parse under SR-069". Those are not
# complements: a merely DAMAGED DataPath parses under neither grammar, and
# SR-049/SR-053/SR-056 require the per-row audit, heal and verify machinery to
# answer for it. Refusing the whole store there would turn one repairable row
# into an unrestorable backup.
#
# A blank DataPath means 'resolve by (hash, length)' and is NOT tested by 2 - a
# blank string carries no grammar. That gap is benign: a pre-WP12 object name
# never parses under SR-069, so the name index cannot misread one, and the
# content scan behind it matches CONTENT, never names. A store reached through
# blank rows alone restores correctly whatever its objects are called.
$legacyRow = $null
$legacyWhy = $null

foreach ($rel in $main.Keys) {
    $candidate = $main[$rel]
    if ("$($candidate.StoredAsHashSize)" -eq 'Original') {
        $legacyRow = $candidate
        $legacyWhy = "carries StoredAsHashSize='$($candidate.StoredAsHashSize)'"
        break
    }
    # A POSITIVE test for the retired grammars, never the negation of the
    # current one. A row whose DataPath is merely DAMAGED parses under neither,
    # and SR-056's verify-and-heal machinery must get to answer for it - a
    # whole-store refusal would turn one repairable row into an unrestorable
    # backup. Refuse the old FORMAT; let damaged ROWS take the content path.
    if (Test-LegacyStoredObjectName -Name "$($candidate.DataPath)") {
        $legacyRow = $candidate
        $legacyWhy = "names its data '$($candidate.DataPath)', a retired stored-object name"
        break
    }
}
if ($legacyRow) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message (
        "'$authorityFolder' is not a store this kit can restore: row '$($legacyRow.RelativePath)' $legacyWhy. " +
        'This kit (revision 9) restores only content-addressed stores using the SR-069 base-57 name grammar ' +
        '(SR-061). Restore it with the kit bundled inside that backup folder, which was written by the build ' +
        'that produced it.')
}

# ---- Create the target and open the log (first mutation of this run) ----
# Everything above refuses with 2 without writing a single byte into the
# target. Failures here are PRECONDITION failures: nothing has been
# attempted, and reconstruct.sh's `mkdir -p || die` returns 2 for the same
# causes (a file occupying the target path, a read-only parent).
if (Test-Path -LiteralPath $TargetRoot -PathType Leaf) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "Cannot create target folder '$TargetRoot': a file occupies that path."
}
if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $TargetRoot -Force -ErrorAction Stop | Out-Null
    } catch {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "Cannot create target folder '$TargetRoot': $($_.Exception.Message)"
    }
}
# Where the content scan expands a candidate archive to test it: the target's
# own volume (each file is created and deleted beside the restored tree).
$script:ExpandScratch = $TargetRoot

$logPath = Join-Path $TargetRoot $ReconstructLogName
try {
    "$(Get-Date -Format 'O') - Reconstruction starting" | Out-File -LiteralPath $logPath -Encoding UTF8 -ErrorAction Stop
} catch {
    $logPath = $null
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "Cannot open the restore log in target folder '$TargetRoot': $($_.Exception.Message)"
}
foreach ($line in $pendingLog) { $line | Out-File -LiteralPath $logPath -Append }
$pendingLog.Clear()

# ---- Capacity pre-check (B11: skip compressed rows; lengths are uncompressed) ----
$totalBytes = 0L
$anyCompressed = $false
foreach ($rel in $main.Keys) {
    $row = $main[$rel]
    if ($row.Compressed -eq 'Yes') { $anyCompressed = $true; continue }
    if ($row.Length) { $totalBytes += [long]$row.Length }
}
# Measure the target volume through Get-FreeSpaceBytes (SR-052), which never
# throws and works for a rooted POSIX path as well as a drive-qualified Windows
# one. The previous `Split-Path -Qualifier` lookup ERRORED on '/restore' and was
# swallowed by the adjacent catch, so this whole check was silently inert on
# Linux and in the container while bash/reconstruct.sh's `df` half worked.
# An UNMEASURABLE volume still skips the check: not knowing the free space is
# not evidence that there is none (SR-023 / B11).
$freeBytes = Get-FreeSpaceBytes -Path $TargetRoot
if ($null -eq $freeBytes) {
    Write-Verbose "Capacity pre-check skipped (could not measure the target volume)."
} else {
    if ($freeBytes -lt $totalBytes) {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "Not enough free space on target drive. Required (uncompressed rows only): $totalBytes, Free: $freeBytes"
    }
    if ($anyCompressed) {
        "$(Get-Date -Format 'O') - NOTE: backup contains compressed rows; capacity check excluded them (true need is higher)." |
            Out-File -LiteralPath $logPath -Append
    }
}

# ---- Data pool for hash recovery (SR-010): backup root + every snapshot ----
# A blank/relocated DataPath resolves its bytes by (hash,length) wherever they
# survived: unchanged files from the live backup, superseded versions from the
# snapshot that retained them. Built as a list so an empty snapshot set never
# injects a $null folder.
$searchFolders   = New-Object System.Collections.Generic.List[string]
$snapshotFolders = New-Object System.Collections.Generic.List[string]
if ($haveSnapshotTree) {
    # -Force (SR-057): a hidden snapshot folder must not drop out of the pool.
    $snapEnumErr = $null
    Get-ChildItem -LiteralPath $changeRoot -Directory -Force -ErrorAction SilentlyContinue -ErrorVariable snapEnumErr |
        Where-Object { $_.Name -match $ChangeFolderPattern } |
        Sort-Object Name -Descending |
        ForEach-Object { $snapshotFolders.Add($_.FullName) }
    foreach ($snap in $snapshotFolders) { $searchFolders.Add($snap) }
    if ($snapEnumErr) {
        # The snapshot tree exists but could not be LISTED: the pool is
        # incomplete in an unknowable way, and silently continuing would let
        # a blank row whose only copy lives in a snapshot report "your bytes
        # are gone" (exit 1) for what is a host problem. Adding the unlistable
        # root itself makes the locator surface StorageUnreadable (exit 4)
        # instead (2026-08-25 Terra review, T2).
        $searchFolders.Add($changeRoot)
    }
}
$searchFolders.Add($backupRoot)

# ---- Name index folders (kit revision 14) ----
# The same pool, in the order a row's bytes are most likely to be: the restore
# origin first (a snapshot's own superseded objects), then the backup root
# (latest), then snapshots newest first. Built lazily, on the first row that
# needs it, so a restore whose every DataPath resolves never lists the pool.
$indexFolders = New-Object System.Collections.Generic.List[string]
foreach ($folder in @($authorityFolder, $backupRoot) + @($snapshotFolders)) {
    $full = [System.IO.Path]::GetFullPath($folder).TrimEnd('\', '/')
    if ($indexFolders -notcontains $full) { $indexFolders.Add($full) }
}
$script:nameIndex = $null

function Resolve-RowDataSource {
    <#
    .SYNOPSIS
        Decides which file supplies a row's bytes: its own DataPath, else the
        name index, else the content scan (kit revision 14).

    .DESCRIPTION
        A non-blank DataPath whose file exists in the row's own folder is used
        as before. Otherwise the row's (hash, length) is looked up in the name
        index, built on first use (New-StoredObjectNameIndex). A hit is treated
        exactly like a DataPath file: LocatedForm stays $null, so the caller
        decides the form from the bytes (SR-068) and verifies the write
        (SR-056). Only when the index has no usable candidate does
        Find-DataFileByHash scan the pool by content - the last resort, which
        reports the form it PROVED (SR-050) and the cause of a failure
        (SR-040). The log says which of the three resolved the row.

    .PARAMETER Row
        The manifest row, carrying SourceFolder.

    .PARAMETER Rel
        The row's RelativePath, for the log.

    .OUTPUTS
        [pscustomobject] Path / LocatedForm / Cause / Detail. Path set: restore
        from it. Path $null: Cause and Detail are ready for Add-Unrestored.
    #>
    # Implements: SR-010, SR-040, SR-050, SR-068, SR-069, LLR-040, LLR-050
    param(
        [Parameter(Mandatory)][pscustomobject]$Row,
        [Parameter(Mandatory)][string]$Rel
    )
    $dataPath = "$($Row.DataPath)"
    $blank    = [string]::IsNullOrWhiteSpace($dataPath)
    if (-not $blank) {
        $own = Join-Path $Row.SourceFolder (ConvertTo-LocalRelativePath $dataPath)
        if (Test-Path -LiteralPath $own -PathType Leaf) {
            return [pscustomobject]@{ Path = $own; LocatedForm = $null; Cause = $null; Detail = $null }
        }
    }

    # No usable DataPath. Without a key there is nothing to look up or scan for.
    if (-not $Row.xxH2Hash -or -not $Row.Length) {
        if ($blank) {
            return [pscustomobject]@{ Path = $null; LocatedForm = $null; Cause = 'NoDataPathOrHash'
                Detail = 'The manifest row carries neither a DataPath nor a (hash,length) to recover by.' }
        }
        return [pscustomobject]@{ Path = $null; LocatedForm = $null; Cause = 'MissingDataFile'
            Detail = "The row's data file '$dataPath' is not present in the restore origin, and no pool file matches its (hash,length)." }
    }
    $why = if ($blank) { "No datapath for $Rel" } else { "Data file '$dataPath' missing for $Rel" }

    if ($null -eq $script:nameIndex) {
        $script:nameIndex = New-StoredObjectNameIndex -Folders $indexFolders
        Add-ReconstructLog "Name index built: $($script:nameIndex.Count) object key(s) from $($indexFolders.Count) pool folder(s)."
    }
    $byName = Find-DataFileByName -Index $script:nameIndex -Hash $Row.xxH2Hash -Length ([long]$Row.Length)
    if ($byName) {
        Add-ReconstructLog "$why; resolved by name index to '$byName'"
        return [pscustomobject]@{ Path = $byName; LocatedForm = $null; Cause = $null; Detail = $null }
    }

    Add-ReconstructLog "$why; attempting hash scan..."
    $found = Find-DataFileByHash -Hash $Row.xxH2Hash -Length ([long]$Row.Length) -SearchFolders $searchFolders -SevenZipPath $SevenZipPath
    if ($found.Cause -eq 'Found') {
        Add-ReconstructLog "Hash-recovered $Rel from '$($found.Path)' (form: $($found.Form))"
        return [pscustomobject]@{ Path = $found.Path; LocatedForm = $found.Form; Cause = $null; Detail = $null }
    }
    if ($blank -or $found.Cause -ne 'ContentMissing') {
        # One message per CAUSE, not one warning for all four (SR-040). A row
        # WITH a DataPath keeps a host cause too: since C10 nearly every row
        # has one, and reporting an unreadable pool as a missing data file
        # turned "fix this host and retry" (4) into "your bytes are gone" (1)
        # (review 2026-10-26 A7). Only real absence stays MissingDataFile.
        return [pscustomobject]@{ Path = $null; LocatedForm = $null; Cause = $found.Cause; Detail = $found.Detail }
    }
    return [pscustomobject]@{ Path = $null; LocatedForm = $null; Cause = 'MissingDataFile'
        Detail = "The row's data file '$dataPath' is not present in the restore origin, and no pool file matches its (hash,length)." }
}

if ([string]::IsNullOrWhiteSpace($SevenZipPath)) {
    $SevenZipPath = $Def.SevenZipDefaultPath
}
if ($anyCompressed -and
    ([string]::IsNullOrWhiteSpace($SevenZipPath) -or
     -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf))) {
    Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "7-Zip is required to restore compressed rows, but was not found at '$SevenZipPath'. Install 7-Zip or pass -SevenZipPath."
}

# ---- Reconstruct ----
# Every row that cannot be restored is recorded; a partial restore must FAIL
# LOUDLY at the end (SR-029) — a scripted caller checking the exit code must
# never mistake an incomplete tree for success. Recoverable rows are still
# restored first so the caller salvages everything salvageable.
# Each failure carries its CAUSE so the summary can separate "your bytes are
# gone" (exit 1) from "fix this host and retry" (exit 4) — SR-040.
# Implements: SR-009, SR-029, SR-040, LLR-009, LLR-029, LLR-040
$unrestored = New-Object System.Collections.Generic.List[pscustomobject]
function Add-Unrestored {
    <#
    .SYNOPSIS
        Records one unrestorable manifest row with the cause that classifies it
        into the content class (exit 1) or the host class (exit 4).
    #>
    # Implements: SR-040, LLR-040
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Cause,
        [Parameter(Mandatory)][string]$Detail
    )
    "$(Get-Date -Format 'O') - WARN: [$Cause] $RelativePath — $Detail" | Out-File -LiteralPath $logPath -Append
    $unrestored.Add([pscustomobject]@{ RelativePath = $RelativePath; Cause = $Cause; Detail = $Detail })
}

# Manifest paths use the separator of the machine that WROTE the backup. On a
# non-Windows restore host, map '\' to '/' (reconstruct.sh's to_posix does the
# same) — otherwise a Windows-made 'sub\file.txt' is written as one root-level
# file literally named 'sub\file.txt', a structurally wrong tree with exit 0.
function ConvertTo-LocalRelativePath {
    param([string]$Path)
    if ($IsWindows) { return $Path }
    return $Path.Replace('\', '/')
}

function Restore-OneRow {
    <#
    .SYNOPSIS
        Writes one manifest row's bytes to its destination and verifies the
        written file against the row's (Length, xxH2Hash) — SR-056.

    .DESCRIPTION
        The single write+verify implementation (kit revision 6): the restore
        loop calls it once per row, and at most once more after a pool
        recovery. Verification hashes the DESTINATION file — the locator (when
        one was involved) proved the POOL file, not this write, so a truncated
        write to a full target or an extraction that produced a different file
        must not report success. Length is compared first (cheap); the hash
        only when the length agrees. 0-byte rows hash like any other. A row
        carrying no hash restores unverified, as it always did.

        On a mismatch the bad destination file is DELETED before returning —
        wrong bytes must not be left where the user asked for good ones.

    .OUTPUTS
        [pscustomobject] Outcome / Cause / Detail / Got:
          Outcome 'ok'       — written and verified (or unverifiable row).
          Outcome 'mismatch' — written bytes disagree with the row; destination
                               deleted; Got carries "<hash>/<length>" actually
                               written, for the ContentMismatch log line.
          Outcome 'hostfail' — the write itself failed (extraction/copy/
                               read-back I/O); Cause/Detail ready for
                               Add-Unrestored, host class (SR-040). A failed
                               copy or expand never touched the destination:
                               both land by a rename only after succeeding.
    #>
    # Implements: SR-056, LLR-056
    param(
        [Parameter(Mandatory)][string]$SrcFull,
        [Parameter(Mandatory)][string]$DestFull,
        [Parameter(Mandatory)][bool]$NeedsExpand,
        [Parameter(Mandatory)][pscustomobject]$Row
    )
    if ($NeedsExpand) {
        try {
            Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $SrcFull -DestinationFile $DestFull
        } catch {
            return [pscustomobject]@{ Outcome = 'hostfail'; Cause = 'CandidateError'
                Detail = "7-Zip extraction failed from '$SrcFull': $($_.Exception.Message)"; Got = $null }
        }
    } else {
        # The copy lands the way Expand-FileWithSevenZip lands a payload:
        # written under a hidden '.fbrestore-*' name beside the destination
        # (same folder, so same volume) and renamed over it only once the copy
        # succeeded. A copy that fails part-way (a full target volume) leaves
        # no partial file at the restored path, and one that fails before
        # writing anything (an unreadable source) leaves a file already there -
        # a row an earlier run restored and verified - untouched (review
        # 2026-10-26 B). On failure only the temp is removed, never the
        # destination. copy_to_file in reconstruct.sh is the twin.
        $temp = Join-Path ([System.IO.Path]::GetDirectoryName($DestFull)) ('.fbrestore-' + [IO.Path]::GetRandomFileName())
        try {
            Copy-Item -LiteralPath $SrcFull -Destination $temp -Force -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $DestFull -Force -ErrorAction Stop
        } catch {
            $copyError = $_.Exception.Message
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ Outcome = 'hostfail'; Cause = 'CandidateError'
                Detail = "Copy from '$SrcFull' failed: $copyError"; Got = $null }
        }
    }
    # A RESTORED TREE IS ORDINARY WRITABLE FILES (human ruling 2026-08-28).
    # Copy-Item propagates the ReadOnly attribute from the pool object, so a
    # write-protected store would hand its protection straight to the restored
    # file — and a snapshot keeps the kit it was written with FOREVER, so a kit
    # without this clear could never be fixed once a store is protected. Cleared
    # at the single write choke point (covering the expand path too) and BEFORE
    # verification and the SR-066 timestamp stamp, so both act on a writable
    # file. A no-op until the write side lands; it also stops a source file that
    # was itself read-only at backup time restoring read-only, which WP10 ruled
    # out of contract.
    try {
        $written = Get-Item -LiteralPath $DestFull -Force -ErrorAction Stop
        if ($written.IsReadOnly) { $written.IsReadOnly = $false }
    } catch {
        # Non-fatal: the bytes are what matter, and the verification below still
        # has the final say on whether this row restored.
        Write-Verbose "Could not clear the read-only attribute on '$DestFull': $($_.Exception.Message)"
    }
    if (-not $Row.xxH2Hash -or '' -eq "$($Row.Length)") {
        return [pscustomobject]@{ Outcome = 'ok'; Cause = $null; Detail = $null; Got = $null }
    }
    try {
        $gotLen  = (Get-Item -LiteralPath $DestFull -Force).Length
        $gotHash = if ($gotLen -eq [long]$Row.Length) { Get-FileXxHash -FilePath $DestFull } else { '(not hashed)' }
    } catch {
        return [pscustomobject]@{ Outcome = 'hostfail'; Cause = 'CandidateError'
            Detail = "Restored file '$DestFull' could not be read back for verification: $($_.Exception.Message)"; Got = $null }
    }
    if ($gotLen -eq [long]$Row.Length -and $gotHash -eq $Row.xxH2Hash) {
        return [pscustomobject]@{ Outcome = 'ok'; Cause = $null; Detail = $null; Got = $null }
    }
    Remove-Item -LiteralPath $DestFull -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Outcome = 'mismatch'; Cause = 'ContentMismatch'; Detail = $null; Got = "$gotHash/$gotLen" }
}

function Set-RestoredLastWriteTime {
    <#
    .SYNOPSIS
        Stamps a restored file with its OWN row's LastWriteTimeStr (SR-066).

    .DESCRIPTION
        Under dedup every row sharing one pool object used to restore with the
        timestamp of whichever file created that object, because the mtime rode
        along on the copy instead of being applied from the index. The manifest
        has always carried each row's own LastWriteTimeStr correctly; this is
        the restorer finally applying it.

        Called only AFTER the SR-056 (hash,length) verification has passed, so a
        file that was deleted and re-recovered never keeps a stamp from the
        attempt that failed. Never fatal: the bytes are already correct and
        verified by the time this runs, so a blank or unparseable cell warns and
        the row still counts as restored. ReadOnly does not block it:
        SetLastWriteTime needs FILE_WRITE_ATTRIBUTES, which a read-only file
        grants.

    .PARAMETER DestFull
        The restored file, already written and verified.

    .PARAMETER Row
        The manifest row it was restored from.

    .PARAMETER Rel
        The row's RelativePath, for the warning message.
    #>
    # Implements: SR-066, LLR-066
    param(
        [Parameter(Mandatory)][string]$DestFull,
        [Parameter(Mandatory)][object]$Row,
        [Parameter(Mandatory)][string]$Rel
    )
    $stamp = "$($Row.LastWriteTimeStr)"
    if ([string]::IsNullOrWhiteSpace($stamp)) { return }
    try {
        [System.IO.File]::SetLastWriteTime($DestFull, (ConvertFrom-ManifestDateString $stamp))
    } catch {
        Add-ReconstructLog "WARN: could not stamp LastWriteTime on '$Rel' from '$stamp': $($_.Exception.Message) (content is correct and verified)."
    }
}

function Restore-DirectorySidecar {
    <#
    .SYNOPSIS
        Recreates empty directories and re-applies folder attributes from the
        DIRECTORIES.csv sidecar (SR-065).

    .DESCRIPTION
        The manifest has one row per FILE, so before this an empty directory was
        never recreated and a Hidden or System FOLDER came back ordinary. The
        sidecar carries one row per directory that is empty or carries a
        recorded attribute bit.

        Runs LAST, after every file is written and verified, for two reasons:
        a directory must not be given its attributes while its contents are
        still being created, and the deepest-first ordering below only makes
        sense once the tree exists.

        ADVISORY (SR-065): the sidecar is not witnessed and nothing here can
        fail the restore. An absent, unreadable or malformed sidecar leaves
        exactly the pre-SR-065 behaviour, which is why a store written by an
        older engine still restores identically. The contract is bytes at
        paths; this is fidelity on top of it.

    .PARAMETER AuthorityFolder
        The folder whose manifest was the restore authority - its sidecar is the
        one that describes this point in time.

    .PARAMETER TargetRoot
        The restore target. Rows escaping it are refused, as manifest rows are.
    #>
    # Implements: SR-065, LLR-065
    param(
        [Parameter(Mandatory)][string]$AuthorityFolder,
        [Parameter(Mandatory)][string]$TargetRoot
    )
    $sidecar = Join-Path $AuthorityFolder $Def.DirectorySidecarName
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { return }

    $rows = $null
    try { $rows = @(Import-Csv -LiteralPath $sidecar) } catch {
        Add-ReconstructLog "WARN: could not read the directory sidecar '$sidecar': $($_.Exception.Message). Empty directories and folder attributes were not applied."
        return
    }
    $rows = @($rows | Where-Object { $_.PSObject.Properties.Name -contains 'RelativePath' -and $_.RelativePath })
    if ($rows.Count -eq 0) { return }

    # Create parents before children; apply attributes deepest-first so a
    # directory is never given its bits while descendants are still appearing.
    $planned = New-Object System.Collections.Generic.List[object]
    foreach ($row in ($rows | Sort-Object { "$($_.RelativePath)".Length })) {
        $rel  = "$($row.RelativePath)"
        $full = Join-Path $TargetRoot (ConvertTo-LocalRelativePath $rel)
        if (-not (Test-PathIsInside -Child $full -Parent $TargetRoot)) {
            Add-ReconstructLog "WARN: directory row '$rel' escapes the target root (path traversal); refusing."
            continue
        }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) {
            try { New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop | Out-Null } catch {
                Add-ReconstructLog "WARN: could not create directory '$rel': $($_.Exception.Message)."
                continue
            }
        }
        $planned.Add([pscustomobject]@{ Rel = $rel; Full = $full; Token = "$($row.Attributes)" })
    }

    $applied = 0
    foreach ($item in ($planned | Sort-Object { $_.Rel.Length } -Descending)) {
        if ([string]::IsNullOrWhiteSpace($item.Token)) { continue }
        try {
            $dir = Get-Item -LiteralPath $item.Full -Force
            $dir.Attributes = ConvertTo-DirectoryAttributeFlag -Token $item.Token
            $applied++
        } catch {
            Add-ReconstructLog "WARN: could not apply attributes '$($item.Token)' to directory '$($item.Rel)': $($_.Exception.Message)."
        }
    }
    Add-ReconstructLog "Directory sidecar applied: $($planned.Count) directory row(s), $applied with attributes."
}

foreach ($rel in $main.Keys) {
    $row     = $main[$rel]
    $destFull = Join-Path $TargetRoot (ConvertTo-LocalRelativePath $rel)
    if (-not (Test-PathIsInside -Child $destFull -Parent $TargetRoot)) {
        Add-Unrestored -RelativePath $rel -Cause 'PathTraversal' `
            -Detail "'$rel' escapes the target root (path traversal); refusing."
        continue
    }
    $destDir  = [System.IO.Path]::GetDirectoryName($destFull)
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    # Own DataPath, else the name index, else the content scan (kit revision
    # 14). A non-blank DataPath is a locator HINT, not the content authority:
    # snapshot manifests are written once (R6), so a DataPath can name an
    # object that has since moved to another pool folder; its name still
    # carries the row's (hash, length), which is what the index looks up.
    $source = Resolve-RowDataSource -Row $row -Rel $rel
    if (-not $source.Path) {
        Add-Unrestored -RelativePath $rel -Cause $source.Cause -Detail $source.Detail
        continue
    }
    $srcFull = $source.Path
    # The PROVEN form of a content-scanned file, which outranks the row's
    # Compressed column for that row (SR-050). $null for an own-DataPath or
    # name-index source, whose form the bytes decide below (SR-068).
    $locatedForm = $source.LocatedForm

    # SR-050 proved the form for a hash-recovered row. SR-068 (kit revision 8)
    # extends that to a row resolved through its OWN DataPath, which was the
    # last decision either restorer took on the Compressed column's word: the
    # column is a claim about bytes stored apart from them, and D-1 is what that
    # costs. Get-StoredObjectForm reads the bytes and, for an archive-shaped
    # object, asks whether they already reproduce the row - which is the only
    # thing that separates an archive WE created from the user's own
    # already-compressed file stored raw (SR-004 never re-compresses those).
    $needsExpand = if ($null -ne $locatedForm) {
        $locatedForm -eq 'Archive'
    } else {
        (Get-StoredObjectForm -Path $srcFull -ExpectedHash $row.xxH2Hash -ExpectedLength $row.Length) -eq 'Archive'
    }

    # SR-056 (kit revision 6): EVERY restored row — expanded or copied, own
    # DataPath or hash-recovered — is verified against (Length, xxH2Hash) after
    # the write; on a mismatch the bad file is deleted, the (hash,length) pool
    # recovery is attempted at most ONCE, and the result verified again. A row
    # that still cannot be verified is counted into the SR-029 accounting as
    # ContentMismatch (content class, exit 1) — never reported as success.
    $r = Restore-OneRow -SrcFull $srcFull -DestFull $destFull -NeedsExpand $needsExpand -Row $row
    if ($r.Outcome -eq 'hostfail') {
        Add-Unrestored -RelativePath $rel -Cause $r.Cause -Detail $r.Detail
        continue
    }
    if ($r.Outcome -eq 'mismatch') {
        "$(Get-Date -Format 'O') - WARN: [ContentMismatch] '$rel' — restored bytes do not match the manifest (expected $($row.xxH2Hash)/$($row.Length), got $($r.Got)); attempting pool recovery." |
            Out-File -LiteralPath $logPath -Append
        if ($null -ne $locatedForm) {
            # This row was ALREADY resolved through the pool locator, which
            # hashes every candidate before returning it: the pool provably
            # holds the bytes and the WRITE is what failed — a host condition
            # (exit 4), not data loss; re-running the same search cannot
            # produce a different source (2026-08-24 review, major 3).
            Add-Unrestored -RelativePath $rel -Cause 'WriteMismatch' `
                -Detail "the pool source '$srcFull' was PROVEN by hash, but the written destination disagrees (got $($r.Got)) — a destination/write problem on this host."
            continue
        }
        $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders -SevenZipPath $SevenZipPath
        if ($found.Cause -eq 'Found') {
            "$(Get-Date -Format 'O') - Hash-recovered $rel from '$($found.Path)' after a verify mismatch (form: $($found.Form))" |
                Out-File -LiteralPath $logPath -Append
            $r2 = Restore-OneRow -SrcFull $found.Path -DestFull $destFull -NeedsExpand ($found.Form -eq 'Archive') -Row $row
            if ($r2.Outcome -eq 'hostfail') {
                Add-Unrestored -RelativePath $rel -Cause $r2.Cause -Detail $r2.Detail
            } elseif ($r2.Outcome -eq 'mismatch') {
                # The recovery source was hash-proven by the locator, so this
                # second mismatch is a write problem on this host (exit 4) —
                # the backup demonstrably still holds the bytes.
                Add-Unrestored -RelativePath $rel -Cause 'WriteMismatch' `
                    -Detail "the pool copy '$($found.Path)' was PROVEN by hash, but the written destination disagrees (got $($r2.Got)) — a destination/write problem on this host."
            } else {
                Set-RestoredLastWriteTime -DestFull $destFull -Row $row -Rel $rel
            }
            continue
        }
        if ($found.Cause -eq 'ContentMissing') {
            Add-Unrestored -RelativePath $rel -Cause 'ContentMismatch' `
                -Detail "the bytes at '$srcFull' do not reproduce (hash=$($row.xxH2Hash), length=$($row.Length)), and no pool copy does. $($found.Detail)"
        } else {
            # DependencyMissing / StorageUnreadable: the pool may still hold a
            # good copy this host could not check — stay host class (SR-040).
            Add-Unrestored -RelativePath $rel -Cause $found.Cause -Detail $found.Detail
        }
        continue
    }

    Set-RestoredLastWriteTime -DestFull $destFull -Row $row -Rel $rel
}

Restore-DirectorySidecar -AuthorityFolder $authorityFolder -TargetRoot $TargetRoot

if ($unrestored.Count -gt 0) {
    # Classify: content-class rows mean the bytes are gone (exit 1); host-class
    # rows mean this machine is the problem (exit 4) and a wrapper should retry.
    # 4 outranks 1 because it is the actionable one (SR-040 precedence).
    $hostCauses = @('DependencyMissing', 'StorageUnreadable', 'CandidateError', 'WriteMismatch')
    $hostRows    = @($unrestored | Where-Object { $_.Cause -in $hostCauses })
    $contentRows = @($unrestored | Where-Object { $_.Cause -notin $hostCauses })
    $code = if ($hostRows.Count -gt 0) { $EXIT_HOST } else { $EXIT_CONTENT }
    $names = ($unrestored | ForEach-Object { $_.RelativePath }) -join ', '
    Exit-Reconstruct -Code $code -Message ("Reconstruction INCOMPLETE: $($unrestored.Count) file(s) could not be restored " +
        "($($contentRows.Count) content-missing, $($hostRows.Count) host): $names. See log: $logPath")
}
"$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath $logPath -Append
Write-Host "Reconstruction finished. See log: $logPath"
Wait-BeforeClosing -Code $EXIT_COMPLETE
if ($ExitCode) { exit $EXIT_COMPLETE }
