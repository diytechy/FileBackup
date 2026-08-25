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

    When a row's DataPath is blank/missing, the file is recovered by scanning the
    search folders for a file whose length and xxHash128 match.

.NOTES
    Requires PowerShell 7+ (pwsh). Logs to RECONSTRUCT.log in the target root.
    Fails loudly (terminating error / non-zero exit) when any manifest row
    cannot be restored, after restoring everything recoverable (SR-029).

    Restore exit codes (SR-040 — the normative table lives in README
    "Restore exit codes"; reconstruct.sh returns the same numbers):

        0  Complete — every manifest row restored.
        1  Incomplete, CONTENT — the remaining rows' bytes are not in the pool.
        2  Precondition / usage — nothing attempted (bad arguments, missing or
           unrecognizable manifest, target inside the backup, an unusable target
           path, missing required tool, insufficient capacity). Any terminating
           error this script did not classify lands here too: nothing was
           attempted, so it must not be reported as data loss (code 1).
        3  Manifest-witness verification failed — the index is untrustworthy;
           NO file is written to the target (SR-039). Header/witness
           verification runs before the target folder and the log are created,
           so those refusals (and code 3 always) leave the target exactly as
           they found it — as reconstruct.sh does. The later code-2 preflights
           (capacity, 7-Zip) run after target+log creation, identically in
           both restorers.
        4  Incomplete, HOST — rows failed for reasons on this machine, not in
           the backup (unreadable search folder or candidate, 7-Zip unavailable
           for an archive candidate, extraction/copy I/O error on the row's OWN
           file). Retry after fixing the host. Since kit revision 6 a POOL
           candidate that fails to expand is data damage (ContentMissing, 1),
           not a host problem — only the restore loop raises CandidateError.

    Precedence when several apply: 2 > 3 > 4 > 1.

    Delivery: by default every failure is a TERMINATING ERROR (throw), which is
    what in-process callers and the test harness rely on. Pass -ExitCode (as
    RECONSTRUCT.bat does) to exit the process with the table's code instead.
#>

# KitRevision: 5
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
# 7-Zip. Restoring a snapshot with its OWN older kit still carries the
# defects fixed after it.

param(
    [string]$TargetRoot,
    [string]$BackupRootOverride,
    [string]$ChangeRootOverride,
    [string]$SevenZipPath,
    # Report the SR-040 exit code as a process exit status instead of throwing.
    # Only process entry points pass this; in-process callers keep the throw.
    [switch]$ExitCode,
    # Strict mode (SR-039): a MISSING manifest witness becomes an abort instead
    # of an 'unverified index' warning. Off by default so backups written before
    # the witness contract still restore.
    [switch]$RequireWitness
)

$ErrorActionPreference = 'Stop'
$here = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)

# Exit-code constants (SR-040). Named so the call sites read as classifications.
$EXIT_COMPLETE    = 0
$EXIT_CONTENT     = 1
$EXIT_PRECONDITION= 2
$EXIT_WITNESS     = 3
$EXIT_HOST        = 4

$logPath = $null

# Log lines produced BEFORE the target (and therefore RECONSTRUCT.log) exists.
# The index is verified before anything is written to the target (SR-039), so
# its findings are held here and flushed once the log is opened.
$pendingLog = New-Object System.Collections.Generic.List[string]

function Add-ReconstructLog {
    <#
    .SYNOPSIS
        Appends one timestamped line to RECONSTRUCT.log, buffering it when the
        log does not exist yet (verification runs before the target is created).
    #>
    # Implements: SR-039, LLR-039
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
    # A pre-mutation refusal (codes 2 and 3) happens before the target — and its
    # log — exists, on purpose (SR-039): the message goes to the console and the
    # thrown error instead of a log file we must not create.
    if ($logPath) {
        "$(Get-Date -Format 'O') - ERROR: $Message" | Out-File -LiteralPath $logPath -Append
    }
    $script:classified = $true
    if ($ExitCode) {
        [Console]::Error.WriteLine("reconstruct: $Message")
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

    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
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
        $candidates = Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue -ErrorVariable enumErrors |
            Where-Object {
                -not ($_.Name -match $skip -and
                      [System.IO.Path]::GetDirectoryName($_.FullName) -eq $folderNorm)
            }
        if ($enumErrors) {
            $hostIssues.Add([pscustomobject]@{ Cause = 'StorageUnreadable'
                Detail = "Search folder '$folder' could not be fully read: $($enumErrors[0].Exception.Message)" })
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
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
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
                    # Data damage, not a host condition — see $failedExpand above.
                    $failedExpand.Add("'$($f.FullName)': $expandError")
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
            " (data damage, not a host problem): $($failedExpand[0])."
    }
    return [pscustomobject]@{
        Path   = $null
        Cause  = 'ContentMissing'
        Form   = $null
        Detail = $detail
    }
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
} else {
    $backupRoot = $here
    $changeRoot = $null     # B10: no assumed CHANGES sibling; only used if known.
}

if ($BackupRootOverride) { $backupRoot = $BackupRootOverride }
if ($ChangeRootOverride) { $changeRoot = $ChangeRootOverride }

if (-not $TargetRoot) {
    $TargetRoot = Read-Host 'Enter target folder to reconstruct into'
}

# Reject a target inside the backup/change root (SR-009). Compare normalized full
# paths with a trailing separator so a prefix-sharing sibling (e.g. 'bkp' vs
# 'bkp-restore') is allowed and bracket/wildcard chars are treated literally —
# '-like' would mishandle both.
function Test-PathIsInside {
    param([string]$Child, [string]$Parent)
    $c = [System.IO.Path]::GetFullPath($Child).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $p = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
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
        Reads the restore origin's MANIFEST.csv after proving it is trustworthy:
        it exists, its header is a FileBackup manifest header, and (when a
        witness sidecar is present) its bytes/rows/digest match that witness.

    .DESCRIPTION
        Runs BEFORE the target folder, the log, and the capacity pre-check exist,
        so a damaged index refuses the restore rather than "succeeding" against a
        shrunken job (SR-039) and leaves the target byte-for-byte untouched — not
        even a RECONSTRUCT.log — exactly as reconstruct.sh does. Its own log
        lines are therefore buffered (Add-ReconstructLog) and flushed once the
        log exists; refusals go to the console and the thrown error. Three
        outcomes:

          * header unrecognizable  -> exit 2 (this is not a manifest at all —
            the legacy corrupt-file guard, matching reconstruct.sh's wording)
          * witness disagrees / unparseable, or absent under -RequireWitness
            -> exit 3
          * witness absent          -> WARN 'unverified index' and continue, so
            backups written before the witness contract still restore.

    .PARAMETER Folder
        The restore origin (backup root or Snapshot_<date> folder).
    #>
    # Implements: SR-039, SR-040, LLR-039, LLR-040
    param([string]$Folder)

    $path = Join-Path $Folder $DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "MANIFEST.csv not found in restore origin '$Folder'. The backup folder is incomplete."
    }

    # Header-shape guard (mirrors reconstruct.sh): a legitimately empty backup
    # still carries the full header row, so this only rejects a corrupt or
    # wrong file — including a legacy one that has no witness to check.
    $header = ("$(Get-Content -LiteralPath $path -TotalCount 1)").TrimStart([char]0xFEFF)
    if ($header -notmatch 'RelativePath' -or $header -notmatch 'xxH2Hash') {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "'$path' is not a FileBackup manifest (unexpected header). Corrupt or wrong file."
    }

    $verdict = Test-ManifestWitness -FolderPath $Folder
    switch ($verdict.Status) {
        'Verified' {
            if ($verdict.VersionUnknown) {
                Add-ReconstructLog "WARN: manifest witness declares format version $($verdict.Version) (newer than this build understands); verified the known fields only."
            }
            if ($verdict.Warning) {
                # Rows-only divergence: the digest says the bytes are right, so
                # this is a counting-semantics difference, not damage (SR-039).
                Add-ReconstructLog "WARN: $($verdict.Warning)"
                Write-Warning $verdict.Warning
            }
            Add-ReconstructLog $verdict.Detail
        }
        'Absent' {
            if ($RequireWitness) {
                Exit-Reconstruct -Code $EXIT_WITNESS -Message "No manifest witness beside '$path' and -RequireWitness was given: the index cannot be verified."
            }
            Add-ReconstructLog "WARN: $($verdict.Detail) Restoring against an UNVERIFIED index (backup predates the witness contract)."
            Write-Warning "Restoring against an unverified index: $($verdict.Detail)"
        }
        default {
            Exit-Reconstruct -Code $EXIT_WITNESS -Message "Manifest witness verification failed for '$path'. $($verdict.Detail) The index is damaged; nothing was restored."
        }
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

# ---- Create the target and open the log (first mutation of this run) ----
# Everything above refuses with 2 or 3 without writing a single byte into the
# target (SR-039). Failures here are PRECONDITION failures: nothing has been
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
$searchFolders = New-Object System.Collections.Generic.List[string]
if ($haveSnapshotTree) {
    Get-ChildItem -LiteralPath $changeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $ChangeFolderPattern } |
        Sort-Object Name -Descending |
        ForEach-Object { $searchFolders.Add($_.FullName) }
}
$searchFolders.Add($backupRoot)

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

    $srcFolder = $row.SourceFolder
    $dataPath  = $row.DataPath
    # The PROVEN form of a hash-recovered file, which outranks the row's
    # Compressed column for that row (SR-050). Stays $null for a non-blank
    # DataPath, whose Compressed does describe its own folder's file.
    $locatedForm = $null

    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        if ($row.xxH2Hash -and $row.Length) {
            "$(Get-Date -Format 'O') - No datapath for $rel; attempting hash scan..." | Out-File -LiteralPath $logPath -Append
            $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders -SevenZipPath $SevenZipPath
            if ($found.Cause -eq 'Found') {
                "$(Get-Date -Format 'O') - Hash-recovered $rel from '$($found.Path)' (form: $($found.Form))" | Out-File -LiteralPath $logPath -Append
                $srcFull     = $found.Path
                $locatedForm = $found.Form
            } else {
                # One message per CAUSE, not one warning for all four (SR-040).
                Add-Unrestored -RelativePath $rel -Cause $found.Cause -Detail $found.Detail
                continue
            }
        } else {
            Add-Unrestored -RelativePath $rel -Cause 'NoDataPathOrHash' `
                -Detail "The manifest row carries neither a DataPath nor a (hash,length) to recover by."
            continue
        }
    } else {
        $srcFull = Join-Path $srcFolder (ConvertTo-LocalRelativePath $dataPath)
    }

    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) {
        # A non-blank DataPath is a locator HINT, not the content authority: a
        # run killed between Optimize-ChangeFolders' duplicate deletion and its
        # manifest rewrite leaves rows naming deleted files while the keeper
        # copy still sits in the pool. Try (hash,length) recovery — the same
        # machinery blank rows use — before declaring the content missing.
        $recovered = $false
        if ($row.xxH2Hash -and $row.Length) {
            "$(Get-Date -Format 'O') - Data file '$dataPath' missing for $rel; attempting hash scan..." | Out-File -LiteralPath $logPath -Append
            $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders -SevenZipPath $SevenZipPath
            if ($found.Cause -eq 'Found') {
                "$(Get-Date -Format 'O') - Hash-recovered $rel from '$($found.Path)' (form: $($found.Form))" | Out-File -LiteralPath $logPath -Append
                $srcFull     = $found.Path
                $locatedForm = $found.Form
                $recovered   = $true
            }
        }
        if (-not $recovered) {
            Add-Unrestored -RelativePath $rel -Cause 'MissingDataFile' `
                -Detail "The row's data file '$dataPath' is not present in the restore origin, and no pool file matches its (hash,length)."
            continue
        }
    }

    # SR-050: a hash-recovered file is decided by the form the locator PROVED;
    # only a row resolved through its own DataPath is decided by its Compressed.
    $needsExpand = if ($null -ne $locatedForm) { $locatedForm -eq 'Archive' } else { $row.Compressed -eq 'Yes' }

    if ($needsExpand) {
        try {
            Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $srcFull -DestinationFile $destFull
        } catch {
            Add-Unrestored -RelativePath $rel -Cause 'CandidateError' `
                -Detail "7-Zip extraction failed from '$srcFull': $($_.Exception.Message)"
            continue
        }
    } else {
        try {
            Copy-Item -LiteralPath $srcFull -Destination $destFull -Force
        } catch {
            Add-Unrestored -RelativePath $rel -Cause 'CandidateError' `
                -Detail "Copy from '$srcFull' failed: $($_.Exception.Message)"
            continue
        }
    }
}

if ($unrestored.Count -gt 0) {
    # Classify: content-class rows mean the bytes are gone (exit 1); host-class
    # rows mean this machine is the problem (exit 4) and a wrapper should retry.
    # 4 outranks 1 because it is the actionable one (SR-040 precedence).
    $hostCauses = @('DependencyMissing', 'StorageUnreadable', 'CandidateError')
    $hostRows    = @($unrestored | Where-Object { $_.Cause -in $hostCauses })
    $contentRows = @($unrestored | Where-Object { $_.Cause -notin $hostCauses })
    $code = if ($hostRows.Count -gt 0) { $EXIT_HOST } else { $EXIT_CONTENT }
    $names = ($unrestored | ForEach-Object { $_.RelativePath }) -join ', '
    Exit-Reconstruct -Code $code -Message ("Reconstruction INCOMPLETE: $($unrestored.Count) file(s) could not be restored " +
        "($($contentRows.Count) content-missing, $($hostRows.Count) host): $names. See log: $logPath")
}
"$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath $logPath -Append
Write-Host "Reconstruction finished. See log: $logPath"
if ($ExitCode) { exit $EXIT_COMPLETE }
