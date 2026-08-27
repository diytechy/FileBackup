<#
.SYNOPSIS
    FileBackup engine — everything needed to *produce* a backup.

.DESCRIPTION
    Depends on FileBackup.Common.psm1 (restore-safe primitives). This module is
    NOT deployed into backup folders; only Common is. It contains the source-walk,
    diff, copy/dedup, storage-layout migration, change-folder finalization, the
    reconstruct-script generator, and the per-set orchestrator Invoke-BackupSet.

    Bug fixes folded in (see CHANGELOG / README "Known issues"):
        B2  Test-HashRecalcDue treats DateTime.MinValue as "never run".
        B3  Last-hash-run is persisted in a state file, not inferred from mtimes.
        B4  The hash-recalc decision now actually drives a forced rehash.
        B6  Only the *root* MANIFEST.csv is skipped; nested ones are real files.
        B7  Storage migration copies-new + writes manifest before deleting old.
        B8  Hash-group lookups are wrapped with @() before indexing.
        B9  Removed-file eviction refcounts shared data files first.
#>

# Import Common without -Force so we don't disturb an outer-scope import that the
# entry-point script (FileBackup.ps1) relies on for New-Logger et al.
if (-not (Get-Module -Name 'FileBackup.Common')) {
    Import-Module (Join-Path $PSScriptRoot 'FileBackup.Common.psm1')
}
$script:Def = Get-FileBackupDefaults

# region Infrastructure-file filtering

function Test-IsInfrastructureFile {
    <#
    .SYNOPSIS
        True when a file is a FileBackup-managed artifact sitting at the *root* of
        a backup/source tree (manifest, reconstruct scripts, bundled module/DLL,
        state file). Nested user files that happen to share those names are NOT
        treated as infrastructure — that is the B6 fix.
    #>
    # Implements: SR-022, SR-038, LLR-022, LLR-038
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FullPath
    )
    $rel = $FullPath.Substring((Resolve-Path -LiteralPath $Root).Path.Length).TrimStart('\','/')
    # Only root-level (no directory separator) files can be infrastructure.
    if ($rel -match '[\\/]') { return $false }
    $infra = @(
        $script:Def.DatabaseFilename,
        $script:Def.ReconstructPs1Name,
        $script:Def.ReconstructBatName,
        $script:Def.ReconstructShName,
        $script:Def.ReconstructLogName,
        $script:Def.CommonModuleName,
        'System.IO.Hashing.dll',
        'FileBackupState.json',
        'backup.log',
        # New-ReconstructScript's path sidecar — omitting it produced false
        # orphan/not-in-DB WARNs every run (SR-022, 2026-07-02 review).
        'RECONSTRUCT.paths.json',
        # Write-Manifest's witness sidecar — omitting it would produce false
        # orphan/not-in-DB WARNs every run (SR-038, SR-022). Root-level only:
        # a nested user file of the same name is still data (B6).
        $script:Def.WitnessFilename,
        # ...and its publish-by-rename staging file: a crash between
        # WriteAllText and Move-Item leaves this behind, and a leftover must not
        # be backed up as user data or warned about as an orphan (SR-038).
        "$($script:Def.WitnessFilename).tmp",
        # The directory sidecar (SR-065). Root-level only, like the rest: a
        # nested user file called DIRECTORIES.csv is data (B6).
        $script:Def.DirectorySidecarName
    )
    return ($infra -contains $rel)
}

function Test-PortableRelativePath {
    <#
    .SYNOPSIS
        Returns $null when every component of a relative path is a legal file
        name on BOTH Windows and Linux; otherwise a short reason naming the
        offending component and character (SR-055).

    .OUTPUTS
        [string] $null when portable, else the reason.
    #>
    # Implements: SR-055, LLR-055
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        # Test seam (WP8 review, minor 1): classify as a POSIX host would.
        # Defaults to the actual platform; lets the Windows unit suite assert
        # the Linux-only backslash-in-name arm instead of leaving it untested.
        [bool]$TreatAsPosix = (-not $IsWindows)
    )
    # On Windows both slashes separate; on Linux only '/' does — a '\' there is
    # part of the NAME, and means a path separator to the Windows restorer.
    # TYPED assignment on purpose (WP9 step 8b finding): an if-EXPRESSION
    # unrolls a [char[]] to object[], and String.Split then binds an overload
    # that never splits — every prior predicate was character- or
    # suffix-scoped, so the wrong (whole-path) component was invisible until
    # the first genuinely component-scoped rule below.
    [char[]]$separators = if ($TreatAsPosix) { '/' } else { '\', '/' }
    foreach ($component in $RelativePath.Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) {
        foreach ($ch in $component.ToCharArray()) {
            if ([int]$ch -lt 32) {
                return "name component '$component' contains a control character (0x$(([int]$ch).ToString('X2'))), which no Windows file name may carry"
            }
            if ($ch -in '<', '>', ':', '"', '|', '?', '*') {
                return "name component '$component' contains '$ch', which no Windows file name may carry"
            }
            if ($TreatAsPosix -and $ch -eq '\') {
                return "name component '$component' contains '\', which is a path separator on Windows"
            }
        }
        if ($component.EndsWith('.') -or $component.EndsWith(' ')) {
            return "name component '$component' ends with a dot or space, which Windows silently strips"
        }
        # WP9 step 8b (SR-055 amendment, ruled IN 2026-08-25): a component
        # whose stem — the text before the FIRST dot — is a Windows reserved
        # device name cannot be created on a Windows restore, with or without
        # an extension ('NUL.txt' is as unusable as 'NUL').
        $stem = $component.Split('.')[0]
        if ($stem -match '^(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            return "name component '$component' is a Windows reserved device name ('$stem'), which no Windows file may use"
        }
    }
    return $null
}

function Get-DataFile {
    <#
    .SYNOPSIS
        Enumerates real data files under a root, skipping root-level infrastructure.

    .DESCRIPTION
        With -EnumerationErrorOut, an unlistable directory (Deny ACE — the
        shape of 'System Volume Information' or another user's $RECYCLE.BIN,
        both now VISIBLE under -Force) is reported as a record instead of
        aborting the walk; the caller decides how loudly to fail (source walks
        mark the set failed, SR-057). Without it the walk stays strict — a
        pool walk that cannot read our own store must keep throwing.
    #>
    # Implements: SR-057, LLR-057
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [AllowNull()][System.Collections.Generic.List[object]]$EnumerationErrorOut
    )
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    # -Force (SR-057): hidden/dot files are data — without it they were never
    # backed up, and -Recurse skipped hidden DIRECTORIES entirely (D-4).
    if ($null -ne $EnumerationErrorOut) {
        $enumErr = $null
        $found = Get-ChildItem -LiteralPath $resolved -Recurse -File -Force `
            -ErrorAction SilentlyContinue -ErrorVariable enumErr |
            Where-Object { -not (Test-IsInfrastructureFile -Root $resolved -FullPath $_.FullName) }
        foreach ($e in @($enumErr)) {
            $EnumerationErrorOut.Add([pscustomobject]@{
                Path = "$($e.TargetObject)"; Message = $e.Exception.Message })
        }
        return $found
    }
    Get-ChildItem -LiteralPath $resolved -Recurse -File -Force |
        Where-Object { -not (Test-IsInfrastructureFile -Root $resolved -FullPath $_.FullName) }
}

# endregion

# region Backup state file (B3 + dated snapshots)

function Read-BackupState {
    <#
    .SYNOPSIS
        Reads FileBackupState.json, returning an empty state only when the file
        does not exist.
    .DESCRIPTION
        A malformed state file is a safety failure, not an absent first-run
        state. Callers use LastBackupRun to name the snapshot that preserves the
        current backup; silently treating corrupt JSON as empty can cause that
        staging snapshot to be discarded.
    #>
    # Implements: SR-011, SR-028, LLR-011, LLR-028
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupRoot)
    $statePath = Join-Path $BackupRoot 'FileBackupState.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return @{} }
    try {
        $obj = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
        return $h
    } catch {
        throw "Could not parse backup state '$statePath'. Refusing to continue because snapshot history cannot be dated safely. $($_.Exception.Message)"
    }
}

function Set-BackupStateField {
    # Merges a single field into FileBackupState.json (so LastHashRun and
    # LastBackupRun coexist instead of clobbering each other).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()]$Value
    )
    $state = Read-BackupState -BackupRoot $BackupRoot
    $state[$Name] = $Value
    $statePath = Join-Path $BackupRoot 'FileBackupState.json'
    # Publish by rename: a crash mid-write must not leave a torn JSON that
    # Read-BackupState refuses forever (the manifest witness gets the same
    # write-then-rename treatment).
    $tmpPath = "$statePath.tmp"
    $state | ConvertTo-Json | Set-Content -LiteralPath $tmpPath -Encoding UTF8
    Move-Item -LiteralPath $tmpPath -Destination $statePath -Force
}

function Get-LastHashRun {
    <#
    .SYNOPSIS
        Reads the persisted time of the last scheduled re-hash sweep
        ($null if one has never run).
    #>
    # Implements: SR-011, LLR-011
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupRoot)
    $v = (Read-BackupState -BackupRoot $BackupRoot)['LastHashRun']
    if ($v) { return [datetime]::Parse($v) }
    return $null
}

function Set-LastHashRun {
    <#
    .SYNOPSIS
        Persists the time of the completed re-hash sweep to FileBackupState.json.
    #>
    # Implements: SR-011, LLR-011
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [datetime]$When = (Get-Date)
    )
    Set-BackupStateField -BackupRoot $BackupRoot -Name 'LastHashRun' -Value $When.ToString('O')
}

function Get-LastBackupRun {
    <#
    .SYNOPSIS
        Reads the completion date of the most recent backup — it dates the *next*
        run's point-in-time snapshot. $null until the first backup has run.
    #>
    # Implements: SR-005, SR-028, LLR-005, LLR-028
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupRoot)
    $v = (Read-BackupState -BackupRoot $BackupRoot)['LastBackupRun']
    if ($v) { return [datetime]::Parse($v) }
    return $null
}

function Set-LastBackupRun {
    <#
    .SYNOPSIS
        Persists this run's completion date to FileBackupState.json
        (-When is the deterministic test seam).
    #>
    # Implements: SR-005, SR-028, LLR-005, LLR-028
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [datetime]$When = (Get-Date)
    )
    Set-BackupStateField -BackupRoot $BackupRoot -Name 'LastBackupRun' -Value $When.ToString('O')
}

# endregion

# region Dependency loading (7z, ffprobe, xxHash)

function Resolve-OptionalTool {
    # Implements: SR-020 (optional-dependency degradation), SR-016 (non-blocking).
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Path,
        [scriptblock]$InstallHint,
        [switch]$NonInteractive,
        [switch]$Required
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($InstallHint) { & $InstallHint }
        if ($Required) { throw "$Name is required by the selected configuration but no executable path was resolved." }
        return $null
    }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }

    Write-Warning "$Name not found at '$Path'."
    if ($InstallHint) { & $InstallHint }
    if ($Required) {
        throw "$Name is required by the selected configuration but was not found at '$Path'."
    }
    # SR-016: under -NonInteractive degrade silently to "absent" rather than block.
    if ($NonInteractive) {
        Write-Warning "Continuing without $Name (non-interactive)."
        return $null
    }
    Write-Host "Press Enter to continue without $Name, or Ctrl+C to abort."
    [void](Read-Host)
    return $null
}

function Initialize-Dependencies {
    # Implements: SR-019 (required dep), SR-020 (optional deps), SR-016 (non-blocking).
    [CmdletBinding()]
    param(
        [bool]$AnyCompressionNeeded,
        [bool]$AnyMediaMetricsNeeded,
        [scriptblock]$Log,
        [switch]$NonInteractive,
        [switch]$AutoInstall,
        [AllowNull()][string]$SevenZipPath = $script:Def.SevenZipDefaultPath,
        [AllowNull()][string]$FfprobePath = $script:Def.FfprobePathDefault
    )
    $deps = [ordered]@{}

    if ($AnyCompressionNeeded) {
        $deps['7z'] = Resolve-OptionalTool -Name '7-Zip' -Path $SevenZipPath -Required -NonInteractive:$NonInteractive -InstallHint {
            & $Log 'Install 7-Zip or set Tools.SevenZipPath / FILEBACKUP_7ZIP_PATH.' 'ERROR'
        }
    } else {
        # Compression being OFF does not mean 7-Zip is unneeded: the backup may
        # still HOLD Compressed=Yes rows written under a previous configuration,
        # and a compressed row needs 7-Zip to be read back at all -- nothing
        # already stored is ever re-formed (SR-061), so a flip to CompressEnabled
        # false leaves every existing archive exactly where it is. Resolve it
        # opportunistically and silently: absent is genuinely not fatal on this
        # branch, and Resolve-OptionalTool's non-Required path can PROMPT, which
        # SR-016 forbids for something this run may not need at all.
        $deps['7z'] = if (-not [string]::IsNullOrWhiteSpace($SevenZipPath) -and
                          (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) { $SevenZipPath } else { $null }
    }

    if ($AnyMediaMetricsNeeded) {
        $deps['ffprobe'] = Resolve-OptionalTool -Name 'ffprobe' -Path $FfprobePath -NonInteractive:$NonInteractive -InstallHint {
            & $Log 'Install ffmpeg/ffprobe or set Tools.FfprobePath / FILEBACKUP_FFPROBE_PATH.' 'WARN'
        }
    } else {
        $deps['ffprobe'] = $null
    }

    Initialize-XxHashLibrary -NonInteractive:$NonInteractive -AutoInstall:$AutoInstall | Out-Null
    $deps['xxhash'] = $true
    return $deps
}

# endregion

# region Media metrics

function Get-MediaMBPerSec {
    # Implements: SR-020, LLR-020
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$FfprobePath
    )
    if (-not $FfprobePath -or -not (Test-Path -LiteralPath $FfprobePath -PathType Leaf)) {
        return $null
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $FfprobePath
    $psi.Arguments = "-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 `"$FilePath`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $output = $p.StandardOutput.ReadToEnd().Trim()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not $output) { return $null }

    [double]$duration = 0
    if (-not [double]::TryParse($output, [ref]$duration)) { return $null }
    if ($duration -le 0) { return $null }

    $info     = Get-Item -LiteralPath $FilePath
    $sizeMB   = $info.Length / 1MB
    $mbPerSec = $sizeMB / $duration
    return [Math]::Round($mbPerSec, 3)
}

# endregion

# region Hash-recalc schedule

function Test-HashRecalcDue {
    <#
    .SYNOPSIS
        Decides whether untouched files should be re-hashed this run, given the
        frequency code and the timestamp of the last hash run.
    .NOTES
        B2: DateTime.MinValue (the unbound default) means "never run" -> recalc.
    #>
    # Implements: SR-011, LLR-011
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FreqCode,
        [datetime]$LastHashRun = [datetime]::MinValue,
        [datetime]$Now = (Get-Date)        # injectable for deterministic tests
    )
    if ($LastHashRun -eq [datetime]::MinValue) { return $true }
    $today = $Now

    switch ($FreqCode.ToUpperInvariant()) {
        'A' { return $true }
        'E' { return $true }
        'D' { return $today.Date -gt $LastHashRun.Date }
        'W' {
            $cal      = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
            $weekNow  = $cal.GetWeekOfYear($today,       [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
            $weekLast = $cal.GetWeekOfYear($LastHashRun, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
            return ($today.Year -ne $LastHashRun.Year) -or ($weekNow -ne $weekLast)
        }
        'M' { return ($today.Year -ne $LastHashRun.Year) -or ($today.Month -ne $LastHashRun.Month) }
        'Y' { return $today.Year -gt $LastHashRun.Year }
        'N' { return $false }
        default { return $true }
    }
}

# endregion

# region Source manifest

function Update-SourceManifest {
    <#
    .SYNOPSIS
        Walks the source tree, (re)hashes new/changed files (and all files when
        -ForceRehash), marks (hash,length) duplicates, and writes the source
        MANIFEST.csv. ManifestFolderPath may place that mutable hash cache
        outside a read-only source tree. Returns the rows.
    #>
    # Implements: SR-001, SR-024, SR-055, LLR-001, LLR-024, LLR-055
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$ManifestFolderPath,
        [string]$FfprobePath,
        [switch]$ForceRehash,
        # SR-055: receives one record per skipped non-portable name. The skip
        # must happen HERE, before hashing — a name Windows cannot open (e.g. a
        # trailing dot) would otherwise abort the whole set on a read error
        # instead of being reported as the name problem it is.
        [AllowNull()][System.Collections.Generic.List[object]]$UnportableOut,
        # SR-057: receives one record per directory the walk could not
        # enumerate (Deny ACE on a hidden/system dir made visible by -Force).
        # The caller fails the set loudly but still backs up everything
        # reachable — one unlistable 'System Volume Information' must not turn
        # into a run that writes NO manifest at all (2026-08-24 review, B1).
        [AllowNull()][System.Collections.Generic.List[object]]$UnreadableOut
    )
    $sourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    if ([string]::IsNullOrWhiteSpace($ManifestFolderPath)) {
        $manifestFolder = $sourcePath
    } else {
        if (-not (Test-Path -LiteralPath $ManifestFolderPath -PathType Container)) {
            New-Item -ItemType Directory -Path $ManifestFolderPath -Force | Out-Null
        }
        $manifestFolder = (Resolve-Path -LiteralPath $ManifestFolderPath).Path
    }
    $existing = Read-Manifest -FolderPath $manifestFolder

    # Filesystem-faithful key comparison (SR-034): a case-insensitive map on
    # Linux would hand one case-differing file the OTHER file's cached hash
    # whenever length+mtime happen to coincide.
    $existingMap = New-RelativePathMap
    foreach ($row in $existing) { $existingMap[$row.RelativePath] = $row }

    # With the legacy in-source cache, skip only root-level infrastructure and
    # keep nested files with those names. With an external cache every source
    # file is user data, including a root-level MANIFEST.csv.
    $files = if ($manifestFolder -eq $sourcePath) {
        Get-DataFile -Root $sourcePath -EnumerationErrorOut $UnreadableOut
    } else {
        # -Force (SR-057): the external-cache branch bypasses Get-DataFile and
        # must include hidden/dot entries the same way (D-4) — including the
        # tolerate-and-report handling of an unlistable directory.
        if ($null -ne $UnreadableOut) {
            $enumErr = $null
            $walked = Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force `
                -ErrorAction SilentlyContinue -ErrorVariable enumErr
            foreach ($e in @($enumErr)) {
                $UnreadableOut.Add([pscustomobject]@{
                    Path = "$($e.TargetObject)"; Message = $e.Exception.Message })
            }
            $walked
        } else {
            Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force
        }
    }

    $updated = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $rel  = $f.FullName.Substring($sourcePath.Length).TrimStart('\','/')

        # SR-055 portable-name guard, BEFORE any open/hash attempt.
        if ($null -ne $UnportableOut) {
            $reason = Test-PortableRelativePath -RelativePath $rel
            if ($reason) {
                $UnportableOut.Add([pscustomobject]@{ RelativePath = $rel; Reason = $reason })
                continue
            }
        }

        $prev = $existingMap[$rel]

        $needsHash = $false
        $hashValue = $null
        $mediaMB   = $null

        if ($prev) {
            if ($prev.Length -ne $f.Length -or $prev.LastWriteTime -ne $f.LastWriteTime) {
                $needsHash = $true
            } elseif ($ForceRehash) {
                $needsHash = $true          # B4: scheduled recalc actually forces a rehash
            } else {
                $hashValue = $prev.xxH2Hash
                $mediaMB   = $prev.MediaMBPerSec
            }
        } else {
            $needsHash = $true
        }

        if ($needsHash) {
            $hashValue = Get-FileXxHash -FilePath $f.FullName
            $mediaMB   = Get-MediaMBPerSec -FilePath $f.FullName -FfprobePath $FfprobePath
        }

        $updated.Add([pscustomobject]@{
            DataPath         = ''
            RelativePath     = $rel
            Length           = $f.Length
            LastWriteTime    = $f.LastWriteTime
            xxH2Hash         = $hashValue
            Compressed       = ''
            StoredAsHashSize = ''
            Duplicate        = 0
            MediaMBPerSec    = $mediaMB
        })
    }

    $sorted = $updated | Sort-Object { $_.RelativePath.Length } -Descending

    $groups = $sorted | Group-Object xxH2Hash, Length
    foreach ($grp in $groups) {
        if ($grp.Count -gt 1) {
            $gSorted = $grp.Group | Sort-Object { $_.RelativePath.Length }
            foreach ($o in $gSorted[1..($gSorted.Count - 1)]) { $o.Duplicate = 1 }
        }
    }

    Write-Manifest -FolderPath $manifestFolder -Records $sorted
    return $sorted
}

# endregion

# region Directory sidecar (SR-065)

function Get-SourceDirectoryRecord {
    <#
    .SYNOPSIS
        Returns the directory rows the manifest cannot carry (SR-065): every
        source directory that is EMPTY of files or holds a recorded attribute
        bit, as {RelativePath, Attributes}.

    .DESCRIPTION
        MANIFEST.csv has one row per FILE, so an empty directory was never
        recreated by a restore and a Hidden or System FOLDER came back ordinary.
        This is the smallest thing that fixes both: one advisory row per
        directory that would otherwise be lost.

        "Empty" means no file ANYWHERE beneath it, decided from the file rows
        the walk already produced rather than by re-enumerating each directory -
        a per-directory recursive scan would be O(directories x files) on a tree
        whose whole point is scale (the SR-064 discipline). A directory holding
        only other empty directories is therefore emitted along with them, and
        the deepest row alone would recreate the chain.

        Directories the walk could not enumerate are NOT emitted: we cannot know
        whether they are empty, and claiming empty for an unreadable directory
        would be a lie in the dangerous direction. Their SR-057 handling in
        Invoke-BackupSet is unchanged.

        Non-portable directory names (SR-055) are skipped with a warning rather
        than failing the set again - the files beneath such a name have already
        failed it, and a directory row is advisory.

    .PARAMETER SourcePath
        The source root being backed up.

    .PARAMETER FileRelativePath
        Every file RelativePath the source walk produced. Ancestors of these are
        the populated directories.

    .PARAMETER Log
        Optional logger for skipped names.

    .OUTPUTS
        [object[]] rows sorted ordinally by RelativePath, so two runs over the
        same state write byte-identical sidecars (the canonical-bytes rule the
        manifest follows).
    #>
    # Implements: SR-065, LLR-065
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [AllowNull()][AllowEmptyCollection()][string[]]$FileRelativePath,
        [AllowNull()][scriptblock]$Log
    )
    $root = (Resolve-Path -LiteralPath $SourcePath).Path

    # Populated = every ancestor directory of every file row. Filesystem-faithful
    # keys (SR-034): case-differing directories are distinct on Linux.
    $populated = New-RelativePathMap
    foreach ($rel in @($FileRelativePath)) {
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        $parent = $rel
        while ($true) {
            $parent = [IO.Path]::GetDirectoryName($parent)
            if ([string]::IsNullOrEmpty($parent)) { break }
            if ($populated.ContainsKey($parent)) { break }   # ancestors already marked
            $populated[$parent] = $true
        }
    }

    $enumErr = $null
    $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force `
                -ErrorAction SilentlyContinue -ErrorVariable enumErr)
    $unreadable = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($enumErr)) {
        $target = "$($e.TargetObject)"
        if ($target) { $unreadable.Add($target) }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($root.Length).TrimStart('\', '/')
        if (-not $rel) { continue }

        $isUnreadable = $false
        foreach ($bad in $unreadable) {
            if ($d.FullName.Equals($bad, [System.StringComparison]::OrdinalIgnoreCase)) { $isUnreadable = $true; break }
        }
        if ($isUnreadable) { continue }

        $reason = Test-PortableRelativePath -RelativePath $rel
        if ($reason) {
            if ($Log) { & $Log "Directory '$rel' is not recorded in the directory sidecar: $reason (SR-055/SR-065)." 'WARN' }
            continue
        }

        $token = Get-DirectoryAttributeToken -Attributes $d.Attributes
        if (-not $token -and $populated.ContainsKey($rel)) { continue }
        $rows.Add([pscustomobject]@{ RelativePath = $rel; Attributes = $token })
    }

    # .ToArray(), not @(...): the array subexpression over a List throws
    # "Argument types do not match" on PS 7.5 (AGENTS.md sec.4).
    $out = $rows.ToArray()
    [Array]::Sort($out, [Comparison[object]] {
        param($a, $b) [string]::CompareOrdinal($a.RelativePath, $b.RelativePath) })
    return $out
}

function Write-DirectorySidecar {
    <#
    .SYNOPSIS
        Writes DIRECTORIES.csv beside a manifest, or removes it when there is
        nothing to record (SR-065).

    .DESCRIPTION
        Deliberately NOT witnessed: the sidecar is advisory, no restorer fails
        over it, and the bytes-at-paths contract does not depend on it. Removing
        the file when there are no rows keeps a store that has no empty or
        attributed directories byte-identical to a pre-SR-065 store, so nothing
        about kit comparison or run idempotency changes for such a tree.

    .PARAMETER FolderPath
        The folder holding the MANIFEST.csv this sidecar accompanies.

    .PARAMETER Records
        Get-SourceDirectoryRecord's output.
    #>
    # Implements: SR-065, LLR-065
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Records
    )
    $path = Join-Path $FolderPath $script:Def.DirectorySidecarName
    if ($null -eq $Records -or $Records.Count -eq 0) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return
    }
    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
    }
    $out = foreach ($r in $Records) {
        [pscustomobject]@{ RelativePath = [string]$r.RelativePath; Attributes = [string]$r.Attributes }
    }
    $out | Export-Csv -LiteralPath $path -NoTypeInformation
}

# endregion

# region Backup copy

# Transient-failure retry for a single copy/compress (SR-067). A source file
# held open by an antivirus scanner, an indexer or another writer fails one
# instant and succeeds the next, and before this a file whose content was UNIQUE
# got exactly ONE attempt: the SR-060 candidate loop only falls back to other
# MEMBERS of a content group, and a unique file's group has one member.
#
# One delay per retry, so three attempts cost at most 1.25s of waiting for a
# file that never becomes readable. The per-RUN budget is the automation rail:
# a systemic failure (a whole tree the account cannot read) fails
# DETERMINISTICALLY for every file in it, and retrying thousands of those would
# turn a scheduled run into an hours-long sleep. Once the budget is spent the
# run stops waiting and fails the remaining files immediately, saying so.
$script:CopyRetryDelayMs  = @(250, 1000)
$script:CopyRetryBudgetMs = 60000

function Get-CopyRetryDelayMs {
    <#
    .SYNOPSIS
        The delay before retry number -Attempt, or $null when the attempts for
        one file are exhausted (SR-067).

    .PARAMETER Attempt
        1-based count of attempts ALREADY made against this file.

    .OUTPUTS
        [int] milliseconds to wait, or $null to stop retrying.
    #>
    # Implements: SR-067, LLR-067
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Attempt)
    if ($Attempt -lt 1 -or $Attempt -gt $script:CopyRetryDelayMs.Count) { return $null }
    return $script:CopyRetryDelayMs[$Attempt - 1]
}

function Test-CopyFailureIsTransient {
    <#
    .SYNOPSIS
        False for a copy failure that cannot change on a retry (SR-067).

    .DESCRIPTION
        Only one failure is deterministic by construction today: a DIRECTORY
        occupying the destination (the step-4 review's n6 guard). Waiting on it
        wastes the run's retry budget and delays a loud, accurate error.
        Everything else - a lock, a permission that may be released, an I/O
        blip, a vanished temp file - is treated as possibly transient, because
        guessing wrong in that direction only costs time, while guessing wrong
        the other way costs the file.

    .PARAMETER Message
        The failure string Copy-SourceFileToBackup returned.

    .OUTPUTS
        [bool] whether a retry is worth attempting.
    #>
    # Implements: SR-067, LLR-067
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    return ($Message -notlike '*is a directory; refusing to copy into it*')
}

function Copy-SourceFileToBackup {
    # Implements: SR-003, LLR-003
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceFilePath,
        [Parameter(Mandatory)][string]$BackupFilePath,
        [Parameter(Mandatory)][bool]$ShouldCompress,
        [string]$SevenZipPath
    )
    try {
        # A DIRECTORY occupying the destination made Copy-Item copy INTO it
        # and report success, so the manifest row named a folder (step-4
        # review, incidental finding n6). Refuse: the caller logs the error
        # string and the row is not written.
        if (Test-Path -LiteralPath $BackupFilePath -PathType Container) {
            return "destination '$BackupFilePath' is a directory; refusing to copy into it"
        }
        if ($ShouldCompress -and $SevenZipPath) {
            Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $SourceFilePath -Destination7z $BackupFilePath
        } else {
            $dir = [System.IO.Path]::GetDirectoryName($BackupFilePath)
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            # -ErrorAction Stop, not the caller's preference: a NON-terminating
            # Copy-Item failure (an unreadable or vanished source) skipped this
            # try/catch entirely and the function returned 0 - "copied" with no
            # file written, and a manifest row naming it. The entry point does
            # set 'Stop', so this was latent there; correctness must not depend
            # on a caller's preference (found 2026-08-25 while testing the WP9
            # review's MIN-1 fallback, which the silent success also disarmed).
            Copy-Item -LiteralPath $SourceFilePath -Destination $BackupFilePath -Force -ErrorAction Stop
        }
        return 0
    }
    catch {
        return $_.Exception.Message
    }
}

# endregion

# region Backup manifest integrity + storage-layout migration

function Test-BackupManifest {
    <#
    .SYNOPSIS
        Refuses a legacy path-addressed store (SR-061), then blanks DataPaths
        whose files are missing and warns about unreferenced files — in one
        linear pass over rows plus disk (SR-064).
    #>
    # Implements: SR-061, SR-064, LLR-060, LLR-062
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $db = Read-Manifest -FolderPath $FolderRoot

    # SR-061: a row in the legacy path-addressed 'Original' form marks a store
    # written by a pre-content-addressed build. There is no in-place conversion
    # (human ruling 2026-08-25: no store exists that must be maintained), and
    # writing on would interleave two addressing semantics — the copy step
    # adopts and propagates existing DataPaths verbatim. Refuse BEFORE the
    # sanitize pass below rewrites the manifest; the throw reaches the step-6
    # catch in Invoke-BackupSet, which discards the still-empty staging folder.
    # -Action Verify still audits such a store (the LegacyStoredForm finding).
    $legacy = @($db | Where-Object { $_.StoredAsHashSize -eq 'Original' })
    if ($legacy.Count -gt 0) {
        throw ("Backup manifest at '$FolderRoot' holds $($legacy.Count) row(s) in the legacy path-addressed form " +
               "(StoredAsHashSize='Original'), e.g. '$($legacy[0].RelativePath)'. This store was written by a " +
               'pre-content-addressed build and cannot be written to (SR-061). Back up to a fresh BackupPath; ' +
               'the old store stays restorable as-is and -Action Verify can still audit it.')
    }

    # SR-061 + SR-069 (WP12): the same refusal for a PRE-WP12 CONTENT-ADDRESSED
    # store. StoredAsHashSize cannot tell those apart - a base-85 store says
    # 'Hash', exactly like this one does - so the discriminators are the witness
    # format version and the name grammar itself.
    #
    # Two of them because neither is complete alone. The witness is present on
    # every store this build writes but is OPTIONAL on older ones (SR-039 warns
    # and continues when it is absent), and a shape test cannot classify a row
    # whose DataPath is blank, which is the supported 'recover by hash' state.
    # Together they leave only one gap - a witness-less store whose EVERY row is
    # blank - and such a store carries no name to misread anyway.
    $witness = Test-ManifestWitness -FolderPath $FolderRoot
    if ($witness.Status -ne 'Absent' -and $witness.Version -gt 0 -and
        $witness.Version -lt $script:WitnessFormatVersion) {
        throw ("Backup manifest at '$FolderRoot' is a pre-WP12 store: its witness declares format version " +
               "$($witness.Version), and this build writes $($script:WitnessFormatVersion) (the SR-069 base-57 " +
               'name grammar). Mixing the two grammars in one pool is refused (SR-061). Back up to a fresh ' +
               'BackupPath; restore the old store with the kit bundled inside it.')
    }
    $badName = @($db | Where-Object { Test-LegacyStoredObjectName -Name "$($_.DataPath)" })
    if ($badName.Count -gt 0) {
        throw ("Backup manifest at '$FolderRoot' holds $($badName.Count) row(s) named under a retired grammar, " +
               "e.g. '$($badName[0].DataPath)' for '$($badName[0].RelativePath)'. This store was written by a " +
               'pre-WP12 build and cannot be written to (SR-061). Back up to a fresh BackupPath.')
    }

    # SR-064 (LLR-062): ONE pass over the disk and ONE over the rows — the old
    # shape re-piped the whole manifest through Where-Object once PER on-disk
    # file, O(rows x files) on a store whose whole point is scale. Both maps
    # are New-RelativePathMap so path keys compare the way the local
    # filesystem does.
    $existingPaths = New-RelativePathMap
    $rootFull = (Resolve-Path -LiteralPath $FolderRoot).Path
    Get-DataFile -Root $FolderRoot |
        ForEach-Object { $existingPaths[$_.FullName.Substring($rootFull.Length).TrimStart('\', '/')] = $true }

    $referenced = New-RelativePathMap
    foreach ($row in $db) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $rel = $row.DataPath.TrimStart('\', '/')
        if (-not $existingPaths.ContainsKey($rel)) {
            & $Log "Datapath missing in backup DB: $rel" 'WARN'
            $row.DataPath = ''
        } else {
            $referenced[$rel] = $true
        }
    }

    foreach ($rel in $existingPaths.Keys) {
        if (-not $referenced.ContainsKey($rel)) {
            & $Log "File exists in backup folder but not in DB: $rel" 'WARN'
        }
    }

    Write-Manifest -FolderPath $FolderRoot -Records $db
    return $db
}

function Get-BackupContentIndex {
    <#
    .SYNOPSIS
        Builds the physical content index over a backup pool (backup root +
        snapshot folders): "<xxH2Hash>|<Length>" -> every folder that actually
        holds those bytes, plus each folder's manifest.

    .DESCRIPTION
        One scan, two consumers (LLR-047). Optimize-ChangeFolders uses it to
        elect a keeper per key; the retention mechanism (SR-045/SR-047) uses it
        to find content whose only physical copy lives in the snapshot about to
        be removed. Blank DataPaths, blank hashes and rows whose file is not on
        disk are skipped: the index describes bytes that EXIST, so a blank row
        is demand, never supply.

        The backup root is ordered -1 and the snapshot folders 1..n in the order
        given (Optimize passes them sorted by name, i.e. oldest first), so
        "newest wins" is `Sort-Object FolderOrder -Descending`.

    .PARAMETER BackupRoot
        The live backup root. Its manifest is read when present.

    .PARAMETER SnapshotFolder
        Full paths of the snapshot folders to index, oldest first. May be empty.

    .OUTPUTS
        [pscustomobject] Map (hashtable key -> List of location records with
        LocationType/Folder/DataPath/FullPath/IsBackup/FolderOrder) and Folders
        (one record per indexed folder: Folder, Name, Order, Manifest, IsBackup).
    #>
    # Implements: SR-026, SR-045, SR-047, LLR-047
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][string[]]$SnapshotFolder
    )
    $map = @{}   # "<hash>|<len>" -> list of location records

    $addToMap = {
        param([string]$LocationType, [string]$Folder, [object]$Row, [int]$FolderOrder)
        if ([string]::IsNullOrWhiteSpace($Row.DataPath)) { return }
        if ([string]::IsNullOrWhiteSpace($Row.xxH2Hash)) { return }
        $key  = "$($Row.xxH2Hash)|$($Row.Length)"
        $full = Join-Path $Folder $Row.DataPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
        if (-not $map.ContainsKey($key)) {
            $map[$key] = New-Object System.Collections.Generic.List[object]
        }
        $map[$key].Add([pscustomobject]@{
            LocationType = $LocationType
            Folder       = $Folder
            DataPath     = $Row.DataPath
            FullPath     = $full
            IsBackup     = ($LocationType -eq 'Backup')
            FolderOrder  = $FolderOrder
        })
    }

    $folders = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath (Join-Path $BackupRoot $script:Def.DatabaseFilename) -PathType Leaf) {
        $backupManifest = Read-Manifest -FolderPath $BackupRoot
        $folders.Add([pscustomobject]@{
            Folder = $BackupRoot; Name = [IO.Path]::GetFileName($BackupRoot)
            Order = -1; Manifest = $backupManifest; IsBackup = $true
        })
        foreach ($row in $backupManifest) { & $addToMap 'Backup' $BackupRoot $row -1 }
    }

    $folderOrder = 0
    # Where-Object guards the AGENTS.md §4 hazard: an empty result reaching this
    # parameter as $null makes @($SnapshotFolder) one $null element.
    foreach ($dir in @($SnapshotFolder | Where-Object { $_ })) {
        $folderOrder++
        $manifest = Read-Manifest -FolderPath $dir
        $folders.Add([pscustomobject]@{
            Folder = $dir; Name = [IO.Path]::GetFileName($dir)
            Order = $folderOrder; Manifest = $manifest; IsBackup = $false
        })
        foreach ($row in $manifest) { & $addToMap 'Change' $dir $row $folderOrder }
    }

    return [pscustomobject]@{ Map = $map; Folders = $folders }
}

function Optimize-ChangeFolders {
    <#
    .SYNOPSIS
        Collapses duplicate (hash,length) data files across change folders,
        preferring the backup copy then the newest change folder, and blanks
        DataPaths whose files were removed (reconstruct recovers them by hash).
    #>
    # Implements: SR-026, LLR-026
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
        & $Log "Change root '$ChangeRoot' does not exist. Skipping sanitize." 'INFO'
        return
    }

    & $Log "Starting Optimize-ChangeFolders for '$ChangeRoot' and backup '$BackupRoot'." 'INFO'
    $changeFolderRegex = $script:Def.ChangeFolderRegex

    # -Force (SR-057): a hidden Snapshot_* folder must not escape sanitization.
    $changeDirs = Get-ChildItem -LiteralPath $ChangeRoot -Directory -Force |
                  Where-Object { $_.Name -match $changeFolderRegex } |
                  Sort-Object Name
    if (-not $changeDirs -or $changeDirs.Count -eq 0) {
        & $Log "No change folders found under '$ChangeRoot'." 'INFO'
        return
    }

    # One shared scan (LLR-047): the same index the retention mechanism reads.
    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($changeDirs | ForEach-Object { $_.FullName })
    $globalMap       = $index.Map
    $changeManifests = @($index.Folders | Where-Object { -not $_.IsBackup })

    foreach ($key in $globalMap.Keys) {
        $entries = $globalMap[$key]
        if ($entries.Count -le 1) { continue }

        $backupEntry = $entries | Where-Object { $_.IsBackup } | Select-Object -First 1
        $keeper = if ($backupEntry) {
            $backupEntry
        } else {
            $entries | Where-Object { -not $_.IsBackup } | Sort-Object FolderOrder -Descending | Select-Object -First 1
        }

        $toDelete = $entries | Where-Object { $_.FullPath -ne $keeper.FullPath -and -not $_.IsBackup }
        foreach ($del in $toDelete) {
            if (Test-Path -LiteralPath $del.FullPath -PathType Leaf) {
                try {
                    Remove-Item -LiteralPath $del.FullPath -Force
                    & $Log "Removed duplicate datapath '$($del.DataPath)' from change folder '$($del.Folder)' (hash/len: $key)." 'INFO'
                } catch {
                    & $Log "Failed to remove duplicate datapath '$($del.DataPath)' from '$($del.Folder)': $($_.Exception.Message)" 'ERROR'
                }
            }
        }
    }

    foreach ($cm in $changeManifests) {
        $changed = $false
        foreach ($row in $cm.Manifest) {
            if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
            $full = Join-Path $cm.Folder $row.DataPath
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $row.DataPath = ''
                $changed = $true
            }
        }
        if ($changed) {
            & $Log "Updating MANIFEST in change folder '$($cm.Folder)' after datapath cleanup." 'INFO'
            Write-Manifest -FolderPath $cm.Folder -Records $cm.Manifest
        }
    }

    & $Log "Optimize-ChangeFolders completed for '$ChangeRoot'." 'INFO'
}

# endregion

# region Snapshot retention (SR-045..SR-047)

function Get-PoolSnapshotFolder {
    <#
    .SYNOPSIS
        Returns the dated snapshot folders under a change root, oldest first
        (name order), filtered by the one $Def.ChangeFolderRegex every consumer
        uses. Nothing else in the change root is a snapshot.
    #>
    # Implements: SR-045, LLR-045
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChangeRoot)
    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { return @() }
    # -Force (SR-057): the data POOL is built from this list — a hidden snapshot
    # folder would silently drop out of recovery and prune alike (D-4).
    return @(Get-ChildItem -LiteralPath $ChangeRoot -Directory -Force |
             Where-Object { $_.Name -match $script:Def.ChangeFolderRegex } |
             Sort-Object Name)
}

function Get-SnapshotDate {
    <#
    .SYNOPSIS
        Parses the point-in-time date out of a Snapshot_<date> folder name
        (tolerating Complete-ChangeFolder's _NNN collision disambiguator).
        Returns $null when the name carries no parseable date.
    #>
    # Implements: SR-047, LLR-047
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '^Snapshot_(\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2})') { return $null }
    try { return [datetime]::ParseExact($Matches[1], $script:Def.FileLabelDateFormat, $null) }
    catch { return $null }
}

function Get-SnapshotPrunePlan {
    <#
    .SYNOPSIS
        Computes — without touching a byte — what removing one snapshot would
        cost and what must be re-homed first so no surviving manifest is left
        pointing at content that no longer exists (SR-045).

    .DESCRIPTION
        Pool = backup root + every Snapshot_* folder. The physical index (bytes
        that EXIST) comes from Get-BackupContentIndex. The demand set is every
        row OUTSIDE the target whose DataPath is blank, or whose DataPath names
        a file that is not there — those rows resolve by (hash,length) from
        anywhere in the pool. A demanded key whose every physical copy lies
        inside the target is ENDANGERED: exactly one file per endangered key is
        copied out before the folder dies.

        The destination is where Optimize-ChangeFolders would have elected the
        keeper had the target never existed — the backup root when it demands
        the key, else the newest surviving snapshot that demands it. That
        guarantees the destination already carries a manifest row for the
        content, so one row is edited (DataPath + the storage-form pair) and no
        row is added, removed or reordered.

        Refusals discoverable at plan time are returned in Problems (each with
        its SR-040 code) rather than thrown, so -WhatIf can report all of them
        and Remove-BackupSnapshot can apply the 2 > 3 > 4 > 1 precedence over
        the whole set.

    .PARAMETER BackupRoot
        The live backup root.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .PARAMETER Name
        Exact snapshot folder name (no wildcards). See SR-046 for containment.

    .OUTPUTS
        [pscustomobject] Name, Folder, Date, Rows, PhysicalBytes, Items,
        BytesReHomed, BytesReclaimed, UnreferencedData, Problems, Index,
        Manifests.
    #>
    # Implements: SR-045, SR-047, LLR-045, LLR-047
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][string]$Name
    )
    $problems = New-Object System.Collections.Generic.List[object]
    $items    = New-Object System.Collections.Generic.List[object]
    $plan = [pscustomobject]@{
        Name = $Name; Folder = $null; Date = (Get-SnapshotDate -Name $Name)
        Rows = 0; PhysicalBytes = [long]0; Items = $items
        BytesReHomed = [long]0; BytesReclaimed = [long]0
        UnreferencedData = @(); Problems = $problems
        Index = $null; Manifests = @{}
    }

    $snapshots = Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot
    $target    = $snapshots | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $target) {
        $problems.Add([pscustomobject]@{ Code = 2; Kind = 'bad-target'
            Message = "'$Name' is not a snapshot folder directly under '$ChangeRoot'." })
        return $plan
    }
    $targetFolder = $target.FullName
    $plan.Folder  = $targetFolder

    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($snapshots | ForEach-Object { $_.FullName })
    $plan.Index = $index
    foreach ($f in $index.Folders) { $plan.Manifests[$f.Folder] = $f.Manifest }
    $targetManifest = @($index.Folders | Where-Object { $_.Folder -eq $targetFolder } | ForEach-Object { $_.Manifest })
    $plan.Rows = $targetManifest.Count

    # Everything in the folder disappears with it — data files and the snapshot's
    # own restore-kit copies alike.
    # -Force (SR-057): hidden files are deleted with the folder — omitting them
    # makes the reclaim figure lie.
    $plan.PhysicalBytes = [long](Get-ChildItem -LiteralPath $targetFolder -File -Recurse -Force |
        Measure-Object -Property Length -Sum).Sum

    # Bytes in the target that its own manifest does not reference are unexplained
    # (the pipeline never creates one) — a refusal, not something to plan around.
    $ownReferenced = @{}
    foreach ($row in $targetManifest) {
        if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) { $ownReferenced[$row.DataPath.TrimStart('\','/')] = $true }
    }
    $targetPrefix = (Resolve-Path -LiteralPath $targetFolder).Path
    $unreferenced = foreach ($file in (Get-DataFile -Root $targetFolder)) {
        $rel = $file.FullName.Substring($targetPrefix.Length).TrimStart('\','/')
        if (-not $ownReferenced[$rel] -and $rel -notlike '*.fbprune.tmp') { $rel }
    }
    $plan.UnreferencedData = @($unreferenced)

    # Demand: rows OUTSIDE the target that resolve by (hash,length).
    $demand = @{}
    foreach ($f in $index.Folders) {
        if ($f.Folder -eq $targetFolder) { continue }
        foreach ($row in $f.Manifest) {
            if ([string]::IsNullOrWhiteSpace($row.xxH2Hash)) { continue }
            $resolvesByHash = [string]::IsNullOrWhiteSpace($row.DataPath) -or
                -not (Test-Path -LiteralPath (Join-Path $f.Folder $row.DataPath) -PathType Leaf)
            if (-not $resolvesByHash) { continue }
            $key = "$($row.xxH2Hash)|$($row.Length)"
            if (-not $demand.ContainsKey($key)) { $demand[$key] = New-Object System.Collections.Generic.List[object] }
            $demand[$key].Add([pscustomobject]@{ FolderRecord = $f; Row = $row })
        }
    }

    foreach ($key in $demand.Keys) {
        # .ToArray(), not @(...): a List reached through a PSObject property
        # throws "Argument types do not match" under the array subexpression on
        # PS 7.5 (the same gotcha AGENTS.md §4 records for Compare-SourceToBackup).
        $locations = @()
        if ($index.Map.ContainsKey($key)) { $locations = $index.Map[$key].ToArray() }
        if ($locations.Count -eq 0) { continue }                                    # already broken: Test-PoolResolves reports it
        if (@($locations | Where-Object { $_.Folder -ne $targetFolder }).Count -gt 0) { continue }  # survives without the target

        $source    = $locations[0]
        $sourceRow = @($targetManifest | Where-Object { $_.DataPath -eq $source.DataPath })[0]
        if (-not $sourceRow) { continue }

        $claims  = $demand[$key].ToArray()
        $winner  = @($claims | Where-Object { $_.FolderRecord.IsBackup })[0]
        if (-not $winner) {
            $winner = @($claims | Sort-Object { $_.FolderRecord.Order } -Descending)[0]
        }
        $destFolder = $winner.FolderRecord.Folder
        # The S3 collapse (WP9 step 8 measured it; taken 2026-08-26 once legacy
        # path-addressed support was withdrawn): a data file's name derives from
        # its CONTENT and its stored form, so a re-homed object's destination
        # name is ALWAYS identical to its source name and the 30-line
        # Get-ReHomedDataPathName synthesizer collapses to the source DataPath.
        # $sourceRow was selected BY that DataPath just above, so it is never
        # blank. This held only for hash-addressed rows, which is now all of
        # them - Test-BackupManifest refuses a legacy store (SR-061) and both
        # restorers refuse to read one (kit revision 7).
        $destName   = $sourceRow.DataPath
        $destFull   = Join-Path $destFolder $destName

        if (Test-IsInfrastructureFile -Root $destFolder -FullPath ([IO.Path]::GetFullPath($destFull))) {
            $problems.Add([pscustomobject]@{ Code = 2; Kind = 'infrastructure-name'
                Message = "Re-homing '$($sourceRow.RelativePath)' into '$destFolder' would create the root-level infrastructure name '$destName', which hash recovery skips." })
            continue
        }
        if (Test-Path -LiteralPath $destFull -PathType Leaf) {
            # Something already occupies the elected name. Identical bytes mean a
            # previous interrupted prune already materialized it (resume); anything
            # else is a collision we refuse rather than overwrite.
            if ((Get-Item -LiteralPath $destFull).Length -eq (Get-Item -LiteralPath $source.FullPath).Length -and
                (Get-FileXxHash -FilePath $destFull) -eq (Get-FileXxHash -FilePath $source.FullPath)) {
                # fall through: the copy step is a no-op, the row edit still has to publish
            } else {
                $problems.Add([pscustomobject]@{ Code = 2; Kind = 'destination-collision'
                    Message = "Re-homing '$($sourceRow.RelativePath)' into '$destFolder' would overwrite the different file already at '$destName'." })
                continue
            }
        }

        $items.Add([pscustomobject]@{
            Key                 = $key
            SourceFullPath      = $source.FullPath
            SourceDataPath      = $source.DataPath
            SourceRow           = $sourceRow
            DestinationFolder   = $destFolder
            DestinationDataPath = $destName
            DestinationRow      = $winner.Row
            Compressed          = $sourceRow.Compressed
            StoredAsHashSize    = $sourceRow.StoredAsHashSize
            Bytes               = [long](Get-Item -LiteralPath $source.FullPath).Length
        })
    }

    $plan.BytesReHomed   = [long](@($items | Measure-Object -Property Bytes -Sum).Sum)
    $plan.BytesReclaimed = $plan.PhysicalBytes - $plan.BytesReHomed
    return $plan
}

function Test-StorageFormAgreement {
    <#
    .SYNOPSIS
        True when a manifest row's Compressed column agrees with the storage form
        of a named data file — the ONE predicate prune (SR-046) and storage-form
        verification (SR-049) both ask, so they cannot drift.

    .DESCRIPTION
        The form of a stored file is carried by its extension: '.7z' means an
        archive, anything else means raw bytes (the SR-021 invariant that a
        content-addressed name carries the storage extension in BOTH tree modes).
        A row claiming Compressed='Yes' must therefore name a '.7z' file, and a
        row claiming 'No' must not.

        ONE deliberate exemption: a row whose own RelativePath ends in '.7z' is a
        legitimately stored already-compressed SOURCE file (SR-004 declines to
        re-compress it), so its data file is a '.7z' regardless of the column.
        Such a row is never a disagreement.

    .PARAMETER Compressed
        The row's Compressed column ('Yes' / 'No').

    .PARAMETER RelativePath
        The row's RelativePath — the source file's name, which drives the
        already-compressed exemption above.

    .PARAMETER DataPath
        The stored file being judged. For a non-blank-DataPath row this is the
        row's own DataPath; for a blank row it is the DataPath of the copy hash
        recovery would locate elsewhere in the pool.

    .OUTPUTS
        [bool] True when the column and the file's form agree (or the row is
        exempt); false for a genuine disagreement.
    #>
    # Implements: SR-046, SR-049, LLR-046, LLR-049
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Compressed,
        [AllowNull()][AllowEmptyString()][string]$RelativePath,
        [AllowNull()][AllowEmptyString()][string]$DataPath
    )
    if ([IO.Path]::GetExtension([string]$RelativePath) -ieq '.7z') { return $true }
    $wantsArchive = ($Compressed -eq 'Yes')
    $isArchive    = ([IO.Path]::GetExtension([string]$DataPath) -ieq '.7z')
    return ($wantsArchive -eq $isArchive)
}

function Test-PoolResolves {
    <#
    .SYNOPSIS
        Proves that every manifest row in a backup pool still resolves to real
        bytes of the right form, optionally with one folder excluded — the
        phase-3 proof that makes snapshot removal safe (SR-046).

    .DESCRIPTION
        A non-blank DataPath must name a file present in its own folder (a
        PRESENT file is restored by the row's Compressed column, so its form
        must also agree — that half is unchanged). A blank DataPath must find
        its (hash,length) somewhere in the pool. Whether a located copy's FORM
        must also agree depends on the folder's own restore kit (WP7, SR-046
        as amended): revision-2+ kits decide a hash-recovered file's form from
        the FILE they locate (SR-050), so for them a form disagreement restores
        correctly and is NOT a problem — refusing it wedged every prune in a
        store that had merely flipped CompressEnabled. A folder with no kit or
        a pre-revision-2 kit still branches on the ROW and still refuses. A row
        whose RelativePath is itself '.7z' stays exempt either way.

        Reports rather than throws, so the caller can name every unresolvable row
        at once.

    .PARAMETER BackupRoot
        The live backup root.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .PARAMETER ExcludeFolder
        Full path of a folder to leave out of BOTH the index and the rows being
        checked — the snapshot about to be removed.

    .OUTPUTS
        [pscustomobject] Code / Kind / Message, one per unresolvable row or form
        disagreement. Empty means the pool resolves.
    #>
    # Implements: SR-046, SR-045, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [string]$ExcludeFolder
    )
    $problems  = New-Object System.Collections.Generic.List[object]
    $snapshots = @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot |
                   Where-Object { $_.FullName -ne $ExcludeFolder })
    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($snapshots | ForEach-Object { $_.FullName })

    # WP7 (SR-046 as amended): whether a blank row's located copy must agree in
    # FORM depends on the kit that would restore it — the folder's own. Cached
    # per folder; revision >= 2 decides form from the located file (SR-050).
    $kitRevisionOf = @{}

    foreach ($f in $index.Folders) {
        if ($f.Folder -eq $ExcludeFolder) { continue }
        foreach ($row in $f.Manifest) {
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) {
                $full = Join-Path $f.Folder $row.DataPath
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    # BytesSurvive: whether the CONTENT still exists somewhere a
                    # revision-4+ kit's fallback can reach — Verify must not call
                    # a restorable row "no bytes anywhere in the pool" (WP7
                    # review, required change 2). Checked on DISK, not just the
                    # index, since this very branch proves rows can lie.
                    $bytesSurvive = $false
                    if ($row.xxH2Hash) {
                        $contentKey = "$($row.xxH2Hash)|$($row.Length)"
                        if ($index.Map.ContainsKey($contentKey)) {
                            foreach ($location in $index.Map[$contentKey].ToArray()) {
                                if ($location.FullPath -ne $full -and (Test-Path -LiteralPath $location.FullPath -PathType Leaf)) {
                                    $bytesSurvive = $true; break
                                }
                            }
                        }
                    }
                    $problems.Add([pscustomobject]@{ Code = 2; Kind = 'broken-pool'
                        Folder = $f.Name; RelativePath = $row.RelativePath; DataPath = $row.DataPath
                        BytesSurvive = $bytesSurvive
                        Message = "'$($f.Name)': row '$($row.RelativePath)' points at '$($row.DataPath)', which is not in that folder." })
                    continue
                }
                if (-not (Test-StorageFormAgreement -Compressed $row.Compressed -RelativePath $row.RelativePath -DataPath $row.DataPath)) {
                    $problems.Add([pscustomobject]@{ Code = 2; Kind = 'form-mismatch'
                        Folder = $f.Name; RelativePath = $row.RelativePath; DataPath = $row.DataPath
                        Message = "'$($f.Name)': row '$($row.RelativePath)' is Compressed=$($row.Compressed) but its data file '$($row.DataPath)' has the opposite form." })
                }
                continue
            }
            if ([string]::IsNullOrWhiteSpace($row.xxH2Hash)) { continue }   # pre-existing unrestorable row; not prune's to judge
            $key = "$($row.xxH2Hash)|$($row.Length)"
            if (-not $index.Map.ContainsKey($key)) {
                $problems.Add([pscustomobject]@{ Code = 2; Kind = 'broken-pool'
                    Folder = $f.Name; RelativePath = $row.RelativePath; DataPath = ''
                    BytesSurvive = $false
                    Message = "'$($f.Name)': row '$($row.RelativePath)' resolves by hash, but no copy of its content exists in the pool." })
                continue
            }
            if (-not $kitRevisionOf.ContainsKey($f.Folder)) {
                $kitRevisionOf[$f.Folder] = Get-BackupKitRevision -Folder $f.Folder
            }
            if ($kitRevisionOf[$f.Folder] -ge 2) { continue }   # kit decides form from the FILE — a form difference restores correctly
            foreach ($location in $index.Map[$key].ToArray()) {
                if (-not (Test-StorageFormAgreement -Compressed $row.Compressed -RelativePath $row.RelativePath -DataPath $location.DataPath)) {
                    $problems.Add([pscustomobject]@{ Code = 2; Kind = 'form-mismatch'
                        Folder = $f.Name; RelativePath = $row.RelativePath; DataPath = ''
                        Message = "'$($f.Name)': row '$($row.RelativePath)' is Compressed=$($row.Compressed) but the copy hash recovery would find, '$($location.DataPath)' in '$([IO.Path]::GetFileName($location.Folder))', has the opposite form — and this folder's kit (revision $($kitRevisionOf[$f.Folder])) branches on the row, not the file. Run -Action Verify -RefreshKits to upgrade the kit, then retry." })
                    break
                }
            }
        }
    }
    return $problems.ToArray()
}

function Get-StoredFileForm {
    <#
    .SYNOPSIS
        Classifies one stored file as 'Archive' or 'Raw' from its first six
        bytes — the 7-Zip signature 37 7A BC AF 27 1C — with no hashing and no
        7-Zip (SR-049).

    .DESCRIPTION
        The BYTES are ground truth. The extension is only a claim, and the whole
        point of storage-form verification is to catch a claim that is false.
        Reading six bytes is cheap enough to do for every row in a pool.

    .PARAMETER Path
        Full path of the stored data file.

    .OUTPUTS
        [string] 'Archive', 'Raw', or 'Missing' when the file is not there.
    #>
    # Implements: SR-049, LLR-049
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'Missing' }
    $magic = [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C)
    $head  = New-Object byte[] $magic.Length
    $read  = 0
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { $read = $fs.Read($head, 0, $magic.Length) } finally { $fs.Dispose() }
    if ($read -lt $magic.Length) { return 'Raw' }
    for ($i = 0; $i -lt $magic.Length; $i++) {
        if ($head[$i] -ne $magic[$i]) { return 'Raw' }
    }
    return 'Archive'
}

function Get-StorageFormFinding {
    <#
    .SYNOPSIS
        Evaluates ONE pool folder's manifest against the bytes in that folder (and,
        for blank-DataPath rows, against the pool index) and returns one finding
        per disagreement (SR-049). Pure with respect to the store: it reads, and
        never writes.

    .DESCRIPTION
        Classes, in the order they are decided so a row yields exactly ONE finding:

          DanglingDataPath          a non-blank DataPath naming no file.
          FlagOverRaw               Compressed='Yes' over bytes that are raw.
          FlagOverArchive           Compressed='No' over bytes that are a 7z
                                    archive AND are not the row's own payload.
          NameLies                  flag and bytes agree, but the DataPath's
                                    extension claims the other form.
          PayloadMismatch           -Deep only: the stored bytes do not reproduce
                                    the row's (xxH2Hash,Length).
          BlankRowFormDisagreement  a blank-DataPath row whose Compressed
                                    disagrees with the form of the copy hash
                                    recovery would locate. REPORTED, never
                                    repaired: the "correct" value is
                                    location-dependent, and SR-050 is the durable
                                    fix. Carries the folder's kit revision,
                                    because a snapshot restored by its OWN
                                    pre-revision-2 kit is still exposed.
          Unreferenced              a data file in the folder that no row names.

        The exemption is keyed on the PAYLOAD, not on the file's name. An
        already-compressed SOURCE file (SR-004 declines to re-compress it) is
        stored raw, so its stored bytes are a 7z archive while its row correctly
        says Compressed='No' — and such a source can be called anything
        ('archive.7z.bak', a '.pack' file, an installer payload), so keying the
        exemption on a '.7z' extension alone mis-classified an UNTAMPERED store as
        FlagOverArchive and let repair set Compressed='Yes', after which restore
        expanded the user's own archive (WP5 re-review residual). A '.7z'
        RelativePath is kept only as the cheap fast path; otherwise, when the
        bytes are an archive and the row says 'No', the file's OWN bytes are
        hashed against the row's (xxH2Hash,Length): a match is correct raw storage
        and yields no finding, and only a mismatch is a genuine FlagOverArchive.

        That confirming hash runs ONLY for archive-shaped bytes under a
        Compressed='No' row — rare — so the default (non-Deep) scan stays a
        six-byte read per row. -Deep uses the same answer, so it never expands a
        file whose own bytes already reproduce the row.

    .PARAMETER Folder
        The pool folder being audited (backup root or one Snapshot_* folder).

    .PARAMETER Manifest
        That folder's own manifest rows.

    .PARAMETER Index
        A Get-BackupContentIndex result over the pool, used to resolve
        blank-DataPath rows. Omit to skip the blank-row check.

    .PARAMETER Deep
        Also prove payload identity (requires 7-Zip for archive rows). See
        SR-049 for the cost.

    .PARAMETER SevenZipPath
        7-Zip, required by -Deep when the folder holds archives.

    .OUTPUTS
        [pscustomobject[]] Folder, FolderName, RelativePath, DataPath, Class,
        Observed, Expected, Repairable, KitRevision.
    #>
    # Implements: SR-049, LLR-049
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Manifest,
        [object]$Index,
        [switch]$Deep,
        [string]$SevenZipPath
    )
    $findings  = New-Object System.Collections.Generic.List[object]
    $name      = [IO.Path]::GetFileName($Folder)
    $revision  = Get-BackupKitRevision -Folder $Folder
    $referenced = @{}

    $add = {
        param([object]$Row, [string]$Class, [string]$Observed, [string]$Expected, [bool]$Repairable)
        $findings.Add([pscustomobject]@{
            Folder = $Folder; FolderName = $name
            RelativePath = $Row.RelativePath; DataPath = $Row.DataPath
            Class = $Class; Observed = $Observed; Expected = $Expected
            Repairable = $Repairable; KitRevision = $revision
        })
    }

    foreach ($row in @($Manifest)) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) {
            if ($null -eq $Index) { continue }
            if ([string]::IsNullOrWhiteSpace($row.xxH2Hash)) { continue }
            $key = "$($row.xxH2Hash)|$($row.Length)"
            if (-not $Index.Map.ContainsKey($key)) { continue }   # absence is Test-PoolResolves' finding, not a FORM finding
            foreach ($location in $Index.Map[$key].ToArray()) {
                if (-not (Test-StorageFormAgreement -Compressed $row.Compressed -RelativePath $row.RelativePath -DataPath $location.DataPath)) {
                    & $add $row 'BlankRowFormDisagreement' `
                        "the pool copy '$($location.DataPath)' in '$([IO.Path]::GetFileName($location.Folder))'" `
                        "Compressed=$($row.Compressed)" $false
                    break
                }
            }
            continue
        }

        $referenced[$row.DataPath] = $true
        $full     = Join-Path $Folder $row.DataPath
        $observed = Get-StoredFileForm -Path $full
        if ($observed -eq 'Missing') {
            & $add $row 'DanglingDataPath' 'no file' "a file at '$($row.DataPath)'" $false
            continue
        }

        # THE exemption: a row whose stored bytes ARE the source file's own bytes
        # is correct even when those bytes look like an archive — the user's own
        # file happened to be one (SR-004 declines to re-compress it). The
        # exemption is keyed on the PAYLOAD, not on the name: a '.7z' extension is
        # only the cheap fast path for the common case, because an
        # already-compressed source can be called anything ('archive.7z.bak', a
        # '.pack' file, an installer payload).
        #
        # Cost: the confirming hash runs ONLY for a file whose bytes are an
        # archive while its row says Compressed='No' — rare — so the default
        # (non-Deep) scan stays a six-byte read per row.
        $rawArchiveOk = $null      # $null = not asked; $true/$false = own bytes (mis)match the row
        $exempt = ([IO.Path]::GetExtension([string]$row.RelativePath) -ieq '.7z')
        if (-not $exempt -and $observed -eq 'Archive' -and $row.Compressed -ne 'Yes' -and
            -not [string]::IsNullOrWhiteSpace($row.xxH2Hash)) {
            $rawArchiveOk = ((Get-Item -LiteralPath $full).Length -eq [long]$row.Length -and
                             (Get-FileXxHash -FilePath $full) -eq $row.xxH2Hash)
            if ($rawArchiveOk) { $exempt = $true }
        }
        if (-not $exempt) {
            $claimed  = if ($row.Compressed -eq 'Yes') { 'Archive' } else { 'Raw' }
            $nameForm = if ([IO.Path]::GetExtension([string]$row.DataPath) -ieq '.7z') { 'Archive' } else { 'Raw' }
            if ($claimed -ne $observed) {
                $class = if ($observed -eq 'Raw') { 'FlagOverRaw' } else { 'FlagOverArchive' }
                & $add $row $class $observed $claimed $true
                continue
            }
            if ($nameForm -ne $observed) {
                & $add $row 'NameLies' $observed "a name meaning $nameForm" $true
                continue
            }
        }
        if ($Deep) {
            $payloadOk = $false
            if ($observed -eq 'Archive') {
                # Archive-shaped bytes that ARE the row's payload (an
                # already-compressed source stored raw) prove themselves without
                # 7-Zip — and must not be expanded, which would compare the
                # user's archive against its own inner file. Only bytes that do
                # NOT reproduce the row are worth expanding.
                if ($null -eq $rawArchiveOk -and $row.Compressed -ne 'Yes' -and
                    -not [string]::IsNullOrWhiteSpace($row.xxH2Hash)) {
                    $rawArchiveOk = ((Get-Item -LiteralPath $full).Length -eq [long]$row.Length -and
                                     (Get-FileXxHash -FilePath $full) -eq $row.xxH2Hash)
                }
                if ($rawArchiveOk -eq $true) {
                    $payloadOk = $true
                } else {
                    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                    try {
                        Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $full -DestinationFile $tmp
                        $payloadOk = ((Get-Item -LiteralPath $tmp).Length -eq [long]$row.Length -and
                                      (Get-FileXxHash -FilePath $tmp) -eq $row.xxH2Hash)
                    } catch {
                        $payloadOk = $false
                    } finally {
                        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    }
                }
            } else {
                $payloadOk = ((Get-Item -LiteralPath $full).Length -eq [long]$row.Length -and
                              (Get-FileXxHash -FilePath $full) -eq $row.xxH2Hash)
            }
            if (-not $payloadOk) {
                & $add $row 'PayloadMismatch' 'other bytes' "(hash=$($row.xxH2Hash), length=$($row.Length))" $false
            }
        }
    }

    # Bytes in the folder that no row explains. Enumerated through Get-DataFile,
    # so root-level infrastructure is excluded and a NESTED file named like
    # infrastructure is still data (B6 / SN-018).
    $rootPrefix = (Resolve-Path -LiteralPath $Folder).Path
    foreach ($file in @(Get-DataFile -Root $Folder)) {
        $rel = $file.FullName.Substring($rootPrefix.Length).TrimStart('\', '/')
        if ($referenced.ContainsKey($rel)) { continue }
        $findings.Add([pscustomobject]@{
            Folder = $Folder; FolderName = $name
            RelativePath = ''; DataPath = $rel
            Class = 'Unreferenced'; Observed = 'a data file no manifest row names'; Expected = ''
            Repairable = $false; KitRevision = $revision
        })
    }

    return $findings.ToArray()
}

function Get-BackupKitRevision {
    <#
    .SYNOPSIS
        Reads the '# KitRevision: <n>' marker out of the RECONSTRUCT.ps1 bundled
        in a pool folder, so a finding can say which restore kit that folder
        carries (SR-049).
    .DESCRIPTION
        A snapshot keeps the kit it was written with forever; the SR-050 fix
        reaches only folders written by revision 2 or later. Folders written
        before the marker existed report 1.
    .PARAMETER Folder
        The pool folder.
    .OUTPUTS
        [int] the revision, or 0 when the folder carries no restore kit at all.
    #>
    # Implements: SR-049, LLR-049
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)
    $kit = Join-Path $Folder $script:Def.ReconstructPs1Name
    if (-not (Test-Path -LiteralPath $kit -PathType Leaf)) { return 0 }
    # ReadAllLines, not the lazy ReadLines: PowerShell does not dispose a lazy
    # enumerator on an early return, and the leaked handle inside a snapshot
    # folder blocked that folder's prune commit rename with access-denied
    # (WP7 — the rail gate made prune the first caller that renames after).
    foreach ($line in [IO.File]::ReadAllLines($kit)) {
        if ($line -match '^\s*#\s*KitRevision:\s*(\d+)') { return [int]$Matches[1] }
    }
    return 1
}

function Test-BackupStorageForm {
    <#
    .SYNOPSIS
        Audits a whole backup pool — the live backup root and, by default, every
        Snapshot_* folder — for disagreements between what the index says about a
        row's storage form and what the bytes actually are (SR-049). Mutates
        nothing.

    .DESCRIPTION
        Never called by a normal backup run: a physical verify inside every
        migration would fight SR-024 idempotence and run-time cost, so this is a
        separate opt-in action (TC-094 pins that no verification symbol is
        reachable from Invoke-BackupSet).

    .PARAMETER BackupRoot
        The live backup root.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders. Ignored under
        -BackupRootOnly.

    .PARAMETER BackupRootOnly
        Audit only the backup root — the fast pass. The default includes every
        snapshot, because that is where the SR-050 defect lives.

    .PARAMETER Deep
        Also prove payload identity for every row (SR-049); needs 7-Zip.

    .PARAMETER SevenZipPath
        7-Zip, required by -Deep.

    .OUTPUTS
        [pscustomobject[]] the findings, backup root first then snapshots in name
        order. Empty means the pool's storage form is coherent.
    #>
    # Implements: SR-049, SR-038, SR-040, SR-061, LLR-049, LLR-060
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$ChangeRoot,
        [switch]$BackupRootOnly,
        [switch]$Deep,
        [string]$SevenZipPath
    )
    if (-not (Test-Path -LiteralPath (Join-Path $BackupRoot $script:Def.DatabaseFilename) -PathType Leaf)) {
        throw "No manifest at '$BackupRoot': there is nothing to verify."
    }
    if ($Deep -and (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf))) {
        throw "-Deep proves payload identity and needs 7-Zip, which was not found at '$SevenZipPath'."
    }

    $snapshots = @()
    if (-not $BackupRootOnly -and $ChangeRoot -and (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
        $snapshots = @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | Where-Object { $_ } | ForEach-Object { $_.FullName })
    }
    # The index always spans the whole pool, even under -BackupRootOnly: a blank
    # row's bytes may live in a folder we are not auditing, and resolving it
    # against a partial pool would invent findings.
    $poolSnapshots = if ($ChangeRoot -and (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
        # Where-Object first: piping a $null result into ForEach-Object yields one
        # $null iteration, and @($null) casts to [string[]] as @('') (AGENTS.md §4).
        @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | Where-Object { $_ } | ForEach-Object { $_.FullName })
    } else { @() }
    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder $poolSnapshots

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($folder in @($BackupRoot) + $snapshots) {
        $manifest = Read-Manifest -FolderPath $folder
        # SR-061: rows in the legacy path-addressed form mark a store written
        # by a pre-content-addressed build. Backup REFUSES such a store
        # (Test-BackupManifest); an audit that refused would be useless, so
        # Verify reports it — one per-folder finding (exit 1), never a throw.
        # Added here, not in Get-StorageFormFinding, so the per-row form
        # classes keep their one-finding-per-row contract and -RepairStorage
        # (which consumes the per-row scan) never sees it.
        $legacyRows = @($manifest | Where-Object { $_.StoredAsHashSize -eq 'Original' })
        if ($legacyRows.Count -gt 0) {
            $all.Add([pscustomobject]@{
                Folder = $folder; FolderName = [IO.Path]::GetFileName($folder)
                RelativePath = $legacyRows[0].RelativePath; DataPath = $legacyRows[0].DataPath
                Class = 'LegacyStoredForm'
                Observed = "$($legacyRows.Count) row(s) stored in the legacy path-addressed form (StoredAsHashSize='Original')"
                Expected = "every row content-addressed ('Hash'); this store was written by a pre-content-addressed build — back up to a fresh BackupPath (SR-061)"
                Repairable = $false; KitRevision = Get-BackupKitRevision -Folder $folder
            })
        }
        foreach ($f in @(Get-StorageFormFinding -Folder $folder -Manifest $manifest -Index $index -Deep:$Deep -SevenZipPath $SevenZipPath)) {
            $all.Add($f)
        }
    }
    return $all.ToArray()
}

function Repair-BackupStorageForm {
    <#
    .SYNOPSIS
        Makes the index agree with the bytes for the findings that are
        unambiguous from the row's OWN folder, taking the physical bytes as
        ground truth (SR-049).

    .DESCRIPTION
        Repairs exactly two things and never anything else: the Compressed
        column, and the data file's NAME so it stops lying about its form. It
        never re-packs or re-compresses content, never edits the six logical
        columns (RelativePath, Length, LastWriteTimeStr, xxH2Hash, Duplicate,
        MediaMBPerSec), and never migrates layout.

        BlankRowFormDisagreement, DanglingDataPath, PayloadMismatch and
        Unreferenced are reported and never repaired — for the blank-row class
        the "correct" value is location-dependent and SR-050 is the durable fix;
        for the others the evidence is not in the row's own folder.

        Findings are per ROW, but a repair renames a PHYSICAL file — and dedup
        means several rows can name the SAME file. Repairs are therefore grouped
        by (Folder, DataPath): the rename happens ONCE and EVERY row that
        referenced the old path adopts the observed form. Repairing row by row
        renamed the file for the first row and then saw 'Missing' for the second,
        leaving it dangling and unrestorable — the same lesson
        the layout migration learned in ddf52ab (WP5 review, finding H1),
        before that migration was deleted whole (SR-061).

        A rename that would produce a ROOT-LEVEL infrastructure name is refused
        (SR-022 / B6), and every touched folder is persisted through
        Write-Manifest so its SR-038 witness is re-stamped by the one writer —
        never Export-Csv, never a direct Write-ManifestWitness call.

    .PARAMETER BackupRoot
        The live backup root.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .PARAMETER BackupRootOnly
        Repair only the backup root.

    .PARAMETER Log
        Logger scriptblock (message, level).

    .OUTPUTS
        [pscustomobject] Repaired (count), Skipped (the findings left alone) and
        Findings (the pre-repair audit).
    #>
    # Implements: SR-049, SR-024, SR-038, LLR-049
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$ChangeRoot,
        [switch]$BackupRootOnly,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $findings = @(Test-BackupStorageForm -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot -BackupRootOnly:$BackupRootOnly)
    $repaired = 0
    $skipped  = New-Object System.Collections.Generic.List[object]

    foreach ($group in ($findings | Group-Object Folder)) {
        $folder   = $group.Name
        $manifest = @(Read-Manifest -FolderPath $folder)
        $dirty    = $false

        # ONE physical file per group: the rename is done once and every row
        # naming that file adopts the result (finding H1).
        foreach ($byPath in ($group.Group | Group-Object DataPath)) {
            $dataPath   = [string]$byPath.Name
            $repairable = @($byPath.Group | Where-Object { $_.Repairable })
            foreach ($f in @($byPath.Group | Where-Object { -not $_.Repairable })) { $skipped.Add($f) }
            if ($repairable.Count -eq 0) { continue }

            # EVERY row that references this physical file, not just the ones
            # that produced a finding — a row exempted by the '.7z' source rule
            # still has to follow its data file through a rename.
            $rows = @($manifest | Where-Object { $_.DataPath -eq $dataPath })
            if ($rows.Count -eq 0) { foreach ($f in $repairable) { $skipped.Add($f) }; continue }

            $full     = Join-Path $folder $dataPath
            $observed = Get-StoredFileForm -Path $full
            if ($observed -eq 'Missing') { foreach ($f in $repairable) { $skipped.Add($f) }; continue }

            # The row loop below rewrites Compressed for EVERY row naming this
            # file, including rows that produced no finding — so it needs the
            # SAME payload-keyed exemption Get-StorageFormFinding applies. Read
            # the bytes' identity ONCE, and BEFORE any rename moves them.
            $ownHash = $null; $ownLength = ''
            if ($observed -eq 'Archive') {
                $ownLength = [string](Get-Item -LiteralPath $full).Length
                $ownHash   = Get-FileXxHash -FilePath $full
            }

            # The bytes decide both columns. Rename only when the name's claim
            # differs from what the bytes are.
            $newCompressed = if ($observed -eq 'Archive') { 'Yes' } else { 'No' }
            $newDataPath   = $dataPath
            $nameIsArchive = ([IO.Path]::GetExtension($dataPath) -ieq '.7z')
            if ($observed -eq 'Archive' -and -not $nameIsArchive) { $newDataPath = "$dataPath.7z" }
            if ($observed -eq 'Raw'     -and $nameIsArchive)      { $newDataPath = $dataPath.Substring(0, $dataPath.Length - 3) }

            if ($newDataPath -ne $dataPath) {
                $target = Join-Path $folder $newDataPath
                if (Test-IsInfrastructureFile -Root $folder -FullPath ([IO.Path]::GetFullPath($target))) {
                    & $Log "Refusing to rename '$dataPath' to the root-level infrastructure name '$newDataPath' (SR-022)." 'WARN'
                    foreach ($f in $repairable) { $skipped.Add($f) }; continue
                }
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    & $Log "Refusing to rename '$dataPath' to '$newDataPath': a file is already there." 'WARN'
                    foreach ($f in $repairable) { $skipped.Add($f) }; continue
                }
                if ($PSCmdlet.ShouldProcess($target, "rename '$dataPath' so its name matches its bytes")) {
                    Move-Item -LiteralPath $full -Destination $target -Force
                } else { foreach ($f in $repairable) { $skipped.Add($f) }; continue }
            }

            foreach ($row in $rows) {
                # A row whose stored bytes ARE its own payload is an
                # already-compressed SOURCE file: its Compressed column is not a
                # disagreement, and rewriting it from the bytes would make the
                # restorer expand the user's archive. Keyed on the payload, with
                # a '.7z' RelativePath as the fast path — the source can be named
                # anything. Such a row still follows the file through the rename.
                $exempt = ([IO.Path]::GetExtension([string]$row.RelativePath) -ieq '.7z') -or
                          ($null -ne $ownHash -and $ownHash -eq $row.xxH2Hash -and $ownLength -eq [string]$row.Length)
                & $Log ("Repaired '$([IO.Path]::GetFileName($folder))' row '$($row.RelativePath)': " +
                        "Compressed $($row.Compressed) -> $(if ($exempt) { $row.Compressed } else { $newCompressed }), " +
                        "DataPath '$dataPath' -> '$newDataPath'.") 'INFO'
                $row.DataPath = $newDataPath
                if (-not $exempt) { $row.Compressed = $newCompressed }
            }
            $dirty = $true
            $repaired += $repairable.Count
        }

        # One write per folder, through the SOLE manifest writer, so the SR-038
        # witness is re-stamped with it (never a caller-side stamp).
        if ($dirty -and $PSCmdlet.ShouldProcess($folder, 'persist the repaired manifest')) {
            Write-Manifest -FolderPath $folder -Records $manifest
        }
    }

    return [pscustomobject]@{ Repaired = $repaired; Skipped = $skipped.ToArray(); Findings = $findings }
}

function Update-BackupSnapshotKit {
    <#
    .SYNOPSIS
        Re-copies the backup root's current restore-kit artifacts into every
        Snapshot_* folder — the only mechanism that retires an old kit from a
        snapshot written before the SR-050 fix (SR-049, plan §5 / decision Q3).

    .DESCRIPTION
        Opt-in and NEVER default: it rewrites files inside immutable snapshot
        folders, which is a deliberate operator act.

        Copies exactly the six kit artifacts Complete-ChangeFolder copies and
        NOTHING else. The manifest witness (MANIFEST.csv.meta) is emphatically
        NOT one of them: each snapshot witnesses its OWN manifest, and copying
        the root's over it is the single most dangerous mistake available here
        (AGENTS.md §3, pinned by TC-067).

    .PARAMETER BackupRoot
        The live backup root, whose kit is the current one.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .PARAMETER Log
        Logger scriptblock (message, level).

    .OUTPUTS
        [pscustomobject] Refreshed (folder count) and Revision (the kit revision
        now present in each).
    #>
    # Implements: SR-049, SR-007, SR-038, LLR-049
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $artifacts = @($script:Def.ReconstructPs1Name, $script:Def.ReconstructBatName,
                   $script:Def.ReconstructShName, $script:Def.CommonModuleName,
                   'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')
    $refreshed = 0
    foreach ($snapshot in @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | Where-Object { $_ })) {
        if (-not $PSCmdlet.ShouldProcess($snapshot.FullName, 'refresh the bundled restore kit')) { continue }
        foreach ($artifact in $artifacts) {
            $src = Join-Path $BackupRoot $artifact
            if (Test-Path -LiteralPath $src -PathType Leaf) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $snapshot.FullName $artifact) -Force
            }
        }
        & $Log "Refreshed the restore kit in '$($snapshot.Name)' (the manifest witness was NOT copied)." 'INFO'
        $refreshed++
    }
    return [pscustomobject]@{ Refreshed = $refreshed; Revision = (Get-BackupKitRevision -Folder $BackupRoot) }
}

function Get-PruneCapacityRefusal {
    <#
    .SYNOPSIS
        The prune capacity rail: proves each destination VOLUME has room for the
        bytes the plan would copy into it, measured through Common's
        cross-platform probes (SR-046, SR-052).

    .DESCRIPTION
        Items are grouped by Get-VolumeIdentity, not by `Split-Path -Qualifier`:
        that cmdlet cannot parse a UNC or rooted POSIX path ("does not have a
        qualifier specified"), and WP4 asked it for one inside a Group-Object
        key — terminating under the entry point's $ErrorActionPreference='Stop',
        and otherwise yielding an empty drive name that the Get-PSDrive fallback
        rejected into a swallowing catch. Either way the rail silently did not
        exist on a UNC store (AGENTS.md §4). Get-VolumeIdentity and
        Get-FreeSpaceBytes never throw.

        An unmeasurable volume ($null free space) SKIPS the check rather than
        refusing: not being able to measure a volume is not evidence that it is
        full (SR-052). Two destinations on the same volume are summed once.

    .PARAMETER Item
        The plan items (each with DestinationFolder and Bytes). May be empty.

    .PARAMETER PlanName
        The snapshot being planned, for the refusal message.

    .OUTPUTS
        [pscustomobject] Code=2 / Kind='capacity' / Message per short volume;
        empty when every destination volume has room or cannot be measured.
    #>
    # Implements: SR-046, SR-052, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Item,
        [string]$PlanName
    )
    $refusals = New-Object System.Collections.Generic.List[object]
    if (-not $Item) { return $refusals.ToArray() }

    $byVolume = [ordered]@{}
    foreach ($entry in $Item) {
        $folder = [string]$entry.DestinationFolder
        $volume = Get-VolumeIdentity -Path $folder
        # An unidentifiable volume still gets its own bucket keyed by folder, so
        # the free-space probe is at least attempted for it.
        $key = if ($volume) { $volume } else { $folder }
        if (-not $byVolume.Contains($key)) {
            $byVolume[$key] = [pscustomobject]@{ Probe = $folder; Needed = [long]0 }
        }
        $byVolume[$key].Needed += [long]$entry.Bytes
    }

    foreach ($key in @($byVolume.Keys)) {
        $group = $byVolume[$key]
        $free  = Get-FreeSpaceBytes -Path $group.Probe
        if ($null -eq $free) {
            Write-Verbose "Capacity rail skipped for '$key': the volume could not be measured."
            continue
        }
        if ($free -lt $group.Needed) {
            $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'capacity'
                Message = "Not enough free space on '$key' to re-home '$PlanName': required $($group.Needed), free $free." })
        }
    }
    return $refusals.ToArray()
}

function Assert-PrunePrecondition {
    <#
    .SYNOPSIS
        Every rail snapshot removal must clear, evaluated before a single byte
        moves; returns the full set of refusals with their SR-040 codes (SR-046).

    .DESCRIPTION
        Returns rather than throws on the first problem — Remove-BackupSnapshot
        applies the 2 > 3 > 4 > 1 precedence over the whole set, and -WhatIf can
        report every refusal at once instead of one per invocation.

        Rails: the plan's own problems (unknown target, an infrastructure name or
        a colliding file at the destination); the SR-035 run-state gate; no Temp
        staging folder in the change root (SR-017 mutual exclusion, so a
        concurrent backup aborts on the existing guard); no unreferenced data
        files in the target unless -DiscardUnreferencedData; the whole pool
        already resolves (Test-PoolResolves — prune refuses to prune INTO a
        broken or form-disagreeing pool and hands the repro on); free space at
        every destination volume through Get-PruneCapacityRefusal (Common's
        cross-platform probes — an unmeasurable volume skips, never refuses);
        7-Zip when a compressed row must be verified;
        and Test-ManifestWitness Verified for every manifest in the pool, with
        Absent refused unless -AllowUnverifiedIndex (the deliberate inverse of
        the restore default: restoring against an unverified index is
        recoverable, deleting against one is not).

    .PARAMETER Plan
        The Get-SnapshotPrunePlan result for the target snapshot.

    .OUTPUTS
        [pscustomobject] Code / Kind / Message per refusal; empty means go.
    #>
    # Implements: SR-046, SR-035, SR-039, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][object]$Plan,
        [string]$SevenZipPath,
        [switch]$SkipContentVerify,
        [switch]$AllowUnverifiedIndex,
        [switch]$DiscardUnreferencedData
    )
    $refusals = New-Object System.Collections.Generic.List[object]
    foreach ($problem in $Plan.Problems.ToArray()) { $refusals.Add($problem) }
    if (-not $Plan.Folder) { return $refusals.ToArray() }

    # SR-035 run-state gate: a store whose history cannot be dated safely must
    # not be edited at all, let alone have a dated state deleted.
    try {
        $state = Read-BackupState -BackupRoot $BackupRoot
        if (-not $state['LastBackupRun'] -and @(Read-Manifest -FolderPath $BackupRoot).Count -gt 0) {
            $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'run-state'
                Message = "The backup state at '$BackupRoot' has no LastBackupRun but its manifest has rows; snapshot history cannot be dated safely (SR-035)." })
        }
    } catch {
        $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'run-state'
            Message = "The backup state at '$BackupRoot' could not be read: $($_.Exception.Message)" })
    }

    $staging = Join-Path $ChangeRoot 'Temp'
    if (Test-Path -LiteralPath $staging -PathType Container) {
        $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'staging-busy'
            Message = "A staging folder is present at '$staging' — a backup is running or a previous run failed. Prune and backup are mutually exclusive (SR-017)." })
    }

    if ($Plan.UnreferencedData.Count -gt 0 -and -not $DiscardUnreferencedData) {
        $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'unreferenced-data'
            Message = ("'$($Plan.Name)' holds $($Plan.UnreferencedData.Count) data file(s) its own manifest does not reference (" +
                       (($Plan.UnreferencedData | Select-Object -First 3) -join ', ') +
                       "). Those bytes are unexplained; pass -DiscardUnreferencedData to discard them deliberately.") })
    }

    foreach ($problem in (Test-PoolResolves -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot)) {
        $refusals.Add([pscustomobject]@{ Code = 2; Kind = $problem.Kind
            Message = ("The pool does not resolve as it stands, so it must not be pruned: $($problem.Message) " +
                       "This blocks EVERY prune in this store until it is resolved — run '-Action Verify' to enumerate the damage.") })
    }

    $items = $Plan.Items.ToArray()
    foreach ($refusal in (Get-PruneCapacityRefusal -Item $items -PlanName $Plan.Name)) { $refusals.Add($refusal) }

    if (-not $SkipContentVerify -and @($items | Where-Object { $_.Compressed -eq 'Yes' }).Count -gt 0) {
        if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
            $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'no-7zip'
                Message = "Re-homing '$($Plan.Name)' moves compressed data, whose content cannot be verified without 7-Zip (looked for '$SevenZipPath'). Install it or pass -SkipContentVerify." })
        }
    }

    foreach ($f in $Plan.Index.Folders) {
        $verdict = Test-ManifestWitness -FolderPath $f.Folder
        switch ($verdict.Status) {
            'Verified' { }
            'Absent'   {
                if (-not $AllowUnverifiedIndex) {
                    $refusals.Add([pscustomobject]@{ Code = 3; Kind = 'witness-absent'
                        Message = "'$($f.Name)' has no manifest witness, so its index cannot be proven intact. Deleting against an unverified index is not recoverable; pass -AllowUnverifiedIndex to accept that risk." })
                }
            }
            default    {
                $refusals.Add([pscustomobject]@{ Code = 3; Kind = 'witness-mismatch'
                    Message = "'$($f.Name)': $($verdict.Detail)" })
            }
        }
    }

    return $refusals.ToArray()
}

function Get-BackupSnapshot {
    <#
    .SYNOPSIS
        Read-only inventory of the dated snapshots in a store, with the
        dedup-aware reclaim figures only this tool can compute (SR-047).

    .DESCRIPTION
        Mutates nothing. BytesReclaimed is what removing that snapshot NOW would
        actually free across the whole store (its physical size less the bytes
        that must first be re-homed into the surviving pool), and BytesReHomed
        is the copy cost — both taken from the same Get-SnapshotPrunePlan the
        real removal executes, so the reported figure is the achieved figure by
        construction.

    .PARAMETER BackupRoot
        The live backup root.

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .OUTPUTS
        [pscustomobject] per snapshot, oldest first: Name, Date, Rows,
        PhysicalBytes, BytesReclaimed, BytesReHomed.
    #>
    # Implements: SR-047, LLR-047
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot
    )
    foreach ($snapshot in (Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot)) {
        $plan = Get-SnapshotPrunePlan -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot -Name $snapshot.Name
        [pscustomobject]@{
            Name           = $snapshot.Name
            Date           = $plan.Date
            Rows           = $plan.Rows
            PhysicalBytes  = $plan.PhysicalBytes
            BytesReclaimed = $plan.BytesReclaimed
            BytesReHomed   = $plan.BytesReHomed
        }
    }
}

function Remove-CommittedPruneResidue {
    <#
    .SYNOPSIS
        Finishes a prior, already-COMMITTED deletion of one named snapshot: a
        leftover 'Pruning_<name>' folder is past the commit point, invisible to
        every consumer, and only its deletion remains (SR-046).

    .DESCRIPTION
        Scoped to the name being pruned, deliberately. It runs before that name
        is planned — the plan cannot be computed while the folder still occupies
        the name, and finishing the caller's OWN previous instruction for THIS
        name is the only mutation any prune performs outside the transaction.
        Residue for any other name is left alone, so a refused prune of one
        snapshot never touches another's.

        The folder is already outside the ^Snapshot_ namespace, so no restorer,
        inventory or Optimize-ChangeFolders can see it and nothing referenced it
        (the pool was proven redundant before the rename).

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .PARAMETER Name
        The snapshot name whose committed deletion should be completed.

    .OUTPUTS
        [int] 1 when a residue folder was deleted, otherwise 0.
    #>
    # Implements: SR-046, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { return 0 }
    $residue = Join-Path $ChangeRoot ('Pruning_' + $Name)
    if (-not (Test-Path -LiteralPath $residue -PathType Container)) { return 0 }

    & $Log "Completing an interrupted prune: removing 'Pruning_$Name' (already past the commit point)." 'WARN'
    Remove-Item -LiteralPath $residue -Recurse -Force
    return 1
}

function Invoke-PruneEntrySweep {
    <#
    .SYNOPSIS
        Removes the '*.fbprune.tmp' staged copies an interrupted prune left
        behind — and ONLY those, never a user file that merely bears the suffix
        (SR-046).

    .DESCRIPTION
        Runs INSIDE the transaction, after every rail has passed and the Temp
        lock is held, so a refusal never mutates and a failure here classifies as
        the retriable code 4 like any other host I/O problem.

        The guard is the manifest, not the name. A staged copy is by
        construction UNREFERENCED — Copy-ReHomedDataFile writes
        '<destination>.fbprune.tmp' and only publishes it by rename — whereas a
        genuine user file called 'notes.fbprune.tmp' carries a manifest row, and
        in a legacy path-addressed store is stored at that verbatim path (which
        prune still serves - SR-061 refuses only WRITING to one). Deleting by
        bare suffix therefore destroyed real content in the backup root and in
        every snapshot at once (WP4 review, finding H1); a file its own folder's
        manifest references is data and is never swept.

        Only pool folders are scanned (the backup root and each Snapshot_*),
        because those are the only re-home destinations.

    .PARAMETER BackupRoot
        The live backup root — a re-home destination, so it can hold a staged copy.

    .PARAMETER ChangeRoot
        The change root, which holds the snapshot folders.

    .OUTPUTS
        [int] the number of staged copies removed.
    #>
    # Implements: SR-046, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $normalize = { param([string]$Value) ($Value -replace '[\\/]+', '/').Trim('/') }
    $removed = 0
    $folders = @($BackupRoot) + @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | ForEach-Object { $_.FullName })
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        $referenced = @{}
        foreach ($row in @(Read-Manifest -FolderPath $folder)) {
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) { $referenced[(& $normalize $row.DataPath)] = $true }
        }
        $prefix = (Resolve-Path -LiteralPath $folder).Path
        # -Force (SR-057): hidden residue would otherwise never be swept.
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force -Filter '*.fbprune.tmp')) {
            $rel = & $normalize $file.FullName.Substring($prefix.Length)
            if ($referenced[$rel]) { continue }   # real content that merely ends in '.fbprune.tmp'
            & $Log "Removing an interrupted prune's staged copy '$($file.FullName)'." 'WARN'
            Remove-Item -LiteralPath $file.FullName -Force
            $removed++
        }
    }
    return $removed
}

function Copy-ReHomedDataFile {
    <#
    .SYNOPSIS
        Materializes one re-homed data file at its destination: copy to
        '<destination>.fbprune.tmp' on the same volume, verify, then publish by
        atomic rename (SR-045/SR-046 phase 1).

    .DESCRIPTION
        Stored-form identity (length + xxHash128 of the copy against the source)
        is always checked. Content identity — the copy's payload really is the
        row's (xxH2Hash, Length), expanding a '.7z' to a temp file first, exactly
        Find-DataFileByHash's check — is checked unless -SkipContentVerify.

        A destination file that is already there and already identical is an
        interrupted run's completed copy (Get-SnapshotPrunePlan proved the bytes
        match), so this is a no-op and the row edit still publishes.

    .PARAMETER Item
        One Get-SnapshotPrunePlan item.

    .OUTPUTS
        [string] the published destination path.
    #>
    # Implements: SR-045, LLR-045
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [string]$SevenZipPath,
        [switch]$SkipContentVerify
    )
    $destFull = Join-Path $Item.DestinationFolder $Item.DestinationDataPath
    if (Test-Path -LiteralPath $destFull -PathType Leaf) { return $destFull }

    $destDir = [System.IO.Path]::GetDirectoryName($destFull)
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $temp = "$destFull.fbprune.tmp"
    Copy-Item -LiteralPath $Item.SourceFullPath -Destination $temp -Force

    $sourceInfo = Get-Item -LiteralPath $Item.SourceFullPath
    $copyInfo   = Get-Item -LiteralPath $temp
    if ($copyInfo.Length -ne $sourceInfo.Length) {
        throw "Re-homed copy of '$($Item.SourceDataPath)' is $($copyInfo.Length) bytes, source is $($sourceInfo.Length)."
    }
    if ((Get-FileXxHash -FilePath $temp) -ne (Get-FileXxHash -FilePath $Item.SourceFullPath)) {
        throw "Re-homed copy of '$($Item.SourceDataPath)' does not hash equal to its source."
    }

    if (-not $SkipContentVerify) {
        $payload = $temp
        $scratch = $null
        try {
            if ($Item.Compressed -eq 'Yes') {
                $scratch = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $temp -DestinationFile $scratch
                $payload = $scratch
            }
            $payloadInfo = Get-Item -LiteralPath $payload
            if ($payloadInfo.Length -ne [long]$Item.SourceRow.Length -or
                (Get-FileXxHash -FilePath $payload) -ne $Item.SourceRow.xxH2Hash) {
                throw "Re-homed content for '$($Item.SourceRow.RelativePath)' does not match its manifest (hash,length)."
            }
        } finally {
            if ($scratch) { Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue }
        }
    }

    Move-Item -LiteralPath $temp -Destination $destFull -Force
    return $destFull
}

function Publish-PruneManifest {
    <#
    .SYNOPSIS
        Points each destination row at its re-homed file and persists every
        touched manifest through Write-Manifest (SR-045/SR-046 phase 2), which
        re-stamps the SR-038 witness by its one writer.

    .DESCRIPTION
        Only DataPath, Compressed and StoredAsHashSize are ever assigned, and
        only on rows the plan named: no row is added, removed or reordered, and
        the six logical columns are untouched. MANIFEST.csv.meta is never copied
        between folders — each folder's witness is stamped for its own manifest.

    .PARAMETER Plan
        The Get-SnapshotPrunePlan result whose items have been materialized.

    .OUTPUTS
        [string[]] the folders whose manifests were rewritten.
    #>
    # Implements: SR-045, SR-038, LLR-045
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $touched = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Plan.Items.ToArray()) {
        $item.DestinationRow.DataPath         = $item.DestinationDataPath
        $item.DestinationRow.Compressed       = $item.Compressed
        $item.DestinationRow.StoredAsHashSize = $item.StoredAsHashSize
        if (-not $touched.Contains($item.DestinationFolder)) { $touched.Add($item.DestinationFolder) }
    }
    foreach ($folder in $touched) {
        & $Log "Re-homed data published into '$folder'; rewriting its manifest." 'INFO'
        Write-Manifest -FolderPath $folder -Records $Plan.Manifests[$folder]
    }
    return $touched.ToArray()
}

function Complete-PruneDeletion {
    <#
    .SYNOPSIS
        The commit point: renames the snapshot out of the ^Snapshot_ namespace
        to 'Pruning_<name>' — which fails the pattern Reconstruct.ps1,
        reconstruct.sh AND Optimize-ChangeFolders all use, so one atomic rename
        removes it from every consumer's view — and then deletes it (SR-046).

    .PARAMETER SnapshotFolder
        Full path of the snapshot folder to remove.

    .OUTPUTS
        None.
    #>
    # Implements: SR-046, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotFolder,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $parent      = [System.IO.Path]::GetDirectoryName($SnapshotFolder)
    $pruningName = 'Pruning_' + [System.IO.Path]::GetFileName($SnapshotFolder)
    Rename-Item -LiteralPath $SnapshotFolder -NewName $pruningName
    & $Log "Commit point passed: '$([System.IO.Path]::GetFileName($SnapshotFolder))' is no longer visible to any restorer." 'INFO'
    Remove-Item -LiteralPath (Join-Path $parent $pruningName) -Recurse -Force
}

function Remove-BackupSnapshot {
    <#
    .SYNOPSIS
        Removes one or more dated snapshots, re-homing any content whose only
        physical copy they hold into the surviving pool first, and proving the
        pool still resolves before the folder is deleted (SR-045/SR-046).

    .DESCRIPTION
        HomeHub owns retention POLICY; this is the mechanism (IF-001). Named
        snapshots only — no -KeepLast/-OlderThan, no wildcards. Each name is an
        independent transaction, processed in the order given; the batch outcome
        is the worst code by the SR-040 precedence 2 > 3 > 4 > 1.

        Ordering (the invariant is that the pool goes redundant, then the
        snapshot disappears — never deficient): complete a prior COMMITTED
        deletion of this same name if one is outstanding; plan; check every
        rail; take the Temp lock; sweep any staged copies an interrupted run
        left; materialize each re-homed file; publish the destination manifests;
        prove every surviving row resolves with the target excluded; only then
        commit and delete.

        Exactly one thing happens before the rails, and only for the name being
        pruned: Remove-CommittedPruneResidue finishes an outstanding
        'Pruning_<name>' deletion, which is past the point of no return and
        already invisible to every consumer (the plan cannot even be computed
        while it holds the name). Everything else — the staged-copy sweep
        included (WP4 review, findings H2/M1) — happens inside the transaction,
        so a refusal (code 2/3) genuinely mutates nothing and a host failure in
        the sweep classifies as the retriable code 4 rather than escaping
        unclassified.

        -WhatIf runs the full preflight and reports the classification and the
        reclaim figures the real run would achieve, mutating nothing at all:
        neither the residue completion nor the sweep runs, so nothing is logged
        or counted that did not happen. ConfirmImpact is Medium so an automated
        run never prompts.

    .PARAMETER Name
        Exact snapshot folder name(s). See SR-046 for the containment rules.

    .PARAMETER SkipContentVerify
        Verify only stored-form identity of each copy, not that its payload
        hashes to the row's (xxH2Hash, Length).

    .PARAMETER AllowUnverifiedIndex
        Proceed when a pool manifest has no witness at all (a backup predating
        SR-038). A witness that MISMATCHES still refuses.

    .PARAMETER DiscardUnreferencedData
        Accept data files in the target that its own manifest does not
        reference, discarding them with the folder.

    .OUTPUTS
        [pscustomobject] per name: Name, Status (Pruned|Refused|WhatIf), Code,
        BytesReclaimed, BytesReHomed, ReHomeDestinations, Refusals, Message.
    #>
    # Implements: SR-045, SR-046, SR-040, LLR-045, LLR-046
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][string[]]$Name,
        [string]$SevenZipPath = $script:Def.SevenZipDefaultPath,
        [switch]$SkipContentVerify,
        [switch]$AllowUnverifiedIndex,
        [switch]$DiscardUnreferencedData,
        [switch]$NonInteractive,
        [scriptblock]$Log
    )
    $log = if ($Log) { $Log } else { { param([string]$Message, [string]$Level = 'INFO') Write-Verbose "[$Level] $Message" } }
    $bkp = (Resolve-Path -LiteralPath $BackupRoot).Path
    $chg = (Resolve-Path -LiteralPath $ChangeRoot).Path

    foreach ($snapshotName in $Name) {
        # The one pre-rail action, scoped to THIS name: finish its own committed
        # deletion if one is outstanding. A host failure here is retriable (4),
        # not an unclassified throw out of the cmdlet.
        if (-not $WhatIfPreference) {
            try {
                Remove-CommittedPruneResidue -ChangeRoot $chg -Name $snapshotName -Log $log | Out-Null
            } catch {
                & $log "Could not complete the outstanding deletion of 'Pruning_$snapshotName': $($_.Exception.Message)" 'ERROR'
                [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = 4
                    BytesReclaimed = 0; BytesReHomed = 0; ReHomeDestinations = @()
                    Refusals = @([pscustomobject]@{ Code = 4; Kind = 'host-io'; Message = $_.Exception.Message })
                    Message = "The outstanding deletion of 'Pruning_$snapshotName' could not be completed; nothing else was attempted. $($_.Exception.Message)" }
                continue
            }
        }

        $plan     = Get-SnapshotPrunePlan -BackupRoot $bkp -ChangeRoot $chg -Name $snapshotName
        $refusals = @(Assert-PrunePrecondition -BackupRoot $bkp -ChangeRoot $chg -Plan $plan `
                        -SevenZipPath $SevenZipPath -SkipContentVerify:$SkipContentVerify `
                        -AllowUnverifiedIndex:$AllowUnverifiedIndex -DiscardUnreferencedData:$DiscardUnreferencedData)
        $destinations = @($plan.Items.ToArray() | ForEach-Object { $_.DestinationFolder } | Select-Object -Unique)
        & $log ("Plan for '$snapshotName': folder='$($plan.Folder)', rows=$($plan.Rows), re-home $($plan.Items.Count) file(s)/$($plan.BytesReHomed) byte(s), reclaim $($plan.BytesReclaimed) byte(s), refusals=$($refusals.Count).") 'DEBUG'

        if ($refusals.Count -gt 0) {
            $worst = @($refusals | Sort-Object { switch ($_.Code) { 2 { 0 } 3 { 1 } 4 { 2 } default { 3 } } })[0]
            foreach ($refusal in $refusals) { & $log "Refusing to remove '$snapshotName' [$($refusal.Code)/$($refusal.Kind)]: $($refusal.Message)" 'ERROR' }
            [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = $worst.Code
                BytesReclaimed = 0; BytesReHomed = 0; ReHomeDestinations = $destinations
                Refusals = $refusals; Message = $worst.Message }
            continue
        }

        $what = "remove it, re-homing $($plan.Items.Count) file(s) / $($plan.BytesReHomed) byte(s) first and reclaiming $($plan.BytesReclaimed) byte(s)"
        if (-not $PSCmdlet.ShouldProcess($plan.Folder, $what)) {
            & $log "Dry run: '$snapshotName' would $what." 'INFO'
            [pscustomobject]@{ Name = $snapshotName; Status = 'WhatIf'; Code = 0
                BytesReclaimed = $plan.BytesReclaimed; BytesReHomed = $plan.BytesReHomed
                ReHomeDestinations = $destinations; Refusals = @(); Message = "Dry run: would $what." }
            continue
        }

        # Creating the lock directory IS the test (M4): -Force would succeed on
        # an existing folder, letting two prunes past the staging-busy rail
        # between its check and here. Failure means someone else holds it, so it
        # is the staging-busy refusal — and the finally below must not delete a
        # folder this invocation did not create.
        $staging = Join-Path $chg 'Temp'
        try {
            New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
        } catch {
            & $log "Refusing to remove '$snapshotName' [2/staging-busy]: the staging lock at '$staging' could not be taken: $($_.Exception.Message)" 'ERROR'
            $busy = [pscustomobject]@{ Code = 2; Kind = 'staging-busy'
                Message = "The staging folder '$staging' already exists — a backup or another prune is running. Prune and backup are mutually exclusive (SR-017)." }
            [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = 2
                BytesReclaimed = 0; BytesReHomed = 0; ReHomeDestinations = $destinations
                Refusals = @($busy); Message = $busy.Message }
            continue
        }
        try {
            Set-Content -LiteralPath (Join-Path $staging 'PRUNE.inprogress') -Value $snapshotName -Encoding UTF8
            # Inside the transaction: staged copies are residue, and clearing
            # them is host I/O like any other (code 4 if it fails).
            Invoke-PruneEntrySweep -BackupRoot $bkp -ChangeRoot $chg -Log $log | Out-Null
            foreach ($item in $plan.Items.ToArray()) {
                & $log "Re-homing '$($item.SourceRow.RelativePath)' from '$snapshotName' to '$($item.DestinationFolder)' as '$($item.DestinationDataPath)'." 'INFO'
                Copy-ReHomedDataFile -Item $item -SevenZipPath $SevenZipPath -SkipContentVerify:$SkipContentVerify | Out-Null
            }
            Publish-PruneManifest -Plan $plan -Log $log | Out-Null

            $unresolved = @(Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg -ExcludeFolder $plan.Folder)
            if ($unresolved.Count -gt 0) {
                foreach ($problem in $unresolved) { & $log "Aborting: $($problem.Message)" 'ERROR' }
                throw "The surviving pool would not resolve without '$snapshotName' ($($unresolved.Count) row(s)); nothing was deleted."
            }

            Complete-PruneDeletion -SnapshotFolder $plan.Folder -Log $log
            & $log "Removed '$snapshotName': reclaimed $($plan.BytesReclaimed) byte(s), re-homed $($plan.BytesReHomed)." 'INFO'
            [pscustomobject]@{ Name = $snapshotName; Status = 'Pruned'; Code = 0
                BytesReclaimed = $plan.BytesReclaimed; BytesReHomed = $plan.BytesReHomed
                ReHomeDestinations = $destinations; Refusals = @()
                Message = "Removed '$snapshotName'." }
        } catch {
            & $log "Removal of '$snapshotName' failed before the commit point; NO DATA WAS LOST: $($_.Exception.Message)" 'ERROR'
            [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = 4
                BytesReclaimed = 0; BytesReHomed = 0; ReHomeDestinations = $destinations
                Refusals = @([pscustomobject]@{ Code = 4; Kind = 'host-io'; Message = $_.Exception.Message })
                Message = "Removal aborted before the commit point; no data was lost. $($_.Exception.Message)" }
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-PruneBatchExitCode {
    <#
    .SYNOPSIS
        Collapses a Remove-BackupSnapshot batch into one SR-040 process exit
        code with the documented precedence 2 > 3 > 4 > 1 (0 only when every
        named snapshot was removed or dry-run).

    .PARAMETER Result
        The records Remove-BackupSnapshot emitted.

    .OUTPUTS
        [int] 0, 1, 2, 3 or 4.
    #>
    # Implements: SR-040, SR-046, SR-048, LLR-046, LLR-048
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Result)
    if (-not $Result) { return 0 }
    foreach ($code in 2, 3, 4, 1) {
        if (@($Result | Where-Object { $_.Code -eq $code }).Count -gt 0) { return $code }
    }
    return 0
}

# endregion

# region Reconstruct-script generator

function New-ReconstructScript {
    <#
    .SYNOPSIS
        Copies the Windows and POSIX restore entry points into the backup root,
        writes a path sidecar, and bundles the PowerShell runtime dependencies
        (FileBackup.Common.psm1 + System.IO.Hashing.dll) so a restore works from
        the backup folder alone.
    .NOTES
        Earlier versions prepended "$BackupRootOverride = ..." lines ahead of the
        script's param() block, which is invalid PowerShell. Paths are now passed
        via a JSON sidecar that Reconstruct.ps1 reads from its own folder.
    #>
    # Implements: SR-007, LLR-007
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot
    )
    $templateRoot = Split-Path $PSScriptRoot -Parent
    $templatePs1 = @($script:Def.ReconstructPs1Name, 'Reconstruct.ps1') |
        Select-Object -Unique |
        ForEach-Object { Join-Path $templateRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $templatePs1) {
        throw "Reconstruct.ps1 not found at '$templateRoot'"
    }

    # Copy the reconstruct script verbatim.
    Copy-Item -LiteralPath $templatePs1 -Destination (Join-Path $BackupRoot $script:Def.ReconstructPs1Name) -Force

    # The bash restorer is deliberately self-contained and needs no PowerShell.
    # Deposit it beside the Windows kit so a copied backup remains recoverable on
    # POSIX hosts without access to this repository.
    $templateSh = Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path 'bash' $script:Def.ReconstructShName)
    if (-not (Test-Path -LiteralPath $templateSh -PathType Leaf)) {
        throw "reconstruct.sh not found at '$templateSh'"
    }
    Copy-Item -LiteralPath $templateSh -Destination (Join-Path $BackupRoot $script:Def.ReconstructShName) -Force

    # Path bindings as a sidecar (read by Reconstruct.ps1 from $PSScriptRoot).
    @{ BackupRoot = $BackupRoot; ChangeRoot = $ChangeRoot } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupRoot 'RECONSTRUCT.paths.json') -Encoding UTF8

    # -ExitCode makes the process entry point report the SR-040 exit-code table
    # (0/1/2/3/4) instead of throwing; in-process callers omit it and keep the
    # terminating-error behavior they assert on.
    $bat = "@echo off`r`npwsh -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$($script:Def.ReconstructPs1Name)`" -ExitCode %*"
    Set-Content -LiteralPath (Join-Path $BackupRoot $script:Def.ReconstructBatName) -Value $bat -Encoding ASCII

    # Bundle the shared module so the deployed reconstruct script is self-contained.
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script:Def.CommonModuleName) `
              -Destination (Join-Path $BackupRoot $script:Def.CommonModuleName) -Force

    # Bundle the xxHash DLL so hashing works on a machine without the NuGet package.
    $dll = Get-XxHashDllPath
    if ($dll) {
        Copy-Item -LiteralPath $dll -Destination (Join-Path $BackupRoot 'System.IO.Hashing.dll') -Force
    }
}

# endregion

# region Per-set orchestration helpers

function Resolve-BackupSetPaths {
    <#
    .SYNOPSIS
        Validates the set's SourcePath and resolves (creating if needed) the
        Backup/Change paths to absolute form.

    .PARAMETER Set
        The backup set to resolve.

    .PARAMETER ReadOnly
        Resolve EXISTING roots only: create nothing, and do not require
        SourcePath. For the read-only actions (-Action Verify, SR-049), which
        are about the STORE — the source may legitimately be offline, and an
        action that mutates nothing must not conjure a backup root. A backup
        root that does not exist is a precondition failure the caller reports as
        code 2 (WP5 review, finding m2).

    .OUTPUTS
        [pscustomobject] SrcPath / SrcStatePath / BkpPath / ChgPath / ViewPath
        (resolved full path when BrowseView is 'index', else $null). Under
        -ReadOnly, SrcPath and SrcStatePath are $null when the source is absent
        and ChgPath may name a folder that does not exist (there are then no
        snapshots to audit). The view IS still rail-checked read-only - the
        checks are pure path arithmetic and -Action View goes through here.
    #>
    # Implements: SR-014, SR-049, SR-063, LLR-014, LLR-063
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [switch]$ReadOnly
    )

    if ($ReadOnly) {
        $bkpPath = (Resolve-Path -LiteralPath $Set.BackupPath -ErrorAction SilentlyContinue).Path
        if (-not $bkpPath) {
            throw "Backup path '$($Set.BackupPath)' for set '$($Set.Name)' does not exist; there is nothing to read there."
        }
        $chgPath = (Resolve-Path -LiteralPath $Set.ChangePath -ErrorAction SilentlyContinue).Path
        if (-not $chgPath) { $chgPath = [IO.Path]::GetFullPath([string]$Set.ChangePath) }
        $srcPath = (Resolve-Path -LiteralPath $Set.SourcePath -ErrorAction SilentlyContinue).Path
        return [pscustomobject]@{
            SrcPath = $srcPath
            SrcStatePath = $srcPath
            BkpPath = $bkpPath
            ChgPath = $chgPath
            ViewPath = Resolve-ViewRootPath -Set $Set -BkpPath $bkpPath -ChgPath $chgPath `
                -SrcPath $srcPath -SrcStatePath $srcPath
        }
    }

    if (-not (Test-Path -LiteralPath $Set.SourcePath -PathType Container)) {
        throw "Source path '$($Set.SourcePath)' for set '$($Set.Name)' does not exist."
    }
    $srcPath = (Resolve-Path -LiteralPath $Set.SourcePath).Path

    $bkpPath = (Resolve-Path -LiteralPath $Set.BackupPath -ErrorAction SilentlyContinue).Path
    if (-not $bkpPath) {
        New-Item -ItemType Directory -Path $Set.BackupPath -Force | Out-Null
        $bkpPath = (Resolve-Path -LiteralPath $Set.BackupPath).Path
    }

    $chgPath = (Resolve-Path -LiteralPath $Set.ChangePath -ErrorAction SilentlyContinue).Path
    if (-not $chgPath) {
        New-Item -ItemType Directory -Path $Set.ChangePath -Force | Out-Null
        $chgPath = (Resolve-Path -LiteralPath $Set.ChangePath).Path
    }

    $srcStatePath = $srcPath
    if (-not [string]::IsNullOrWhiteSpace([string]$Set.SourceStatePath)) {
        $srcStatePath = (Resolve-Path -LiteralPath $Set.SourceStatePath -ErrorAction SilentlyContinue).Path
        if (-not $srcStatePath) {
            New-Item -ItemType Directory -Path $Set.SourceStatePath -Force | Out-Null
            $srcStatePath = (Resolve-Path -LiteralPath $Set.SourceStatePath).Path
        }
    }

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $isWithin = {
        param([string]$Candidate, [string]$Root)
        $prefix = $Root.TrimEnd('\','/') + $separator
        return $Candidate.StartsWith($prefix, $comparison)
    }

    if ($srcStatePath -ne $srcPath) {
        if (& $isWithin $srcStatePath $srcPath) {
            throw "SourceStatePath '$srcStatePath' must not be inside SourcePath '$srcPath' because its cache would be backed up as source data."
        }
        foreach ($ownedPath in @($bkpPath, $chgPath)) {
            if ($srcStatePath -eq $ownedPath -or (& $isWithin $srcStatePath $ownedPath)) {
                throw "SourceStatePath '$srcStatePath' must be separate from backup/change storage '$ownedPath'."
            }
        }
    }

    return [pscustomobject]@{
        SrcPath = $srcPath
        SrcStatePath = $srcStatePath
        BkpPath = $bkpPath
        ChgPath = $chgPath
        ViewPath = Resolve-ViewRootPath -Set $Set -BkpPath $bkpPath -ChgPath $chgPath `
            -SrcPath $srcPath -SrcStatePath $srcStatePath
    }
}

function Resolve-ViewRootPath {
    <#
    .SYNOPSIS
        Resolves and rail-checks a set's view root (SR-063): $null when the set
        has no view; otherwise the full path, refused when it OVERLAPS any path
        the set owns - in EITHER direction - or lies off the backup volume.
        BrowseView 'off' pays nothing and validates nothing.

    .DESCRIPTION
        The view root is WIPED and regenerated on every refresh
        (New-BrowseViewIndex), so containment here is a data-safety rail, not
        tidiness. It must be checked BOTH ways, against BOTH storage roots AND
        the source paths:

          - view INSIDE an owned path -> the engine would walk the view as data;
          - view CONTAINING an owned path, or equal to one -> the wipe deletes
            that path. A ViewPath naming an ancestor of BackupPath destroys the
            whole store; one naming SourcePath destroys the user's source tree;
            and the run still reports success. Both were reproduced on
            2026-08-25 (WP9 independent review, MAJ-1) - the one-directional
            rail that shipped at step 7 caught neither.

        The source paths matter as much as the storage roots: SourcePath is the
        thing this tool exists to protect, and the volume rail cannot help,
        because in an ordinary local deployment the source is ON the backup
        volume. New-BrowseViewIndex carries an independent second guard - it
        refuses to wipe a directory that is not already a view - so a caller
        that bypasses this function still cannot delete user data.

    .PARAMETER SrcPath
        The set's resolved source root, when known; $null under -ReadOnly with
        an offline source, which simply drops that pair of comparisons.

    .PARAMETER SrcStatePath
        The set's resolved source-state (hash cache) location, when known.
    #>
    # Implements: SR-063, LLR-063
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$ChgPath,
        [AllowNull()][string]$SrcPath,
        [AllowNull()][string]$SrcStatePath
    )
    if ([string]$Set.BrowseView -ne 'index') { return $null }

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separator  = [System.IO.Path]::DirectorySeparatorChar
    $viewRaw = [string]$Set.ViewPath
    if ([string]::IsNullOrWhiteSpace($viewRaw)) { $viewRaw = $BkpPath.TrimEnd('\', '/') + '_View' }
    $viewFull = [IO.Path]::GetFullPath($viewRaw)
    $isWithin = {
        param([string]$Candidate, [string]$Root)
        return $Candidate.StartsWith($Root.TrimEnd('\', '/') + $separator, $comparison)
    }
    $owned = [ordered]@{ 'backup/change storage' = @($BkpPath, $ChgPath) }
    $sourcePaths = @(@($SrcPath, $SrcStatePath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($sourcePaths.Count -gt 0) { $owned['the source tree'] = $sourcePaths }
    foreach ($label in $owned.Keys) {
        foreach ($ownedPath in $owned[$label]) {
            if ($viewFull -eq $ownedPath) {
                throw "ViewPath '$viewFull' for set '$($Set.Name)' IS $label '$ownedPath'. The view root is WIPED and regenerated on every refresh, so this would delete it. Point ViewPath at a folder of its own."
            }
            if (& $isWithin $viewFull $ownedPath) {
                throw "ViewPath '$viewFull' for set '$($Set.Name)' must lie outside $label '$ownedPath': the engine would walk the view as data."
            }
            if (& $isWithin $ownedPath $viewFull) {
                throw "ViewPath '$viewFull' for set '$($Set.Name)' CONTAINS $label '$ownedPath'. The view root is WIPED and regenerated on every refresh, so this would delete it. Point ViewPath at a folder of its own."
            }
        }
    }
    $bkpVolume  = Get-VolumeIdentity -Path $BkpPath
    $viewAnchor = Resolve-ExistingAncestor -Path $viewFull
    $viewVolume = if ($viewAnchor) { Get-VolumeIdentity -Path $viewAnchor } else { $null }
    if ($bkpVolume -and $viewVolume -and $viewVolume -ne $bkpVolume) {
        throw "ViewPath '$viewFull' for set '$($Set.Name)' must be on the backup volume ('$bkpVolume'; the view path resolves to '$viewVolume'): the view's relative links into the pool only work there."
    }
    return $viewFull
}

function Initialize-StagingFolder {
    <#
    .SYNOPSIS
        Creates the run's Temp staging folder in the change root; aborts loudly
        if a stale Temp from a failed prior run is still present.
    #>
    # Implements: SR-005, SR-017, LLR-005, LLR-017
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChgPath,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $stagingFolder = Join-Path $ChgPath 'Temp'
    # The create IS the lock take: CreateDirectory-without-Force fails when the
    # folder already exists, so two overlapping runs cannot both pass a
    # Test-Path look-then-create window (the same TOCTOU Remove-BackupSnapshot
    # already closes for the prune path).
    try {
        New-Item -ItemType Directory -Path $stagingFolder -ErrorAction Stop | Out-Null
    } catch {
        & $Log "Staging folder '$stagingFolder' already exists. Previous run may have failed or still be running." 'ERROR'
        & $Log "If no other run is active, do NOT delete Temp: it may hold the only copy of snapshot-demanded bytes. Move it aside and follow the safe recovery in README, 'A run refuses because Temp exists'." 'ERROR'
        throw "Cannot initialize staging folder; Temp already exists at '$stagingFolder'"
    }
    return $stagingFolder
}

function Compare-SourceToBackup {
    <#
    .SYNOPSIS
        Pure diff: returns NewOrChanged (source rows) and RemovedFromSource
        (backup rows) by RelativePath. No I/O — unit-testable.
    #>
    # Implements: SR-001, SR-053, LLR-001, LLR-053
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$SourceDb,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb
    )
    # New-RelativePathMap: case-sensitive keys on Linux (container runs), where
    # case-differing filenames are distinct ordinary files (SR-034).
    $sourceMap = New-RelativePathMap; foreach ($row in $SourceDb) { $sourceMap[$row.RelativePath] = $row }
    $backupMap = New-RelativePathMap; foreach ($row in $BackupDb) { $backupMap[$row.RelativePath] = $row }

    $newOrChanged      = New-Object System.Collections.Generic.List[object]
    $removedFromSource = New-Object System.Collections.Generic.List[object]

    foreach ($rel in $sourceMap.Keys) {
        $s = $sourceMap[$rel]
        $b = $backupMap[$rel]
        if (-not $b) {
            $newOrChanged.Add($s)
        } elseif ($s.Length -ne $b.Length -or $s.LastWriteTime -ne $b.LastWriteTime -or $s.xxH2Hash -ne $b.xxH2Hash) {
            $newOrChanged.Add($s)
        } elseif ([string]::IsNullOrWhiteSpace($b.DataPath)) {
            # WP7 (SR-053): a root row with a BLANK DataPath is a row whose
            # bytes were lost (Test-BackupManifest blanked it) — metadata
            # equality must not hide it from the diff, or the store never
            # heals while the source still holds the content. Re-entering the
            # diff re-copies the bytes (or re-points at a surviving dedup
            # copy — Invoke-BackupFileGroup's SR-053 filter guarantees the
            # adopted DataPath is non-blank).
            $newOrChanged.Add($s)
        }
    }
    foreach ($rel in $backupMap.Keys) {
        if (-not $sourceMap.ContainsKey($rel)) { $removedFromSource.Add($backupMap[$rel]) }
    }

    return [pscustomobject]@{ NewOrChanged = $newOrChanged; RemovedFromSource = $removedFromSource }
}

function Invoke-BackupFileGroup {
    <#
    .SYNOPSIS
        Backs up one (hash,length) group: reuses an existing backup data file if
        present, otherwise copies/compresses once and points every logical name
        at it.

    .DESCRIPTION
        Content-addressed storage keeps exactly ONE physical object per
        (hash,length), so the group must agree on that object's form before any
        of it is written (SR-060). Members can disagree: identical bytes under
        'a.txt' and 'a.dat' have different extensions, and under CompressEnabled
        'x.txt' and 'x.jpg' get different Test-ShouldCompress answers. The group
        therefore elects an OWNER — shortest RelativePath, ordinal tie-break,
        the same election Update-SourceManifest already uses to assign
        Duplicate — and the owner's extension and compression answer define the
        single object. The first member writes it; the rest adopt it from an
        in-process memo instead of re-copying the same bytes to the same name
        (D-5's other face: the pre-WP9 lookup consulted only the PRIOR backup,
        so a group first seen in ONE run wrote once per member).

        The destination is always the content-derived hash name (SR-058):
        different content means a different name, so an existing stored object
        is never overwritten in place — D-1's hazard class is deleted, not
        guarded. A hash-grammar name ('<hash16> <len10><ext>') also cannot
        spell a root-level infrastructure name, which is why the Mirror-era
        SR-022 refusal that lived in this branch is gone (TC-123 audits the
        grammar at the root as the compensating control).
    #>
    # Implements: SR-003, SR-013, SR-053, SR-058, SR-060, LLR-003, LLR-053, LLR-058
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Group,
        [Parameter(Mandatory)][string]$SrcPath,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][bool]$CompressEnabled,
        [string]$SevenZipPath,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][ref]$BackupMap,
        [Parameter(Mandatory)][ref]$ChangedCount,
        [Parameter(Mandatory)][scriptblock]$Log,
        [Parameter(Mandatory)][ref]$OverallSuccess,
        # SR-067: milliseconds of retry waiting this RUN may still spend, shared
        # across every group so a systemic failure cannot sleep the run away.
        # Omitted (a direct unit-test call) means "this call gets a fresh
        # budget of its own".
        [AllowNull()][ref]$RetryBudgetMs
    )
    if ($null -eq $RetryBudgetMs) {
        $ownBudget = $script:CopyRetryBudgetMs
        $RetryBudgetMs = [ref]$ownBudget
    }
    $hash = $Group[0].xxH2Hash
    $len  = $Group[0].Length
    $exts = ($Group | ForEach-Object { [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() } | Select-Object -Unique)
    if ($exts.Count -gt 1) {
        & $Log "Multiple extensions for hash=$hash len=$len : $($exts -join ', ')" 'WARN'
    }

    # B8: force an array so [0] is always valid even for a single match.
    # WP7 (SR-053): a row whose DataPath is BLANK is damage being healed, not
    # existing content — adopting it gave a brand-new file a row that points
    # nowhere and its bytes were never written (investigation R5). Blank rows
    # are excluded, so the group falls through to the copy branch instead.
    $existingBackupWithHash = @($BackupDb | Where-Object {
        $_.xxH2Hash -eq $hash -and $_.Length -eq $len -and -not [string]::IsNullOrWhiteSpace($_.DataPath) })

    # Owner election (SR-060): shortest RelativePath wins, ties broken ORDINALLY
    # — CompareOrdinal rather than PowerShell's culture-aware comparison, so the
    # elected object does not depend on the host's locale (SR-024 determinism).
    $owner = $Group[0]
    foreach ($candidate in $Group) {
        if ($candidate.RelativePath.Length -lt $owner.RelativePath.Length) { $owner = $candidate; continue }
        if ($candidate.RelativePath.Length -eq $owner.RelativePath.Length -and
            [string]::CompareOrdinal($candidate.RelativePath, $owner.RelativePath) -lt 0) { $owner = $candidate }
    }
    $ownerExt      = [IO.Path]::GetExtension($owner.RelativePath)
    $ownerSrcFull  = Join-Path $SrcPath $owner.RelativePath
    $ownerCompress = Test-ShouldCompress -FileName $ownerSrcFull -CompressEnabled $CompressEnabled
    # The group's single stored object, once written this run (SR-060). Null
    # until the first member writes.
    $writtenThisRun = $null

    foreach ($entry in $Group) {
        $rel = $entry.RelativePath

        # Adopt this run's own write before consulting the prior backup: the
        # object we just created is the one this group's rows must name.
        if ($null -ne $writtenThisRun) {
            $BackupMap.Value[$rel] = [pscustomobject]@{
                DataPath         = $writtenThisRun.DataPath
                RelativePath     = $rel
                Length           = $len
                LastWriteTime    = $entry.LastWriteTime
                xxH2Hash         = $hash
                Compressed       = $writtenThisRun.Compressed
                StoredAsHashSize = $writtenThisRun.StoredAsHashSize
                Duplicate        = $entry.Duplicate
                MediaMBPerSec    = $entry.MediaMBPerSec
            }
            # Counted like the write it replaces, so the run's "changed files"
            # figure keeps meaning logical files rather than physical copies.
            $ChangedCount.Value++
            continue
        }

        if ($existingBackupWithHash.Count -gt 0) {
            $existing = $existingBackupWithHash[0]
            $BackupMap.Value[$rel] = [pscustomobject]@{
                DataPath         = $existing.DataPath
                RelativePath     = $rel
                Length           = $len
                LastWriteTime    = $entry.LastWriteTime
                xxH2Hash         = $hash
                Compressed       = $existing.Compressed
                StoredAsHashSize = $existing.StoredAsHashSize
                Duplicate        = $entry.Duplicate
                MediaMBPerSec    = $entry.MediaMBPerSec
            }
        } else {
            # The single object's name derives from the content and the OWNER's
            # form (SR-058/SR-060): different content, different name, so no
            # existing object is ever overwritten in place (SR-059).
            $dataExt  = if ($ownerCompress) { '.7z' } else { $ownerExt }
            $dataPath = Get-HashSizeFileName -HashHex $hash -Length $len -Extension $dataExt
            $destFull = Join-Path $BkpPath $dataPath

            # Every member of a (hash,length) group holds identical bytes, so
            # ANY member's file can supply them. Try the elected owner first
            # (its extension and compressibility already chose the object's
            # form), then fall back to the other members: before this, one
            # locked owner failed the WHOLE group, so a perfectly readable file
            # went unbacked-up because a DIFFERENT file was open - and the
            # error named the wrong file (WP9 review, MIN-1). The destination
            # name never changes, because it derives from the content and the
            # owner's form, not from whichever file was readable.
            $sourceCandidates = [System.Collections.Generic.List[string]]::new()
            $sourceCandidates.Add($ownerSrcFull)
            foreach ($member in @($entry) + $Group) {
                $candidate = Join-Path $SrcPath $member.RelativePath
                if (-not $sourceCandidates.Contains($candidate)) { $sourceCandidates.Add($candidate) }
            }
            # Attempt rounds (SR-067): each round tries every member of the
            # content group, then waits and tries the whole list again. A file
            # whose content is unique has ONE member, so before this it had one
            # attempt and a momentary lock cost it the entire run.
            $result = $null
            $usedSource = $null
            $attempts = 0
            while ($true) {
                $attempts++
                foreach ($candidate in $sourceCandidates) {
                    if ($null -ne $result) {
                        # A failed attempt can leave a partial object behind; clear
                        # it so the retry writes a fresh file rather than landing on
                        # (or, for 7-Zip's 'a', merging into) the debris.
                        Remove-Item -LiteralPath $destFull -Force -ErrorAction SilentlyContinue
                    }
                    $result = Copy-SourceFileToBackup -SourceFilePath $candidate -BackupFilePath $destFull -ShouldCompress:$ownerCompress -SevenZipPath $SevenZipPath
                    if ($result -isnot [string]) { $usedSource = $candidate; break }
                    if ($sourceCandidates.Count -gt 1) {
                        & $Log "Could not read '$candidate' for hash=$hash len=$len : $result" 'WARN'
                    }
                }
                if ($result -isnot [string]) { break }
                if (-not (Test-CopyFailureIsTransient -Message $result)) { break }
                $delayMs = Get-CopyRetryDelayMs -Attempt $attempts
                if ($null -eq $delayMs) { break }
                if ($RetryBudgetMs.Value -lt $delayMs) {
                    & $Log ("Not retrying '$rel': this run's copy-retry budget is spent " +
                            "($($script:CopyRetryBudgetMs) ms). A failure this widespread is not transient.") 'WARN'
                    break
                }
                $RetryBudgetMs.Value -= $delayMs
                & $Log ("Copy of '$rel' failed (attempt $attempts): $result. Retrying in ${delayMs} ms.") 'WARN'
                Start-Sleep -Milliseconds $delayMs
            }
            if ($result -is [string]) {
                # No row is written for this file. That is the contract, not an
                # oversight (SR-067): the manifest must never name content the
                # store does not hold. A file that had a PREVIOUS version keeps
                # its previous row - the backup still holds those bytes - which
                # is the same frozen-row treatment SR-055/SR-057 give a file the
                # walk could not read.
                & $Log ("Failed to copy/compress '$rel' -> '$dataPath' after $attempts attempt(s) : $result " +
                        "(no readable source among $($sourceCandidates.Count) member(s) of this content group). " +
                        'This file is NOT in the backup; the set is marked failed.') 'ERROR'
                $OverallSuccess.Value = $false
                continue
            }
            # One line per PHYSICAL write. Operationally useful, and it is what
            # makes SR-060's "one copy/compress operation" observable at all:
            # under content addressing a second write lands on the same name
            # with the same bytes, so the RESULT cannot distinguish one write
            # from two and TC-119 was blind to the memo (WP9 review, MAJ-2).
            & $Log ("Stored object '$dataPath' for hash=$hash len=$len from '$usedSource' " +
                    "(group of $($Group.Count))." ) 'DEBUG'

            $BackupMap.Value[$rel] = [pscustomobject]@{
                DataPath         = $dataPath
                RelativePath     = $rel
                Length           = $len
                LastWriteTime    = $entry.LastWriteTime
                xxH2Hash         = $hash
                Compressed       = if ($ownerCompress) { 'Yes' } else { 'No' }
                StoredAsHashSize = 'Hash'
                Duplicate        = $entry.Duplicate
                MediaMBPerSec    = $entry.MediaMBPerSec
            }
            $ChangedCount.Value++
            $writtenThisRun = [pscustomobject]@{
                DataPath         = $dataPath
                Compressed       = if ($ownerCompress) { 'Yes' } else { 'No' }
                StoredAsHashSize = 'Hash'
            }
        }
    }
}

function Move-RemovedFilesToStaging {
    <#
    .SYNOPSIS
        Evicts data files for source-removed entries into the staging folder.
    .NOTES
        B9: only moves a data file out when no surviving backup entry still
        references it (shared hash/size dedup). When it is still referenced, the
        file is left in the backup root and the change manifest blanks the
        DataPath (reconstruct recovers it by hash).

        A failed move does NOT abort the run (SR-041): it is logged as an ERROR,
        counted, and the loop continues. One locked file must not hide every
        other failure, skip snapshot finalization, and leave the Temp staging
        folder behind for the next run's SR-017 stale-staging guard to trip on.
        Same shape as Invoke-BackupFileGroup's existing per-entry handling.
    #>
    # Implements: SR-006, SR-041, LLR-006, LLR-041
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$RemovedFromSource,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][ref]$BackupMap,
        [Parameter(Mandatory)][ref]$ChangedCount,
        [Parameter(Mandatory)][scriptblock]$Log,
        [Parameter(Mandatory)][ref]$OverallSuccess
    )
    $failures = 0
    foreach ($bk in $RemovedFromSource) {
        $rel  = $bk.RelativePath
        $data = $bk.DataPath
        if ($BackupMap.Value[$rel]) { $BackupMap.Value.Remove($rel) }

        if ([string]::IsNullOrWhiteSpace($data)) { continue }

        # B9: is this data file still referenced by a surviving logical file?
        $stillReferenced = $false
        foreach ($surviving in $BackupMap.Value.Values) {
            if ($surviving.DataPath -eq $data) { $stillReferenced = $true; break }
        }
        if ($stillReferenced) {
            & $Log "Data file '$data' still referenced by another file; leaving in backup (change manifest will hash-recover)." 'INFO'
            continue
        }

        $srcDataFull = Join-Path $BkpPath $data
        if (Test-Path -LiteralPath $srcDataFull -PathType Leaf) {
            $destDataFull = Join-Path $StagingFolder $data
            try {
                $destDir = [System.IO.Path]::GetDirectoryName($destDataFull)
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Move-Item -LiteralPath $srcDataFull -Destination $destDataFull -Force
                $ChangedCount.Value++
            }
            catch {
                & $Log "Failed to evict '$rel' (data '$data') to staging: $($_.Exception.Message)" 'ERROR'
                $OverallSuccess.Value = $false
                $failures++
                continue
            }
        }
    }
    if ($failures -gt 0) {
        & $Log "Removed-file eviction finished with $failures failure(s); the snapshot is partial." 'ERROR'
    }
}

function Save-SupersededData {
    <#
    .SYNOPSIS
        Preserves the prior bytes of files whose content was replaced this run
        into the staging snapshot, unless a live manifest row still claims them.
    .DESCRIPTION
        For each changed file that already existed in the backup with different
        content, the old data file is moved into staging UNLESS it must stay in
        the pool — the EXACT survival test (SR-059). Called AFTER the copy and
        evict steps: content addressing never overwrites an existing object,
        so preservation can wait for the FINAL manifest and ask the real
        question — does any surviving row still claim the old object's
        DataPath. That is the same claim semantics as eviction's B9 refcount.
        Frozen rows (SR-055/SR-057) and rows whose copy failed keep their
        claim in the final map, so their objects correctly stay in the pool —
        the pre-WP9 source-based approximation moved them out (the D-1 defect
        family, review 2026-08-24).

        Old content that survives in the pool is NOT staged: the snapshot
        recovers it by hash at restore, exactly as eviction's still-referenced
        branch already works.

        A failed move does NOT abort the run (SR-041): it is logged as an ERROR,
        counted, and the loop continues, so the run still finalizes its staging
        folder instead of orphaning it (SR-017). Same shape as
        Invoke-BackupFileGroup's existing per-entry handling.
    #>
    # Implements: SR-010, SR-028, SR-041, SR-059, LLR-010, LLR-028, LLR-041, LLR-059
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$NewOrChanged,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$FinalRows,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][scriptblock]$Log,
        [Parameter(Mandatory)][ref]$OverallSuccess
    )
    if (-not $NewOrChanged) { return }
    $failures = 0
    # Filesystem-faithful keys (SR-034): a case-insensitive map here returns the
    # WRONG row for a case-differing Linux pair, and its content "surviving"
    # skips staging the superseded bytes the snapshot needs (review 83cc5f1 R1).
    $backupByRel = New-RelativePathMap; foreach ($b in $BackupDb) { if ($b.RelativePath) { $backupByRel[$b.RelativePath] = $b } }
    # A DataPath any FINAL row still claims stays in the pool (SR-059).
    # Deliberately a plain case-insensitive set: this mirrors eviction's B9
    # refcount (string -eq), not the SR-034 RelativePath identity above.
    $claimedData = @{}
    foreach ($r in $FinalRows) { if (-not [string]::IsNullOrWhiteSpace($r.DataPath)) { $claimedData[$r.DataPath] = $true } }

    foreach ($chg in $NewOrChanged) {
        $old = $backupByRel[$chg.RelativePath]
        if (-not $old) { continue }                                  # brand-new file: nothing superseded
        if ($old.xxH2Hash -eq $chg.xxH2Hash -and $old.Length -eq $chg.Length) { continue }  # same content
        if ([string]::IsNullOrWhiteSpace($old.DataPath)) { continue }
        if ($claimedData.ContainsKey($old.DataPath)) { continue }    # a live row still claims the old object
        $srcDataFull = Join-Path $BkpPath $old.DataPath
        if (-not (Test-Path -LiteralPath $srcDataFull -PathType Leaf)) { continue }  # already moved / shared
        $destFull = Join-Path $StagingFolder $old.DataPath
        try {
            $destDir = [System.IO.Path]::GetDirectoryName($destFull)
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Move-Item -LiteralPath $srcDataFull -Destination $destFull -Force
            & $Log "Preserved superseded data for '$($chg.RelativePath)' into the snapshot."
        }
        catch {
            & $Log "Failed to preserve superseded data for '$($chg.RelativePath)' (data '$($old.DataPath)'): $($_.Exception.Message)" 'ERROR'
            $OverallSuccess.Value = $false
            $failures++
            continue
        }
    }
    if ($failures -gt 0) {
        & $Log "Superseded-data preservation finished with $failures failure(s); the snapshot is partial." 'ERROR'
    }
}

function Complete-ChangeFolder {
    <#
    .SYNOPSIS
        Finalizes the staging folder into a dated point-in-time snapshot, or
        discards it when the manifest state did not change.
    .DESCRIPTION
        When this run changed the manifest state ($ManifestChanged — any row
        added, removed, or changed, per the SR-005 supersession criterion) and a
        prior backup date is known ($SnapshotDate), the staging folder becomes
        Snapshot_<SnapshotDate> — the state of the superseded backup, named by
        that backup's completion date (SR-005). Otherwise (a manifest-identical
        no-op run, or the very first backup) the staging folder is discarded:
        the live backup root is itself the latest state, so it needs no snapshot.

        The gate is deliberately the manifest diff, NOT the physical-copy count:
        a duplicate-content add (served by dedup reuse) or a shared-content
        removal (no byte evicted) moves no data yet still supersedes the prior
        state, which must stay restorable (2026-07-02 review finding).

        On finalize, stale DataPaths are blanked (the bytes live in the backup
        root or a sibling snapshot and are recovered by hash at restore), and the
        full reconstruct kit — including the RECONSTRUCT.paths.json sidecar — is
        copied in so a snapshot restore can locate the data pool.
    .PARAMETER ManifestChanged
        True when the run's Compare-SourceToBackup diff was non-empty (SR-005).
    .PARAMETER SnapshotDate
        Completion date of the backup whose state this snapshot preserves (the
        previous run). $null on the first backup ⇒ no snapshot.
    #>
    # Implements: SR-005, SR-028, LLR-005, LLR-028
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChgPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][bool]$ManifestChanged,
        [Parameter(Mandatory)][scriptblock]$Log,
        [AllowNull()][Nullable[datetime]]$SnapshotDate
    )
    if (-not $ManifestChanged -or $null -eq $SnapshotDate) {
        Remove-Item -LiteralPath $StagingFolder -Recurse -Force -ErrorAction SilentlyContinue
        $why = if ($null -eq $SnapshotDate) { 'first backup' } else { 'manifest unchanged (no-op run)' }
        & $Log "No prior state superseded ($why); no snapshot created (the live backup is the latest state)."
        return $null
    }

    $stagingDb = Read-Manifest -FolderPath $StagingFolder
    foreach ($row in $stagingDb) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $full = Join-Path $StagingFolder $row.DataPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $row.DataPath = '' }
    }
    Write-Manifest -FolderPath $StagingFolder -Records $stagingDb

    # Copy the full reconstruct kit (incl. the path sidecar) INTO STAGING,
    # BEFORE the rename (F8, WP9 step 8): the rename is the publish, and a
    # crash between a publish and a later kit copy used to leave a valid
    # snapshot with no restore kit. With the copy first, a Snapshot_* folder
    # structurally cannot exist without its kit — a crash before the rename
    # leaves only a Temp folder for the SR-017 stale-staging guard.
    foreach ($artifact in @($script:Def.ReconstructPs1Name, $script:Def.ReconstructBatName, $script:Def.ReconstructShName, $script:Def.CommonModuleName, 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')) {
        # NOTE: the directory sidecar is deliberately absent from this list - it
        # is NOT part of the kit. Step 7 already placed the PRIOR state's
        # sidecar in staging, and copying the backup root's current one here
        # would overwrite that point-in-time truth with the live state.
        $src = Join-Path $BkpPath $artifact
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination $StagingFolder -Force
        }
    }

    $label = ([datetime]$SnapshotDate).ToString($script:Def.FileLabelDateFormat)
    # Second precision ⇒ two snapshots dated the same second would collide; append
    # a numeric disambiguator (still matches the ^Snapshot_<date> regex prefix).
    $base      = "$($script:Def.SnapshotPrefix)$label"
    $finalName = $base
    $n = 1
    while (Test-Path -LiteralPath (Join-Path $ChgPath $finalName)) {
        $finalName = "${base}_$('{0:D3}' -f $n)"
        $n++
    }
    $finalSnapshot = Join-Path $ChgPath $finalName
    Rename-Item -LiteralPath $StagingFolder -NewName $finalName

    & $Log "Snapshot finalized: $finalSnapshot"
    return $finalSnapshot
}

# endregion

# region Per-set orchestrator

function Get-BackupCapacityDemand {
    <#
    .SYNOPSIS
        Bytes this run will add to the backup volume and to the change volume
        (SR-052). Pure: it reads no filesystem.

    .DESCRIPTION
        BACKUP: the new deduplicated content only — one entry per
        (xxH2Hash,Length) that the backup does not already hold — sized by
        uncompressed Length, which is the upper bound whether or not the bytes
        end up compressed.

        CHANGE: what Save-SupersededData and Move-RemovedFilesToStaging must put
        in staging. Counted ONLY when the change root is on a DIFFERENT volume
        than the backup root: on the same volume those are renames and cost
        nothing. Also deduplicated by (xxH2Hash,Length), because dedup means one
        physical file backs several rows.

    .PARAMETER NewOrChanged
        Compare-SourceToBackup's NewOrChanged rows.

    .PARAMETER RemovedFromSource
        Compare-SourceToBackup's RemovedFromSource rows.

    .PARAMETER BackupDb
        What the backup already holds.

    .PARAMETER SameVolume
        True when the change root and the backup root are on one volume.

    .OUTPUTS
        [pscustomobject] BackupBytes, ChangeBytes.
    #>
    # Implements: SR-052, SR-013, LLR-052
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$NewOrChanged,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$RemovedFromSource,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][bool]$SameVolume
    )
    $held = @{}
    $byPath = New-RelativePathMap   # SR-034: RelativePath keys compare like the filesystem
    foreach ($row in @($BackupDb | Where-Object { $_ })) {
        # A blank-DataPath row holds NO bytes: the SR-053 heal will copy them,
        # so its key must not read as "already held" or the SR-052 preflight
        # budgets zero for a heal and the run fails mid-copy on a full volume
        # instead of refusing before mutation (WP7 review, required change 1 —
        # mirrors Invoke-BackupFileGroup's adoption filter).
        if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) {
            $held["$($row.xxH2Hash)|$($row.Length)"] = $true
        }
        $byPath[$row.RelativePath] = $row
    }

    $backupBytes = 0L
    $seen = @{}
    foreach ($row in @($NewOrChanged | Where-Object { $_ })) {
        $key = "$($row.xxH2Hash)|$($row.Length)"
        if ($held.ContainsKey($key) -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $backupBytes += [long]$row.Length
    }

    $changeBytes = 0L
    if (-not $SameVolume) {
        $staged = @{}
        # Where-Object guards the AGENTS.md §4 hazard: an empty list arriving as
        # $null makes @(...) one $null element.
        foreach ($row in @(@($NewOrChanged) + @($RemovedFromSource) | Where-Object { $_ })) {
            $prior = $byPath[$row.RelativePath]
            if (-not $prior) { continue }                       # nothing of this path is stored yet
            $key = "$($prior.xxH2Hash)|$($prior.Length)"
            if ($seen.ContainsKey($key) -or $staged.ContainsKey($key)) { continue }
            $staged[$key] = $true
            $changeBytes += [long]$prior.Length
        }
    }

    return [pscustomobject]@{ BackupBytes = $backupBytes; ChangeBytes = $changeBytes }
}

function Assert-BackupCapacity {
    <#
    .SYNOPSIS
        Refuses a backup set BEFORE any mutation when the destination volumes
        cannot hold what the run is about to add (SR-052).

    .DESCRIPTION
        The backup half of SN-019, mirroring the restore side's SR-023 check. The
        destination is typically a HomeHub-controlled bind mount, so a full
        volume is a realistic failure mode, and a run that fills it mid-way
        leaves the manifest and the bytes out of step.

        The two demands are grouped by Get-VolumeIdentity and the group's total
        is checked against that volume's free space. When the backup and change
        roots live on the SAME volume they compete for the same bytes, so
        checking them separately passed two demands that each fit and together
        did not (WP5 review, finding M2). On different volumes the grouping is a
        no-op and each is checked alone, as before.

        A volume whose free space cannot be MEASURED is skipped, not refused:
        not knowing is not evidence of a shortfall. There is deliberately no
        configurable margin (decision Q8; SR-042's schema is closed).

    .PARAMETER BackupPath
        The backup root's volume.

    .PARAMETER ChangePath
        The change root's volume.

    .PARAMETER BackupBytes
        Bytes the run will add to the backup volume.

    .PARAMETER ChangeBytes
        Bytes the run will add to the change volume.

    .PARAMETER Log
        Logger scriptblock (message, level).

    .OUTPUTS
        None. Throws a message naming the volume, the requirement and the free
        space; the caller fails the SET (entry-point status 1 — other sets may
        still run), leaving the tree byte-identical.
    #>
    # Implements: SR-052, SR-013, SR-014, LLR-052
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][string]$ChangePath,
        [long]$BackupBytes = 0,
        [long]$ChangeBytes = 0,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $byVolume = [ordered]@{}
    foreach ($demand in @(
        [pscustomobject]@{ Name = 'backup'; Path = $BackupPath; Bytes = $BackupBytes }
        [pscustomobject]@{ Name = 'change'; Path = $ChangePath; Bytes = $ChangeBytes }
    )) {
        if ($demand.Bytes -le 0) { continue }
        # An unidentifiable volume keeps its own bucket keyed by path, so the
        # free-space probe is still attempted for it.
        $volume = Get-VolumeIdentity -Path $demand.Path
        $key    = if ($volume) { $volume } else { $demand.Path }
        if (-not $byVolume.Contains($key)) {
            $byVolume[$key] = [pscustomobject]@{ Names = @(); Path = $demand.Path; Bytes = [long]0 }
        }
        $byVolume[$key].Names += $demand.Name
        $byVolume[$key].Bytes += [long]$demand.Bytes
    }

    foreach ($key in @($byVolume.Keys)) {
        $group = $byVolume[$key]
        $label = $group.Names -join '+'
        $free  = Get-FreeSpaceBytes -Path $group.Path
        if ($null -eq $free) {
            & $Log "Capacity check skipped for the $label volume '$($group.Path)': its free space could not be measured." 'WARN'
            continue
        }
        if ($free -lt $group.Bytes) {
            throw ("Not enough free space on the $label volume '$($group.Path)'. " +
                   "Required: $($group.Bytes) byte(s), Free: $free byte(s). Refusing before writing anything.")
        }
        & $Log "Capacity check passed for the $label volume '$($group.Path)': needs $($group.Bytes), has $free." 'DEBUG'
    }
}

function New-BrowseViewIndex {
    <#
    .SYNOPSIS
        Generates the manifest-derived browse view (SR-062): INDEX.tsv always,
        one INDEX.html per source folder mirroring the tree as PAGES, and a
        root page with an embedded search box under a row threshold — all
        outside the backup root, and read by NOTHING in the engine or the
        restorers.
    .DESCRIPTION
        The view replaces Mirror's only real value — browse and search without
        a restore — and is MORE faithful than Mirror was: every logical path
        appears, including every dedup sibling (Mirror omitted borrower paths
        entirely). Entry names come from the ROW (RelativePath, plus '.7z'
        exactly when that row's Compressed is 'Yes'), never from the set's
        config: compression is per-file, so a tree is mixed. Each file entry
        is a relative <a href> to its pool object (percent-encoded — hash
        names contain URL-special glyphs), so opening an entry opens that
        object. Pages are bounded by folder fan-out and open instantly at any
        library size; a single flat page over the production library would be
        ~100 MB of markup (work order §3.6, human-approved 2026-08-25).

        Search: at or under -SearchRowThreshold rows the ROOT page embeds the
        row list and a filter box INLINE (browsers block file:// XHR, so a
        side data file cannot be fetched — the §3.6 "compact data file"
        realized as an embedded array); above it, the page prints the exact
        grep / Select-String one-liners against INDEX.tsv. Honest degradation,
        never a page that hangs the browser.

        Freshness: '.viewstamp' records a digest of the manifest ROWS the view
        mirrors (content-keyed — manifest bytes can be rewritten with
        different quoting by a manifest-identical run), written LAST — a torn
        generation is detectably stale and rebuilt, never trusted (TC-131). Regeneration wipes the view root
        first so removed rows drop out; as the never-delete-user-data guard,
        a view root holding a root-level MANIFEST.csv is refused outright —
        that is a STORE, not a view.

        A source DIRECTORY literally named 'INDEX.html' cannot be mirrored as
        pages (its page file would collide with the directory); generation
        refuses loudly and the caller decides (the pipeline logs a WARNING —
        the view is cosmetic by construction; -Action View reports it).
    .PARAMETER BackupRoot
        The live backup root whose MANIFEST.csv is mirrored.
    .PARAMETER ViewRoot
        The validated view root (Resolve-BackupSetPaths' rails: outside both
        storage roots, on the backup volume).
    .PARAMETER Force
        Regenerate even when the viewstamp matches (-Action View).
    .PARAMETER SearchRowThreshold
        Row count at or under which the root page embeds the search index.
    .OUTPUTS
        [pscustomobject] Regenerated (bool), Rows, Pages.
    #>
    # Implements: SR-062, LLR-061
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ViewRoot,
        [Parameter(Mandatory)][scriptblock]$Log,
        [switch]$Force,
        [int]$SearchRowThreshold = 50000
    )

    $manifestPath = Join-Path $BackupRoot $script:Def.DatabaseFilename
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "No manifest at '$BackupRoot': there is nothing to index."
    }
    $rows = @(Read-Manifest -FolderPath $BackupRoot | Where-Object { $_.RelativePath })

    # Freshness is keyed on canonical ROW CONTENT (sorted; the five columns the
    # view renders), not on manifest BYTES: a manifest-identical run can rewrite
    # the file with different CSV quoting (the step-8 determinism item), and
    # the view must not churn when nothing it shows has changed.
    $canonical = ($rows | Sort-Object RelativePath |
        ForEach-Object { "$($_.RelativePath)|$($_.DataPath)|$($_.Length)|$($_.xxH2Hash)|$($_.Compressed)" }) -join "`n"
    $digest = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)))
    $stampWant = "RowsSHA256=$digest"
    $stampPath = Join-Path $ViewRoot '.viewstamp'
    if (-not $Force -and (Test-Path -LiteralPath $stampPath -PathType Leaf) -and
        ((Get-Content -LiteralPath $stampPath -Raw).Trim() -eq $stampWant)) {
        & $Log 'Browse view is current (.viewstamp matches the manifest rows); skipping regeneration.'
        return [pscustomobject]@{ Regenerated = $false; Rows = 0; Pages = 0 }
    }

    if (Test-Path -LiteralPath (Join-Path $ViewRoot $script:Def.DatabaseFilename) -PathType Leaf) {
        throw "View root '$ViewRoot' contains a MANIFEST.csv at its top level — that is a backup STORE, not a generated view. Refusing to overwrite it; point ViewPath elsewhere."
    }

    # A directory named INDEX.html would collide with its parent's page file.
    foreach ($row in $rows) {
        $probe = [IO.Path]::GetDirectoryName($row.RelativePath)
        while ($probe) {
            if ([IO.Path]::GetFileName($probe) -ceq 'INDEX.html') {
                throw "Source directory '$probe' is named INDEX.html, which collides with the view's page files. Rename it at the source, or set BrowseView to 'off'."
            }
            $probe = [IO.Path]::GetDirectoryName($probe)
        }
    }

    # Resolve BEFORE the wipe: afterwards a mis-pointed ViewRoot may no longer
    # resolve at all (WP9 review MAJ-1), and the failure then lands far from its
    # cause.
    $bkpFull  = (Resolve-Path -LiteralPath $BackupRoot).Path

    # POSITIVE OWNERSHIP is the second, independent guard on the wipe: this
    # function deletes ONLY a directory it can prove is one of its own views.
    # Resolve-ViewRootPath's containment rails are the first guard; this one
    # holds even when a caller bypasses them, and it is what turns "the operator
    # pointed ViewPath at the wrong folder" from data loss into a refusal. An
    # empty directory (or one that does not exist yet) is fair game - there is
    # nothing to lose - and so is one already carrying our own artifacts.
    # Wipe + recreate: regeneration must drop removed rows, and the stamp is
    # written LAST so a torn run reads as stale next time.
    if (Test-Path -LiteralPath $ViewRoot) {
        $existing = @(Get-ChildItem -LiteralPath $ViewRoot -Force)
        $ours = @('.viewstamp', 'INDEX.tsv', 'INDEX.html')
        if ($existing.Count -gt 0 -and -not ($existing | Where-Object { $ours -contains $_.Name })) {
            $plural = if ($existing.Count -eq 1) { 'entry that is' } else { 'entries that are' }
            throw ("View root '$ViewRoot' holds $($existing.Count) $plural not a " +
                   'generated view (no .viewstamp, INDEX.tsv or INDEX.html among them). ' +
                   'Refusing to wipe it: a view root is regenerated from scratch on every ' +
                   'refresh, so it must be a folder of its own. Point ViewPath elsewhere.')
        }
        $existing | Remove-Item -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $ViewRoot -Force | Out-Null
    }
    $viewFull = (Resolve-Path -LiteralPath $ViewRoot).Path

    # INDEX.tsv — authoritative, greppable, tiny per row (the scripting surface).
    $tsv = New-Object System.Text.StringBuilder
    [void]$tsv.AppendLine("RelativePath`tDataPath`tLength`txxH2Hash`tCompressed")
    foreach ($row in $rows) {
        [void]$tsv.AppendLine("$($row.RelativePath)`t$($row.DataPath)`t$($row.Length)`t$($row.xxH2Hash)`t$($row.Compressed)")
    }
    [IO.File]::WriteAllText((Join-Path $viewFull 'INDEX.tsv'), $tsv.ToString(), [Text.UTF8Encoding]::new($false))

    # Folder tree: every folder with rows, plus every ancestor, gets a page.
    $byFolder   = @{}
    $allFolders = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    [void]$allFolders.Add('')
    foreach ($row in $rows) {
        $dir = [IO.Path]::GetDirectoryName($row.RelativePath); if ($null -eq $dir) { $dir = '' }
        $p = $dir
        while ($p) { [void]$allFolders.Add($p); $p = [IO.Path]::GetDirectoryName($p) }
        if (-not $byFolder.ContainsKey($dir)) { $byFolder[$dir] = New-Object System.Collections.Generic.List[object] }
        $byFolder[$dir].Add($row)
    }
    $children = @{}
    foreach ($f in $allFolders) {
        if (-not $f) { continue }
        $parent = [IO.Path]::GetDirectoryName($f); if ($null -eq $parent) { $parent = '' }
        if (-not $children.ContainsKey($parent)) { $children[$parent] = New-Object System.Collections.Generic.List[string] }
        $children[$parent].Add([IO.Path]::GetFileName($f))
    }

    $enc  = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $href = { param([string]$FromDirFull, [string]$DataPath)
        # Relative page->pool link, forward slashes, percent-encoded segments
        # (hash names contain '#', '%', '+', ';' and friends).
        $relRoot = [IO.Path]::GetRelativePath($FromDirFull, $bkpFull) -replace '\\', '/'
        $segments = ($DataPath -split '[\\/]') | ForEach-Object { [Uri]::EscapeDataString($_) }
        return "$relRoot/$($segments -join '/')"
    }
    $style = '<style>body{font-family:Segoe UI,sans-serif;margin:1.5em}table{border-collapse:collapse}' +
             'td,th{padding:.15em .8em;text-align:left}th{border-bottom:1px solid #999}' +
             'ul{list-style:none;padding-left:0}</style>'

    $pages = 0
    foreach ($folder in $allFolders) {
        $pageDirFull = if ($folder) { Join-Path $viewFull $folder } else { $viewFull }
        if (-not (Test-Path -LiteralPath $pageDirFull)) { New-Item -ItemType Directory -Path $pageDirFull -Force | Out-Null }
        $title = if ($folder) { $folder } else { 'Backup root' }
        $h = New-Object System.Text.StringBuilder
        [void]$h.AppendLine("<!DOCTYPE html><html><head><meta charset=""utf-8""><title>$(& $enc $title) — FileBackup view</title>$style</head><body>")
        [void]$h.AppendLine("<h1>$(& $enc $title)</h1>")
        [void]$h.AppendLine('<p>Generated from MANIFEST.csv. Read-only: nothing in the engine or the restorers reads this view. Every logical path is listed, including duplicates that share one stored object.</p>')
        if ($folder) { [void]$h.AppendLine('<p><a href="../INDEX.html">&#8593; parent folder</a></p>') }
        $kids = if ($children.ContainsKey($folder)) { $children[$folder] | Sort-Object } else { @() }
        if (@($kids).Count -gt 0) {
            [void]$h.AppendLine('<ul>')
            foreach ($kid in $kids) {
                [void]$h.AppendLine("<li>&#128193; <a href=""$([Uri]::EscapeDataString($kid))/INDEX.html"">$(& $enc $kid)/</a></li>")
            }
            [void]$h.AppendLine('</ul>')
        }
        $own = if ($byFolder.ContainsKey($folder)) { $byFolder[$folder] | Sort-Object RelativePath } else { @() }
        if (@($own).Count -gt 0) {
            [void]$h.AppendLine('<table><tr><th>Name</th><th>Bytes</th><th>xxH128</th></tr>')
            foreach ($row in $own) {
                $display = [IO.Path]::GetFileName($row.RelativePath) + $(if ($row.Compressed -eq 'Yes') { '.7z' } else { '' })
                $link = & $href $pageDirFull $row.DataPath
                [void]$h.AppendLine("<tr><td><a href=""$link"">$(& $enc $display)</a></td><td>$($row.Length)</td><td>$(& $enc $row.xxH2Hash)</td></tr>")
            }
            [void]$h.AppendLine('</table>')
        }
        if (-not $folder) {
            if ($rows.Count -le $SearchRowThreshold) {
                # Embedded search: file:// pages cannot fetch a side file, so
                # the row list rides inline (name shown, path matched, href to
                # the object). JSON-escaped via ConvertTo-Json on the array.
                $searchRows = @(foreach ($row in $rows) {
                    ,@([string]$row.RelativePath,
                       (& $href $viewFull $row.DataPath),
                       $(if ($row.Compressed -eq 'Yes') { '.7z' } else { '' }))
                })
                # ConvertTo-Json does NOT escape '<' or '>' in PowerShell 7 and
                # this lands inside a <script> block, so a row named
                # '</script>...' would close it early (WP9 review, nit-2).
                # SR-055 keeps those characters out of any row this build
                # writes, so it takes a hand-edited manifest to reach - but
                # every other field on the page is encoded, and matching that
                # costs one line.
                $json = (ConvertTo-Json -InputObject $searchRows -Compress -Depth 3) -replace '<', '\u003c' -replace '>', '\u003e'
                [void]$h.AppendLine('<h2>Search</h2><input id="q" type="text" placeholder="type part of a path..." size="60"><ul id="hits"></ul>')
                [void]$h.AppendLine("<script>var R=$json;")
                [void]$h.AppendLine('document.getElementById("q").addEventListener("input",function(){var q=this.value.toLowerCase();var o=document.getElementById("hits");o.innerHTML="";if(q.length<2)return;var n=0;for(var i=0;i<R.length&&n<200;i++){if(R[i][0].toLowerCase().indexOf(q)>=0){var li=document.createElement("li");var a=document.createElement("a");a.href=R[i][1];a.textContent=R[i][0]+R[i][2];li.appendChild(a);o.appendChild(li);n++;}}});</script>')
            } else {
                [void]$h.AppendLine('<h2>Search</h2><p>This backup holds too many rows to embed a search index. Search INDEX.tsv instead:</p>')
                [void]$h.AppendLine('<pre>Select-String -LiteralPath INDEX.tsv -Pattern ''name-fragment''')
                [void]$h.AppendLine('grep -i ''name-fragment'' INDEX.tsv</pre>')
            }
        }
        [void]$h.AppendLine('</body></html>')
        [IO.File]::WriteAllText((Join-Path $pageDirFull 'INDEX.html'), $h.ToString(), [Text.UTF8Encoding]::new($false))
        $pages++
    }

    # The stamp is LAST: everything before it is discardably stale.
    [IO.File]::WriteAllText($stampPath, $stampWant + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    & $Log "Browse view regenerated at '$viewFull': $($rows.Count) row(s), $pages page(s)."
    return [pscustomobject]@{ Regenerated = $true; Rows = $rows.Count; Pages = $pages }
}

function Invoke-BackupSet {
    <#
    .SYNOPSIS
        Orchestrates the full backup pipeline for one set (AGENTS.md §2): walk +
        hash the source, sanitize the backup manifest, copy new data, evict
        removed files, preserve superseded bytes no live row still claims,
        finalize the dated snapshot, persist run state.
    #>
    # Implements: SR-014, SR-017, SR-035, SR-036, SR-055, LLR-014, LLR-017, LLR-035, LLR-036, LLR-055
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][hashtable]$Deps,
        [Parameter(Mandatory)][ref]$OverallSuccess,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$LogPaths,
        # SR-005/SR-028 test seam: pins this run's completion date (which dates the
        # NEXT run's snapshot). Defaults to now in production.
        [AllowNull()][Nullable[datetime]]$BackupTime
    )

    # 1. Resolve paths (SR-014: a set that can't even resolve still counts as a failure)
    try { $paths = Resolve-BackupSetPaths -Set $Set } catch {
        Write-Warning $_.Exception.Message
        $OverallSuccess.Value = $false
        return
    }

    # Completion date of the PREVIOUS backup names this run's snapshot (SR-005);
    # $null on the first backup ⇒ no snapshot. Read before we overwrite state.
    $priorBackupDate = Get-LastBackupRun -BackupRoot $paths.BkpPath
    $existingManifest = Join-Path $paths.BkpPath $script:Def.DatabaseFilename
    if ($null -eq $priorBackupDate -and (Test-Path -LiteralPath $existingManifest -PathType Leaf)) {
        $existingRows = @(Read-Manifest -FolderPath $paths.BkpPath)
        if ($existingRows.Count -gt 0) {
            throw "Backup state at '$($paths.BkpPath)' has no LastBackupRun, but its existing MANIFEST.csv contains $($existingRows.Count) row(s). Refusing to mutate it because the prior state could not be snapshotted safely."
        }
    }

    # 1.5 The witness gate the rest of the fleet already honors (SR-038/SR-039):
    # both restorers and prune refuse a manifest whose witness disagrees, but the
    # backup pipeline used to read the same manifest unchecked and then re-stamp
    # a FRESH witness over state derived from a torn index — laundering crash
    # damage into a permanent, silent hole. Mismatch/Malformed refuses the set
    # before anything is staged or mutated; Absent stays legal (a pre-SR-038
    # store must still back up). The distinct ErrorId lets the entry point map
    # this onto the SR-040 witness code (3) instead of the generic set failure.
    if (Test-Path -LiteralPath $existingManifest -PathType Leaf) {
        $witness = Test-ManifestWitness -FolderPath $paths.BkpPath
        if ($witness.Status -in 'Mismatch', 'Malformed') {
            Write-Error -ErrorId 'ManifestWitnessMismatch' -ErrorAction Stop -Message (
                "Backup manifest witness check failed at '$($paths.BkpPath)': $($witness.Detail) " +
                'Refusing to back up over a possibly torn index. Verify the store (-Action Verify) and, ' +
                'if the manifest proves intact or repairable, -RepairStorage re-publishes a matching witness.')
        }
    }
    $thisBackupDate  = if ($BackupTime) { [datetime]$BackupTime } else { Get-Date }

    # 2. Logger
    $logPath = Join-Path $paths.ChgPath 'backup.log'
    $log = New-Logger -LogFile $logPath
    $LogPaths.Add($logPath)
    & $log "----- Backup set '$($Set.Name)' starting -----"

    # 3. Guard staging folder
    try {
        $stagingFolder = Initialize-StagingFolder -ChgPath $paths.ChgPath -Log $log
    } catch {
        & $log "Failed to initialize staging folder: $($_.Exception.Message)" 'ERROR'
        $OverallSuccess.Value = $false
        return
    }

    # 4. Hash-recalc decision (B3: from persisted state, not mtimes)
    $lastHashRun = Get-LastHashRun -BackupRoot $paths.BkpPath
    $recalc = if ($lastHashRun) {
        Test-HashRecalcDue -FreqCode $Set.HashRecalcFreq -LastHashRun $lastHashRun
    } else {
        Test-HashRecalcDue -FreqCode $Set.HashRecalcFreq
    }
    & $log "HashRecalcFreq=$($Set.HashRecalcFreq), LastHashRun=$lastHashRun, Recalculate=$recalc"

    # 5. Update source manifest (B4: forced rehash when scheduled)
    & $log "Updating source manifest cache at '$($paths.SrcStatePath)'."
    $unportableNames = New-Object System.Collections.Generic.List[object]
    $unreadableDirs  = New-Object System.Collections.Generic.List[object]
    try {
        $sourceDb = Update-SourceManifest -SourcePath $paths.SrcPath -ManifestFolderPath $paths.SrcStatePath `
            -FfprobePath $Deps['ffprobe'] -ForceRehash:$recalc -UnportableOut $unportableNames `
            -UnreadableOut $unreadableDirs
    } catch {
        # A source file that cannot be read (open for write, AV hold) fails the
        # set loudly — but must not strand the still-empty staging folder, or
        # every LATER run refuses on the SR-017 stale-Temp guard instead of the
        # real cause. Temp holds nothing of value until the preserve/evict steps.
        Remove-Item -LiteralPath $stagingFolder -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    # 5.1 Portable-name guard (SR-055, human ruling 2026-08-23): a source
    # filename that cannot exist on both platforms was excluded by the scan —
    # BEFORE hashing, which would fail on names Windows cannot even open —
    # and is refused LOUDLY here, not half-handled downstream (7-Zip argument
    # quoting, the bash manifest parser). The skipped file gets no manifest
    # row and the set fails; a PREVIOUSLY stored row under such a name is left
    # frozen rather than evicted (see the step-8 filter) — the operator is
    # being told to fix the name at the source.
    $unportable = New-RelativePathMap
    foreach ($skipped in $unportableNames) {
        & $log "Skipping '$($skipped.RelativePath)': $($skipped.Reason). Rename it at the source; this set is marked failed (SR-055)." 'ERROR'
        $unportable[$skipped.RelativePath] = $true
        $OverallSuccess.Value = $false
    }

    # 5.2 Unreadable-directory guard (SR-057, 2026-08-24 review B1): -Force
    # made previously invisible hidden/system directories enumerable, and one
    # with a Deny ACE ('System Volume Information', another user's
    # $RECYCLE.BIN) must not abort the run with NO manifest written. The walk
    # reported it; the set fails LOUDLY here, everything reachable is still
    # backed up, and rows under the unreadable path are frozen (not evicted) —
    # we cannot know whether their files still exist.
    $unreadablePrefixes = New-Object System.Collections.Generic.List[string]
    foreach ($bad in $unreadableDirs) {
        & $log "Cannot enumerate '$($bad.Path)': $($bad.Message). Files beneath it are NOT backed up this run and existing rows there are frozen; this set is marked failed (SR-057). Point SourcePath below it, or grant read access." 'ERROR'
        $OverallSuccess.Value = $false
        $badFull = "$($bad.Path)"
        $srcRoot = (Resolve-Path -LiteralPath $paths.SrcPath).Path
        if ($badFull.StartsWith($srcRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relPrefix = $badFull.Substring($srcRoot.Length).TrimStart('\', '/')
            if ($relPrefix) { $unreadablePrefixes.Add($relPrefix + [IO.Path]::DirectorySeparatorChar) }
        }
    }

    # A previously populated source becoming completely empty is commonly an
    # unavailable/mis-mounted share. Treat it as unsafe before any backup bytes
    # are migrated or staged. Operators performing an intentional delete-all can
    # opt in per set with AllowEmptySource = $true; an initially empty source is
    # still valid.
    if ($sourceDb.Count -eq 0 -and (Test-Path -LiteralPath $existingManifest -PathType Leaf)) {
        $priorRows = @(Read-Manifest -FolderPath $paths.BkpPath)
        if ($priorRows.Count -gt 0 -and -not ([bool]$Set.AllowEmptySource)) {
            Remove-Item -LiteralPath $stagingFolder -Recurse -Force -ErrorAction SilentlyContinue
            throw "Source '$($paths.SrcPath)' is empty while the existing backup contains $($priorRows.Count) manifest row(s). Refusing delete-all; set AllowEmptySource = `$true for an intentional empty-source backup."
        }
    }

    # 5.5 Capacity-refusal machinery, shared by step 9.4 (SR-052). The MIGRATION
    # component that used to sit here died with the migration itself (SR-061) -
    # nothing already stored is re-formed, so there is nothing to size before
    # step 6. What survives is the refusal discipline: a refusal must not orphan
    # the staging folder, or the NEXT run aborts on the SR-017 stale-Temp guard
    # instead of on the real cause (same discipline as the AllowEmptySource
    # refusal above).
    $refuseCapacity = {
        param([string]$Message)
        Remove-Item -LiteralPath $stagingFolder -Recurse -Force -ErrorAction SilentlyContinue
        throw $Message
    }
    $sameVolume = ((Get-VolumeIdentity -Path $paths.BkpPath) -eq (Get-VolumeIdentity -Path $paths.ChgPath))

    # 6. Sanitize the backup manifest (SR-061: there is no layout migration).
    # Step 9.4 proves room for THIS RUN's content (SR-052). Blanking a missing
    # DataPath and warning about orphans is what survives here, and it is now
    # the store's ONLY orphan scan - linear in rows + pool files (SR-064).
    & $log "Sanitizing backup manifest at '$($paths.BkpPath)'."
    try {
        $backupDb = Test-BackupManifest -FolderRoot $paths.BkpPath -Log $log
    } catch {
        # Same discipline as step 5: a throw before Temp holds anything of
        # value must not strand it for the SR-017 guard.
        Remove-Item -LiteralPath $stagingFolder -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }

    # 7. Pre-backup snapshot into staging
    & $log "Saving pre-backup manifest to staging '$stagingFolder'."
    Write-Manifest -FolderPath $stagingFolder -Records $backupDb
    # The PRIOR state's directory sidecar (SR-065) travels with the prior
    # manifest: the snapshot describes the tree as it was, so this is the
    # existing file copied, not the one this run is about to write.
    $priorSidecar = Join-Path $paths.BkpPath $script:Def.DirectorySidecarName
    if (Test-Path -LiteralPath $priorSidecar -PathType Leaf) {
        Copy-Item -LiteralPath $priorSidecar -Destination $stagingFolder -Force
    }

    # 8. Diff
    $diff = Compare-SourceToBackup -SourceDb $sourceDb -BackupDb $backupDb
    # A file skipped by the SR-055 portable-name guard must not read as
    # "removed from source" — its existing row (if any) stays frozen. Same for
    # every row under an unreadable directory (SR-057, step 5.2): the walk
    # could not see those files, which is not evidence they are gone.
    if ($unportable.Count -gt 0 -or $unreadablePrefixes.Count -gt 0) {
        $stillRemoved = New-Object System.Collections.Generic.List[object]
        foreach ($removedRow in $diff.RemovedFromSource) {
            if ($unportable.ContainsKey($removedRow.RelativePath)) { continue }
            $underUnreadable = $false
            foreach ($prefix in $unreadablePrefixes) {
                if ($removedRow.RelativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $underUnreadable = $true; break
                }
            }
            if (-not $underUnreadable) { $stillRemoved.Add($removedRow) }
        }
        $diff.RemovedFromSource = $stillRemoved
    }
    & $log "New or changed files: $($diff.NewOrChanged.Count)"
    & $log "Removed files: $($diff.RemovedFromSource.Count)"
    # SR-005 supersession criterion: the manifest state changed. A dedup-served
    # add or shared-content removal moves no bytes but still changes the state.
    # (.Count direct — Compare-SourceToBackup always returns real lists, and
    # @() around a List reached via a PSObject property throws on PS 7.5.)
    $manifestChanged = ($diff.NewOrChanged.Count -gt 0) -or ($diff.RemovedFromSource.Count -gt 0)

    # 9. Working backup map (filesystem-faithful key comparison, SR-034)
    $backupMap = New-RelativePathMap
    foreach ($row in $backupDb) { $backupMap[$row.RelativePath] = $row }
    $changedCount = 0

    # 9.4 Capacity preflight (SR-052): the last point at which
    # none of THIS RUN'S CONTENT has been written. A refusal here fails this SET
    # (status 1) with no data file added, no manifest row changed and no staging
    # folder left behind; other sets still run (SR-014). It is not a promise that
    # the tree is byte-identical to the pre-run state: step 6 may have blanked
    # a row whose data file went missing (SR-053's heal input). It no longer
    # re-forms anything - the migration that once did died at WP9 step 3
    # (SR-061), and its own 5.5 preflight with it (WP5 review, finding m5).
    $demand = Get-BackupCapacityDemand -NewOrChanged $diff.NewOrChanged `
                -RemovedFromSource $diff.RemovedFromSource -BackupDb $backupDb -SameVolume $sameVolume
    try {
        Assert-BackupCapacity -BackupPath $paths.BkpPath -ChangePath $paths.ChgPath -Log $log `
            -BackupBytes $demand.BackupBytes -ChangeBytes $demand.ChangeBytes
    } catch { & $refuseCapacity $_.Exception.Message }

    # 10. Copy new/changed files. One retry budget for the whole set (SR-067):
    # a handful of transiently locked files get their retries, a systemically
    # unreadable tree cannot turn a scheduled run into an hours-long sleep.
    $retryBudgetMs = $script:CopyRetryBudgetMs
    foreach ($grp in ($diff.NewOrChanged | Group-Object xxH2Hash, Length)) {
        Invoke-BackupFileGroup `
            -Group $grp.Group `
            -SrcPath $paths.SrcPath -BkpPath $paths.BkpPath `
            -CompressEnabled ([bool]$Set.CompressEnabled) `
            -SevenZipPath $Deps['7z'] -BackupDb $backupDb `
            -BackupMap ([ref]$backupMap) -ChangedCount ([ref]$changedCount) `
            -Log $log -OverallSuccess $OverallSuccess -RetryBudgetMs ([ref]$retryBudgetMs)
    }

    # 11. Evict removed files to staging
    Move-RemovedFilesToStaging `
        -RemovedFromSource $diff.RemovedFromSource `
        -BkpPath $paths.BkpPath -StagingFolder $stagingFolder `
        -BackupMap ([ref]$backupMap) -ChangedCount ([ref]$changedCount) -Log $log `
        -OverallSuccess $OverallSuccess

    # 11.5 Preserve superseded bytes into the snapshot (SR-059, LLR-059).
    # Content addressing never overwrites an existing object at step 10, so
    # preservation runs AFTER the copy/evict steps and asks the exact
    # question: does any row of the FINAL manifest still claim the old object?
    # Frozen rows (SR-055/SR-057) and rows whose copy failed keep their claim,
    # so their bytes correctly stay in the pool — the pre-WP9 source-based
    # approximation moved them out (the D-1 family). A move failure is
    # aggregated, not thrown (SR-041): the run must reach step 13 so the
    # staging folder is finalized or discarded rather than orphaned for the
    # next run's SR-017 guard.
    Save-SupersededData -NewOrChanged $diff.NewOrChanged -BackupDb $backupDb `
        -FinalRows @($backupMap.Values) `
        -BkpPath $paths.BkpPath -StagingFolder $stagingFolder -Log $log -OverallSuccess $OverallSuccess

    # 12. Save updated backup manifest — CANONICAL (WP9 step 8): rows in
    # ordinal RelativePath order and every text column materialized as a
    # string ('' for null), so two runs over the same state write
    # byte-identical manifests. Step 7's viewstamp work caught the drift this
    # kills: fresh rows carried $null MediaMBPerSec while adopted rows carried
    # Import-Csv's '', and Export-Csv quotes the two differently.
    $backupDbFinal = [object[]]@($backupMap.Values | ForEach-Object {
        [pscustomobject]@{
            DataPath         = [string]$_.DataPath
            RelativePath     = [string]$_.RelativePath
            Length           = [string]$_.Length
            LastWriteTime    = $_.LastWriteTime
            xxH2Hash         = [string]$_.xxH2Hash
            Compressed       = [string]$_.Compressed
            StoredAsHashSize = [string]$_.StoredAsHashSize
            Duplicate        = [string]$_.Duplicate
            MediaMBPerSec    = [string]$_.MediaMBPerSec
        }
    })
    [Array]::Sort($backupDbFinal, [Comparison[object]] {
        param($a, $b) [string]::CompareOrdinal($a.RelativePath, $b.RelativePath) })
    Write-Manifest -FolderPath $paths.BkpPath -Records $backupDbFinal

    # 12.5 Directory sidecar (SR-065): the empty directories and folder
    # attributes MANIFEST.csv has no row type for. Written after the manifest so
    # a crash between them leaves a store whose sidecar is merely stale - which
    # is exactly the advisory failure mode the sidecar is designed around, and
    # never a reason a restore refuses. A failure here is a WARNING, not a set
    # failure: every byte is already stored and manifested.
    try {
        $dirRows = Get-SourceDirectoryRecord -SourcePath $paths.SrcPath `
                    -FileRelativePath @($sourceDb | ForEach-Object { $_.RelativePath }) -Log $log
        Write-DirectorySidecar -FolderPath $paths.BkpPath -Records $dirRows
        & $log "Directory sidecar: $($dirRows.Count) row(s) recorded (empty or attributed directories)."
    } catch {
        & $log "Directory sidecar not written: $($_.Exception.Message) (files and manifest are unaffected; empty directories and folder attributes will not be restored)." 'WARN'
    }

    # 13. Finalize the dated snapshot (of the PRIOR state) + reconstruct scripts
    New-ReconstructScript -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
    [void](Complete-ChangeFolder -ChgPath $paths.ChgPath -StagingFolder $stagingFolder -BkpPath $paths.BkpPath -ManifestChanged $manifestChanged -Log $log -SnapshotDate $priorBackupDate)

    # 14. De-duplicate data shared across snapshots
    Optimize-ChangeFolders -ChangeRoot $paths.ChgPath -BackupRoot $paths.BkpPath -Log $log

    # 15. Record state: hashes ran (B3) + this backup's completion date (dates the next snapshot)
    if ($recalc) { Set-LastHashRun -BackupRoot $paths.BkpPath -When $thisBackupDate }
    Set-LastBackupRun -BackupRoot $paths.BkpPath -When $thisBackupDate

    # 16. Browse view (SR-062): only for sets that asked, skipped while the
    # viewstamp matches the manifest. A failure here is a WARNING, not a set
    # failure: the view is cosmetic by construction — nothing in the engine or
    # the restorers reads it — and a completed backup must not be reported
    # failed over a browse page. -Action View rebuilds loudly on demand.
    if ([string]$Set.BrowseView -eq 'index' -and $paths.ViewPath) {
        try {
            [void](New-BrowseViewIndex -BackupRoot $paths.BkpPath -ViewRoot $paths.ViewPath -Log $log)
        } catch {
            & $log "Browse view generation failed: $($_.Exception.Message) (the backup itself is unaffected; -Action View retries loudly)" 'WARN'
        }
    }

    & $log "Changed files count = $changedCount"
    & $log "----- Backup set '$($Set.Name)' completed -----"
}

# endregion

# region Configuration loading (SR-042, SR-043)

# The ConfigVersion this build understands (SR-042, SR-063). Version 2 (WP9):
# the PreserveFolderTree layout selector is REMOVED — storage is always
# content-addressed — and BrowseView/ViewPath are added. A config declaring a
# HIGHER version is refused ("upgrade FileBackup"); a version-1 document is
# refused as TOO OLD rather than half-understood, because its key set differs.
# JSON has ONE number type, so an integral-valued number is that integer:
# "ConfigVersion": 2.0 is the same document as "ConfigVersion": 2 and is
# accepted; 2.5 is not. The published schema's `const: 2` agrees (TC-077).
$script:ConfigSchemaVersion = 2

function Assert-NoUnknownConfigKey {
    <#
    .SYNOPSIS
        Recursively rejects any JSON key the SR-042 schema does not define, at
        the top level, Tools, Secrets, and every BackupSets[] entry, naming the
        offending key by its full JSON path. Also bans Secrets.Credential (JSON
        cannot carry a PSCredential).
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Node,
        [Parameter(Mandatory)][string]$ConfigPath
    )

    $topLevelKeys = 'ConfigVersion', 'BackupSets', 'Tools', 'Secrets'
    $setKeys      = 'Name', 'SourcePath', 'BackupPath', 'ChangePath', 'HashRecalcFreq',
                    'CompressEnabled', 'SourceStatePath', 'AllowEmptySource',
                    'BrowseView', 'ViewPath'
    $toolsKeys    = 'SevenZipPath', 'FfprobePath'
    $secretsKeys  = 'ToEmail', 'FromEmail', 'SmtpServer', 'SmtpPort', 'Credential'
    # Removed keys get a NAMED diagnostic (SR-063, LLR-063): the generic
    # unknown-key message reads as a typo, and an author coming from v1 must be
    # told the layout selector is GONE, not misspelled.
    $retiredKeys  = @{
        PreserveFolderTree = 'PreserveFolderTree was removed in ConfigVersion 2: storage is always content-addressed. Remove the key.'
    }

    function Test-ConfigKeySet {
        param($Obj, [string[]]$Allowed, [string]$ObjJsonPath)
        foreach ($prop in $Obj.PSObject.Properties.Name) {
            if ($retiredKeys.Contains($prop)) {
                throw "Config '$ConfigPath' is invalid: $ObjJsonPath.$prop — $($retiredKeys[$prop])"
            }
            if ($prop -notin $Allowed) {
                throw "Config '$ConfigPath' is invalid: $ObjJsonPath.$prop — unrecognized key (expected one of: $($Allowed -join ', '))."
            }
        }
    }

    Test-ConfigKeySet -Obj $Node -Allowed $topLevelKeys -ObjJsonPath '$'

    if ($Node.PSObject.Properties.Name -contains 'Tools' -and $null -ne $Node.Tools) {
        Test-ConfigKeySet -Obj $Node.Tools -Allowed $toolsKeys -ObjJsonPath '$.Tools'
    }

    if ($Node.PSObject.Properties.Name -contains 'Secrets' -and $null -ne $Node.Secrets) {
        Test-ConfigKeySet -Obj $Node.Secrets -Allowed $secretsKeys -ObjJsonPath '$.Secrets'
        if ($Node.Secrets.PSObject.Properties.Name -contains 'Credential') {
            throw "Config '$ConfigPath' is invalid: `$.Secrets.Credential — JSON cannot carry a PSCredential (expected: omit Secrets.Credential; containerized runs are -NoMail)."
        }
    }

    $sets = @($Node.BackupSets)
    for ($i = 0; $i -lt $sets.Count; $i++) {
        if ($null -eq $sets[$i]) { continue }
        Test-ConfigKeySet -Obj $sets[$i] -Allowed $setKeys -ObjJsonPath "`$.BackupSets[$i]"
    }
}

function Test-ConfigValueJsonType {
    <#
    .SYNOPSIS
        Returns $true when a ConvertFrom-Json node has the given JSON type
        (SR-042). JSON has a single number type, so 'integer' accepts any
        numeric node whose value has no fractional part (1.0 is the integer 1).
    .PARAMETER Value
        The parsed node to classify.
    .PARAMETER JsonType
        One of string, boolean, integer, number, object, array.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][ValidateSet('string', 'boolean', 'integer', 'number', 'object', 'array')][string]$JsonType
    )

    if ($null -eq $Value) { return $false }
    switch ($JsonType) {
        'string'  { return ($Value -is [string]) }
        'boolean' { return ($Value -is [bool]) }
        'object'  { return ($Value -is [System.Management.Automation.PSCustomObject]) -or ($Value -is [hashtable]) }
        'array'   { return (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])) }
        'number'  { return (Test-IsJsonNumber -Value $Value) }
        'integer' {
            if (-not (Test-IsJsonNumber -Value $Value)) { return $false }
            # Culture-safe integral test (no string formatting), and one that
            # avoids [math]::Floor's ambiguous overload for BigInteger — a JSON
            # number too large for Int64 parses to that type and is integral.
            if (($Value -is [double]) -or ($Value -is [single])) {
                return ([double]$Value -eq [math]::Truncate([double]$Value))
            }
            if ($Value -is [decimal]) {
                return ([decimal]$Value -eq [math]::Truncate([decimal]$Value))
            }
            return $true
        }
    }
    return $false
}

function Test-IsJsonNumber {
    <#
    .SYNOPSIS
        True when a ConvertFrom-Json node is a JSON number (SR-042). Excludes
        [bool] and [char], which are .NET value types but not JSON numbers.
    .PARAMETER Value
        The parsed node to classify.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [char] -or $Value -is [string]) { return $false }
    return (
        ($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [short]) -or ($Value -is [byte]) -or
        ($Value -is [sbyte]) -or ($Value -is [uint32]) -or ($Value -is [uint64]) -or ($Value -is [uint16]) -or
        ($Value -is [double]) -or ($Value -is [single]) -or ($Value -is [decimal]) -or
        ($Value -is [System.Numerics.BigInteger])
    )
}

function Get-ConfigValueJsonTypeName {
    <#
    .SYNOPSIS
        Renders a parsed node's JSON type name for an SR-042 error message
        ("string", "number", "boolean", "array", "object", "null").
    .PARAMETER Value
        The parsed node to describe.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value)                                { return 'null' }
    if ($Value -is [bool])                               { return 'boolean' }
    if ($Value -is [string])                             { return "string ('$Value')" }
    if (Test-IsJsonNumber -Value $Value)                 { return "number ($Value)" }
    if (Test-ConfigValueJsonType -Value $Value -JsonType 'array')  { return 'array' }
    if (Test-ConfigValueJsonType -Value $Value -JsonType 'object') { return 'object' }
    return $Value.GetType().Name
}

function Test-BackupConfigurationShape {
    <#
    .SYNOPSIS
        Validates the BackupSets shape shared by the JSON and CLIXML config
        branches (SR-042): at least one set, five non-empty required strings,
        presence of CompressEnabled, and a recognized HashRecalcFreq.
        Message wording matches the pre-SR-042 checks verbatim so existing
        callers and tests are unaffected.
    .PARAMETER StrictTypes
        JSON only. Additionally type-checks EVERY schema-defined value against
        its JSON type before any coercion runs, so none of PowerShell's silent
        conversions can change the meaning of the document: [bool]'false' is
        $true (a quoted "false" for CompressEnabled/AllowEmptySource would
        enable the feature the operator disabled — and for AllowEmptySource
        that disarms the SR-036 delete-all refusal), and
        [string]@('x','y') is 'x y' (an array where a path belongs would become
        a literal two-word path). Covers every set string, the three set
        booleans, the optional Tools/Secrets strings, Secrets.SmtpPort as an
        integer, and the container types of BackupSets/Tools/Secrets.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Cfg,
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$StrictTypes
    )

    function Assert-ConfigValueType {
        param($Value, [string]$JsonType, [string]$JsonPath)
        if (-not (Test-ConfigValueJsonType -Value $Value -JsonType $JsonType)) {
            throw "Config '$ConfigPath' is invalid: $JsonPath — must be a JSON $JsonType, not $(Get-ConfigValueJsonTypeName -Value $Value) (expected a JSON $JsonType)."
        }
    }

    if ($StrictTypes -and $Cfg.PSObject.Properties.Name -contains 'BackupSets' -and $null -ne $Cfg.BackupSets) {
        # An array of sets, or a single bare set object that the loader wraps
        # (SR-042; the published schema's BackupSets anyOf mirrors this).
        if (-not ((Test-ConfigValueJsonType -Value $Cfg.BackupSets -JsonType 'array') -or
                  (Test-ConfigValueJsonType -Value $Cfg.BackupSets -JsonType 'object'))) {
            throw "Config '$ConfigPath' is invalid: `$.BackupSets — must be a JSON array of backup-set objects (or a single bare object), not $(Get-ConfigValueJsonTypeName -Value $Cfg.BackupSets)."
        }
    }

    $allSets = @($Cfg.BackupSets)
    $sets = @($allSets | Where-Object { $null -ne $_ })
    if ($sets.Count -eq 0) {
        throw "Configuration must define at least one BackupSets entry."
    }
    # Index over the raw array so the JSON path in a message names the entry as
    # it appears in the document.
    for ($i = 0; $i -lt $allSets.Count; $i++) {
        $set = $allSets[$i]
        if ($null -eq $set) { continue }
        $setPath = "`$.BackupSets[$i]"
        if ($StrictTypes) { Assert-ConfigValueType -Value $set -JsonType 'object' -JsonPath $setPath }

        foreach ($field in 'Name', 'SourcePath', 'BackupPath', 'ChangePath', 'HashRecalcFreq') {
            if ($StrictTypes) {
                if ($set.PSObject.Properties.Name -notcontains $field) {
                    throw "Every backup set must define a non-empty '$field'."
                }
                Assert-ConfigValueType -Value $set.$field -JsonType 'string' -JsonPath "$setPath.$field"
            }
            if ([string]::IsNullOrWhiteSpace([string]$set.$field)) {
                throw "Every backup set must define a non-empty '$field'."
            }
        }
        # SR-063: the retired key is refused BY NAME in EVERY format. CLIXML is
        # exempt from the closed schema, so without this a legacy CLIXML config
        # would keep saying "mirror the tree" while the engine content-addresses
        # everything — the exact silent divergence WP9 exists to kill (work
        # order §9 Q3). The JSON branch normally refuses it one step earlier in
        # Assert-NoUnknownConfigKey, with the same wording.
        if ($set.PSObject.Properties.Name -contains 'PreserveFolderTree') {
            throw "Config '$ConfigPath' is invalid: $setPath.PreserveFolderTree — PreserveFolderTree was removed in ConfigVersion 2: storage is always content-addressed. Remove the key."
        }
        foreach ($field in @('CompressEnabled')) {
            if ($set.PSObject.Properties.Name -notcontains $field) {
                throw "Backup set '$($set.Name)' must define '$field' as true or false."
            }
            if ($StrictTypes) { Assert-ConfigValueType -Value $set.$field -JsonType 'boolean' -JsonPath "$setPath.$field" }
        }
        if ($StrictTypes) {
            if ($set.PSObject.Properties.Name -contains 'SourceStatePath') {
                Assert-ConfigValueType -Value $set.SourceStatePath -JsonType 'string' -JsonPath "$setPath.SourceStatePath"
            }
            # The dangerous one: "AllowEmptySource": "false" would coerce true
            # and disarm the SR-036 delete-all refusal.
            if ($set.PSObject.Properties.Name -contains 'AllowEmptySource') {
                Assert-ConfigValueType -Value $set.AllowEmptySource -JsonType 'boolean' -JsonPath "$setPath.AllowEmptySource"
            }
        }
        if ([string]$set.HashRecalcFreq -notin 'A', 'E', 'D', 'W', 'M', 'Y', 'N') {
            throw "Backup set '$($set.Name)' has invalid HashRecalcFreq '$($set.HashRecalcFreq)'. Expected A, E, D, W, M, Y, or N."
        }
        # SR-063 vocabulary: exact-lowercase 'off'|'index', matching the
        # published schema's enum so TC-077's parity holds. 'link' is refused
        # BY NAME — reserved, not a typo (the design record defers it).
        if ($set.PSObject.Properties.Name -contains 'BrowseView' -and $null -ne $set.BrowseView) {
            if ($StrictTypes) { Assert-ConfigValueType -Value $set.BrowseView -JsonType 'string' -JsonPath "$setPath.BrowseView" }
            $bv = [string]$set.BrowseView
            if ($bv -ceq 'link') {
                throw "Backup set '$($set.Name)' has BrowseView 'link': reserved but not implemented (a linked view is deferred by the WP9 design record). Use 'off' or 'index'."
            }
            if ($bv -cnotin 'off', 'index') {
                throw "Backup set '$($set.Name)' has invalid BrowseView '$bv'. Expected 'off' or 'index' ('link' is reserved)."
            }
        }
        if ($StrictTypes -and $set.PSObject.Properties.Name -contains 'ViewPath' -and $null -ne $set.ViewPath) {
            Assert-ConfigValueType -Value $set.ViewPath -JsonType 'string' -JsonPath "$setPath.ViewPath"
        }
    }

    if (-not $StrictTypes) { return }

    if ($Cfg.PSObject.Properties.Name -contains 'Tools' -and $null -ne $Cfg.Tools) {
        Assert-ConfigValueType -Value $Cfg.Tools -JsonType 'object' -JsonPath '$.Tools'
        foreach ($field in 'SevenZipPath', 'FfprobePath') {
            if ($Cfg.Tools.PSObject.Properties.Name -contains $field -and $null -ne $Cfg.Tools.$field) {
                Assert-ConfigValueType -Value $Cfg.Tools.$field -JsonType 'string' -JsonPath "`$.Tools.$field"
            }
        }
    }

    if ($Cfg.PSObject.Properties.Name -contains 'Secrets' -and $null -ne $Cfg.Secrets) {
        $secrets = $Cfg.Secrets
        Assert-ConfigValueType -Value $secrets -JsonType 'object' -JsonPath '$.Secrets'
        foreach ($field in 'ToEmail', 'FromEmail', 'SmtpServer') {
            if ($secrets.PSObject.Properties.Name -contains $field -and $null -ne $secrets.$field) {
                Assert-ConfigValueType -Value $secrets.$field -JsonType 'string' -JsonPath "`$.Secrets.$field"
            }
        }
        if ($secrets.PSObject.Properties.Name -contains 'SmtpPort' -and $null -ne $secrets.SmtpPort) {
            Assert-ConfigValueType -Value $secrets.SmtpPort -JsonType 'integer' -JsonPath '$.Secrets.SmtpPort'
        }
    }
}

function Resolve-BackupSetDefaults {
    <#
    .SYNOPSIS
        Materializes each backup set's optional fields to their documented
        defaults (SourceStatePath = SourcePath, AllowEmptySource = $false,
        BrowseView = 'off', ViewPath = '<BackupPath>_View') and normalizes
        casing/types, so the engine's own [bool] / ToUpperInvariant casts at
        point of use become belt-and-braces (SR-042, SR-063).
    .PARAMETER Sets
        Raw BackupSets objects (JSON or CLIXML), already shape-validated by
        Test-BackupConfigurationShape.
    .OUTPUTS
        [pscustomobject[]] — one normalized object per input set.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Sets)

    foreach ($set in $Sets) {
        $sourceStatePath = if ([string]::IsNullOrWhiteSpace([string]$set.SourceStatePath)) {
            [string]$set.SourcePath
        } else {
            [string]$set.SourceStatePath
        }
        $allowEmptySource = ($set.PSObject.Properties.Name -contains 'AllowEmptySource') -and $null -ne $set.AllowEmptySource -and [bool]$set.AllowEmptySource
        # BrowseView defaults OFF (work order §9 Q2): a config that never asked
        # for a view pays no per-run cost. ViewPath defaults beside the backup
        # root — same volume by construction, outside both roots.
        $browseView = if ($set.PSObject.Properties.Name -contains 'BrowseView' -and
                          -not [string]::IsNullOrWhiteSpace([string]$set.BrowseView)) {
            [string]$set.BrowseView
        } else { 'off' }
        $viewPath = if ($set.PSObject.Properties.Name -contains 'ViewPath' -and
                        -not [string]::IsNullOrWhiteSpace([string]$set.ViewPath)) {
            [string]$set.ViewPath
        } else { ([string]$set.BackupPath).TrimEnd('\', '/') + '_View' }

        [pscustomobject]@{
            Name               = [string]$set.Name
            SourcePath         = [string]$set.SourcePath
            SourceStatePath    = $sourceStatePath
            BackupPath         = [string]$set.BackupPath
            ChangePath         = [string]$set.ChangePath
            HashRecalcFreq     = ([string]$set.HashRecalcFreq).ToUpperInvariant()
            CompressEnabled    = [bool]$set.CompressEnabled
            AllowEmptySource   = $allowEmptySource
            BrowseView         = $browseView
            ViewPath           = $viewPath
        }
    }
}

function Import-BackupConfiguration {
    <#
    .SYNOPSIS
        Loads and validates a FileBackup configuration file (JSON or CLIXML).
    .DESCRIPTION
        Dispatches on the file extension. The JSON branch enforces the SR-042
        versioned, closed schema — a required integer ConfigVersion (checked
        first, in document order), no unrecognized key at any level, the JSON
        type of EVERY schema-defined value (see Test-BackupConfigurationShape's
        -StrictTypes), and no Secrets.Credential — before
        Resolve-BackupSetDefaults materializes
        optional-field defaults. The CLIXML branch is the unversioned legacy
        native-Windows form: it runs the same per-set shape check but skips the
        version, closed-schema, and credential rules. Every rejection is a
        single terminating error naming the offending key/JSON path, reported
        in first-failure-in-document-order.

        A JSON config declaring more than one BackupSets entry is not an
        error — the engine still processes every set — but logs a WARN naming
        the count and pointing at IF-001's one-set-per-invocation ruling.
    .PARAMETER Path
        Resolved path to the .json or .xml config file.
    .PARAMETER Log
        Optional logger scriptblock (as returned by New-Logger), used only for
        the multi-set-JSON warning above. Errors are always thrown, never
        logged here — config loading runs before any logger normally exists.
    .OUTPUTS
        [pscustomobject] with ConfigVersion (int, or $null for CLIXML), Sets
        (defaults materialized, HashRecalcFreq upper-cased, booleans real
        [bool]), Tools, Secrets.
    #>
    # Implements: SR-042, LLR-042
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [scriptblock]$Log
    )

    $extension = [System.IO.Path]::GetExtension($Path)
    switch ($extension.ToLowerInvariant()) {
        '.json' {
            $raw = Get-Content -LiteralPath $Path -Raw
            try {
                $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
            } catch {
                throw "Config '$Path' is invalid: `$ — not valid JSON (expected a JSON document). $($_.Exception.Message)"
            }

            if ($cfg.PSObject.Properties.Name -notcontains 'ConfigVersion') {
                throw "Config '$Path' is invalid: `$.ConfigVersion — missing (expected an integer; this build supports up to $script:ConfigSchemaVersion)."
            }
            $rawVersion = $cfg.ConfigVersion
            if (-not (Test-ConfigValueJsonType -Value $rawVersion -JsonType 'integer')) {
                throw "Config '$Path' is invalid: `$.ConfigVersion — must be an integer with no fractional part, got $(Get-ConfigValueJsonTypeName -Value $rawVersion)."
            }
            # Range-check BEFORE the [int] cast: a JSON number outside Int32 is
            # an unsupported version, and must be refused as such rather than
            # overflowing (or being caught by the fractional-part test by luck).
            if ($rawVersion -lt 1) {
                throw "Config '$Path' is invalid: `$.ConfigVersion — must be >= 1, got $rawVersion."
            }
            if ($rawVersion -gt $script:ConfigSchemaVersion) {
                throw "Config '$Path' is invalid: `$.ConfigVersion — config declares version $rawVersion; this build supports up to $script:ConfigSchemaVersion — upgrade FileBackup."
            }
            # SR-063: version 1 is refused as TOO OLD, not half-understood —
            # its key set includes the removed PreserveFolderTree selector.
            if ($rawVersion -lt $script:ConfigSchemaVersion) {
                throw ("Config '$Path' is invalid: `$.ConfigVersion — config declares version $rawVersion, which is too old for this build (SR-063). " +
                       "Version 2 removed PreserveFolderTree (storage is always content-addressed) and added BrowseView/ViewPath; " +
                       "update the document and set ConfigVersion to $script:ConfigSchemaVersion.")
            }
            $version = [int]$rawVersion

            Assert-NoUnknownConfigKey -Node $cfg -ConfigPath $Path
            Test-BackupConfigurationShape -Cfg $cfg -ConfigPath $Path -StrictTypes

            $sets = @(Resolve-BackupSetDefaults -Sets @($cfg.BackupSets | Where-Object { $null -ne $_ }))
            if ($sets.Count -gt 1 -and $Log) {
                & $Log ("Config '{0}' declares {1} BackupSets entries. FileBackup will process all of them, but IF-001 rules one BackupSet per container invocation — this JSON config is outside that contract for containerized use." -f $Path, $sets.Count) 'WARN'
            }

            [pscustomobject]@{
                ConfigVersion = $version
                Sets          = $sets
                Tools         = if ($cfg.PSObject.Properties.Name -contains 'Tools') { $cfg.Tools } else { [pscustomobject]@{} }
                Secrets       = if ($cfg.PSObject.Properties.Name -contains 'Secrets') { $cfg.Secrets } else { $null }
            }
        }
        '.xml' {
            $cfg = Import-Clixml -LiteralPath $Path
            Test-BackupConfigurationShape -Cfg $cfg -ConfigPath $Path
            $sets = @(Resolve-BackupSetDefaults -Sets @($cfg.BackupSets | Where-Object { $null -ne $_ }))

            [pscustomobject]@{
                ConfigVersion = $null
                Sets          = $sets
                Tools         = $cfg.Tools
                Secrets       = $cfg.Secrets
            }
        }
        default {
            throw "Unsupported config format '$extension'. Use a .xml (CLIXML) or .json file."
        }
    }
}

# endregion

Export-ModuleMember -Function @(
    'Test-IsInfrastructureFile', 'Test-PortableRelativePath', 'Get-DataFile',
    'Get-LastHashRun', 'Set-LastHashRun',
    'Get-LastBackupRun', 'Set-LastBackupRun',
    'Resolve-OptionalTool', 'Initialize-Dependencies', 'Get-MediaMBPerSec',
    'Get-SourceDirectoryRecord', 'Write-DirectorySidecar',
    'Get-CopyRetryDelayMs', 'Test-CopyFailureIsTransient',
    'Test-HashRecalcDue', 'Update-SourceManifest', 'Copy-SourceFileToBackup',
    'Test-BackupManifest',
    'Get-BackupContentIndex', 'Optimize-ChangeFolders',
    'Get-SnapshotPrunePlan', 'Get-BackupSnapshot', 'Get-PoolSnapshotFolder',
    'Test-StorageFormAgreement', 'Test-PoolResolves', 'Assert-PrunePrecondition',
    'Get-PruneCapacityRefusal', 'Remove-CommittedPruneResidue',
    'Get-StoredFileForm', 'Get-StorageFormFinding', 'Get-BackupKitRevision',
    'Test-BackupStorageForm', 'Repair-BackupStorageForm', 'Update-BackupSnapshotKit',
    'Invoke-PruneEntrySweep', 'Copy-ReHomedDataFile', 'Publish-PruneManifest',
    'Complete-PruneDeletion', 'Remove-BackupSnapshot', 'Get-PruneBatchExitCode',
    'Get-BackupCapacityDemand', 'Assert-BackupCapacity',
    'New-ReconstructScript', 'Resolve-BackupSetPaths', 'Initialize-StagingFolder',
    'Compare-SourceToBackup', 'Invoke-BackupFileGroup', 'Move-RemovedFilesToStaging',
    'Save-SupersededData', 'Complete-ChangeFolder', 'Invoke-BackupSet',
    'New-BrowseViewIndex',
    'Import-BackupConfiguration'
)
