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
           unrecognizable manifest, target inside the backup, missing required
           tool, insufficient capacity).
        3  Manifest-witness verification failed — the index is untrustworthy;
           NO file is written to the target (SR-039).
        4  Incomplete, HOST — rows failed for reasons on this machine, not in
           the backup (unreadable search folder, 7-Zip unavailable for an
           archive candidate, extraction/copy I/O error). Retry after fixing
           the host.

    Precedence when several apply: 2 > 3 > 4 > 1.

    Delivery: by default every failure is a TERMINATING ERROR (throw), which is
    what in-process callers and the test harness rely on. Pass -ExitCode (as
    RECONSTRUCT.bat does) to exit the process with the table's code instead.
#>

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
    if ($logPath) {
        "$(Get-Date -Format 'O') - ERROR: $Message" | Out-File -LiteralPath $logPath -Append
    }
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

    .OUTPUTS
        [pscustomobject] Path / Cause / Detail, where Cause is one of:
          Found              — Path holds the data source.
          ContentMissing     — the pool was searched cleanly; the bytes are gone.
          DependencyMissing  — an archive candidate was met with no usable 7-Zip.
          StorageUnreadable  — a search folder is absent or could not be read.
          CandidateError     — a candidate failed to extract (I/O or archive error).

        The three non-ContentMissing causes are HOST problems (exit 4): the
        backup may still hold the bytes, so a wrapper should retry rather than
        report data loss. They are only reported when the scan found nothing.
    #>
    # Implements: SR-040, LLR-040
    param([string]$Hash, [long]$Length, [string[]]$SearchFolders, [string]$SevenZipPath)

    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    # Host-class problems met along the way, reported only if nothing matched — a
    # successful recovery must never be downgraded by an unrelated bad folder.
    $hostIssues = New-Object System.Collections.Generic.List[pscustomobject]

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
                    $hostIssues.Add([pscustomobject]@{ Cause = 'DependencyMissing'
                        Detail = "An archive candidate '$($f.FullName)' needs 7-Zip, which was not found at '$SevenZipPath'." })
                    continue
                }
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $f.FullName -DestinationFile $tmp
                    if ((Get-Item -LiteralPath $tmp).Length -eq $Length -and (Get-FileXxHash -FilePath $tmp) -eq $Hash) {
                        return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Detail = '' }
                    }
                } catch {
                    $hostIssues.Add([pscustomobject]@{ Cause = 'CandidateError'
                        Detail = "Archive candidate '$($f.FullName)' could not be expanded: $($_.Exception.Message)" })
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            } elseif ($f.Length -eq $Length) {
                try {
                    if ((Get-FileXxHash -FilePath $f.FullName) -eq $Hash) {
                        return [pscustomobject]@{ Path = $f.FullName; Cause = 'Found'; Detail = '' }
                    }
                } catch {
                    $hostIssues.Add([pscustomobject]@{ Cause = 'CandidateError'
                        Detail = "Candidate '$($f.FullName)' could not be read: $($_.Exception.Message)" })
                }
            }
        }
    }

    # A missing dependency outranks the others: it is the one with a precise
    # remediation ("install 7-Zip"), so it is what the operator should be told.
    foreach ($preferred in 'DependencyMissing', 'StorageUnreadable', 'CandidateError') {
        $issue = $hostIssues | Where-Object { $_.Cause -eq $preferred } | Select-Object -First 1
        if ($issue) {
            return [pscustomobject]@{ Path = $null; Cause = $issue.Cause; Detail = $issue.Detail }
        }
    }
    return [pscustomobject]@{
        Path   = $null
        Cause  = 'ContentMissing'
        Detail = "No file with (hash=$Hash, length=$Length) survives anywhere in the data pool."
    }
}

# ---- Resolve backup/change roots ----
$isChangeFolder = $folderName -match $ChangeFolderPattern

# Sidecar written by New-ReconstructScript takes precedence over auto-detection (B10).
$sidecar = Join-Path $here 'RECONSTRUCT.paths.json'
if (-not $BackupRootOverride -and (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
    try {
        $paths = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json
        if (-not $BackupRootOverride) { $BackupRootOverride = $paths.BackupRoot }
        if (-not $ChangeRootOverride) { $ChangeRootOverride = $paths.ChangeRoot }
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

if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$logPath = Join-Path $TargetRoot $ReconstructLogName
"$(Get-Date -Format 'O') - Reconstruction starting" | Out-File -LiteralPath $logPath -Encoding UTF8

function Read-RawManifest {
    <#
    .SYNOPSIS
        Reads the restore origin's MANIFEST.csv after proving it is trustworthy:
        it exists, its header is a FileBackup manifest header, and (when a
        witness sidecar is present) its bytes/rows/digest match that witness.

    .DESCRIPTION
        Runs BEFORE the capacity pre-check and before any file is written, so a
        damaged index refuses the restore rather than "succeeding" against a
        shrunken job (SR-039). Three outcomes:

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
                "$(Get-Date -Format 'O') - WARN: manifest witness declares format version $($verdict.Version) (newer than this build understands); verified the known fields only." |
                    Out-File -LiteralPath $logPath -Append
            }
            "$(Get-Date -Format 'O') - $($verdict.Detail)" | Out-File -LiteralPath $logPath -Append
        }
        'Absent' {
            if ($RequireWitness) {
                Exit-Reconstruct -Code $EXIT_WITNESS -Message "No manifest witness beside '$path' and -RequireWitness was given: the index cannot be verified."
            }
            "$(Get-Date -Format 'O') - WARN: $($verdict.Detail) Restoring against an UNVERIFIED index (backup predates the witness contract)." |
                Out-File -LiteralPath $logPath -Append
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
$main = @{}
$haveSnapshotTree = $changeRoot -and (Test-Path -LiteralPath $changeRoot -PathType Container)
$authorityFolder  = if ($isChangeFolder) { $here } else { $backupRoot }

foreach ($row in (Read-RawManifest -Folder $authorityFolder)) {
    if (-not $row.RelativePath) { continue }
    $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $authorityFolder -Force
    $main[$row.RelativePath] = $row
}

# ---- Capacity pre-check (B11: skip compressed rows; lengths are uncompressed) ----
$totalBytes = 0L
$anyCompressed = $false
foreach ($rel in $main.Keys) {
    $row = $main[$rel]
    if ($row.Compressed -eq 'Yes') { $anyCompressed = $true; continue }
    if ($row.Length) { $totalBytes += [long]$row.Length }
}
# Resolve the drive separately so a resolution failure is non-fatal, but an
# actual insufficient-space verdict still aborts (previously the throw was
# swallowed by the same catch that handled drive resolution — SR-023 / B11).
$drive = $null
try {
    $drive = Get-PSDrive -Name (Split-Path -Qualifier $TargetRoot).TrimEnd(':')
} catch {
    Write-Verbose "Capacity pre-check skipped (could not resolve target drive): $($_.Exception.Message)"
}
if ($drive) {
    if ($drive.Free -lt $totalBytes) {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message "Not enough free space on target drive. Required (uncompressed rows only): $totalBytes, Free: $($drive.Free)"
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

foreach ($rel in $main.Keys) {
    $row     = $main[$rel]
    $destFull = Join-Path $TargetRoot $rel
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

    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        if ($row.xxH2Hash -and $row.Length) {
            "$(Get-Date -Format 'O') - No datapath for $rel; attempting hash scan..." | Out-File -LiteralPath $logPath -Append
            $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders -SevenZipPath $SevenZipPath
            if ($found.Cause -eq 'Found') {
                "$(Get-Date -Format 'O') - Hash-recovered $rel from '$($found.Path)'" | Out-File -LiteralPath $logPath -Append
                $srcFull = $found.Path
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
        $srcFull = Join-Path $srcFolder $dataPath
    }

    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) {
        Add-Unrestored -RelativePath $rel -Cause 'MissingDataFile' `
            -Detail "The row's data file '$dataPath' is not present in the restore origin."
        continue
    }

    if ($row.Compressed -eq 'Yes') {
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
