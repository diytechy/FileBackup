<#
.SYNOPSIS
    FileBackup engine — everything needed to *produce* a backup.

.DESCRIPTION
    Depends on FileBackup.Common.psm1 (restore-safe primitives). This module is
    NOT deployed into backup folders; only Common is. It contains the bounded
    backup run (docs/plans/bounded-run-loop.md: the source walk, the object
    index, the per-file capture and the snapshot publication), the retention
    mechanism, the storage audit, the reconstruct-script generator, and the
    per-set orchestrator Invoke-BackupSet.

    Bug fixes folded in (see CHANGELOG / README "Known issues"):
        B2  Test-HashRecalcDue treats DateTime.MinValue as "never run".
        B3  Last-hash-run is persisted in a state file, not inferred from mtimes.
        B4  The hash-recalc decision now actually drives a forced rehash.
        B6  Only the *root* MANIFEST.csv is skipped; nested ones are real files.
        B8  Hash-group lookups are wrapped with @() before indexing.
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
        $script:Def.ReconstructCmdName,
        $script:Def.ReconstructCommandName,
        # Kept forever: pre-revision-10 stores still hold one, and dropping it
        # here would make every run report it as an orphan (SR-022).
        $script:Def.ReconstructLegacyBatName,
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
        # Write-Manifest's own publish-by-rename staging file (SR-082): a kill
        # between the Export-Csv into it and the rename over MANIFEST.csv leaves
        # it behind. It is never data and never referenced by a row, so it must
        # not be backed up, warned about as an orphan, or read as a storage-form
        # finding (SR-083). Root-level only, like the rest: a nested user file
        # called MANIFEST.csv.tmp is data (B6).
        $script:Def.DatabaseTempFilename,
        # The directory sidecar (SR-065). Root-level only, like the rest: a
        # nested user file called DIRECTORIES.csv is data (B6).
        $script:Def.DirectorySidecarName,
        # New-ReconstructScript's publish-by-rename staging files ('<kit file>.tmp'):
        # a kill between the write and the rename leaves one behind, and it is
        # never data (review 2026-10-26 A4). Root-level only, like the rest.
        "$($script:Def.ReconstructPs1Name).tmp", "$($script:Def.ReconstructCmdName).tmp",
        "$($script:Def.ReconstructCommandName).tmp", "$($script:Def.ReconstructShName).tmp",
        "$($script:Def.CommonModuleName).tmp", 'System.IO.Hashing.dll.tmp', 'RECONSTRUCT.paths.json.tmp'
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

function Get-CaseOnlyCollision {
    <#
    .SYNOPSIS
        Finds the relative paths that differ from another one only in letter
        case, and gives each a reason naming the paths it collides with
        (SR-055).

    .DESCRIPTION
        Two such paths are two files on a case-sensitive source (Linux, the
        container, a case-sensitive NTFS folder), but a Windows restore can
        hold only one of them: the second overwrites the first and the restore
        still reports success (review 2026-10-26, restorers F5). So, by the
        Owner's ruling on that review's item 7, every member of such a group
        is as unportable as a name Windows cannot hold at all.

        Whole relative paths are compared, so a collision at any level is
        found ('Docs\a.txt' and 'docs\a.txt'), while two different files under
        folders that differ only in case ('Docs\a.txt', 'docs\b.txt') are not
        a collision: both restore, into one folder. The comparison is
        OrdinalIgnoreCase, the one the restorer's case-insensitive path map
        collapses by. On a Windows source it normally finds nothing.

        A library counts its paths in the hundreds of thousands, so the
        comparison is made by .NET set operations, not by a PowerShell loop:
        on the development PC a loop over 180,000 paths took 2 to 10 s, the
        sets 0.1 s (0.2 s when some collide). Only the members of a collision
        are ever looped over.

    .PARAMETER RelativePath
        The relative paths to compare, as the walk produced them.

    .OUTPUTS
        [hashtable] keyed case-sensitively: each colliding path -> the reason,
        naming the others. Empty when nothing collides.
    #>
    # Implements: SR-055, LLR-055
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseLiteralInitializerForHashtable', '',
        Justification = 'The Ordinal comparer IS the point: a literal hashtable is case-insensitive, and the members of a group differ only in case.')]
    param(
        [AllowNull()][AllowEmptyCollection()][string[]]$RelativePath
    )
    $reasons = [hashtable]::new(0, [System.StringComparer]::Ordinal)
    if ($null -eq $RelativePath -or $RelativePath.Count -lt 2) { return $reasons }
    # A case-insensitive set keeps the first spelling of each path. When it
    # is as large as the exact set, no two paths differ only in case.
    $exact  = [System.Collections.Generic.HashSet[string]]::new($RelativePath, [System.StringComparer]::Ordinal)
    $folded = [System.Collections.Generic.HashSet[string]]::new($RelativePath, [System.StringComparer]::OrdinalIgnoreCase)
    if ($folded.Count -eq $exact.Count) { return $reasons }
    # The later spellings (the exact set less the first ones), then the first
    # spellings they collide with: together, every member of every group.
    $later = $exact
    $later.ExceptWith($folded)
    $firsts = [System.Collections.Generic.HashSet[string]]::new($folded, [System.StringComparer]::OrdinalIgnoreCase)
    $firsts.IntersectWith($later)
    $groups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @($firsts) + @($later)) {
        if (-not $groups.ContainsKey($path)) { $groups[$path] = [System.Collections.Generic.List[string]]::new() }
        $groups[$path].Add($path)
    }
    foreach ($group in $groups.Values) {
        # Ordinal order, so the reason reads the same on every run.
        $members = $group.ToArray()
        [System.Array]::Sort([System.Array]$members, [System.Collections.IComparer][System.StringComparer]::Ordinal)
        foreach ($member in $members) {
            $others = @($members | Where-Object { $_ -cne $member } | ForEach-Object { "'$_'" }) -join ', '
            $reasons[$member] = "its path differs only in letter case from $others, and a Windows restore can hold only one of them"
        }
    }
    return $reasons
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
    # Implements: SR-057, SR-074, LLR-057, LLR-078
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [AllowNull()][System.Collections.Generic.List[object]]$EnumerationErrorOut
    )
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    # -Force (SR-057): hidden/dot files are data — without it they were never
    # backed up, and -Recurse skipped hidden DIRECTORIES entirely (D-4).
    #
    # But -Force also exposed the two pseudo-folders Windows puts at the ROOT of
    # every NTFS volume (SR-074), and they are not data at all. Both the files
    # AND the enumeration errors are dropped here: 'System Volume Information'
    # is unreadable by design, so its error used to mark the whole set failed —
    # a SourcePath of 'D:\' could never report success — and $RECYCLE.BIN IS
    # readable by its owner, so its deleted files were being backed up.
    if ($null -ne $EnumerationErrorOut) {
        $enumErr = $null
        $found = Get-ChildItem -LiteralPath $resolved -Recurse -File -Force `
            -ErrorAction SilentlyContinue -ErrorVariable enumErr |
            Where-Object { -not (Test-IsInfrastructureFile -Root $resolved -FullPath $_.FullName) -and
                           -not (Test-IsVolumeRootPseudoPath -Root $resolved -FullPath $_.FullName) }
        foreach ($e in @($enumErr)) {
            $path = "$($e.TargetObject)"
            if ($path -and (Test-IsVolumeRootPseudoPath -Root $resolved -FullPath $path)) { continue }
            $EnumerationErrorOut.Add([pscustomobject]@{
                Path = $path; Message = $e.Exception.Message })
        }
        return $found
    }
    Get-ChildItem -LiteralPath $resolved -Recurse -File -Force |
        Where-Object { -not (Test-IsInfrastructureFile -Root $resolved -FullPath $_.FullName) -and
                       -not (Test-IsVolumeRootPseudoPath -Root $resolved -FullPath $_.FullName) }
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
    <#
    .SYNOPSIS
        Merges one field into FileBackupState.json, so LastHashRun and
        LastBackupRun coexist instead of clobbering each other.

    .DESCRIPTION
        Published by rename: a crash mid-write must not leave a torn JSON that
        Read-BackupState refuses forever, as the manifest is published. The
        temp file is flushed to the disk first, so a power loss after the
        rename cannot leave the state file empty or full of NULs (review
        2026-10-26 A1).

    .PARAMETER BackupRoot
        The backup root holding the state file.

    .PARAMETER Name
        The field.

    .PARAMETER Value
        Its value.
    #>
    # Implements: SR-005, SR-011, SR-082
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()]$Value
    )
    $state = Read-BackupState -BackupRoot $BackupRoot
    $state[$Name] = $Value
    $statePath = Join-Path $BackupRoot 'FileBackupState.json'
    $tmpPath = "$statePath.tmp"
    $state | ConvertTo-Json | Set-Content -LiteralPath $tmpPath -Encoding UTF8
    Sync-FileToDisk -LiteralPath $tmpPath
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
        failed it, and a directory row is advisory. So are directories whose
        paths differ from another's only in letter case: a Windows restore
        makes one folder of them (Get-CaseOnlyCollision).

        The volume-root pseudo-folders ($RECYCLE.BIN, System Volume Information)
        are skipped exactly as the source walk skips their files (SR-074):
        recorded, every restore of a volume-root backup recreated them.

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
    # Implements: SR-065, SR-074, SR-055, LLR-065
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
    $caseCollision = Get-CaseOnlyCollision -RelativePath ([string[]]@(foreach ($d in $dirs) { $d.FullName.Substring($root.Length).TrimStart('\', '/') }))

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($root.Length).TrimStart('\', '/')
        if (-not $rel) { continue }
        # Not the user's folders, only at a volume root's top level (SR-074,
        # review 2026-10-26): Get-SourceFileList drops their files the same way.
        if (Test-IsVolumeRootPseudoPath -Root $root -FullPath $d.FullName) { continue }

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
        if ($caseCollision.ContainsKey($rel)) {
            if ($Log) { & $Log "Directory '$rel' is not recorded in the directory sidecar: $($caseCollision[$rel]) (SR-055/SR-065)." 'WARN' }
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

# region Backup manifest integrity + storage-layout migration

function Get-FolderFileSet {
    <#
    .SYNOPSIS
        The names of a folder's top-level files, from ONE listing, as a set
        compared the way the platform compares file names.

    .DESCRIPTION
        Asking the set replaces a Test-Path per manifest row - the stat storm of
        the 2026-09-06 defect review. Since the bounded run keeps a snapshot's
        DataPaths (most of them naming objects still in the backup root), a
        per-row probe would cost a stat for nearly every row of every snapshot.

    .PARAMETER Folder
        The folder.

    .OUTPUTS
        [System.Collections.Generic.HashSet[string]] (empty when the folder is
        absent or cannot be listed).
    #>
    # Implements: SR-064, LLR-062
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Folder)
    $comparer = if ($IsWindows) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $set = [System.Collections.Generic.HashSet[string]]::new($comparer)
    try {
        foreach ($f in [System.IO.DirectoryInfo]::new($Folder).EnumerateFiles()) { [void]$set.Add($f.Name) }
    } catch {
        Write-Verbose "Could not list '$Folder': $($_.Exception.Message)"
    }
    return , $set
}

function Test-FolderHoldsFile {
    <#
    .SYNOPSIS
        True when a folder holds the named file: answered from its listing set
        for a plain name, by a probe for a name with a path separator (only a
        legacy path-addressed store has one).

    .PARAMETER Files
        Get-FolderFileSet's set for the folder, or $null to probe.

    .PARAMETER Folder
        The folder.

    .PARAMETER Name
        The DataPath.

    .OUTPUTS
        [bool]
    #>
    # Implements: SR-064, LLR-062
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Files,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -ne $Files -and $Name.IndexOfAny([char[]]@([char]92, [char]47)) -lt 0) { return $Files.Contains($Name) }
    return (Test-Path -LiteralPath (Join-Path $Folder $Name) -PathType Leaf)
}

function Get-BackupContentIndex {
    <#
    .SYNOPSIS
        Builds the physical content index over a backup pool (backup root +
        snapshot folders): "<xxH2Hash>|<Length>" -> every folder that actually
        holds those bytes, plus each folder's manifest.

    .DESCRIPTION
        One scan for the retention mechanism and the storage audit (LLR-047);
        the backup run uses Get-StoreObjectIndex instead. Retention (SR-045/SR-047) uses it
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

    .PARAMETER IncludeManifests
        Retain each folder's whole manifest in Folders[].Manifest. Off by default
        (M-1, defect review 2026-10-05): a retained manifest costs ~2.3 KB per row,
        so the lean default keeps only DataPaths. Callers that read whole rows
        (prune, pool-resolve, the Verify/Rollback paths) pass it.

    .OUTPUTS
        [pscustomobject] Map (hashtable key -> List of location records with
        LocationType/Folder/DataPath/FullPath/IsBackup/FolderOrder) and Folders
        (one record per indexed folder: Folder, Name, Order, IsBackup, DataPaths,
        Files - the set of the folder's top-level file names, from one listing -
        plus Manifest only under -IncludeManifests).
    #>
    # Implements: SR-026, SR-045, SR-047, LLR-047
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][string[]]$SnapshotFolder,
        [switch]$IncludeManifests
    )
    $map = @{}   # "<hash>|<len>" -> list of location records

    $addToMap = {
        param([string]$LocationType, [string]$Folder, [object]$Row, [int]$FolderOrder, [object]$Files)
        if ([string]::IsNullOrWhiteSpace($Row.DataPath)) { return }
        if ([string]::IsNullOrWhiteSpace($Row.xxH2Hash)) { return }
        $key  = "$($Row.xxH2Hash)|$($Row.Length)"
        $full = Join-Path $Folder $Row.DataPath
        if (-not (Test-FolderHoldsFile -Files $Files -Folder $Folder -Name $Row.DataPath)) { return }
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

    # Reads one manifest into the map and returns its non-blank DataPaths as an
    # array. The manifest is then unreferenced unless -IncludeManifests keeps it.
    $indexFolder = {
        param([string]$LocationType, [string]$Folder, [object[]]$Rows, [int]$FolderOrder, [object]$Files)
        $dps = New-Object System.Collections.Generic.List[string]
        foreach ($row in $Rows) {
            & $addToMap $LocationType $Folder $row $FolderOrder $Files
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) { $dps.Add([string]$row.DataPath) }
        }
        return ,($dps.ToArray())
    }

    if (Test-Path -LiteralPath (Join-Path $BackupRoot $script:Def.DatabaseFilename) -PathType Leaf) {
        $backupManifest = Read-Manifest -FolderPath $BackupRoot
        $backupFiles = Get-FolderFileSet -Folder $BackupRoot
        $backupDataPaths = & $indexFolder 'Backup' $BackupRoot $backupManifest -1 $backupFiles
        if ($IncludeManifests) {
            $folders.Add([pscustomobject]@{
                Folder = $BackupRoot; Name = [IO.Path]::GetFileName($BackupRoot)
                Order = -1; IsBackup = $true; DataPaths = $backupDataPaths; Files = $backupFiles; Manifest = $backupManifest
            })
        } else {
            $folders.Add([pscustomobject]@{
                Folder = $BackupRoot; Name = [IO.Path]::GetFileName($BackupRoot)
                Order = -1; IsBackup = $true; DataPaths = $backupDataPaths; Files = $backupFiles
            })
        }
        $backupManifest = $null
    }

    $folderOrder = 0
    # Where-Object guards the AGENTS.md §4 hazard: an empty result reaching this
    # parameter as $null makes @($SnapshotFolder) one $null element.
    foreach ($dir in @($SnapshotFolder | Where-Object { $_ })) {
        $folderOrder++
        $manifest = Read-Manifest -FolderPath $dir
        $files = Get-FolderFileSet -Folder $dir
        $dataPaths = & $indexFolder 'Change' $dir $manifest $folderOrder $files
        if ($IncludeManifests) {
            $folders.Add([pscustomobject]@{
                Folder = $dir; Name = [IO.Path]::GetFileName($dir)
                Order = $folderOrder; IsBackup = $false; DataPaths = $dataPaths; Files = $files; Manifest = $manifest
            })
        } else {
            $folders.Add([pscustomobject]@{
                Folder = $dir; Name = [IO.Path]::GetFileName($dir)
                Order = $folderOrder; IsBackup = $false; DataPaths = $dataPaths; Files = $files
            })
        }
        $manifest = $null
    }

    return [pscustomobject]@{ Map = $map; Folders = $folders }
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
        (tolerating the _NNN collision disambiguator older builds appended).
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

        The destination is where a keeper would be elected had the target
        never existed — the backup root when it demands
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

    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($snapshots | ForEach-Object { $_.FullName }) -IncludeManifests
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
                -not (Test-FolderHoldsFile -Files $f.Files -Folder $f.Folder -Name $row.DataPath)
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
        # them - the backup run refuses a legacy store (SR-061) and both
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
    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder @($snapshots | ForEach-Object { $_.FullName }) -IncludeManifests

    # WP7 (SR-046 as amended): whether a blank row's located copy must agree in
    # FORM depends on the kit that would restore it — the folder's own. Cached
    # per folder; revision >= 2 decides form from the located file (SR-050).
    $kitRevisionOf = @{}

    foreach ($f in $index.Folders) {
        if ($f.Folder -eq $ExcludeFolder) { continue }
        foreach ($row in $f.Manifest) {
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) {
                $full = Join-Path $f.Folder $row.DataPath
                if (-not (Test-FolderHoldsFile -Files $f.Files -Folder $f.Folder -Name $row.DataPath)) {
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
                    # A DataPath goes stale whenever its object moves to another
                    # folder of the pool (bounded-run-loop plan R6: snapshots are
                    # write-once, and re-added content moves back to the latest
                    # state). From kit revision 4 a missing named file is
                    # recovered by (hash, length), its form decided from the bytes,
                    # so for such a folder the row resolves exactly like a blank
                    # one and is no problem while its content survives. An older
                    # kit cannot fall back, so for it the row stays broken.
                    if ($bytesSurvive) {
                        if (-not $kitRevisionOf.ContainsKey($f.Folder)) {
                            $kitRevisionOf[$f.Folder] = Get-BackupKitRevision -Folder $f.Folder
                        }
                        if ($kitRevisionOf[$f.Folder] -ge 4) { continue }
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
    if (Test-SevenZipSignature -Path $Path) { return 'Archive' }
    return 'Raw'
}

function Test-SevenZipSignature {
    <#
    .SYNOPSIS
        True when a file begins with the 7-Zip signature 37 7A BC AF 27 1C:
        six bytes read, no hashing and no 7-Zip.

    .DESCRIPTION
        The one byte test behind the storage audit's Get-StoredFileForm and
        the backup run's damage check (Get-ListedObjectDamage). It stands
        apart so a backup run reads these six bytes without reaching the
        audit, which a backup never runs (SR-049). Throws when the file
        cannot be opened.

    .PARAMETER Path
        Full path of the file.

    .OUTPUTS
        [bool]
    #>
    # Implements: SR-049, SR-068
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)
    $magic = [byte[]](0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C)
    $head  = New-Object byte[] $magic.Length
    $read  = 0
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try { $read = $fs.Read($head, 0, $magic.Length) } finally { $fs.Dispose() }
    if ($read -lt $magic.Length) { return $false }
    for ($i = 0; $i -lt $magic.Length; $i++) {
        if ($head[$i] -ne $magic[$i]) { return $false }
    }
    return $true
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

        WP17 Part A made that shape common rather than rare (adding '.z7' to the
        already-compressed list turns 43% of the production library into
        Compressed='No' rows over archive bytes), so the NON-Deep scan gained a
        second cheap exemption, narrowly scoped to exactly that shape: an object
        stored raw under its OWN extension (DataPath extension = RelativePath
        extension), at the row's OWN Length, AND under a name the
        already-compressed extension list exempts (Test-ShouldCompress is $false)
        is exempt WITHOUT hashing. Be precise about what that costs and what it
        does not: the non-Deep scan is the FORM audit, and it never hashed any
        other raw object in the store, so this exemption withdraws the confirming
        hash only from a list-exempt raw object at its own size. It does NOT
        prove that object's payload — a same-length substitution under a listed
        name (a '.z7' whose bytes are different archive bytes) passes the
        non-Deep scan and is caught by -Deep, which is the payload audit and
        always hashes. An archive-magic object under a name the list does NOT
        exempt still takes the confirming hash, exactly as before WP17
        (LLR-049, TC-229).

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

    .PARAMETER ScratchFolder
        Where -Deep expands an archive: a folder on the backup volume, outside
        every pool folder. The system temp folder is used only when none is
        given (it is RAM in the container).

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
        [string]$SevenZipPath,
        [string]$ScratchFolder
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
            # A DataPath goes stale when its object moves to another folder of
            # the pool (bounded-run-loop plan R6); while that content survives,
            # every restore finds it by name, so the row is no finding.
            $key = "$($row.xxH2Hash)|$($row.Length)"
            if ($null -ne $Index -and -not [string]::IsNullOrWhiteSpace($row.xxH2Hash) -and $Index.Map.ContainsKey($key)) { continue }
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
        # WP17 Part A widens that fast path, for the NON-Deep scan only, and only
        # for the shape it exists to fix. Once '.z7' joined the
        # already-compressed list, every one of the production library's 649
        # '.z7' objects became exactly the shape the comment above calls "rare" -
        # a Compressed='No' row over archive-magic bytes - so the confirming hash
        # below would re-read 880 GB on every Verify pass. A list-exempt object
        # stored raw UNDER ITS OWN EXTENSION at ITS OWN SIZE is precisely what
        # SR-004 writes for an already-compressed source: the write path names it
        # '<hash>_<len><ownerExt>' and records Compressed='No'.
        #
        # What this proves and what it does not: the non-Deep pass is the FORM
        # audit - it never hashed any other raw object in this store - and the
        # exemption withdraws the confirming hash from ONE class only, a
        # list-exempt raw object at its own length. It does not prove that
        # object's payload: a same-length substitution under a listed name passes
        # here and is caught by -Deep, which is the payload audit and ALWAYS
        # hashes. An archive-magic object under a name the list does NOT exempt
        # keeps the confirming hash exactly as before WP17 (LLR-049, TC-229).
        if (-not $exempt -and -not $Deep -and $observed -eq 'Archive' -and $row.Compressed -ne 'Yes' -and
            -not [string]::IsNullOrWhiteSpace([string]$row.Length) -and
            ((Test-ShouldCompress -FileName ([string]$row.RelativePath) -CompressEnabled $true) -eq $false) -and
            ([IO.Path]::GetExtension([string]$row.DataPath) -ieq [IO.Path]::GetExtension([string]$row.RelativePath)) -and
            (Get-Item -LiteralPath $full).Length -eq [long]$row.Length) {
            $exempt = $true
        }
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
                    $scratchBase = if ($ScratchFolder) { [void][System.IO.Directory]::CreateDirectory($ScratchFolder); $ScratchFolder } else { [IO.Path]::GetTempPath() }
                    $tmp = Join-Path $scratchBase ([IO.Path]::GetRandomFileName())
                    try {
                        Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $full -DestinationFile $tmp
                        $payloadOk = ((Get-Item -LiteralPath $tmp).Length -eq [long]$row.Length -and
                                      (Get-FileXxHash -FilePath $tmp) -eq $row.xxH2Hash)
                    } catch {
                        # The expand did not complete (a corrupt archive, or a
                        # full volume - 7-Zip cannot tell): no comparison was
                        # made, so this is no PayloadMismatch. The object audit
                        # reports the object as UnverifiedObject (plan C22, C33).
                        $payloadOk = $null
                    } finally {
                        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    }
                }
            } else {
                $payloadOk = ((Get-Item -LiteralPath $full).Length -eq [long]$row.Length -and
                              (Get-FileXxHash -FilePath $full) -eq $row.xxH2Hash)
            }
            if ($payloadOk -eq $false) {
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
    $index = Get-BackupContentIndex -BackupRoot $BackupRoot -SnapshotFolder $poolSnapshots -IncludeManifests

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($folder in @($BackupRoot) + $snapshots) {
        $manifest = Read-Manifest -FolderPath $folder
        # SR-061: rows in the legacy path-addressed form mark a store written
        # by a pre-content-addressed build. Backup REFUSES such a store
        # (Assert-CurrentStoreForm); an audit that refused would be useless, so
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
        $scratch = if ($ChangeRoot -and (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { Join-Path $ChangeRoot "$($script:VerifyFolderName)\.expand" } else { $null }
        foreach ($f in @(Get-StorageFormFinding -Folder $folder -Manifest $manifest -Index $index -Deep:$Deep -SevenZipPath $SevenZipPath -ScratchFolder $scratch)) {
            $all.Add($f)
        }
    }
    if ($ChangeRoot -and (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { Remove-VerifyScratch -ChangeRoot $ChangeRoot }
    return $all.ToArray()
}

function Get-StoredObjectVerdict {
    <#
    .SYNOPSIS
        Checks a stored object's bytes - expanded, for an archive this tool
        made - against the content key its name carries, and says whether they
        are good, proven damaged, or could not be checked.

    .DESCRIPTION
        An object whose file length equals its content length is read raw (that
        includes the user's own '.7z' stored as is, SR-068); a '.7z' of another
        length is expanded into a scratch file beside the change root - on the
        backup volume, never the system temp folder (RAM in the container) -
        hashed from disk rather than RAM (the C-12 lesson) and deleted. A raw object of the wrong length
        is damaged by its size alone.

        'Unverified' is the answer whenever the bytes could not be judged: no
        7-Zip for an archive, a read or expand that failed. A failed expand can
        be a corrupt archive or a host problem (a full scratch volume), and
        7-Zip does not tell them apart, so only a completed comparison is
        evidence of damage: nothing is moved aside on anything less.

    .PARAMETER Entry
        A Get-StoreObjectIndex entry.

    .PARAMETER ScratchFolder
        Where an archive is expanded.

    .PARAMETER SevenZipPath
        7-Zip, needed only for an archive.

    .OUTPUTS
        [pscustomobject] Verdict ('Good' | 'Damaged' | 'Unverified'), Reason.
    #>
    # Implements: SR-049, SR-068, LLR-049
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$ScratchFolder,
        [AllowNull()][string]$SevenZipPath
    )
    $verdict = { param([string]$V, [string]$R) [pscustomobject]@{ Verdict = $V; Reason = $R } }
    $key = ConvertFrom-HashSizeFileName -Name $Entry.Name
    if ($null -eq $key) { return (& $verdict 'Unverified' 'its name does not carry a content key') }
    $want = $key.HashHex.ToUpperInvariant()
    try {
        if ($Entry.FileLength -eq $Entry.ContentLength) {
            if ((Get-FileXxHash -FilePath $Entry.Path) -eq $want) { return (& $verdict 'Good' '') }
            # An archive exactly as long as its content (an older build could
            # write one) hashes wrong when read raw: expand it before calling it
            # damaged, as the restorers do (SR-068).
            if ($Entry.Extension -ine '.7z' -or (Get-StoredFileForm -Path $Entry.Path) -ne 'Archive') {
                return (& $verdict 'Damaged' 'its bytes do not hash to the content its name records')
            }
        } elseif ($Entry.Extension -ine '.7z') {
            return (& $verdict 'Damaged' 'its length is not the content length its name records')
        }
        if (-not $SevenZipPath) { return (& $verdict 'Unverified' 'an archive, and no 7-Zip to expand it') }
        [void][System.IO.Directory]::CreateDirectory($ScratchFolder)
        $scratch = Join-Path $ScratchFolder ([guid]::NewGuid().ToString('N'))
        try {
            Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $Entry.Path -DestinationFile $scratch
            $file = [System.IO.FileInfo]::new($scratch)
            # No file is no comparison: the expand did not complete here.
            if (-not $file.Exists) { return (& $verdict 'Unverified' 'its expanded bytes never reached the scratch folder') }
            if ($file.Length -eq $Entry.ContentLength -and (Get-FileXxHash -FilePath $scratch) -eq $want) {
                return (& $verdict 'Good' '')
            }
            return (& $verdict 'Damaged' 'it expands to bytes that are not the content its name records')
        } finally {
            Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
        }
    } catch {
        return (& $verdict 'Unverified' "it could not be checked: $($_.Exception.Message)")
    }
}

function Get-StoreObjectFinding {
    <#
    .SYNOPSIS
        The object-level audit of -Action Verify: every second copy of one
        content in the pool and every object whose listing shows it damaged
        (always), and with -Deep every object whose bytes do not match its name
        (plan R9, R10, C4; review 2026-10-26 G1). Mutates nothing.

    .DESCRIPTION
        A backup run no longer collapses duplicates and never deletes an object
        (R9); the listing it already makes shows them, and Verify reports them.
        -RepairStorage moves the findings into the change root's Verify folder
        through Move-StoreObjectToVerify. For each content the copy kept is the
        backup root's, else the newest snapshot's - unless -Deep finds that copy
        damaged and another one good, in which case the good one is kept. Each
        DuplicateObject finding carries the copy kept (Kept), and KeptVerified
        says -Deep already proved it good. An object of a length its name rules
        out (Get-ListedObjectDamage: empty, or a raw object of the wrong length
        that is no archive) is a DamagedObject finding without -Deep and is
        never a copy kept. Under
        -Deep a copy that could not be checked is an 'UnverifiedObject' finding,
        never repairable, and -Deep without 7-Zip is refused up front, as the
        storage-form audit refuses it, so nothing is moved on missing evidence. A
        duplicate in a folder whose restore kit is older than revision 4 is
        reported but not repairable: that kit finds a row's object only where
        its DataPath names it (-RefreshKits upgrades it).

    .PARAMETER BackupRoot
        The backup root.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER Deep
        Also check every object's bytes.

    .PARAMETER SevenZipPath
        7-Zip, for archives under -Deep.

    .OUTPUTS
        [pscustomobject[]] findings with Class 'DuplicateObject',
        'DamagedObject' or 'UnverifiedObject', the object's Path, Folder,
        FolderName and DataPath.
    #>
    # Implements: SR-003, SR-049, LLR-049
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [switch]$Deep,
        [AllowNull()][string]$SevenZipPath
    )
    if ($Deep -and (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf))) {
        throw "-Deep proves payload identity and needs 7-Zip, which was not found at '$SevenZipPath'."
    }
    $findings = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { $ChangeRoot = $BackupRoot }
    $index = Get-StoreObjectIndex -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot
    $groups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $index.Objects.Values) { $groups[$entry.Prefix] = [System.Collections.Generic.List[object]]::new(); $groups[$entry.Prefix].Add($entry) }
    foreach ($dup in $index.Duplicates) { $groups[$dup.Prefix].Add($dup) }
    $scratch = Join-Path $ChangeRoot "$($script:VerifyFolderName)\.expand"
    $kitRevisionOf = @{}
    $newFinding = {
        param($Entry, [string]$Class, [string]$Observed, [string]$Expected)
        [pscustomobject]@{
            Folder = [System.IO.Path]::GetDirectoryName($Entry.Path)
            FolderName = if ($Entry.Folder) { $Entry.Folder } else { [System.IO.Path]::GetFileName($BackupRoot.TrimEnd('\', '/')) }
            RelativePath = ''; DataPath = $Entry.Name; Path = $Entry.Path; Class = $Class
            Observed = $Observed; Expected = $Expected; Repairable = $true
            FileLength = [long]$Entry.FileLength; Kept = $null; KeptVerified = $false
        }
    }
    # Damage the listing already shows (Get-ListedObjectDamage) is reported
    # without -Deep, and such a copy is never the one kept.
    foreach ($d in $index.Damaged) {
        $findings.Add((& $newFinding $d 'DamagedObject' $d.Reason 'every object''s length fits the content its name records (SR-049)'))
    }
    foreach ($copies in $groups.Values) {
        $keep = $copies[0]
        if ($Deep) {
            $good = [System.Collections.Generic.List[object]]::new()
            foreach ($copy in $copies) {
                $check = Get-StoredObjectVerdict -Entry $copy -ScratchFolder $scratch -SevenZipPath $SevenZipPath
                switch ($check.Verdict) {
                    'Good'    { $good.Add($copy) }
                    'Damaged' { $findings.Add((& $newFinding $copy 'DamagedObject' $check.Reason 'every object''s bytes match its name (SR-049)')) }
                    default {
                        $unverified = & $newFinding $copy 'UnverifiedObject' $check.Reason 'every object''s bytes checked against its name (SR-049)'
                        $unverified.Repairable = $false
                        $findings.Add($unverified)
                    }
                }
            }
            if ($good.Count -eq 0) { continue }
            $keep = $good[0]
            $copies = $good
        }
        foreach ($other in @($copies | Where-Object { -not [object]::ReferenceEquals($_, $keep) })) {
            $where = if ($keep.Folder) { "'$($keep.Folder)'" } else { 'the latest state' }
            $finding = & $newFinding $other 'DuplicateObject' "a second copy of content also held in $where" 'one copy of each content in the pool (SR-003)'
            # The copy kept, so a repair can confirm it before this one goes;
            # under -Deep it is already proven good.
            $finding.Kept = $keep
            $finding.KeptVerified = [bool]$Deep
            if (-not $kitRevisionOf.ContainsKey($finding.Folder)) { $kitRevisionOf[$finding.Folder] = Get-BackupKitRevision -Folder $finding.Folder }
            if ($kitRevisionOf[$finding.Folder] -lt 4) {
                $finding.Repairable = $false
                $finding.Observed += "; left in place: that folder's restore kit (revision $($kitRevisionOf[$finding.Folder])) finds an object only where its row names it - run -RefreshKits first"
            }
            $findings.Add($finding)
        }
    }
    Remove-VerifyScratch -ChangeRoot $ChangeRoot
    return $findings.ToArray()
}

function Move-StoreObjectToVerify {
    <#
    .SYNOPSIS
        Moves the objects of DuplicateObject and DamagedObject findings into
        <ChangeRoot>/Verify/<folder>/, so nothing is deleted (R9); the Owner
        empties that folder by hand. Returns how many moved.

    .DESCRIPTION
        No restorer and no backup run reads the Verify folder. Every remaining
        state still resolves: a duplicate's content stays in the copy that is
        kept, found by name (plan §7), and a damaged object restored nothing
        correct anyway; the next backup stores that content again while the
        source still holds it (SR-053).

        A duplicate is real redundancy until then: a restore that finds the
        kept copy damaged heals from another copy in the pool, and Verify/ is
        not in the pool. So the copy kept is read and checked first (plan C28)
        - once per content, and not at all when -Deep already proved it - and
        a duplicate whose kept copy is not proven good stays where it is. The
        work is timed and logged, with a progress line every minute.

        Moving an object out of the pool writes the store, so it holds the
        staging OS lock for its whole run, as the repair and the kit refresh do
        (SR-085, SR-086): taken first, so a held lock refuses (throws) before
        anything moves, and released in a finally. The audit that produced the
        findings ran before the lock, so each finding is checked again under
        it: an object, or the copy kept for it, that is no longer where the
        finding says - a prune or a backup ran in between - is left alone with
        a warning (review 2026-10-26 A5). -WhatIf takes no lock and moves
        nothing; it says what it would move.

    .PARAMETER Finding
        Get-StoreObjectFinding results.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER SevenZipPath
        7-Zip, to confirm a kept copy that is an archive.

    .PARAMETER Metrics
        The run's metrics (New-RunMetric), or $null.

    .PARAMETER Log
        The logger.

    .OUTPUTS
        [int] how many objects moved (0 under -WhatIf).
    #>
    # Implements: SR-049, SR-109, SR-085, SR-086, LLR-049
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Finding,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [AllowNull()][string]$SevenZipPath,
        [AllowNull()][hashtable]$Metrics,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    # The staging OS lock first (SR-085, SR-086): a move takes an object out of
    # the pool, so it must not race a backup or a prune, and a lock that cannot
    # be taken refuses (throws) before anything moves. -WhatIf moves nothing and
    # takes no lock.
    $osLock = $null
    if (-not $WhatIfPreference) {
        $osLock = Enter-StoreMutationLock -ChangeRoot $ChangeRoot -Activity 'set objects aside into Verify' -Log $Log
    }
    try {
        $scratch = Join-Path (Join-Path $ChangeRoot $script:VerifyFolderName) '.expand'
        $verdictOf = @{}
        $cost = Measure-DuplicateRepairCost -Finding $Finding
        if ($cost.ConfirmCount -gt 0) {
            & $Log "Confirming $($cost.ConfirmCount) kept cop(ies) ($(Format-RunByteCount $cost.ConfirmBytes)) before their duplicates are set aside." 'INFO'
        }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $nextProgress = [datetime]::UtcNow.AddSeconds($script:ProgressIntervalSeconds)
        $confirmedBytes = [long]0
        $leftAlone = 0
        $moved = 0
        foreach ($f in $Finding) {
            if ($f.Class -notin 'DuplicateObject', 'DamagedObject' -or -not $f.Repairable) { continue }
            # The findings predate the lock. Under it nothing else moves either
            # file from here to the move, so check once: the object is still
            # there, and for a duplicate so is the copy kept for it - a prune
            # that deleted that copy since the audit made this one the last.
            $gone = $null
            if (-not [System.IO.File]::Exists($f.Path)) { $gone = $f.Path }
            elseif ($f.Class -eq 'DuplicateObject') {
                if ($null -eq $f.Kept) { $gone = 'the copy kept for it' }
                elseif (-not [System.IO.File]::Exists($f.Kept.Path)) { $gone = $f.Kept.Path }
            }
            if ($null -ne $gone) {
                & $Log ("[$($f.Class)] left '$($f.Path)' alone: '$gone' is no longer where the audit found it " +
                        '(the store changed since). Run -Action Verify again.') 'WARN'
                continue
            }
            if ($f.Class -eq 'DuplicateObject' -and -not $f.KeptVerified) {
                $kept = $f.Kept
                if (-not $verdictOf.ContainsKey($kept.Path)) {
                    $one = [System.Diagnostics.Stopwatch]::StartNew()
                    $verdictOf[$kept.Path] = Get-StoredObjectVerdict -Entry $kept -ScratchFolder $scratch -SevenZipPath $SevenZipPath
                    $confirmedBytes += [long]$kept.FileLength
                    if ($null -ne $Metrics) { Add-RunMetric -Metrics $Metrics -Name 'confirm kept copy' -Bytes ([long]$kept.FileLength) -Ticks $one.ElapsedTicks }
                    if ([datetime]::UtcNow -ge $nextProgress) {
                        & $Log ("Confirming kept copies: $($verdictOf.Count) of $($cost.ConfirmCount), $(Format-RunByteCount $confirmedBytes) of " +
                                "$(Format-RunByteCount $cost.ConfirmBytes), {0:N0} s." -f $watch.Elapsed.TotalSeconds) 'INFO'
                        $nextProgress = [datetime]::UtcNow.AddSeconds($script:ProgressIntervalSeconds)
                    }
                }
                $check = $verdictOf[$kept.Path]
                if ($check.Verdict -ne 'Good') {
                    & $Log ("[DuplicateObject] left '$($f.Path)' in place: the copy kept, '$($kept.Path)', is $($check.Verdict.ToLowerInvariant()) " +
                            "($($check.Reason)). Run -Action Verify -Deep to judge every copy.") 'WARN'
                    $leftAlone++
                    continue
                }
            }
            $target = Get-VerifyDestination -ChangeRoot $ChangeRoot -FolderName $f.FolderName -Name $f.DataPath
            $folder = $target.Folder
            $dest = $target.Path
            if (-not $PSCmdlet.ShouldProcess($f.Path, "move into '$folder'")) {
                & $Log "[$($f.Class)] would move '$($f.Path)' to '$dest' (-WhatIf: nothing was moved)." 'INFO'
                continue
            }
            [void][System.IO.Directory]::CreateDirectory($folder)
            try {
                [System.IO.File]::Move($f.Path, $dest)
                & $Log "[$($f.Class)] moved '$($f.Path)' to '$dest'." 'INFO'
                $moved++
            } catch {
                & $Log "[$($f.Class)] could not move '$($f.Path)': $($_.Exception.Message)" 'WARN'
            }
        }
        if ($verdictOf.Count -gt 0) {
            & $Log ("Confirmed $($verdictOf.Count) kept cop(ies) ($(Format-RunByteCount $confirmedBytes)) in {0:N1} s; " -f $watch.Elapsed.TotalSeconds +
                    "$leftAlone duplicate(s) left in place because the copy kept was not proven good.") 'INFO'
        }
        Remove-VerifyScratch -ChangeRoot $ChangeRoot
        return $moved
    } finally {
        Exit-StagingOsLock -Lock $osLock -Log $Log
    }
}

function Get-VerifyDestination {
    <#
    .SYNOPSIS
        Where an object set aside from a pool folder goes:
        <ChangeRoot>/Verify/<folder>/<name>, with '.<n>' appended until the
        name is free, so nothing already set aside is overwritten.

    .DESCRIPTION
        The one layout of Verify/, shared by -RepairStorage
        (Move-StoreObjectToVerify) and the backup run's setting aside of
        damaged objects (Move-DamagedStoreObject). Nothing is created here.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER FolderName
        The pool folder the object is in: a snapshot's folder name, or the
        backup root's.

    .PARAMETER Name
        The object's file name.

    .OUTPUTS
        [pscustomobject] Folder, Path.
    #>
    # Implements: SR-049, SR-109
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][string]$FolderName,
        [Parameter(Mandatory)][string]$Name
    )
    $folder = Join-Path (Join-Path $ChangeRoot $script:VerifyFolderName) $FolderName
    $dest = Join-Path $folder $Name
    $n = 1
    while (Test-Path -LiteralPath $dest) { $dest = Join-Path $folder "$Name.$n"; $n++ }
    return [pscustomobject]@{ Folder = $folder; Path = $dest }
}

function Move-DamagedStoreObject {
    <#
    .SYNOPSIS
        Sets aside every object the run's index found damaged by its listing,
        moving each into <ChangeRoot>/Verify/<folder>/ (review 2026-10-26 G1).

    .DESCRIPTION
        Runs right after the index, before the library loop, under the run's
        OS lock. A damaged object is never reused and nothing is deleted (R9):
        it moves into Verify/ - which no restore and no run reads - laid out
        as -RepairStorage lays it out (Get-VerifyDestination), so it is not
        lost and a person can look at it. Its content is then stored again by
        the loop only from a source file whose bytes hash to it (SR-053, SR-059):
        identical content lands at that name again, changed content gets its
        own, and the damaged history is not rewritten.

        Each object gets a WARN, and one summary line says the set reports 1,
        so the scheduler and HomeHub see it. A move that fails is a WARN too:
        the object stays where it is, out of the index, and
        Publish-StagedObject refuses to take it for the content it names.

    .PARAMETER Damaged
        Get-StoreObjectIndex's Damaged entries.

    .PARAMETER BackupRoot
        The backup root, whose folder name labels its objects in Verify/.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER Metrics
        The run's metrics (New-RunMetric).

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [pscustomobject] Found, Moved.
    #>
    # Implements: SR-049, SR-053, SR-059
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Damaged,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $moved = 0
    foreach ($d in $Damaged) {
        $folderName = if ($d.Folder) { $d.Folder } else { [System.IO.Path]::GetFileName($BackupRoot.TrimEnd('\', '/')) }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $target = Get-VerifyDestination -ChangeRoot $ChangeRoot -FolderName $folderName -Name $d.Name
            [void][System.IO.Directory]::CreateDirectory($target.Folder)
            [System.IO.File]::Move($d.Path, $target.Path)
            Add-RunMetric -Metrics $Metrics -Name 'set aside damaged object' -Bytes ([long]$d.FileLength) -Ticks $watch.ElapsedTicks
            & $Log "[DamagedObject] '$($d.Path)' is damaged ($($d.Reason)), as a power loss can leave it; moved it to '$($target.Path)' and it is not reused." 'WARN'
            $moved++
        } catch {
            & $Log "[DamagedObject] '$($d.Path)' is damaged ($($d.Reason)) and could not be moved into Verify: $($_.Exception.Message). It is not reused." 'WARN'
        }
    }
    if ($Damaged.Count -gt 0) {
        & $Log ("Set aside $moved of $($Damaged.Count) damaged stored object(s) into '$(Join-Path $ChangeRoot $script:VerifyFolderName)'. " +
                'Their content is stored again from the source where the source still holds it; a state whose content is gone ' +
                'cannot be restored for those files. This set reports 1 so that it is seen.') 'WARN'
        Complete-RunStep -Metrics $Metrics -Name 'set aside damaged objects'
    }
    return [pscustomobject]@{ Found = $Damaged.Count; Moved = $moved }
}

function Measure-DuplicateRepairCost {
    <#
    .SYNOPSIS
        What setting a store's duplicates aside would cost and free: the
        duplicates a repair would move, the bytes they waste, and the kept
        copies it must first read to confirm (plan C28).

    .PARAMETER Finding
        Get-StoreObjectFinding results.

    .OUTPUTS
        [pscustomobject] Copies, Contents, WastedBytes, ConfirmCount, ConfirmBytes.
    #>
    # Implements: SR-049, SR-109, LLR-049
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Finding)
    $kept = @{}
    $toConfirm = @{}
    $copies = 0
    $wasted = [long]0
    foreach ($f in $Finding) {
        if ($f.Class -ne 'DuplicateObject' -or -not $f.Repairable) { continue }
        $copies++
        $wasted += [long]$f.FileLength
        if ($null -eq $f.Kept) { continue }
        $kept[$f.Kept.Path] = $true
        if (-not $f.KeptVerified) { $toConfirm[$f.Kept.Path] = [long]$f.Kept.FileLength }
    }
    $confirmBytes = [long]0
    foreach ($v in $toConfirm.Values) { $confirmBytes += $v }
    return [pscustomobject]@{
        Copies = $copies; Contents = $kept.Count; WastedBytes = $wasted
        ConfirmCount = $toConfirm.Count; ConfirmBytes = $confirmBytes
    }
}

function Remove-VerifyScratch {
    <#
    .SYNOPSIS
        Removes Verify's scratch folder, and the Verify folder itself, when
        they are empty, so a read-only Verify leaves nothing behind (SR-103).

    .PARAMETER ChangeRoot
        The change root.
    #>
    # Implements: SR-103, LLR-049
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChangeRoot)
    $verify = Join-Path $ChangeRoot $script:VerifyFolderName
    foreach ($folder in (Join-Path $verify '.expand'), $verify) {
        try {
            if ([System.IO.Directory]::Exists($folder) -and @([System.IO.Directory]::EnumerateFileSystemEntries($folder) | Select-Object -First 1).Count -eq 0) {
                [System.IO.Directory]::Delete($folder)
            }
        } catch { Write-Verbose "Could not remove '$folder': $($_.Exception.Message)" }
    }
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
    # Implements: SR-049, SR-024, SR-038, SR-085, SR-086, LLR-049, LLR-094
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$ChangeRoot,
        [switch]$BackupRootOnly,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    # The staging OS lock (SR-085, LLR-094), taken BEFORE the audit so the
    # findings and the repair see one state: a repair renames pool objects
    # and rewrites manifests, and must not race a backup's root-manifest
    # publish or finalize, a prune, or the coming staging recovery. A lock
    # that cannot be taken refuses (throws) touching nothing (SR-086).
    # -WhatIf mutates nothing and takes no lock.
    $osLock = $null
    if (-not $WhatIfPreference) {
        $osLock = Enter-StoreMutationLock -ChangeRoot $ChangeRoot -Activity 'repair the storage form' -Log $Log
    }
    try {
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
    } finally {
        Exit-StagingOsLock -Lock $osLock -Log $Log
    }
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

        Copies exactly the seven kit artifacts Publish-PriorStateSnapshot copies and
        NOTHING else. The manifest witness (MANIFEST.csv.meta) is emphatically
        NOT one of them: each snapshot witnesses its OWN manifest, and copying
        the root's over it is the single most dangerous mistake available here
        (AGENTS.md §3, pinned by TC-067).

        Each file is written as the backup root's kit is (Write-KitFile): only
        when it differs, through a temp file flushed to the disk and renamed
        over it. Overwriting in place could leave a snapshot's only kit torn,
        or empty after a power loss, and an old kit already current is not
        touched at all (review 2026-10-26 A1).

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
    # Implements: SR-049, SR-007, SR-038, SR-085, SR-086, LLR-049, LLR-094
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    # The staging OS lock (SR-085, LLR-094): a kit refresh overwrites files
    # inside every Snapshot_* folder and must not race a backup publishing
    # or deduplicating snapshots, a prune, or the coming staging recovery.
    # A lock that cannot be taken refuses (throws) touching nothing
    # (SR-086). -WhatIf mutates nothing and takes no lock.
    $osLock = $null
    if (-not $WhatIfPreference) {
        $osLock = Enter-StoreMutationLock -ChangeRoot $ChangeRoot -Activity 'refresh the snapshot restore kits' -Log $Log
    }
    try {
        $artifacts = @($script:Def.ReconstructPs1Name, $script:Def.ReconstructCmdName,
                       $script:Def.ReconstructCommandName, $script:Def.ReconstructShName,
                       $script:Def.CommonModuleName,
                       'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')
        $refreshed = 0
        # The root's kit is read once, not once per snapshot.
        $kit = [ordered]@{}
        foreach ($snapshot in @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | Where-Object { $_ })) {
            if (-not $PSCmdlet.ShouldProcess($snapshot.FullName, 'refresh the bundled restore kit')) { continue }
            if ($kit.Count -eq 0) {
                foreach ($artifact in $artifacts) {
                    $src = Join-Path $BackupRoot $artifact
                    if (Test-Path -LiteralPath $src -PathType Leaf) {
                        $kit[$artifact] = [System.IO.File]::ReadAllBytes($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($src))
                    }
                }
            }
            $written = 0
            foreach ($artifact in $kit.Keys) {
                if (Write-KitFile -Path (Join-Path $snapshot.FullName $artifact) -Bytes $kit[$artifact]) { $written++ }
            }
            & $Log "Refreshed the restore kit in '$($snapshot.Name)': $written file(s) rewritten (the manifest witness was NOT copied)." 'INFO'
            $refreshed++
        }
        return [pscustomobject]@{ Refreshed = $refreshed; Revision = (Get-BackupKitRevision -Folder $BackupRoot) }
    } finally {
        Exit-StagingOsLock -Lock $osLock -Log $Log
    }
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
        and no witness an older build left disagreeing with its manifest (no
        witness is written any more, bounded-run-loop plan R5, so an absent one
        is the normal case; a disagreeing one is evidence of damage, and
        deleting is not recoverable).

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
    if ($AllowUnverifiedIndex) { Write-Verbose '-AllowUnverifiedIndex has no effect: no witness is written any more (plan R5).' }
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
    # Verifying a re-homed archive expands it, one at a time, into the prune's
    # staging folder on the backup volume (plan C31): the largest such payload
    # must fit there as well as the copies (C34).
    $capacityItems = [System.Collections.Generic.List[object]]::new()
    foreach ($i in $items) { $capacityItems.Add($i) }
    if (-not $SkipContentVerify) {
        $largest = [long]0
        foreach ($i in $items) { if ($i.Compressed -eq 'Yes' -and [long]$i.SourceRow.Length -gt $largest) { $largest = [long]$i.SourceRow.Length } }
        if ($largest -gt 0) { $capacityItems.Add([pscustomobject]@{ DestinationFolder = $ChangeRoot; Bytes = $largest }) }
    }
    foreach ($refusal in (Get-PruneCapacityRefusal -Item $capacityItems.ToArray() -PlanName $Plan.Name)) { $refusals.Add($refusal) }

    if (-not $SkipContentVerify -and @($items | Where-Object { $_.Compressed -eq 'Yes' }).Count -gt 0) {
        if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
            $refusals.Add([pscustomobject]@{ Code = 2; Kind = 'no-7zip'
                Message = "Re-homing '$($Plan.Name)' moves compressed data, whose content cannot be verified without 7-Zip (looked for '$SevenZipPath'). Install it or pass -SkipContentVerify." })
        }
    }

    foreach ($f in $Plan.Index.Folders) {
        # No witness is written any more (bounded-run-loop plan R5), so an absent
        # one is the normal case. A witness an older build left must still agree
        # with its manifest: a disagreement is evidence of damage, and deleting is
        # not recoverable.
        $verdict = Test-ManifestWitness -FolderPath $f.Folder
        switch ($verdict.Status) {
            'Verified' { }
            'Absent'   { }
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
        Finishes every snapshot deletion an earlier prune COMMITTED but did not
        complete: each 'Pruning_<snapshot name>' folder in the change root is
        past its own commit point, invisible to every consumer, and only its
        deletion remains (SR-046).

    .DESCRIPTION
        Remove-BackupSnapshot runs it once per batch, right after it takes the
        OS lock and before any plan or rail - the capacity rail included - and
        never under -WhatIf (review 2026-10-26 B). Such a folder is read by no
        restorer, run or prune, so finishing it completes an earlier committed
        operation rather than making a refusal mutate anything; and freeing its
        space first is what lets a nearly full volume's capacity rail pass. Run
        inside the transaction instead, a leftover holding the space a re-home
        needed was never cleared, because every prune was refused before it.
        Before that, only 'Pruning_<the name being pruned>' was finished; a
        caller that takes its names from -Action Snapshots never names a
        committed snapshot again, so its space leaked for good.

        Only Complete-PruneDeletion's commit rename makes such a folder, and
        only after the pool was proven to resolve without it, so nothing any
        state needs is inside. A 'Pruning_' folder whose remainder is not a
        snapshot name was not made by that rename and is left alone.

        Nothing here refuses: a change root that cannot be listed, or a folder
        that cannot be deleted, is a warning, and the next prune tries again.
        A leftover under the name being pruned that stays makes that prune's
        commit rename fail before the commit point (4, nothing lost).

    .PARAMETER ChangeRoot
        The change root holding the snapshot folders.

    .OUTPUTS
        [int] the number of residue folders deleted.
    #>
    # Implements: SR-046, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) { return 0 }
    $removed = 0
    try {
        # -Force (SR-057): a hidden leftover would otherwise never be finished.
        $residue = @(Get-ChildItem -LiteralPath $ChangeRoot -Directory -Force -ErrorAction Stop |
                     Where-Object { $_.Name.StartsWith('Pruning_', [System.StringComparison]::Ordinal) -and
                                    $_.Name.Substring(8) -match $script:Def.ChangeFolderRegex })
    } catch {
        & $Log "Could not look for earlier prunes' leftover folders in '$ChangeRoot': $($_.Exception.Message) The next prune tries again." 'WARN'
        return 0
    }
    foreach ($folder in $residue) {
        & $Log "Completing an earlier prune: removing '$($folder.Name)' (already past its commit point)." 'WARN'
        try {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction Stop
            $removed++
        } catch {
            & $Log "Could not finish removing '$($folder.FullName)': $($_.Exception.Message) It holds nothing any state needs; the next prune tries again." 'WARN'
        }
    }
    return $removed
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
        '<destination>.fbprune.tmp' on the same volume, flush it to the disk,
        verify, then publish by atomic rename (SR-045/SR-046 phase 1).

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

    .PARAMETER ScratchFolder
        Where an archive is expanded to verify it: the prune's own transaction
        folder, on the backup volume. The system temp folder (RAM in the
        container) is used only when none is given.

    .OUTPUTS
        [string] the published destination path.
    #>
    # Implements: SR-045, LLR-045
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [string]$SevenZipPath,
        [string]$ScratchFolder,
        [switch]$SkipContentVerify
    )
    $destFull = Join-Path $Item.DestinationFolder $Item.DestinationDataPath
    if (Test-Path -LiteralPath $destFull -PathType Leaf) { return $destFull }

    $destDir = [System.IO.Path]::GetDirectoryName($destFull)
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $temp = "$destFull.fbprune.tmp"
    Copy-Item -LiteralPath $Item.SourceFullPath -Destination $temp -Force
    # On the disk before the rename that publishes it (review 2026-10-26 A1):
    # the prune then deletes the source snapshot, so this copy may be the only
    # one, and without the flush a power loss can keep the rename and the
    # deletion but not the bytes (an empty or NUL-filled object).
    Sync-FileToDisk -LiteralPath $temp

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
                $scratchBase = if ($ScratchFolder) { $ScratchFolder } else { [IO.Path]::GetTempPath() }
                $scratch = Join-Path $scratchBase ([IO.Path]::GetRandomFileName())
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
        reconstruct.sh AND the backup run's object index all use, so one atomic rename
        removes it from every consumer's view — and then deletes it (SR-046).

    .DESCRIPTION
        The rename is the commit. A rename that fails throws, and nothing is
        committed. A delete that fails after it is a warning naming the
        leftover folder, never a failure: the snapshot is already gone from
        every consumer's view and the pool was proven not to need it, so its
        prune succeeded, and the next prune of any name finishes the folder
        (Remove-CommittedPruneResidue). It used to throw, and the prune was
        reported as failed before the commit point (review 2026-10-26 B).

    .PARAMETER SnapshotFolder
        Full path of the snapshot folder to remove.

    .OUTPUTS
        [bool] $true when the folder is gone; $false when the leftover
        'Pruning_<name>' folder stays for the next prune.
    #>
    # Implements: SR-046, LLR-046
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SnapshotFolder,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $name     = [System.IO.Path]::GetFileName($SnapshotFolder)
    $leftover = Join-Path ([System.IO.Path]::GetDirectoryName($SnapshotFolder)) ('Pruning_' + $name)
    Rename-Item -LiteralPath $SnapshotFolder -NewName ('Pruning_' + $name) -ErrorAction Stop
    # Out-Null: the caller reads this function's output as the outcome.
    & $Log "Commit point passed: '$name' is no longer visible to any restorer." 'INFO' | Out-Null
    try {
        Remove-Item -LiteralPath $leftover -Recurse -Force -ErrorAction Stop
        return $true
    } catch {
        & $Log ("'$name' is pruned, but its folder could not be deleted yet: '$leftover' is left behind ($($_.Exception.Message)). " +
                'It is invisible to every restore and holds nothing any state needs; the next prune finishes it.') 'WARN' | Out-Null
        return $false
    }
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
        snapshot disappears — never deficient): take the OS lock; finish every
        committed 'Pruning_*' deletion an earlier prune left; then per name:
        plan; check every rail; take the Temp lock; sweep any staged copies an
        interrupted run left; materialize each re-homed file; publish the
        destination manifests; prove every surviving row resolves with the
        target excluded; only then commit and delete.

        Exactly one thing happens before the rails: Remove-CommittedPruneResidue
        finishes the 'Pruning_<snapshot name>' folders, each past its own
        commit point and read by no restorer, run or prune - completing an
        earlier committed operation, never refusing, and freeing the space a
        nearly full volume's capacity rail needs (review 2026-10-26 B).
        Everything else - the staged-copy sweep included (WP4 review, findings
        H2/M1) - happens inside the transaction, so a refusal (code 2/3)
        mutates nothing the store's states use and a host failure in the sweep
        classifies as the retriable code 4 rather than escaping unclassified.
        The rename to 'Pruning_<name>' is the commit: a delete that fails after
        it is a warning naming the leftover folder and the name is reported
        Pruned (0); the next prune finishes it.

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
        Accepted for compatibility and has no effect: an absent witness never
        refuses any more (plan R5). A witness that MISMATCHES still refuses.

    .PARAMETER DiscardUnreferencedData
        Accept data files in the target that its own manifest does not
        reference, discarding them with the folder.

    .OUTPUTS
        [pscustomobject] per name: Name, Status (Pruned|Refused|WhatIf), Code,
        BytesReclaimed, BytesReHomed, ReHomeDestinations, Refusals, Message.
    #>
    # Implements: SR-045, SR-046, SR-040, SR-085, SR-086, LLR-045, LLR-046, LLR-092
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

    # The staging OS lock (SR-085), the SAME lock every backup holds, taken
    # before anything -- the residue completion included -- and held for the
    # whole batch: a backup moves objects between the backup root and the
    # snapshots for its whole run, so a prune running beside it would plan on a
    # pool that is changing under it. A lock that cannot be taken is LIVE (SR-086): every name is refused
    # as staging-busy (code 2) and nothing is touched. -WhatIf mutates nothing,
    # so it takes no lock.
    $osLock = $null
    if (-not $WhatIfPreference) {
        try {
            $osLock = Enter-StagingOsLock -ChgPath $chg -Log $log
        } catch {
            $held = $_.Exception.Message
            & $log "Refusing to prune [2/staging-busy]: $held" 'ERROR'
            foreach ($snapshotName in $Name) {
                [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = 2
                    BytesReclaimed = 0; BytesReHomed = 0; ReHomeDestinations = @()
                    Refusals = @([pscustomobject]@{ Code = 2; Kind = 'staging-busy'; Message = $held })
                    Message = $held }
            }
            return
        }
    }

    try {
        # Before any plan or rail, under the OS lock, never under -WhatIf: finish
        # every deletion an earlier prune committed (review 2026-10-26 B). It
        # never refuses, and the space it frees counts for the capacity rail.
        if (-not $WhatIfPreference) { Remove-CommittedPruneResidue -ChangeRoot $chg -Log $log | Out-Null }

        foreach ($snapshotName in $Name) {
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
                # Test seam: park a live prune inside its transaction (TC-246).
                Invoke-StagingTestHook -Hook $script:PruneTestHook_InTransaction -Context $staging
                # Inside the transaction: staged copies are residue, and clearing
                # them is host I/O like any other (code 4 if it fails).
                Invoke-PruneEntrySweep -BackupRoot $bkp -ChangeRoot $chg -Log $log | Out-Null
                foreach ($item in $plan.Items.ToArray()) {
                    & $log "Re-homing '$($item.SourceRow.RelativePath)' from '$snapshotName' to '$($item.DestinationFolder)' as '$($item.DestinationDataPath)'." 'INFO'
                    Copy-ReHomedDataFile -Item $item -SevenZipPath $SevenZipPath -ScratchFolder $staging -SkipContentVerify:$SkipContentVerify | Out-Null
                }
                Publish-PruneManifest -Plan $plan -Log $log | Out-Null

                $unresolved = @(Test-PoolResolves -BackupRoot $bkp -ChangeRoot $chg -ExcludeFolder $plan.Folder)
                if ($unresolved.Count -gt 0) {
                    foreach ($problem in $unresolved) { & $log "Aborting: $($problem.Message)" 'ERROR' }
                    throw "The surviving pool would not resolve without '$snapshotName' ($($unresolved.Count) row(s)); nothing was deleted."
                }

                $deleted = Complete-PruneDeletion -SnapshotFolder $plan.Folder -Log $log
                & $log "Removed '$snapshotName': reclaimed $($plan.BytesReclaimed) byte(s), re-homed $($plan.BytesReHomed)." 'INFO'
                $done = if ($deleted) { "Removed '$snapshotName'." } else {
                    "Removed '$snapshotName'; its folder 'Pruning_$snapshotName' could not be deleted yet, and the next prune finishes it." }
                [pscustomobject]@{ Name = $snapshotName; Status = 'Pruned'; Code = 0
                    BytesReclaimed = $plan.BytesReclaimed; BytesReHomed = $plan.BytesReHomed
                    ReHomeDestinations = $destinations; Refusals = @()
                    Message = $done }
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
    } finally {
        Exit-StagingOsLock -Lock $osLock -Log $log
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

function Write-KitFile {
    <#
    .SYNOPSIS
        Writes one restore-kit file only when its bytes differ from what it
        should hold, through '<name>.tmp' beside it, flushed to the disk and
        renamed over it.

    .DESCRIPTION
        Length first, then content: the common case is an identical file,
        decided without a write, so an unchanged kit touches no file and a
        restore holding the bundled DLL does not stop a backup (review
        2026-10-26 A4). A kill leaves the old file or the new one; the flush
        before the rename makes that true across a power loss too, which
        otherwise can leave the renamed file empty or full of NULs (A1). A
        read-only file being replaced is made writable first, as the copy
        that wrote kits before did with -Force. A write that must happen and
        fails throws, leaving the old file whole and no temp file.

        The temp names are on the root-level infrastructure list
        (Test-IsInfrastructureFile) and follow no SR-069 grammar, so a
        leftover is neither data nor an object, in the backup root or in a
        snapshot.

    .PARAMETER Path
        The kit file.

    .PARAMETER Bytes
        What it should hold.

    .OUTPUTS
        [bool] true when the file was written.
    #>
    # Implements: SR-007, SR-082, LLR-007
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )
    # Absolute for .NET, which resolves against the PROCESS directory.
    $dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $have = [System.IO.FileInfo]::new($dest)
    if ($have.Exists -and $have.Length -eq $Bytes.Length -and
        [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($dest), $Bytes)) { return $false }
    $temp = "$dest.tmp"
    try {
        $stream = [System.IO.FileStream]::new($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            Sync-FileToDisk -Stream $stream
        } finally {
            $stream.Dispose()
        }
        if ($have.Exists -and $have.IsReadOnly) { $have.IsReadOnly = $false }
        [System.IO.File]::Move($temp, $dest, $true)
    } catch {
        try { [System.IO.File]::Delete($temp) } catch { Write-Verbose "Could not remove '$temp': $($_.Exception.Message)" }
        throw
    }
    return $true
}

function New-ReconstructScript {
    <#
    .SYNOPSIS
        Copies the Windows and POSIX restore entry points into the backup root,
        writes a path sidecar, and bundles the PowerShell runtime dependencies
        (FileBackup.Common.psm1 + System.IO.Hashing.dll) so a restore works from
        the backup folder alone.
    .DESCRIPTION
        Each of the seven files is written by Write-KitFile: only when its
        bytes differ from what it should be, and then through '<name>.tmp'
        beside it, flushed to the disk and renamed over it - so an unchanged
        kit (every run but the first after an upgrade) touches no file, and a
        kill or a power loss leaves the old file or the new one, never a torn
        one. Overwriting in place made every backup stop with 4 while a
        restore started from the backup root still had its
        System.IO.Hashing.dll loaded (review 2026-10-26 A4). A write that
        must happen and fails still throws.
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
    $writeKitFile = {
        param([string]$Name, [byte[]]$Bytes)
        [void](Write-KitFile -Path (Join-Path $BackupRoot $Name) -Bytes $Bytes)
    }

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
    & $writeKitFile $script:Def.ReconstructPs1Name ([System.IO.File]::ReadAllBytes($templatePs1))

    # The bash restorer is deliberately self-contained and needs no PowerShell.
    # Deposit it beside the Windows kit so a copied backup remains recoverable on
    # POSIX hosts without access to this repository.
    $templateSh = Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path 'bash' $script:Def.ReconstructShName)
    if (-not (Test-Path -LiteralPath $templateSh -PathType Leaf)) {
        throw "reconstruct.sh not found at '$templateSh'"
    }
    & $writeKitFile $script:Def.ReconstructShName ([System.IO.File]::ReadAllBytes($templateSh))

    # The macOS double-click launcher, beside its POSIX restorer. It delegates
    # to reconstruct.sh, so it adds an entry point without adding a third copy
    # of the restore logic (SR-072).
    $templateCommand = Join-Path (Split-Path $PSScriptRoot -Parent) (Join-Path 'bash' 'reconstruct.command')
    if (-not (Test-Path -LiteralPath $templateCommand -PathType Leaf)) {
        throw "reconstruct.command not found at '$templateCommand'"
    }
    & $writeKitFile $script:Def.ReconstructCommandName ([System.IO.File]::ReadAllBytes($templateCommand))

    # Path bindings as a sidecar (read by Reconstruct.ps1 from $PSScriptRoot).
    # [ordered]: a hashtable's key order varies from process to process, which
    # would rewrite an unchanged sidecar on about every other run. The bytes are
    # what Set-Content -Encoding UTF8 wrote: no BOM, a trailing newline.
    $sidecar = [ordered]@{ BackupRoot = $BackupRoot; ChangeRoot = $ChangeRoot } | ConvertTo-Json
    & $writeKitFile 'RECONSTRUCT.paths.json' ([System.Text.UTF8Encoding]::new($false).GetBytes($sidecar + [Environment]::NewLine))

    # The Windows double-click launcher. -ExitCode makes the process entry point
    # report the SR-040 exit-code table (0/1/2/3/4) instead of throwing;
    # in-process callers omit it and keep the terminating-error behavior they
    # assert on.
    #
    # It is a PURE PASSTHROUGH and must stay one. An earlier draft paused here
    # so a double-clicked window would not vanish before the operator read the
    # outcome, but `pause` blocks a console-attached automated caller that
    # passes no arguments and never returns its exit code (2026-08-28
    # independent review, T6). The window-holding lives in RECONSTRUCT.ps1
    # instead, on the branch that has already proved a human is present.
    #
    # .cmd, not .bat: this repo's own convention is run.{cmd,sh,command}
    # (docs/process-options.md). cmd.exe treats the two identically for a file
    # this shape - they differ only in ERRORLEVEL handling around built-ins
    # none of this uses. CRLF and ASCII, as cmd.exe expects.
    $cmd = "@echo off`r`npwsh -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$($script:Def.ReconstructPs1Name)`" -ExitCode %*"
    & $writeKitFile $script:Def.ReconstructCmdName ([System.Text.Encoding]::ASCII.GetBytes($cmd + [Environment]::NewLine))

    # Bundle the shared module so the deployed reconstruct script is self-contained.
    & $writeKitFile $script:Def.CommonModuleName ([System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $script:Def.CommonModuleName)))

    # Bundle the xxHash DLL so hashing works on a machine without the NuGet package.
    $dll = Get-XxHashDllPath
    if ($dll) {
        & $writeKitFile 'System.IO.Hashing.dll' ([System.IO.File]::ReadAllBytes($dll))
    }
}

# endregion

# region Exclusive use: the OS lock (SR-085, SR-086)

# Test seams. Each defaults to $null and is assigned nowhere outside the suite.
$script:PruneTestHook_InTransaction              = $null   # TC-246 (a backup against a live prune)
$script:StagingOsLockTestHook_BeforeOpen         = $null   # TC-249 (an open failure that is not a sharing violation)

# The staging OS lock (SR-085). A plain file at the CHANGE ROOT, outside Temp:
# the change root is enumerated for DIRECTORIES only by every consumer (the
# engine's snapshot enumerators, both restorers), and a run's own backup.log
# already lives beside it, so a file here is invisible to all of them. It is
# opened with FileShare.None and held for the whole of a backup or prune; the
# OS closes the handle however the holder dies. Never deleted (SR-087).
$script:StagingOsLockFileName    = 'Temp.lock'
# An open that fails is retried briefly before it refuses: a scanner holding the
# file for a moment must not cost a nightly run. A lock that STAYS unopenable is
# LIVE, whatever the reason (SR-086) -- retrying only ever delays a refusal.
$script:StagingOsLockOpenAttempts = 3
$script:StagingOsLockRetryDelayMs = 250

function Invoke-StagingTestHook {
    <#
    .SYNOPSIS
        Invokes one of the SR-075 reclaim/fence test seams if the suite has
        installed it. A no-op in production, where every seam is $null.

    .PARAMETER Hook
        The seam's scriptblock, or $null.

    .PARAMETER Context
        Passed to the seam as its single positional argument.

    .OUTPUTS
        None.
    #>
    # Implements: SR-075, LLR-017
    [CmdletBinding()]
    param(
        [AllowNull()][scriptblock]$Hook,
        [AllowNull()][object]$Context
    )

    if ($null -eq $Hook) { return }
    & $Hook $Context
}

function Get-StagingOsLockPath {
    <#
    .SYNOPSIS
        The path of a change root's staging OS lock file (SR-085):
        <ChangeRoot>/Temp.lock, OUTSIDE Temp.

    .PARAMETER ChgPath
        The change root.

    .OUTPUTS
        [string]
    #>
    # Implements: SR-085, SR-087, LLR-090, LLR-093
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChgPath)

    return (Join-Path $ChgPath $script:StagingOsLockFileName)
}

function Enter-StagingOsLock {
    <#
    .SYNOPSIS
        Takes the change root's staging OS lock -- Temp.lock opened with
        FileShare.None, non-blocking -- and returns the handle the caller must
        release with Exit-StagingOsLock in a finally. Throws
        '[SR-075/lock-held] ...' when it cannot.

    .DESCRIPTION
        The lock is the one liveness signal a killed process cannot fake: the
        OS closes the handle however its holder ends -- normal exit, throw,
        TerminateProcess, SIGKILL, OOM kill, container stop -- so a held lock
        means a holder that is ALIVE, and nothing else does (SR-085).

        Fail closed (SR-086). ANY failure to open the file is LIVE: a sharing
        violation (another FileBackup holds it), access denied, an antivirus or
        indexer holding it, a directory squatting on the name, an I/O error.
        None of those is evidence that no run is alive, so every one refuses,
        after a short retry that only ever delays the refusal. The caller must
        then touch nothing -- not Temp, not the pool, not a manifest.

        Acquiring it proves only that no CURRENT-version FileBackup is alive
        here. A run of an older FileBackup -- and the hub's container image
        lags this repository -- never takes it, so a free lock is NOT evidence
        of death: the owner record, heartbeat and confirmation sample (SR-075)
        still decide whatever they decided before. The lock only ever ADDS a
        refusal (SR-086).

        The file is opened OpenOrCreate with READ access only, so a read-only
        attribute on it cannot wedge the store, and it is never written and
        never deleted (SR-087).

        Platform semantics (SR-085): on Windows FileShare.None is a mandatory
        share mode that every opener honours, FileBackup or not. On Linux and
        macOS .NET emulates it with an ADVISORY flock(LOCK_EX | LOCK_NB), which
        excludes only processes that also flock the file -- every FileBackup
        does -- and which .NET silently skips when the filesystem does not
        support flock or when System.IO.DisableFileLocking is set: the open then
        SUCCEEDS without a lock, and the SR-075 rules are all that remains.

    .PARAMETER ChgPath
        The change root (must exist).

    .PARAMETER Log
        The set logger, or $null.

    .OUTPUTS
        [pscustomobject] Path, Stream.
    #>
    # Implements: SR-085, SR-086, SR-087, LLR-090
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChgPath,
        [AllowNull()][scriptblock]$Log
    )

    $path     = Get-StagingOsLockPath -ChgPath $ChgPath
    $attempts = [math]::Max(1, [int]$script:StagingOsLockOpenAttempts)
    $failure  = $null
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        if ($attempt -gt 1) { Start-Sleep -Milliseconds ([int]$script:StagingOsLockRetryDelayMs) }
        try {
            # Test seam INSIDE the try: a throwing seam stands in for an open
            # that fails for a reason other than a sharing violation (TC-249).
            Invoke-StagingTestHook -Hook $script:StagingOsLockTestHook_BeforeOpen -Context $path
            $stream = [System.IO.FileStream]::new($path,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::None)
            if ($null -ne $Log) {
                try { & $Log "Staging OS lock taken at '$path' (SR-085)." } catch { Write-Debug "OS-lock log line swallowed: $($_.Exception.Message)" }
            }
            return [pscustomobject]@{ Path = $path; Stream = $stream }
        } catch {
            $failure = $_
        }
    }

    # Wording only -- every branch below refuses identically (SR-086).
    $inner = $failure.Exception
    while ($inner -is [System.Management.Automation.MethodInvocationException] -and $null -ne $inner.InnerException) {
        $inner = $inner.InnerException
    }
    $hr = $inner.HResult
    $sharing = ($inner -is [System.IO.IOException]) -and (
        $hr -eq [int]0x80070020 -or $hr -eq [int]0x80070021 -or
        ($IsLinux -and $hr -eq 11) -or ($IsMacOS -and $hr -eq 35))
    $why = if ($sharing) {
        'another process holds it -- a FileBackup run or prune that is ALIVE, since the OS releases this lock when its holder exits, however it exits'
    } else {
        "it could not be opened ($($inner.GetType().Name): $($inner.Message)); an open failure is never evidence that no run is alive"
    }
    throw ("[SR-075/lock-held] The staging lock '$path' is held: $why. Refusing without touching the staging folder, " +
        "the pool or any manifest (SR-086). Wait for the other run to finish; if none is running, find what holds the file.")
}

function Exit-StagingOsLock {
    <#
    .SYNOPSIS
        Releases a staging OS lock taken by Enter-StagingOsLock. Idempotent,
        $null-safe and never throws; the file is left in place (SR-087).

    .DESCRIPTION
        The file is deliberately NOT deleted. On Linux the lock is an flock on
        an INODE: unlinking the path while (or just after) it is held lets a
        process that opened the old inode lock it, while a third creates a fresh
        file at the path and locks THAT -- two holders at once. Leaving one
        permanent, never-written, zero-length file has no such window on any
        platform.

    .PARAMETER Lock
        The Enter-StagingOsLock result, or $null.

    .PARAMETER Log
        The set logger, or $null.

    .OUTPUTS
        None.
    #>
    # Implements: SR-085, SR-087, LLR-090, LLR-093
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Lock,
        [AllowNull()][scriptblock]$Log
    )

    if ($null -eq $Lock) { return }
    try {
        $stream = $Lock.Stream
        if ($null -eq $stream) { return }
        $Lock.Stream = $null
        $stream.Dispose()
        if ($null -ne $Log) { & $Log "Staging OS lock released at '$($Lock.Path)' (SR-085)." }
    } catch {
        Write-Debug "Exit-StagingOsLock swallowed: $($_.Exception.Message)"
    }
}

function Enter-StoreMutationLock {
    <#
    .SYNOPSIS
        Takes the staging OS lock for a store-maintenance mutator that is not a
        backup or a prune (-RepairStorage, -RefreshKits), or throws a refusal
        carrying '[SR-075/lock-held]' after logging it (SR-085, SR-086).

    .DESCRIPTION
        The same lock and the same fail-closed rule every backup and prune
        uses: ANY failure to take it is a live holder, and the caller must
        mutate nothing. Two edge cases:

          * no change root was given -- there is nowhere to take the lock, so
            it refuses, since nothing then proves no backup is running;
          * the change root does not exist -- it is CREATED (a backup would
            create it too) and then locked, so a backup that is in its first
            instants either already holds the lock or will find it held.

        The caller releases with Exit-StagingOsLock in a finally. It is called
        from the mutator itself, not from the entry point, so a direct module
        caller is covered exactly like FileBackup.ps1.

    .PARAMETER ChangeRoot
        The store's change root.

    .PARAMETER Activity
        What the caller was about to do, for the refusal sentence.

    .PARAMETER Log
        The caller's logger, or $null.

    .OUTPUTS
        [pscustomobject] the Enter-StagingOsLock handle.
    #>
    # Implements: SR-085, SR-086, LLR-094
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$ChangeRoot,
        [Parameter(Mandatory)][string]$Activity,
        [AllowNull()][scriptblock]$Log
    )

    $message = $null
    if ([string]::IsNullOrWhiteSpace($ChangeRoot)) {
        $message = ("[SR-075/lock-held] Refusing to ${Activity}: no change root was given, so the staging lock that " +
            'excludes a running backup or prune cannot be taken (SR-086). Nothing was touched.')
    } else {
        try {
            if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $ChangeRoot -Force | Out-Null
            }
            return (Enter-StagingOsLock -ChgPath $ChangeRoot -Log $Log)
        } catch {
            $detail = $_.Exception.Message
            if ($detail.IndexOf('[SR-075/lock-held]', [System.StringComparison]::Ordinal) -lt 0) {
                $detail = "[SR-075/lock-held] the staging lock could not be taken: $detail"
            }
            $message = "Refusing to ${Activity}: $detail Nothing was touched."
        }
    }
    if ($null -ne $Log) {
        try { & $Log $message 'ERROR' } catch { Write-Debug "Refusal log line swallowed: $($_.Exception.Message)" }
    }
    throw $message
}

# endregion

# region Compressibility probe (SR-081)

# The two ruled defaults (plan §2.2, Owner Q2/Q3), module-scope constants IN
# ENGINE: there is deliberately no Common accessor (Common is kit-bundled and an
# accessor there would cost a KitRevision for a concept restore has no use for)
# and no configuration key (SR-081 rationale: two knobs nobody can measure).
# Tests read them through InModuleScope.
$script:CompressProbeThreshold   = 0.10      # aggregate shrink a file must show
$script:CompressProbeMinBytes    = 262144    # 256 KiB floor: below it, no probe
$script:CompressProbeSampleBytes = 262144    # 256 KiB per sampled window
$script:CompressProbeSampleCount = 3         # windows: start, middle, end

function Measure-SampleCompressibility {
    <#
    .SYNOPSIS
        Samples a file at fixed offsets, compresses each window into a counting
        null sink, and reports how much the sampled bytes actually shrink
        (SR-081). The I/O shell; the decision is Resolve-CompressionDecision's.

    .DESCRIPTION
        The filename is a claim; the bytes are the evidence. This reads at most
        Samples x SampleBytes and never touches any destination path.

        It opens the source with FileShare.Read — the same share Get-FileXxHash
        (Common.psm1:352) and the stored-form sniffer (Common.psm1:847) use — so
        probe success predicts copy success. What that share mode buys is
        PLATFORM-QUALIFIED. On Windows the kernel checks sharing in both
        directions, so a FileShare.Read open FAILS with a sharing violation
        while any writer holds the file (verified live): the probe therefore
        cannot sample a file that is open for writing — it returns $null and the
        caller takes the list's answer. On POSIX, .NET's FileShare is advisory
        emulation only, so a non-cooperating writer CAN change bytes under the
        sample. Against that, and against a Windows writer that opens after the
        probe does, the probe takes a cheap stability check: it reads the
        stream's Length and the file's LastWriteTimeUtc before and after
        sampling and returns $null if either moved. A changed file costs a
        decision (the list answers instead), never a file (I-6).

        GEOMETRY. When the file is shorter than Samples x SampleBytes it is read
        ONCE, whole, as a single sample (this avoids the 1.9x over-read three
        overlapping windows would produce in the 256 KiB-768 KiB band).
        Otherwise Samples windows of SampleBytes are read at Int64 offsets
        evenly spaced across the file — for the shipped Samples = 3 those are
        exactly 0, floor((len - SampleBytes) / 2) and len - SampleBytes. Each
        window is filled by an exact-read loop that retries a short Read until
        the window is full or EOF.

        CODEC: BrotliStream at CompressionLevel.Fastest, chosen by the Part B1
        calibration (docs/plans/wp17-codec-calibration.md, recorded in LLR-086).
        DeflateStream at Fastest was the drafted alternative and lost on both
        counts measured: it disagreed with a real `7z -mx=9` outcome on two of
        eleven corpus files against Brotli's one (Deflate's 32 KiB history
        cannot see the 64 KiB-period repetition Brotli's ~4 MB window catches
        inside a single 256 KiB sample), and it cost ~5x the CPU per sample
        (137 ms vs 28 ms over the corpus).

        The compressed count is read AFTER the encoder's Dispose(): a count
        taken before the encoder is closed reads short and would call random
        bytes compressible. TC-223 pins this by asserting random never measures
        below 0.98.

        ANY failure — a missing path, a share violation, a permission error, an
        I/O fault — returns $null. This function never throws to its caller
        (I-6): a lock costs a decision, never a file.

    .PARAMETER Path
        Full path of the SOURCE file to sample. Never a destination path.

    .PARAMETER SampleBytes
        Bytes per window. Defaults to $script:CompressProbeSampleBytes (256 KiB).

    .PARAMETER Samples
        Number of windows. Defaults to $script:CompressProbeSampleCount (3).

    .OUTPUTS
        [pscustomobject] with SampledBytes (long), CompressedBytes (long),
        Windows (double[], the per-window compressed/sampled ratio, for the log
        line) and Ratio (CompressedBytes / SampledBytes) — or $null when the
        file is empty or could not be sampled at all.
    #>
    # Implements: SR-081, LLR-086
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$SampleBytes = $script:CompressProbeSampleBytes,
        [int]$Samples     = $script:CompressProbeSampleCount
    )

    if ($SampleBytes -lt 1 -or $Samples -lt 1) { return $null }

    $stream = $null
    try {
        # The counting null sink, compiled once per session (the LLR-080 precedent
        # for Add-Type idempotence). The probe never needs the compressed BYTES,
        # only how many there are, so nothing is allocated to hold them. It is C#
        # rather than a PowerShell class because a PowerShell class's methods would
        # land in the GENERATED module map as bogus top-level functions.
        if (-not ('FileBackup.CountingSink' -as [type])) {
            Add-Type -TypeDefinition @'
namespace FileBackup
{
    using System;
    using System.IO;

    /// <summary>Write-only /dev/null that only counts the bytes written.</summary>
    public sealed class CountingSink : Stream
    {
        private long _count;
        public long Count { get { return _count; } }
        public override bool CanRead  { get { return false; } }
        public override bool CanSeek  { get { return false; } }
        public override bool CanWrite { get { return true; } }
        public override long Length   { get { return _count; } }
        public override long Position { get { return _count; } set { } }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override void Write(byte[] buffer, int offset, int count) { _count += count; }
    }
}
'@
        }

        $stream = [System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read)

        $length = $stream.Length
        if ($length -le 0) { return $null }   # empty file: nothing to measure

        # Stability witnesses, read BEFORE the windows and compared after: on
        # POSIX the share mode is advisory, so a writer can move bytes under the
        # sample; on Windows one can still open after this handle does. Either
        # way a measurement taken across a rewrite describes no file that exists,
        # so it is discarded (return $null) and the list answers instead.
        $lengthBefore = $length
        $stampBefore  = [IO.File]::GetLastWriteTimeUtc($Path)

        if ($length -lt ([long]$Samples * [long]$SampleBytes)) {
            $window  = [int]$length
            $offsets = @([long]0)
        } else {
            $window = $SampleBytes
            $span   = $length - [long]$SampleBytes
            $offsets = @(0..($Samples - 1) | ForEach-Object {
                if ($Samples -eq 1) { [long]0 }
                else { [long][math]::Floor(($_ * $span) / ($Samples - 1)) }
            })
        }

        $buffer         = [byte[]]::new($window)
        $totalSampled   = [long]0
        $totalCompressed = [long]0
        $ratios         = [System.Collections.Generic.List[double]]::new()

        foreach ($offset in $offsets) {
            $null = $stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
            $filled = 0
            while ($filled -lt $window) {
                $read = $stream.Read($buffer, $filled, $window - $filled)
                if ($read -le 0) { break }    # EOF: take the short window
                $filled += $read
            }
            if ($filled -le 0) { continue }

            $sink    = [FileBackup.CountingSink]::new()
            $encoder = [System.IO.Compression.BrotliStream]::new(
                $sink, [System.IO.Compression.CompressionLevel]::Fastest, $true)
            try { $encoder.Write($buffer, 0, $filled) } finally { $encoder.Dispose() }

            # Read the count only now — the encoder has flushed its final block.
            $totalSampled    += [long]$filled
            $totalCompressed += $sink.Count
            $ratios.Add([double]$sink.Count / [double]$filled)
        }

        if ($totalSampled -le 0) { return $null }

        # Did the file hold still while we sampled it? (See the witnesses above.)
        if ($stream.Length -ne $lengthBefore -or
            [IO.File]::GetLastWriteTimeUtc($Path) -ne $stampBefore) { return $null }

        return [pscustomobject]@{
            SampledBytes    = $totalSampled
            CompressedBytes = $totalCompressed
            Windows         = $ratios.ToArray()
            Ratio           = [double]$totalCompressed / [double]$totalSampled
        }
    } catch {
        # Missing, locked, denied, faulted — all the same answer, and never a
        # throw: the caller falls back to the extension list's opinion (I-6).
        return $null
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Resolve-CompressionDecision {
    <#
    .SYNOPSIS
        SR-081's ordered rule: composes the CompressEnabled switch, the probe
        mode, the extension list's opinion, the size floor and the measured
        sample into ONE { Compress; Reason } record. Pure — no I/O, no logging.

    .DESCRIPTION
        Rule order, exactly as SR-081 states it (rule 1, a name-based override,
        was REMOVED by Owner ruling Q7 — no input here is named after a format
        and no Reason is either):

          0. CompressEnabled = $false  -> raw, CompressDisabled. NOTHING below
             runs. This is the reviewers' P0: the guard lives inside
             Test-ShouldCompress today, and a rule that consulted the probe
             first would name a .7z object and record Compressed=Yes on a Plain
             set whose 7-Zip is not even resolved.
          2. Mode 'off'                -> the list's answer, unchanged
             pre-WP17 behaviour. Reason ModeOff when the list says compress,
             ListExempt when it says no.
          3. Length < ProbeMinBytes    -> the list's answer, Reason BelowFloor
             in BOTH directions: the Reason names WHY the list was consulted,
             not what it said.
          4. Mode 'excluded-extensions' and the list says no -> raw, ListExempt.
          5. Probe unavailable         -> the list's answer, ProbeUnavailable.
             The CALLER emits the one WARN; this function never logs.
          6. CompressedBytes <= (1 - Threshold) x SampledBytes -> compress,
             ProbeCompressible. This is the AGGREGATE rule: a multi-gigabyte
             random file with a 64 KiB text head reads ~0.93 and stays raw
             (the defect review's own failure mode), while a file one third
             text reads ~0.7 and compresses.
          7. otherwise                 -> raw, ProbeIncompressible.

    .PARAMETER CompressEnabled
        The set's CompressEnabled flag. $false dominates every other input.

    .PARAMETER Mode
        The SR-081 probe mode, exact lowercase: 'off', 'excluded-extensions' or
        'always'. Anything else is rejected by the ValidateSet — the config
        validator guarantees lowercase before this is ever called.

    .PARAMETER ListSaysCompress
        The Test-ShouldCompress answer computed with -CompressEnabled $true, so
        it carries ONLY the extension list's opinion and not the set's switch.

    .PARAMETER Length
        The source file's length in bytes, compared against ProbeMinBytes.

    .PARAMETER ProbeMinBytes
        The size floor. Defaults to $script:CompressProbeMinBytes.

    .PARAMETER SampledBytes
        Measure-SampleCompressibility's SampledBytes total. Zero (the default)
        means the probe was UNAVAILABLE — that is how a $null probe result is
        represented here, so the pure core needs no separate availability flag.

    .PARAMETER CompressedBytes
        Measure-SampleCompressibility's CompressedBytes total.

    .PARAMETER Threshold
        The fraction the sampled bytes must shrink by. Defaults to
        $script:CompressProbeThreshold (0.10).

    .OUTPUTS
        [pscustomobject] @{ Compress = [bool]; Reason = [string] } where Reason
        is one of CompressDisabled, ModeOff, BelowFloor, ListExempt,
        ProbeUnavailable, ProbeCompressible, ProbeIncompressible.
    #>
    # Implements: SR-081, LLR-086
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$CompressEnabled,
        [Parameter(Mandatory)][ValidateSet('off', 'excluded-extensions', 'always')]
        [string]$Mode,
        [Parameter(Mandatory)][bool]$ListSaysCompress,
        [long]$Length          = 0,
        [long]$ProbeMinBytes   = $script:CompressProbeMinBytes,
        [long]$SampledBytes    = 0,
        [long]$CompressedBytes = 0,
        [double]$Threshold     = $script:CompressProbeThreshold
    )

    # ValidateSet is case-INSENSITIVE, so pin the exact-lowercase vocabulary the
    # config validator publishes (the BrowseView precedent, -cnotin).
    if ($Mode -cnotin @('off', 'excluded-extensions', 'always')) {
        throw "Resolve-CompressionDecision: Mode must be one of off, excluded-extensions, always (exact lowercase); got '$Mode'."
    }

    $verdict = { param([bool]$Compress, [string]$Reason)
        [pscustomobject]@{ Compress = $Compress; Reason = $Reason } }

    # 0. The set switch dominates everything. Nothing below runs.
    if (-not $CompressEnabled) { return (& $verdict $false 'CompressDisabled') }

    # 2. Mode off: exactly the pre-WP17 path.
    if ($Mode -ceq 'off') {
        if ($ListSaysCompress) { return (& $verdict $true 'ModeOff') }
        return (& $verdict $false 'ListExempt')
    }

    # 3. Below the floor: never probed, so the list answers.
    if ($Length -lt $ProbeMinBytes) { return (& $verdict $ListSaysCompress 'BelowFloor') }

    # 4. excluded-extensions: the list still exempts what it knows.
    if ($Mode -ceq 'excluded-extensions' -and -not $ListSaysCompress) {
        return (& $verdict $false 'ListExempt')
    }

    # 5. No measurement: fall back to today's answer, never to a guess.
    if ($SampledBytes -le 0) { return (& $verdict $ListSaysCompress 'ProbeUnavailable') }

    # 6/7. The aggregate measurement decides.
    if ($CompressedBytes -le ((1.0 - $Threshold) * $SampledBytes)) {
        return (& $verdict $true 'ProbeCompressible')
    }
    return (& $verdict $false 'ProbeIncompressible')
}

function Resolve-GroupStorageForm {
    <#
    .SYNOPSIS
        The I/O shell around Resolve-CompressionDecision: decides ONE
        (hash,length) group's stored form, sampling the group's readable
        candidates only when the ordered rule actually needs a measurement
        (SR-081).

    .DESCRIPTION
        Publish-StagedObject calls this ONCE per new stored object, with the
        staged copy as the only candidate (LLR-058) - so content already in the
        store, and a twin seen later in the same run, never reach it.

        THE PROBE IS NOT OPENED unless rules 0/2/3/4 leave the measurement
        decisive: compression must be enabled, the mode must not be 'off', the
        length must be at or above the floor, and 'excluded-extensions' must
        not already have exempted the name. Rule 0 first is the reviewers' P0 —
        with CompressEnabled=false nothing is read at all.

        CANDIDATE WALK. Every member of a (hash,length) group holds identical
        bytes, so any member can supply the sample. The candidate list is the
        same owner-then-members list the copy path builds (WP9 MIN-1): a locked
        owner must not cost the group its measurement when a readable twin can
        serve it. The first candidate that opens decides; only when none opens
        is the verdict ProbeUnavailable — the LIST'S answer, never a guess, and
        the caller emits the one WARN (I-6).

    .PARAMETER CompressEnabled
        The set's CompressEnabled flag. $false dominates: rule 0, no probe.

    .PARAMETER Mode
        The set's CompressProbe mode, exact lowercase (SR-081).

    .PARAMETER ListSaysCompress
        Test-ShouldCompress on the OWNER's name, computed with -CompressEnabled
        $true so it carries only the extension list's opinion.

    .PARAMETER Length
        The group's content length (every member shares it), against the floor.

    .PARAMETER Candidate
        Full source paths to sample, in preference order: the owner first, then
        the other members.

    .OUTPUTS
        [pscustomobject] Compress / Reason (Resolve-CompressionDecision's
        verdict) plus SampledBytes, Ratio and Windows for the caller's
        compress-decision DEBUG line and its Probe reads counter. SampledBytes
        is 0 when no probe ran or none could be opened.
    #>
    # Implements: SR-081, LLR-058, LLR-086
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$CompressEnabled,
        [Parameter(Mandatory)][ValidateSet('off', 'excluded-extensions', 'always')]
        [string]$Mode,
        [Parameter(Mandatory)][bool]$ListSaysCompress,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Candidate
    )

    # ValidateSet is case-INSENSITIVE, so a hand-built caller can still reach
    # here with 'Always'. Refuse it BEFORE $probeDecides - i.e. before a single
    # source byte is read - rather than letting the probe run and the pure core
    # throw afterwards (R-10). Same vocabulary, same SR-042 wording.
    if ($Mode -cnotin @('off', 'excluded-extensions', 'always')) {
        throw "Invalid CompressProbe '$Mode'. Expected 'off', 'excluded-extensions' or 'always' (exact lowercase)."
    }

    $probeDecides = $CompressEnabled -and
                    ($Mode -cne 'off') -and
                    ($Length -ge $script:CompressProbeMinBytes) -and
                    -not (($Mode -ceq 'excluded-extensions') -and (-not $ListSaysCompress))

    $probe = $null
    if ($probeDecides) {
        foreach ($path in $Candidate) {
            $probe = Measure-SampleCompressibility -Path $path
            if ($null -ne $probe) { break }
        }
    }

    # Zero SampledBytes IS how "no measurement" reaches the pure core (its
    # documented contract), so a $null probe needs no separate flag.
    $sampled    = [long]0
    $compressed = [long]0
    $ratio      = $null
    $windows    = $null
    if ($null -ne $probe) {
        $sampled    = [long]$probe.SampledBytes
        $compressed = [long]$probe.CompressedBytes
        $ratio      = [double]$probe.Ratio
        $windows    = $probe.Windows
    }

    $verdict = Resolve-CompressionDecision -CompressEnabled $CompressEnabled -Mode $Mode `
                -ListSaysCompress $ListSaysCompress -Length $Length `
                -SampledBytes $sampled -CompressedBytes $compressed

    [pscustomobject]@{
        Compress     = $verdict.Compress
        Reason       = $verdict.Reason
        SampledBytes = $sampled
        Ratio        = $ratio
        Windows      = $windows
    }
}

function New-ProbeStatistic {
    <#
    .SYNOPSIS
        A zeroed SR-081 probe-counter accumulator for one backup set.

    .DESCRIPTION
        RawObjects/RawBytes and CompressedObjects count PHYSICAL objects and are
        incremented AFTER a successful write, so they never describe bytes the
        store does not hold. ReadBytes is the first-run cost figure the operator
        is owed and counts what the probe actually read, whether or not the
        write that followed succeeded.

    .OUTPUTS
        [hashtable] with RawObjects, RawBytes, CompressedObjects, ReadBytes.
    #>
    # Implements: SR-081, LLR-086
    [CmdletBinding()]
    param()
    @{ RawObjects = [long]0; RawBytes = [long]0; CompressedObjects = [long]0; ReadBytes = [long]0 }
}

function Write-ProbeStatistic {
    <#
    .SYNOPSIS
        Emits the three SR-081 per-set summary counter lines through the set's
        logger.

    .PARAMETER Stats
        A New-ProbeStatistic accumulator, filled by Publish-StagedObject.

    .PARAMETER Log
        The set's logging scriptblock.

    .OUTPUTS
        None.
    #>
    # Implements: SR-081, LLR-086
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Stats,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    & $Log "Probe stored raw: $($Stats.RawObjects) objects, $($Stats.RawBytes) bytes"
    & $Log "Probe compressed: $($Stats.CompressedObjects)"
    & $Log "Probe reads: $($Stats.ReadBytes) bytes"
}

# endregion

# region Per-set orchestration helpers

function Assert-StoreVolumePresent {
    <#
    .SYNOPSIS
        Throws System.IO.DriveNotFoundException when the drive or share a store
        path lives on is not attached, so the caller can tell "the drive is not
        there" (retry later, 4) from a path that cannot be created (2).

    .DESCRIPTION
        Decided by the path's root: a Windows drive letter or a UNC share. On
        Linux the root is '/', which always exists; a mount that is not there
        shows instead as a store that lost its backup folder (plan C26) or, on
        HomeHub, is refused by the wrapper before the container starts.

    .PARAMETER Path
        A BackupPath or ChangePath that does not exist.

    .PARAMETER SetName
        The set, for the message.
    #>
    # Implements: SR-014, SR-040, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SetName
    )
    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    if ($root -and -not [System.IO.Directory]::Exists($root)) {
        $hint = if ($root -match '^[A-Za-z]:\\?$') { ' If it is a mapped network drive, a scheduled task cannot see it: use the UNC path (\\server\share\...) instead.' } else { '' }
        throw [System.IO.DriveNotFoundException]::new(
            "The drive '$root' for set '$SetName' ('$Path') is not attached; nothing was written. The next run is the retry once it is back.$hint")
    }
}

function Resolve-BackupSetPaths {
    <#
    .SYNOPSIS
        Validates the set's SourcePath and resolves (creating if needed) the
        Backup/Change paths to absolute form.

    .DESCRIPTION
        A missing root is created only when that is safe:
          * its drive or share is not attached (a Windows drive letter, a UNC
            share): System.IO.DriveNotFoundException, which a backup reports as
            4 - retry when the drive is back (plan C25);
          * BackupPath is missing while ChangePath already holds snapshots: an
            existing store that lost its backup folder (moved, renamed, or a
            mount that is not there) - refused, never answered with a fresh
            full backup (plan C26).

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
        Assert-StoreVolumePresent -Path $Set.BackupPath -SetName $Set.Name
        $chgFull = [System.IO.Path]::GetFullPath([string]$Set.ChangePath)
        if ([System.IO.Directory]::Exists($chgFull) -and
            @(Get-ChildItem -LiteralPath $chgFull -Directory -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match $script:Def.ChangeFolderRegex } | Select-Object -First 1).Count -gt 0) {
            throw ("Backup path '$($Set.BackupPath)' for set '$($Set.Name)' does not exist, but its change folder '$($Set.ChangePath)' holds snapshots: " +
                   "the store has lost its backup folder (moved, renamed, or a mount that is not there). Refusing to start a new full backup; " +
                   "put the folder back, or point BackupPath at it.")
        }
        New-Item -ItemType Directory -Path $Set.BackupPath -Force | Out-Null
        $bkpPath = (Resolve-Path -LiteralPath $Set.BackupPath).Path
    }

    $chgPath = (Resolve-Path -LiteralPath $Set.ChangePath -ErrorAction SilentlyContinue).Path
    if (-not $chgPath) {
        Assert-StoreVolumePresent -Path $Set.ChangePath -SetName $Set.Name
        New-Item -ItemType Directory -Path $Set.ChangePath -Force | Out-Null
        $chgPath = (Resolve-Path -LiteralPath $Set.ChangePath).Path
    }

    # SourceStatePath is no longer used: the latest backup manifest is the
    # change-detection record (plan R3). It is still resolved, never created,
    # because it decides whether root-level infrastructure names in the source
    # are skipped (an old in-source record) or are user data (plan C6).
    $srcStatePath = $srcPath
    if (-not [string]::IsNullOrWhiteSpace([string]$Set.SourceStatePath)) {
        $srcStatePath = [System.IO.Path]::GetFullPath([string]$Set.SourceStatePath)
        $resolvedState = (Resolve-Path -LiteralPath $Set.SourceStatePath -ErrorAction SilentlyContinue).Path
        if ($resolvedState) { $srcStatePath = $resolvedState }
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

# endregion

# region Bounded backup run (docs/plans/bounded-run-loop.md)

# The tunables of the bounded run (plan R12, R13, C7). Module-scope so the suite
# can shorten the waits; production never changes them and none is a
# configuration key.
$script:RetryMinSpacingSeconds = 60      # R12: a failed file waits this long since its last attempt
$script:RetryMaxAttempts       = 3       # R12: attempts in all, then a warning
$script:CheckpointMinSeconds   = 60      # R13: progress is saved at most this often...
$script:ProgressIntervalSeconds = 60      # a progress line in long runs
$script:CheckpointWriteFactor  = 10      # ...and never more often than ten times the last write took
$script:LocalTempMaxBytes      = 256MB   # C7: largest file staged in the host or container temp
$script:IncomingFolderName     = 'Incoming'    # temp copies on the backup volume, under ChangePath
$script:BuildingFolderPrefix   = 'Building_'   # a snapshot being prepared; no restorer reads it
$script:VerifyFolderName       = 'Verify'      # -Action Verify -RepairStorage moves set-aside objects here
$script:MountCheckPrefix       = '.fbmountcheck-'
# Test seam: a scriptblock invoked as (& $hook <Stage> <Context>) at the named
# stages of a run. A hook that throws stands in for a kill at that point,
# because nothing a run does after a throw undoes the work before it.
$script:BackupRunTestHook      = $null

# The stored-object name grammar (SR-069) parsed WITHOUT decoding the hash:
# a backup run indexes every object on every run, and the BigInteger decoder
# in Common costs about a millisecond a name. The name's prefix (the 22-digit
# hash field, the separator and the length field) IS the content key, so the
# index is keyed on that string and only the short length field is decoded.
$script:StoredNameAlphabet = (Get-FileBackupDefaults).Alphabet
$script:StoredNameDigit = [System.Collections.Generic.Dictionary[char, int]]::new()
for ($i = 0; $i -lt $script:StoredNameAlphabet.Length; $i++) { $script:StoredNameDigit[$script:StoredNameAlphabet[$i]] = $i }
$script:StoredNamePattern = [regex]::new(
    '^([' + [regex]::Escape($script:StoredNameAlphabet) + ']{22})_([' + [regex]::Escape($script:StoredNameAlphabet) + ']+)(.*)$',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)

function ConvertFrom-StoredObjectName {
    <#
    .SYNOPSIS
        Splits a stored-object name into its content-key prefix, its content
        length and its extension, or returns $null when the name does not
        follow the SR-069 grammar.

    .DESCRIPTION
        Structurally the same reading as Common's ConvertFrom-HashSizeFileName
        (22 hash digits, the separator, the longest run of length digits, then
        an extension that is empty or starts with '.'), without decoding the
        hash. The prefix is compared ordinally: the alphabet has both cases.

    .PARAMETER Name
        A file name.

    .OUTPUTS
        [pscustomobject] Prefix, Length ([long]), Extension - or $null.
    #>
    # Implements: SR-069, LLR-069
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)
    $m = $script:StoredNamePattern.Match($Name)
    if (-not $m.Success) { return $null }
    $ext = $m.Groups[3].Value
    if ($ext.Length -gt 0 -and ($ext[0] -ne '.' -or $ext.IndexOfAny([char[]]@([char]92, [char]47)) -ge 0)) { return $null }
    $lenField = $m.Groups[2].Value
    [long]$len = 0
    $limit = [long]([long]::MaxValue / $script:StoredNameAlphabet.Length)
    foreach ($ch in $lenField.ToCharArray()) {
        if ($len -gt $limit) { return $null }
        $len = $len * $script:StoredNameAlphabet.Length + $script:StoredNameDigit[$ch]
    }
    return [pscustomobject]@{
        Prefix    = $Name.Substring(0, 23 + $lenField.Length)
        Length    = $len
        Extension = $ext
    }
}

function Get-StoredObjectPrefix {
    <#
    .SYNOPSIS
        The content-key prefix of the stored-object name for (hash, length):
        the name without its extension.

    .PARAMETER HashHex
        The 32-digit xxHash128.

    .PARAMETER Length
        The content length.

    .OUTPUTS
        [string]
    #>
    # Implements: SR-069, LLR-069
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HashHex, [Parameter(Mandatory)][long]$Length)
    return (Get-HashSizeFileName -HashHex $HashHex -Length $Length -Extension '')
}

function Get-ListedObjectDamage {
    <#
    .SYNOPSIS
        Says why a stored object is damaged by what its listing already shows -
        a length its name rules out - or returns $null (review 2026-10-26 G1).

    .DESCRIPTION
        A power loss after an object was renamed to its content name, before
        its bytes reached the disk, leaves it empty (ext4) or at full length
        reading as NULs (NTFS). The empty case, and a torn raw object, show in
        the listing; NULs at full length do not, and only -Action Verify -Deep
        finds them. Damaged when either:

          * it is empty and its name records content; or
          * its name's extension is not '.7z', its length is not the content
            length its name records, and its first bytes are not the 7-Zip
            signature.

        A '.7z' name of nonzero length is never judged by length: an archive is
        legitimately shorter or longer than its content. A raw-named object
        holding archive bytes is an older engine's mislabelled object, which
        the restorers read from its bytes (SR-068): not damage. The bytes are
        read only in that rare mismatched case, never for every object, and a
        file that cannot be read is no evidence, so it is not called damaged
        (C22).

    .PARAMETER Path
        The object file.

    .PARAMETER FileLength
        Its length on disk.

    .PARAMETER ContentLength
        The content length its name records.

    .PARAMETER Extension
        Its name's extension.

    .OUTPUTS
        [string] the reason, or $null when the listing shows no damage.
    #>
    # Implements: SR-049, SR-053, SR-059
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][long]$FileLength,
        [Parameter(Mandatory)][long]$ContentLength,
        [AllowEmptyString()][string]$Extension
    )
    if ($FileLength -eq 0 -and $ContentLength -gt 0) {
        return "it is empty, but its name records $ContentLength byte(s) of content"
    }
    if ($FileLength -eq $ContentLength -or $Extension -ieq '.7z') { return $null }
    try {
        if (Test-SevenZipSignature -Path $Path) { return $null }
    } catch {
        Write-Verbose "Could not read the first bytes of '$Path': $($_.Exception.Message)"
        return $null
    }
    return "it is $FileLength byte(s) long, but its name records $ContentLength byte(s) of raw content and it is no archive"
}

function Get-StoreObjectIndex {
    <#
    .SYNOPSIS
        Indexes every stored object of a backup by name: one listing of the
        backup root and of each Snapshot_* folder, and no manifest read.

    .DESCRIPTION
        An object's name carries its content key (SR-069), so the listings
        alone say what is stored and where (plan step 2). Snapshot manifests
        are never read by a backup run: holding them all was the 6.6 GB OOM of
        the 2026-10-05 defect review. Only top-level files named by the grammar
        count, less a prune's staged copy ('<object>.fbprune.tmp'), which the
        grammar would accept. When one key is found in more than one folder the
        backup root wins, then the newest snapshot; the other copies are listed
        as Duplicates, which a run leaves for -Action Verify (R10).

        An object whose listing shows it damaged (Get-ListedObjectDamage: what
        a power loss can leave) is listed as Damaged instead, and is never an
        object or a duplicate: a run must not reuse it, and an object named
        after content is only ever created from bytes that were hashed as they
        were written (SR-059), so the content is stored again, from the source,
        only while the source still holds it (review 2026-10-26 G1).

    .PARAMETER BackupRoot
        The backup root (the latest state).

    .PARAMETER ChangeRoot
        The change root holding the Snapshot_* folders.

    .OUTPUTS
        [pscustomobject] Objects (an ordinal Dictionary from name prefix to an
        entry: Name, Prefix, Path, Folder - '' for the backup root, else the
        snapshot's folder name - FileLength, ContentLength, Extension), Lengths
        (a HashSet of every stored content length), Duplicates, and Damaged
        (entries of the same shape with a Reason).
    #>
    # Implements: SR-003, SR-053, SR-108
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot
    )
    $objects = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $lengths = [System.Collections.Generic.HashSet[long]]::new()
    $dups    = [System.Collections.Generic.List[object]]::new()
    $damaged = [System.Collections.Generic.List[object]]::new()
    $folders = [System.Collections.Generic.List[object]]::new()
    $folders.Add([pscustomobject]@{ Folder = ''; Path = $BackupRoot })
    $snapshots = @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot)
    for ($i = $snapshots.Count - 1; $i -ge 0; $i--) {
        $folders.Add([pscustomobject]@{ Folder = $snapshots[$i].Name; Path = $snapshots[$i].FullName })
    }
    foreach ($folder in $folders) {
        # DirectoryInfo enumeration includes hidden, system and dot-named files
        # (SR-057): an object name can begin with any alphabet digit.
        foreach ($file in [System.IO.DirectoryInfo]::new($folder.Path).EnumerateFiles()) {
            # A prune killed while copying leaves '<object>.fbprune.tmp' beside
            # the destination (Copy-ReHomedDataFile), possibly partial. The
            # grammar takes '.7z.fbprune.tmp' as an extension, so the staged copy
            # would be indexed as the object - and a run would reuse it, name it
            # in a row, or move it (review 2026-10-26 A3). No object is named so:
            # its extension is its source's last one or '.7z', and a repair only
            # adds or strips '.7z'. Skipped here, never deleted by the suffix -
            # Invoke-PruneEntrySweep removes it, judged by the manifest.
            if ($file.Name.EndsWith('.fbprune.tmp', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $parsed = ConvertFrom-StoredObjectName -Name $file.Name
            if ($null -eq $parsed) { continue }
            $entry = [pscustomobject]@{
                Name          = $file.Name
                Prefix        = $parsed.Prefix
                Path          = $file.FullName
                Folder        = $folder.Folder
                FileLength    = $file.Length
                ContentLength = $parsed.Length
                Extension     = $parsed.Extension
            }
            # Only a length the name rules out can be damage, and never for a
            # '.7z' that is not empty, so the predicate is asked only then: a
            # call per object costs seconds on a store of 180,000 objects.
            if ($file.Length -ne $parsed.Length -and ($file.Length -eq 0 -or $parsed.Extension -ine '.7z')) {
                $damage = Get-ListedObjectDamage -Path $file.FullName -FileLength $file.Length -ContentLength $parsed.Length -Extension $parsed.Extension
                if ($null -ne $damage) {
                    $entry | Add-Member -NotePropertyName Reason -NotePropertyValue $damage
                    $damaged.Add($entry)
                    continue
                }
            }
            if ($objects.ContainsKey($parsed.Prefix)) { $dups.Add($entry); continue }
            $objects[$parsed.Prefix] = $entry
            [void]$lengths.Add($parsed.Length)
        }
    }
    return [pscustomobject]@{ Objects = $objects; Lengths = $lengths; Duplicates = $dups; Damaged = $damaged }
}

function Get-StoredObjectCompressedFlag {
    <#
    .SYNOPSIS
        The manifest's Compressed value for a stored object: 'Yes' for an
        archive this tool made, 'No' otherwise.

    .DESCRIPTION
        Decided from the object itself, as the restorers decide its form
        (SR-068): only a '.7z'-named object whose file length differs from its
        content length is an archive we made. A '.7z' of the user's own stored
        raw has the content's own length. The one case the listing cannot
        decide - a '.7z' as long as its content, which an older build could
        write as an archive - keeps the prior row's answer for that same object.
        The column only feeds the restore capacity estimate; no restorer reads
        it for correctness.

    .PARAMETER Entry
        A Get-StoreObjectIndex entry.

    .PARAMETER PriorCompressed
        The prior row's Compressed value, when that row named this same object.

    .OUTPUTS
        [string] 'Yes' | 'No'
    #>
    # Implements: SR-068, LLR-068
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Entry,
        [AllowNull()][AllowEmptyString()][string]$PriorCompressed
    )
    if ($Entry.Extension -ieq '.7z') {
        if ($Entry.FileLength -ne $Entry.ContentLength) { return 'Yes' }
        if ($PriorCompressed -in 'Yes', 'No') { return $PriorCompressed }
    }
    return 'No'
}

function Assert-SingleStoreMount {
    <#
    .SYNOPSIS
        Refuses a set whose BackupPath and ChangePath are not on one volume and
        one mount (plan R8), by renaming a test directory from one to the other.

    .DESCRIPTION
        Every move between the latest state and a snapshot must be a rename, so
        that an object is in exactly one place before and after it. A path
        comparison cannot prove that: on Linux two bind mounts of one
        filesystem refuse a rename between them. Directory.Move is used because
        it never falls back to copy-and-delete, which File.Move does.

    .PARAMETER BackupRoot
        The resolved backup root.

    .PARAMETER ChangeRoot
        The resolved change root.
    #>
    # Implements: SR-059, LLR-150
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot
    )
    $name = $script:MountCheckPrefix + [guid]::NewGuid().ToString('N')
    $from = Join-Path $ChangeRoot $name
    $to   = Join-Path $BackupRoot $name
    [void][System.IO.Directory]::CreateDirectory($from)
    try {
        [System.IO.Directory]::Move($from, $to)
    } catch {
        $why = $_.Exception.Message
        try { [System.IO.Directory]::Delete($from) } catch { Write-Verbose "could not remove '$from': $($_.Exception.Message)" }
        throw ("BackupPath '$BackupRoot' and ChangePath '$ChangeRoot' must be on one volume and one mount, so that " +
               "moving content between them is a rename. A test rename between them failed: $why " +
               'Put both folders on one drive; in a container, mount one folder that holds both (README).')
    }
    [System.IO.Directory]::Delete($to)
}

function Clear-InterruptedRunResidue {
    <#
    .SYNOPSIS
        Deletes what a killed run leaves behind: the Incoming temp copies, any
        Building_* folder and any mount-check directory. Warns about an old
        engine's Temp staging folder and leaves it alone.

    .DESCRIPTION
        None of these ever holds the only copy of anything (plan step 1): an
        Incoming file is a copy of a source file not yet renamed into the
        store, and a Building_* folder holds only a manifest, a directory
        record and a kit. An older FileBackup's Temp folder is different - it
        can hold the only copy of superseded content - so it is never touched.
        A deletion that fails is a warning; the next run tries again.

    .PARAMETER BackupRoot
        The backup root.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER Log
        The set logger.
    #>
    # Implements: SR-017, SR-075
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $residue = [System.Collections.Generic.List[string]]::new()
    $incoming = Join-Path $ChangeRoot $script:IncomingFolderName
    if (Test-Path -LiteralPath $incoming -PathType Container) { $residue.Add($incoming) }
    foreach ($dir in [System.IO.DirectoryInfo]::new($ChangeRoot).EnumerateDirectories()) {
        if ($dir.Name.StartsWith($script:BuildingFolderPrefix, [System.StringComparison]::Ordinal) -or
            $dir.Name.StartsWith($script:MountCheckPrefix, [System.StringComparison]::Ordinal)) { $residue.Add($dir.FullName) }
    }
    foreach ($dir in [System.IO.DirectoryInfo]::new($BackupRoot).EnumerateDirectories()) {
        if ($dir.Name.StartsWith($script:MountCheckPrefix, [System.StringComparison]::Ordinal)) { $residue.Add($dir.FullName) }
    }
    foreach ($path in $residue) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            & $Log "Removed '$path', left by an interrupted run." 'INFO'
        } catch {
            & $Log "Could not remove '$path', left by an interrupted run: $($_.Exception.Message)" 'WARN'
        }
    }
    $oldStaging = Join-Path $ChangeRoot 'Temp'
    if (Test-Path -LiteralPath $oldStaging -PathType Container) {
        & $Log ("'$oldStaging' was left by an older FileBackup or an interrupted prune and may hold the only copy of " +
                'superseded content. It is left alone; README "A run refuses because Temp exists" says how to recover ' +
                'it by hand.') 'WARN'
    }
}

function Assert-CurrentStoreForm {
    <#
    .SYNOPSIS
        Refuses a store written in a retired form (SR-061): a legacy
        path-addressed row, a pre-WP12 witness version, or a DataPath named
        under a retired grammar.

    .PARAMETER BackupRoot
        The backup root, for the witness an older build left there.

    .PARAMETER Rows
        The latest manifest's rows.
    #>
    # Implements: SR-061, LLR-060
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows
    )
    $legacy = @($Rows | Where-Object { $_.StoredAsHashSize -eq 'Original' })
    if ($legacy.Count -gt 0) {
        throw ("Backup manifest at '$BackupRoot' holds $($legacy.Count) row(s) in the legacy path-addressed form " +
               "(StoredAsHashSize='Original'), e.g. '$($legacy[0].RelativePath)'. This store was written by a " +
               'pre-content-addressed build and cannot be written to (SR-061). Back up to a fresh BackupPath; ' +
               'the old store stays restorable as-is.')
    }
    # A witness only an older build can have left; this build writes none (R5).
    $witness = Test-ManifestWitness -FolderPath $BackupRoot
    if ($witness.Status -ne 'Absent' -and $witness.Version -gt 0 -and $witness.Version -lt $script:Def.WitnessFormatVersion) {
        throw ("Backup manifest at '$BackupRoot' is a pre-WP12 store: its witness declares format version " +
               "$($witness.Version), the retired base-85 name grammar. Mixing two grammars in one pool is refused " +
               '(SR-061). Back up to a fresh BackupPath; restore the old store with the kit bundled inside it.')
    }
    $badName = @($Rows | Where-Object { Test-LegacyStoredObjectName -Name "$($_.DataPath)" })
    if ($badName.Count -gt 0) {
        throw ("Backup manifest at '$BackupRoot' holds $($badName.Count) row(s) named under a retired grammar, " +
               "e.g. '$($badName[0].DataPath)' for '$($badName[0].RelativePath)'. This store was written by a " +
               'pre-WP12 build and cannot be written to (SR-061). Back up to a fresh BackupPath.')
    }
}

function Get-SourceFileList {
    <#
    .SYNOPSIS
        Walks the source once and returns every file to capture, the files whose
        names cannot be restored on both platforms, and the folders that could
        not be listed.

    .DESCRIPTION
        The walk is the one the source-side record's walk always was (SR-057,
        SR-074): hidden, system and dot-named entries included, the volume-root
        pseudo-folders dropped. Nothing is written into the source any more
        (plan R3); the only names still skipped are those of the record older
        builds kept at the source root - MANIFEST.csv, its witness and their
        temp files - and only when that record lived there, i.e. no separate
        SourceStatePath was configured (plan C6). Everything else is user data.
        A name that is not portable is reported, not captured (SR-055), and so
        is every path that differs from another only in letter case: a Windows
        restore holds one file for the group (Get-CaseOnlyCollision).

    .PARAMETER SourcePath
        The resolved source root.

    .PARAMETER ExcludeOldSourceRecord
        Skip the old source-side record at the source root (see .DESCRIPTION).

    .OUTPUTS
        [pscustomobject] Files (a List of [pscustomobject] RelativePath, File),
        Unportable (RelativePath, Reason) and Unreadable (Path, Message).
    #>
    # Implements: SR-001, SR-055, SR-057, SR-074, LLR-001, LLR-055, LLR-057
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][bool]$ExcludeOldSourceRecord
    )
    $unreadable = [System.Collections.Generic.List[object]]::new()
    $unportable = [System.Collections.Generic.List[object]]::new()
    $files      = [System.Collections.Generic.List[object]]::new()
    $filePaths  = [System.Collections.Generic.List[string]]::new()
    $oldRecord  = @($script:Def.DatabaseFilename, $script:Def.WitnessFilename,
                    $script:Def.DatabaseTempFilename, "$($script:Def.WitnessFilename).tmp")
    $enumErr = $null
    $walked = Get-ChildItem -LiteralPath $SourcePath -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable enumErr |
        Where-Object { -not (Test-IsVolumeRootPseudoPath -Root $SourcePath -FullPath $_.FullName) }
    foreach ($e in @($enumErr)) {
        $path = "$($e.TargetObject)"
        if ($path -and (Test-IsVolumeRootPseudoPath -Root $SourcePath -FullPath $path)) { continue }
        $unreadable.Add([pscustomobject]@{ Path = $path; Message = $e.Exception.Message })
    }
    foreach ($f in $walked) {
        $rel = $f.FullName.Substring($SourcePath.Length).TrimStart('\', '/')
        if ($ExcludeOldSourceRecord -and $rel.IndexOfAny([char[]]@([char]92, [char]47)) -lt 0 -and $oldRecord -contains $rel) { continue }
        $reason = Test-PortableRelativePath -RelativePath $rel
        if ($reason) {
            $unportable.Add([pscustomobject]@{ RelativePath = $rel; Reason = $reason })
            continue
        }
        $files.Add([pscustomobject]@{ RelativePath = $rel; File = $f })
        $filePaths.Add($rel)
    }
    # Checked over the portable files only: every SR-055 rule ignores letter
    # case, so the members of a case group are all portable or all not.
    $collisions = Get-CaseOnlyCollision -RelativePath $filePaths.ToArray()
    if ($collisions.Count -gt 0) {
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $files) {
            if ($collisions.ContainsKey($item.RelativePath)) {
                $unportable.Add([pscustomobject]@{ RelativePath = $item.RelativePath; Reason = $collisions[$item.RelativePath] })
            } else {
                $kept.Add($item)
            }
        }
        $files = $kept
    }
    return [pscustomobject]@{ Files = $files; Unportable = $unportable; Unreadable = $unreadable }
}

function Copy-FileWithHash {
    <#
    .SYNOPSIS
        Copies a file once while hashing the bytes it writes, and returns the
        hash and length of exactly those bytes.

    .DESCRIPTION
        The stored object is named after the hash of the bytes that were
        written, never after an earlier read, so an object's name always
        matches its bytes even if the source changed in between (plan §4).
        The source is opened sharing reads only: a file another program holds
        open for writing fails to open, which the caller treats as locked.

    .PARAMETER SourcePath
        The file to read.

    .PARAMETER DestinationPath
        The new file to write (must not exist).

    .OUTPUTS
        [pscustomobject] Hash (32 uppercase hex digits), Length.
    #>
    # Implements: SR-002, SR-059, LLR-002
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    if (-not ('System.IO.Hashing.XxHash128' -as [type])) { Initialize-XxHashLibrary | Out-Null }
    $hasher = [System.IO.Hashing.XxHash128]::new()
    $buffer = [byte[]]::new(1MB)
    [long]$total = 0
    $in = [System.IO.FileStream]::new($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                                      [System.IO.FileShare]::Read, 1MB, [System.IO.FileOptions]::SequentialScan)
    try {
        $out = [System.IO.FileStream]::new($DestinationPath, [System.IO.FileMode]::CreateNew,
                                           [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 1MB)
        try {
            while (($n = $in.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($n -eq $buffer.Length) {
                    $hasher.Append($buffer)
                } else {
                    $tail = [byte[]]::new($n)
                    [System.Array]::Copy($buffer, $tail, $n)
                    $hasher.Append($tail)
                }
                $out.Write($buffer, 0, $n)
                $total += $n
            }
        } finally {
            $out.Dispose()
        }
    } finally {
        $in.Dispose()
    }
    $hash = ([System.BitConverter]::ToString($hasher.GetCurrentHash()) -replace '-', '').ToUpperInvariant()
    return [pscustomobject]@{ Hash = $hash; Length = $total }
}

function Test-BackupDiskFull {
    <#
    .SYNOPSIS
        True when an error record is the destination running out of space,
        which stops the set (plan C3) instead of costing one file.

    .PARAMETER ErrorRecord
        The caught error.

    .OUTPUTS
        [bool]
    #>
    # Implements: SR-052, LLR-052
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $e = $ErrorRecord.Exception
    while ($null -ne $e) {
        if ($e -is [System.IO.IOException]) {
            $hr = $e.HResult
            if ($hr -eq [int]0x80070070 -or $hr -eq [int]0x80070027 -or ((-not $IsWindows) -and $hr -eq 28)) { return $true }
        }
        $e = $e.InnerException
    }
    return $false
}

function Publish-StagedObject {
    <#
    .SYNOPSIS
        Turns a staged copy whose content key is new into a stored object in
        the backup root: decides its form, compresses it if so decided, and
        renames it to its content name.

    .DESCRIPTION
        The form is decided once, from the staged copy, exactly as before
        (SR-081): the set's switch, the extension list on the file's own name,
        and a sampled probe of the bytes. Compression reads the staged copy,
        never the source, so the archive holds the bytes that were hashed. The
        rename never overwrites: an object already at that name holds the same
        content (SR-059), and the staged copy is simply dropped - unless that
        object's listing shows it damaged (Get-ListedObjectDamage), which only
        happens when the run could not set it aside: then nothing is stored
        and this throws, so the file is retried and then warned about (R12)
        rather than recorded against damaged bytes (review 2026-10-26 G1).

        A new object is flushed to the disk before the rename that names it
        (review 2026-10-26 O1), so a power loss cannot leave its name over
        bytes that never arrived.

    .PARAMETER StagedPath
        The staged copy, on the backup volume.

    .PARAMETER SourceName
        The source file's name, whose extension the object keeps and whose
        name the extension list judges.

    .PARAMETER Hash
        The staged bytes' hash.

    .PARAMETER Length
        The staged bytes' length.

    .PARAMETER BackupRoot
        The backup root.

    .PARAMETER Set
        The backup set (CompressEnabled, CompressProbe).

    .PARAMETER SevenZipPath
        7-Zip, when compression may be used.

    .PARAMETER ProbeStats
        The set's SR-081 counters.

    .PARAMETER Metrics
        The run's metrics (New-RunMetric), or $null.

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [pscustomobject] Name, Compressed ('Yes' | 'No').
    #>
    # Implements: SR-003, SR-004, SR-058, SR-081, LLR-003, LLR-058, LLR-086
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StagedPath,
        [Parameter(Mandatory)][string]$SourceName,
        [Parameter(Mandatory)][string]$Hash,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][pscustomobject]$Set,
        [AllowNull()][string]$SevenZipPath,
        [Parameter(Mandatory)][hashtable]$ProbeStats,
        [AllowNull()][hashtable]$Metrics,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $mode = if ([string]::IsNullOrWhiteSpace([string]$Set.CompressProbe)) { 'always' } else { [string]$Set.CompressProbe }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $listSays = Test-ShouldCompress -FileName $SourceName -CompressEnabled $true
    $decision = Resolve-GroupStorageForm -CompressEnabled ([bool]$Set.CompressEnabled -and [bool]$SevenZipPath) -Mode $mode `
                    -ListSaysCompress $listSays -Length $Length -Candidate @($StagedPath)
    $ProbeStats.ReadBytes += [long]$decision.SampledBytes
    if ($null -ne $Metrics -and [long]$decision.SampledBytes -gt 0) { Add-RunMetric -Metrics $Metrics -Name 'compressibility probe' -Bytes ([long]$decision.SampledBytes) -Ticks $watch.ElapsedTicks }
    $compress = [bool]$decision.Compress
    $ext  = if ($compress) { '.7z' } else { [System.IO.Path]::GetExtension($SourceName) }
    $name = Get-HashSizeFileName -HashHex $Hash -Length $Length -Extension $ext
    $dest = Join-Path $BackupRoot $name
    $from = $StagedPath
    if ($compress) {
        $from = "$StagedPath.7z"
        $watch.Restart()
        Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $StagedPath -Destination7z $from
        $archiveLength = ([System.IO.FileInfo]::new($from)).Length
        if ($null -ne $Metrics) {
            Add-RunMetric -Metrics $Metrics -Name 'compress' -Bytes $Length -Ticks $watch.ElapsedTicks
            $Metrics.CompressedOut += $archiveLength
        }
        if ($archiveLength -eq $Length) {
            # An archive exactly as long as its content saves nothing, and its
            # listing could not tell it from the user's own '.7z' stored raw
            # (Get-StoredObjectCompressedFlag): store the content raw instead.
            Remove-Item -LiteralPath $from -Force
            $from = $StagedPath
            $compress = $false
            $ext  = [System.IO.Path]::GetExtension($SourceName)
            $name = Get-HashSizeFileName -HashHex $Hash -Length $Length -Extension $ext
            $dest = Join-Path $BackupRoot $name
            & $Log "The archive of '$SourceName' came out exactly as long as its content; stored raw as '$name'." 'DEBUG'
        } else {
            Remove-Item -LiteralPath $StagedPath -Force
        }
    }
    $existing = [System.IO.FileInfo]::new($dest)
    if ($existing.Exists) {
        # Same name, same content (SR-059) - unless it is a damaged object the
        # run could not set aside (Move-DamagedStoreObject): dropping this good
        # copy would then leave the row naming bytes that are not its content.
        $damage = Get-ListedObjectDamage -Path $dest -FileLength $existing.Length -ContentLength $Length -Extension $ext
        Remove-Item -LiteralPath $from -Force
        if ($null -ne $damage) {
            throw "The stored object '$name' is damaged ($damage) and could not be set aside, so this content cannot be stored under its name this run."
        }
    } else {
        # On the disk before the rename that names it (review 2026-10-26 O1):
        # that rename can reach the disk first, and a power loss then leaves
        # an object empty (ext4) or reading as NULs (NTFS) under its content
        # name - damage no later run can repair once the source has changed.
        # This one point covers every new object: the Incoming copy, a copy
        # brought over from the local temp tier, and the 7-Zip archive.
        # Measured per object: NVMe +1.4 ms, HomeHub's USB NTFS drive
        # (ntfs-3g) +1.9 ms, a laptop SATA HDD +49 ms.
        Sync-FileToDisk -LiteralPath $from
        [System.IO.File]::Move($from, $dest)
    }
    if ($decision.Reason -ceq 'ProbeIncompressible') {
        $ProbeStats.RawObjects++
        $ProbeStats.RawBytes += $Length
    } elseif ($decision.Reason -ceq 'ProbeCompressible') {
        $ProbeStats.CompressedObjects++
    }
    if ($decision.Reason -ceq 'ProbeUnavailable') {
        & $Log "Could not sample '$SourceName' for the compressibility probe; storing by the extension list's answer." 'WARN'
    }
    $ratio = if ($null -ne $decision.Ratio) { [string][math]::Round($decision.Ratio, 3) } else { 'n/a' }
    $windows = if ($null -ne $decision.Windows -and @($decision.Windows).Count -gt 0) {
        (@($decision.Windows) | ForEach-Object { [string][math]::Round($_, 3) }) -join ','
    } else { 'n/a' }
    # One line per PHYSICAL write (SR-060): under content addressing a second
    # write of the same content lands on the same name with the same bytes, so
    # only this line can show that each content was written once.
    & $Log "Stored object '$name' for hash=$Hash len=$Length from '$SourceName'." 'DEBUG'
    # One decision line per stored object (SR-081): why it took its form.
    & $Log "compress-decision: $SourceName $($decision.Reason) ratio=$ratio windows=$windows -> '$name'" 'DEBUG'
    return [pscustomobject]@{ Name = $name; Compressed = if ($compress) { 'Yes' } else { 'No' } }
}

function Invoke-SourceFileCapture {
    <#
    .SYNOPSIS
        Captures one source file into the latest state and returns its new
        manifest row, or says why it could not.

    .DESCRIPTION
        The library loop's body (plan step 4, §4):

          * size and time match the prior row and no re-read is due: the row
            is kept, and its object is brought back into the backup root if it
            sits only in a snapshot. Content missing everywhere is captured
            again (SR-053, SR-108).
          * otherwise the file is hashed, where the copy goes depending on how
            likely its content is new (§4's table), and its object is reused,
            brought back from a snapshot, or stored.

        Size and time are compared before and after every read: a difference
        means the file was being written, and it is retried later like a
        locked one (R12). A file that vanished during the run is Gone and gets
        no row. Running out of space on the backup volume rethrows, which
        stops the set (C3).

    .PARAMETER Item
        A Get-SourceFileList file entry (RelativePath, File).

    .PARAMETER PriorRow
        The prior manifest row for this path, or $null.

    .PARAMETER Context
        The run context New-BackupRunContext builds (roots, set, index, flags).

    .OUTPUTS
        [pscustomobject] Status ('Kept' | 'Captured' | 'Failed' | 'Gone'), Row
        (the new manifest row for Kept/Captured), Message.
    #>
    # Implements: SR-001, SR-003, SR-011, SR-053, SR-059, SR-067, SR-091, SR-105, SR-108
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [AllowNull()][object]$PriorRow,
        [Parameter(Mandatory)][pscustomobject]$Context
    )
    $rel  = $Item.RelativePath
    $full = $Item.File.FullName
    $staged = $null
    try {
        $before = [System.IO.FileInfo]::new($full)
        if (-not $before.Exists) { return [pscustomobject]@{ Status = 'Gone'; Row = $null; Message = 'it no longer exists' } }
        $len   = $before.Length
        $mtime = $before.LastWriteTime
        $unchangedLooking = ($null -ne $PriorRow) -and ([long]$PriorRow.Length -eq $len) -and ($PriorRow.LastWriteTime -eq $mtime) -and
                            -not [string]::IsNullOrWhiteSpace([string]$PriorRow.xxH2Hash)
        $priorPrefix = $null
        if ($unchangedLooking) {
            $parsed = if ([string]::IsNullOrWhiteSpace([string]$PriorRow.DataPath)) { $null } else { ConvertFrom-StoredObjectName -Name ([string]$PriorRow.DataPath) }
            $priorPrefix = if ($parsed) { $parsed.Prefix } else { Get-StoredObjectPrefix -HashHex $PriorRow.xxH2Hash -Length $len }
        }
        $likelyNew = $true
        if ($unchangedLooking -and -not $Context.Recalc) {
            $entry = Get-LatestObject -Prefix $priorPrefix -Context $Context
            if ($null -ne $entry) {
                $Context.Metrics.Kept++
                return [pscustomobject]@{ Status = 'Kept'; Message = $null
                    Row = New-CapturedRow -Entry $entry -RelativePath $rel -Length $len -LastWriteTime $mtime `
                              -Hash ([string]$PriorRow.xxH2Hash) -MediaMBPerSec ([string]$PriorRow.MediaMBPerSec) -PriorRow $PriorRow }
            }
            & $Context.Log "Content of '$rel' is missing from the backup; storing it again (SR-053)." 'WARN'
        } elseif ($unchangedLooking) {
            $likelyNew = $false    # a scheduled re-read: almost always unchanged
        } elseif ($null -eq $PriorRow -and $Context.Index.Lengths.Contains($len)) {
            $likelyNew = $false    # a new path whose length is stored: a rename, move or copy
        }

        $hash = $null
        $copyLength = $null
        # The read is named by why it happened, so the summary shows which kind
        # of read a slow run spends its time on.
        $why = if ($unchangedLooking) { 'scheduled re-read' } elseif ($likelyNew) { 'new or changed' } else { 'likely already stored' }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        if ($likelyNew) {
            $staged = Join-Path $Context.Incoming ([guid]::NewGuid().ToString('N'))
            $copied = Copy-FileWithHash -SourcePath $full -DestinationPath $staged
            $hash = $copied.Hash; $copyLength = $copied.Length
            Add-RunMetric -Metrics $Context.Metrics -Name "copy while hashing ($why)" -Bytes $len -Ticks $watch.ElapsedTicks
        } elseif ($null -ne $Context.LocalTemp -and $len -le $Context.LocalTempMax) {
            $staged = Join-Path $Context.LocalTemp ([guid]::NewGuid().ToString('N'))
            $copied = Copy-FileWithHash -SourcePath $full -DestinationPath $staged
            $hash = $copied.Hash; $copyLength = $copied.Length
            Add-RunMetric -Metrics $Context.Metrics -Name "copy to local temp ($why)" -Bytes $len -Ticks $watch.ElapsedTicks
        } else {
            $hash = Get-FileXxHash -FilePath $full
            $copyLength = $len
            Add-RunMetric -Metrics $Context.Metrics -Name "hash in place ($why)" -Bytes $len -Ticks $watch.ElapsedTicks
        }
        $Context.Metrics.BytesRead += $len
        $after = [System.IO.FileInfo]::new($full)
        if (-not $after.Exists) {
            if ($staged) { Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue }
            return [pscustomobject]@{ Status = 'Gone'; Row = $null; Message = 'it was deleted while being read' }
        }
        if ($after.Length -ne $len -or $after.LastWriteTime -ne $mtime -or $copyLength -ne $len) {
            if ($staged) { Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue }
            return [pscustomobject]@{ Status = 'Failed'; Row = $null; Message = 'it changed while it was being read' }
        }
        if ($unchangedLooking -and $hash -ne [string]$PriorRow.xxH2Hash) {
            & $Context.Log ("'$rel' has new content although its size and modification time did not change; " +
                            'the new content is stored and the old content stays in the snapshot (SR-105).') 'WARN'
        }
        $prefix = if ($unchangedLooking -and $hash -eq [string]$PriorRow.xxH2Hash) { $priorPrefix } else { Get-StoredObjectPrefix -HashHex $hash -Length $len }
        $media = if ($null -ne $PriorRow -and $hash -eq [string]$PriorRow.xxH2Hash) { [string]$PriorRow.MediaMBPerSec } else {
            $watch.Restart()
            [string](Get-MediaMBPerSec -FilePath $full -FfprobePath $Context.Ffprobe)
            if ($Context.Ffprobe) { Add-RunMetric -Metrics $Context.Metrics -Name 'media probe' -Ticks $watch.ElapsedTicks }
        }

        $entry = Get-LatestObject -Prefix $prefix -Context $Context
        if ($null -ne $entry) {
            if ($staged) { Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue; $staged = $null }
            return [pscustomobject]@{ Status = 'Captured'; Message = $null
                Row = New-CapturedRow -Entry $entry -RelativePath $rel -Length $len -LastWriteTime $mtime -Hash $hash -MediaMBPerSec $media -PriorRow $PriorRow }
        }

        # New content. Stage it on the backup volume if it is not there yet.
        if ($null -eq $staged) {
            # Hashed in place: read again while copying, and keep what was copied.
            $staged = Join-Path $Context.Incoming ([guid]::NewGuid().ToString('N'))
            $watch.Restart()
            $copied = Copy-FileWithHash -SourcePath $full -DestinationPath $staged
            Add-RunMetric -Metrics $Context.Metrics -Name 'second read to store new content' -Bytes $len -Ticks $watch.ElapsedTicks
            $Context.Metrics.BytesRead += $len
            $recheck = [System.IO.FileInfo]::new($full)
            if ($copied.Hash -ne $hash -or $copied.Length -ne $len -or -not $recheck.Exists -or
                $recheck.Length -ne $len -or $recheck.LastWriteTime -ne $mtime) {
                Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
                return [pscustomobject]@{ Status = 'Failed'; Row = $null; Message = 'it changed while it was being read' }
            }
        } elseif (-not $staged.StartsWith($Context.Incoming, [System.StringComparison]::Ordinal)) {
            # Staged in the host or container temp: bring it onto the backup volume.
            $onVolume = Join-Path $Context.Incoming ([guid]::NewGuid().ToString('N'))
            $watch.Restart()
            [System.IO.File]::Move($staged, $onVolume)
            Add-RunMetric -Metrics $Context.Metrics -Name 'local temp to backup volume' -Bytes $len -Ticks $watch.ElapsedTicks
            $staged = $onVolume
        }
        $stored = Publish-StagedObject -StagedPath $staged -SourceName $Item.File.Name -Hash $hash -Length $len `
                      -BackupRoot $Context.BackupRoot -Set $Context.Set -SevenZipPath $Context.SevenZip `
                      -ProbeStats $Context.ProbeStats -Metrics $Context.Metrics -Log $Context.Log
        $staged = $null
        $storedPath = Join-Path $Context.BackupRoot $stored.Name
        $newEntry = [pscustomobject]@{
            Name = $stored.Name; Prefix = $prefix; Path = $storedPath; Folder = ''
            FileLength = ([System.IO.FileInfo]::new($storedPath)).Length; ContentLength = $len
            Extension = [System.IO.Path]::GetExtension($stored.Name)
        }
        $Context.Index.Objects[$prefix] = $newEntry
        [void]$Context.Index.Lengths.Add($len)
        $Context.Stats.Stored++
        return [pscustomobject]@{ Status = 'Captured'; Message = $null
            Row = New-CapturedRow -Entry $newEntry -RelativePath $rel -Length $len -LastWriteTime $mtime -Hash $hash -MediaMBPerSec $media -PriorRow $PriorRow }
    } catch {
        if ($staged) { Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue }
        if (Test-BackupDiskFull -ErrorRecord $_) { throw }
        # .NET exceptions reach here wrapped in MethodInvocationException.
        $inner = $_.Exception
        while ($inner -is [System.Management.Automation.MethodInvocationException] -and $null -ne $inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.IO.FileNotFoundException] -or $inner -is [System.IO.DirectoryNotFoundException]) {
            return [pscustomobject]@{ Status = 'Gone'; Row = $null; Message = 'it no longer exists' }
        }
        return [pscustomobject]@{ Status = 'Failed'; Row = $null; Message = $inner.Message }
    }
}

function Get-LatestObject {
    <#
    .SYNOPSIS
        Finds the stored object for a content key and makes sure it is in the
        backup root, moving it back by rename when it sits only in a snapshot.

    .DESCRIPTION
        Re-added content comes back from the snapshot that holds it instead of
        being copied again (plan step 4), so no duplicate is created. The
        snapshot's manifest is not touched (R6): the kit finds a moved object
        by name. When the move fails the object stays where it is and the
        caller's row still restores through that name; a warning says so.

        An object in a folder whose restore kit is older than revision 4 is
        used where it is, never moved: such a kit finds a row's object only in
        the folder its DataPath names, so the move would break that snapshot.
        The latest state's kit finds it there by name.

    .PARAMETER Prefix
        The content-key prefix.

    .PARAMETER Context
        The run context.

    .OUTPUTS
        The index entry (now in the backup root), or $null when nothing holds
        that content.
    #>
    # Implements: SR-003, SR-053, SR-108
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][pscustomobject]$Context
    )
    $entry = $null
    if (-not $Context.Index.Objects.TryGetValue($Prefix, [ref]$entry)) { return $null }
    if ($entry.Folder -eq '') { return $entry }
    $holder = [System.IO.Path]::GetDirectoryName($entry.Path)
    if (-not $Context.KitRevisionOf.ContainsKey($holder)) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $Context.KitRevisionOf[$holder] = Get-BackupKitRevision -Folder $holder
        Add-RunMetric -Metrics $Context.Metrics -Name 'kit revision read' -Ticks $watch.ElapsedTicks
    }
    if ($Context.KitRevisionOf[$holder] -lt 4) { return $entry }
    $dest = Join-Path $Context.BackupRoot $entry.Name
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        [System.IO.File]::Move($entry.Path, $dest)
        Add-RunMetric -Metrics $Context.Metrics -Name 'move back from snapshot' -Ticks $watch.ElapsedTicks
        & $Context.Log "Moved '$($entry.Name)' back from '$($entry.Folder)' into the latest state." 'DEBUG'
        $entry.Path   = $dest
        $entry.Folder = ''
        $Context.Stats.MovedBack++
    } catch {
        & $Context.Log "Could not move '$($entry.Path)' back into the latest state: $($_.Exception.Message). It is restored from where it is." 'WARN'
    }
    return $entry
}

function New-CapturedRow {
    <#
    .SYNOPSIS
        Builds one latest-state manifest row naming a stored object, every
        text column a string so an unchanged run rewrites identical bytes.

    .PARAMETER Entry
        The object's index entry.

    .PARAMETER RelativePath
        The source path.

    .PARAMETER Length
        The content length.

    .PARAMETER LastWriteTime
        The source file's modification time, taken before it was read.

    .PARAMETER Hash
        The content hash.

    .PARAMETER MediaMBPerSec
        The media measure, or ''.

    .PARAMETER PriorRow
        The prior row for this path, or $null; its Compressed value is kept for
        the one form the listing cannot decide (Get-StoredObjectCompressedFlag).

    .OUTPUTS
        [pscustomobject] a manifest row (Duplicate is set by the caller).
    #>
    # Implements: SR-025, SR-024
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][datetime]$LastWriteTime,
        [Parameter(Mandatory)][string]$Hash,
        [AllowNull()][AllowEmptyString()][string]$MediaMBPerSec,
        [AllowNull()][object]$PriorRow
    )
    $priorCompressed = if ($null -ne $PriorRow -and [string]$PriorRow.DataPath -eq [string]$Entry.Name) { [string]$PriorRow.Compressed } else { $null }
    [pscustomobject]@{
        DataPath         = [string]$Entry.Name
        RelativePath     = $RelativePath
        Length           = [string]$Length
        LastWriteTime    = $LastWriteTime
        xxH2Hash         = $Hash
        Compressed       = Get-StoredObjectCompressedFlag -Entry $Entry -PriorCompressed $priorCompressed
        StoredAsHashSize = 'Hash'
        Duplicate        = '0'
        MediaMBPerSec    = [string]$MediaMBPerSec
    }
}

function ConvertTo-FrozenRow {
    <#
    .SYNOPSIS
        Carries a prior row unchanged into the latest state for a file the run
        could not read, so it is never recorded as removed (SR-091).

    .DESCRIPTION
        The row keeps its content; its object is brought back into the backup
        root if it sits only in a snapshot, and its DataPath names it.

    .PARAMETER PriorRow
        The prior manifest row.

    .PARAMETER Context
        The run context.

    .OUTPUTS
        [pscustomobject] a manifest row.
    #>
    # Implements: SR-091, SR-059
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$PriorRow,
        [Parameter(Mandatory)][pscustomobject]$Context
    )
    $dataPath = [string]$PriorRow.DataPath
    $parsed = if ([string]::IsNullOrWhiteSpace($dataPath)) { $null } else { ConvertFrom-StoredObjectName -Name $dataPath }
    $prefix = if ($parsed) { $parsed.Prefix } elseif ($PriorRow.xxH2Hash) { Get-StoredObjectPrefix -HashHex $PriorRow.xxH2Hash -Length ([long]$PriorRow.Length) } else { $null }
    $entry = if ($prefix) { Get-LatestObject -Prefix $prefix -Context $Context } else { $null }
    [pscustomobject]@{
        DataPath         = if ($entry) { [string]$entry.Name } else { $dataPath }
        RelativePath     = [string]$PriorRow.RelativePath
        Length           = [string]$PriorRow.Length
        LastWriteTime    = $PriorRow.LastWriteTime
        xxH2Hash         = [string]$PriorRow.xxH2Hash
        Compressed       = if ($entry) {
                               $same = if ([string]$PriorRow.DataPath -eq [string]$entry.Name) { [string]$PriorRow.Compressed } else { $null }
                               Get-StoredObjectCompressedFlag -Entry $entry -PriorCompressed $same
                           } else { [string]$PriorRow.Compressed }
        StoredAsHashSize = 'Hash'
        Duplicate        = '0'
        MediaMBPerSec    = [string]$PriorRow.MediaMBPerSec
    }
}

function Get-SortedManifestRow {
    <#
    .SYNOPSIS
        Returns the rows in ordinal RelativePath order with Duplicate set: '0'
        for the shortest path of each content (ordinal tie-break), '1' for the
        others - the canonical form an unchanged run rewrites byte for byte.

    .PARAMETER Rows
        The rows.

    .OUTPUTS
        [object[]]
    #>
    # Implements: SR-024, SR-025
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows)
    $keys = [string[]]::new($Rows.Count)
    for ($i = 0; $i -lt $Rows.Count; $i++) { $keys[$i] = [string]$Rows[$i].RelativePath }
    $sorted = [object[]]$Rows.Clone()
    # The casts pick the non-generic Sort(keys, items, comparer): bound as the
    # generic overload, PowerShell sorts a converted copy of the items, so
    # only the keys move.
    [System.Array]::Sort([System.Array]$keys, [System.Array]$sorted, [System.Collections.IComparer][System.StringComparer]::Ordinal)
    $owner = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $sorted) {
        $content = "$($row.xxH2Hash)|$($row.Length)"
        $current = $null
        if (-not $owner.TryGetValue($content, [ref]$current)) { $owner[$content] = $row; continue }
        if ($row.RelativePath.Length -lt $current.RelativePath.Length) { $owner[$content] = $row }
    }
    foreach ($row in $sorted) {
        $row.Duplicate = if ([object]::ReferenceEquals($owner["$($row.xxH2Hash)|$($row.Length)"], $row)) { '0' } else { '1' }
    }
    return , $sorted
}

function Publish-PriorStateSnapshot {
    <#
    .SYNOPSIS
        Publishes the prior state as Snapshot_<D> before the run changes
        anything (plan step 3), unless a snapshot of that name already exists.

    .DESCRIPTION
        The prior manifest is copied as it is - every DataPath still naming the
        object as it is called in the backup root - together with the prior
        directory record and the current restore kit, into Building_<D>; each
        file is flushed to the disk, and one rename then makes it
        Snapshot_<D>. It restores from the moment it
        appears, because every object it needs is still in the backup root or
        an older snapshot, and a row whose object is not in the snapshot's own
        folder is found by name (§7). The DataPaths are kept so that an object
        Move-SupersededObject later moves into this folder - under the same
        name - is named by this folder's own rows, which is what the retention
        mechanism and the storage audit index the pool by. It comes before the
        first progress checkpoint so that no checkpoint can overwrite the prior
        state's only record.

        A snapshot named for D that already exists holds the state completed at
        D - an interrupted run published it - and is kept as it is; the
        checkpointed manifest beside it is only a mix (R13).

    .PARAMETER BackupRoot
        The backup root.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER PriorDate
        The prior state's completion date (LastBackupRun).

    .PARAMETER PriorRows
        The prior manifest's rows.

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [pscustomobject] Path, BuiltNow ([bool]).
    #>
    # Implements: SR-005, SR-007, SR-010, SR-082, LLR-005, LLR-150
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][datetime]$PriorDate,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PriorRows,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $label = $PriorDate.ToString($script:Def.FileLabelDateFormat)
    $name  = "$($script:Def.SnapshotPrefix)$label"
    $final = Join-Path $ChangeRoot $name
    if (Test-Path -LiteralPath $final -PathType Container) {
        & $Log "Snapshot '$name' already exists (published by an interrupted run); keeping it." 'INFO'
        return [pscustomobject]@{ Path = $final; BuiltNow = $false }
    }
    $building = Join-Path $ChangeRoot "$($script:BuildingFolderPrefix)$label"
    [void][System.IO.Directory]::CreateDirectory($building)
    # Write-Manifest flushes the manifest before its own rename. Every other
    # file is flushed here, before the one rename that publishes the folder:
    # that rename can reach the disk before the data, and a power loss would
    # then leave a snapshot whose kit or directory record is empty or NULs
    # (review 2026-10-26 A1).
    Write-Manifest -FolderPath $building -Records $PriorRows
    $copies = [System.Collections.Generic.List[string]]::new()
    foreach ($artifact in @($script:Def.DirectorySidecarName, $script:Def.ReconstructPs1Name, $script:Def.ReconstructCmdName,
                            $script:Def.ReconstructCommandName, $script:Def.ReconstructShName, $script:Def.CommonModuleName,
                            'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')) {
        $src = Join-Path $BackupRoot $artifact
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination $building -Force
            $copies.Add((Join-Path $building $artifact))
        }
    }
    foreach ($copy in $copies) { Sync-FileToDisk -LiteralPath $copy }
    Invoke-BackupRunTestHook -Stage 'BeforeSnapshotPublish' -Context $building
    [System.IO.Directory]::Move($building, $final)
    & $Log "Prior state published as snapshot '$name'." 'INFO'
    return [pscustomobject]@{ Path = $final; BuiltNow = $true }
}

function Remove-UnchangedSnapshot {
    <#
    .SYNOPSIS
        Removes the snapshot a run built when the run changed no row (plan
        step 7, SR-100), without ever leaving a half-deleted Snapshot_* folder.

    .DESCRIPTION
        The folder is first renamed back to Building_<D> - one rename, so it is
        either a whole snapshot or not a snapshot at all - and only then
        deleted. A rename that fails (a scanner holding a file just written)
        keeps the snapshot: it holds the same state as the latest, so it is
        redundant, not wrong. A delete that fails leaves Building_<D>, which
        the next run's residue clean-up removes. Either is a warning; the run
        has finished.

    .PARAMETER SnapshotPath
        The snapshot this run built.

    .PARAMETER ChangeRoot
        The change root.

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [bool] true when the snapshot is gone.
    #>
    # Implements: SR-100, LLR-150
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $label = ([System.IO.Path]::GetFileName($SnapshotPath)).Substring($script:Def.SnapshotPrefix.Length)
    $building = Join-Path $ChangeRoot "$($script:BuildingFolderPrefix)$label"
    try {
        [System.IO.Directory]::Move($SnapshotPath, $building)
    } catch {
        & $Log "No file changed, but the unneeded snapshot '$SnapshotPath' could not be set aside ($($_.Exception.Message)); it is kept, holding the same state as the latest." 'WARN'
        return $false
    }
    try {
        Remove-Item -LiteralPath $building -Recurse -Force -ErrorAction Stop
    } catch {
        & $Log "Could not delete '$building' ($($_.Exception.Message)); the next run removes it." 'WARN'
    }
    & $Log 'No file changed; no snapshot kept (the latest state is unchanged).'
    return $true
}

function Move-SupersededObject {
    <#
    .SYNOPSIS
        Moves every object in the backup root that no row of the final manifest
        uses into the snapshot whose own manifest names it (plan step 8).

    .DESCRIPTION
        The question is asked of the FINAL manifest (SR-059): rows kept for
        files the run could not read still claim their objects, so those stay.
        Normally an unused object was used by the prior state, so it goes to
        this run's snapshot of that state. One left in the backup root by an
        interrupted run, or by a move that failed, is named only by an older
        snapshot: it goes there, so every object lives where a row of its own
        folder names it - what retention and the storage audit index the pool
        by (C10, C12). Older manifests are read only when such an object exists
        and this run keeps a snapshot; one no snapshot names goes to this run's
        snapshot. With no snapshot this run, unused objects stay and a warning
        counts them.

        A move is a rename on one volume (R8), so an object is in exactly one
        place before and after; one that fails to move stays in the backup root
        and still restores. Nothing is deleted (R9).

    .PARAMETER Index
        The run's object index.

    .PARAMETER FinalRows
        The final manifest rows.

    .PARAMETER SnapshotPath
        The run's snapshot folder, or $null.

    .PARAMETER SnapshotRows
        The rows of that snapshot's manifest when they are already in memory
        (a snapshot this run built holds the prior rows), else empty.

    .PARAMETER ChangeRoot
        The change root, for the older snapshots.

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [int] the number of objects moved.
    #>
    # Implements: SR-005, SR-041, SR-059, LLR-059, LLR-150
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Index,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FinalRows,
        [AllowNull()][string]$SnapshotPath,
        [AllowNull()][AllowEmptyCollection()][object[]]$SnapshotRows,
        [Parameter(Mandatory)][string]$ChangeRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in $FinalRows) { if ($row.DataPath) { [void]$used.Add([string]$row.DataPath) } }
    $unused = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Index.Objects.Values) {
        if ($entry.Folder -eq '' -and -not $used.Contains($entry.Name)) { $unused.Add($entry) }
    }
    if ($unused.Count -eq 0) { return 0 }
    if ([string]::IsNullOrWhiteSpace($SnapshotPath)) {
        & $Log "$($unused.Count) stored object(s) in the latest state are used by no row and there is no snapshot this run to move them to; they stay where they are." 'WARN'
        return 0
    }

    # Where each one goes: the newest snapshot whose own manifest names it.
    $destination = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $named = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($row in @($SnapshotRows)) { if ($row -and $row.DataPath) { [void]$named.Add([string]$row.DataPath) } }
    $left = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $unused) {
        if ($named.Contains($entry.Name)) { $destination[$entry.Name] = $SnapshotPath } else { $left.Add($entry) }
    }
    if ($left.Count -gt 0) {
        $placed = 0
        $folders = @(Get-PoolSnapshotFolder -ChangeRoot $ChangeRoot | ForEach-Object FullName)
        [array]::Reverse($folders)
        foreach ($folder in $folders) {
            if ($left.Count -eq 0) { break }
            if ($folder -eq $SnapshotPath -and $named.Count -gt 0) { continue }
            $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            try {
                foreach ($row in @(Import-Csv -LiteralPath (Join-Path $folder $script:Def.DatabaseFilename))) { if ($row.DataPath) { [void]$names.Add([string]$row.DataPath) } }
            } catch { continue }
            $still = [System.Collections.Generic.List[object]]::new()
            foreach ($entry in $left) {
                if (-not $names.Contains($entry.Name)) { $still.Add($entry); continue }
                $destination[$entry.Name] = $folder
                if ($folder -ne $SnapshotPath) { $placed++ }
            }
            $left = $still
        }
        if ($placed -gt 0) {
            & $Log "$placed stored object(s) left in the latest state by an interrupted run go back to the snapshot that names them." 'WARN'
        }
        # No manifest names these: this run's snapshot holds them, as before.
        foreach ($entry in $left) { $destination[$entry.Name] = $SnapshotPath }
    }

    $moved = 0
    foreach ($entry in $unused) {
        Invoke-BackupRunTestHook -Stage 'BeforeSupersededMove' -Context $entry
        $target = $destination[$entry.Name]
        try {
            [System.IO.File]::Move($entry.Path, (Join-Path $target $entry.Name))
            $moved++
        } catch {
            & $Log "Could not move superseded '$($entry.Name)' into '$target': $($_.Exception.Message). It stays in the latest state and still restores." 'WARN'
        }
    }
    return $moved
}

function Invoke-BackupRunTestHook {
    <#
    .SYNOPSIS
        Calls the module's backup-run test seam, when one is set, with a stage
        name and a context object. Production never sets it.

    .PARAMETER Stage
        The stage name.

    .PARAMETER Context
        Whatever the stage passes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Stage, [AllowNull()][object]$Context)
    if ($null -ne $script:BackupRunTestHook) { & $script:BackupRunTestHook $Stage $Context }
}

function Get-PriorBackupDate {
    <#
    .SYNOPSIS
        The prior state's completion date: LastBackupRun, or - when the state
        file is missing or unreadable beside a non-empty manifest - the
        manifest file's own modification time, with a warning (R1).

    .PARAMETER BackupRoot
        The backup root.

    .PARAMETER PriorRowCount
        Rows in the latest manifest.

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [Nullable[datetime]] $null on a first backup.
    #>
    # Implements: SR-005, SR-035, LLR-005, LLR-035
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][int]$PriorRowCount,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $date = $null
    try { $date = Get-LastBackupRun -BackupRoot $BackupRoot } catch {
        # Set aside, so this run can write a fresh one at its end.
        $state = Join-Path $BackupRoot 'FileBackupState.json'
        $aside = "$state.unreadable-$((Get-Date).ToString('yyyyMMddHHmmss'))"
        & $Log "The run-state file '$state' could not be read ($($_.Exception.Message)); it is kept as '$aside'." 'WARN'
        try { Move-Item -LiteralPath $state -Destination $aside -Force } catch { & $Log "Could not set it aside: $($_.Exception.Message)" 'WARN' }
    }
    if ($null -ne $date) { return $date }
    $manifest = Join-Path $BackupRoot $script:Def.DatabaseFilename
    if ($PriorRowCount -gt 0 -and (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        $date = (Get-Item -LiteralPath $manifest).LastWriteTime
        & $Log "No usable LastBackupRun beside a manifest of $PriorRowCount row(s); dating the prior state by the manifest file's time, $($date.ToString('O'))." 'WARN'
        return $date
    }
    return $null
}

# endregion

# region Per-set orchestrator

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

function New-RunMetric {
    <#
    .SYNOPSIS
        A zeroed set of run metrics: step timings, per-operation counts, bytes
        and time, and the slowest files - what Write-RunMetric reports, so a
        check that slows a run can be found and iterated on.

    .DESCRIPTION
        Steps are marked in order with Complete-RunStep; operations are added
        with Add-RunMetric. Kept counts the files skipped without a read, the
        bulk of a nightly run, as a bare counter so it costs nothing per file.

    .OUTPUTS
        [hashtable]
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        Watch     = [System.Diagnostics.Stopwatch]::StartNew()
        Last      = [TimeSpan]::Zero
        Steps     = [System.Collections.Generic.List[object]]::new()
        Ops       = [ordered]@{}
        Kept      = [long]0
        BytesRead = [long]0
        Slowest   = [System.Collections.Generic.List[object]]::new()
        # Only a file that took half a second or more is worth naming.
        SlowFloor = [long]([System.Diagnostics.Stopwatch]::Frequency / 2)
        CompressedOut = [long]0
    }
}

function Complete-RunStep {
    <#
    .SYNOPSIS
        Records the time since the previous step mark under a step name.

    .PARAMETER Metrics
        New-RunMetric's set.

    .PARAMETER Name
        The step that just finished.
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][string]$Name
    )
    $now = $Metrics.Watch.Elapsed
    $Metrics.Steps.Add([pscustomobject]@{ Name = $Name; Seconds = [math]::Round(($now - $Metrics.Last).TotalSeconds, 2) })
    $Metrics.Last = $now
}

function Add-RunMetric {
    <#
    .SYNOPSIS
        Adds one operation - its bytes and its stopwatch ticks - to a named
        counter of the run's metrics.

    .PARAMETER Metrics
        New-RunMetric's set.

    .PARAMETER Name
        The operation, as the summary names it.

    .PARAMETER Bytes
        Bytes the operation moved or read.

    .PARAMETER Ticks
        Its duration in Stopwatch ticks.
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][string]$Name,
        [long]$Bytes = 0,
        [long]$Ticks = 0
    )
    $op = $Metrics.Ops[$Name]
    if ($null -eq $op) { $op = [long[]]::new(3); $Metrics.Ops[$Name] = $op }
    $op[0]++
    $op[1] += $Bytes
    $op[2] += $Ticks
}

function Add-RunSlowFile {
    <#
    .SYNOPSIS
        Keeps the five slowest file captures of a run.

    .DESCRIPTION
        Callers test Ticks against Metrics.SlowFloor first, so a fast file costs
        no call at all.

    .PARAMETER Metrics
        New-RunMetric's set.

    .PARAMETER RelativePath
        The file.

    .PARAMETER Bytes
        Its length.

    .PARAMETER Ticks
        How long its capture took, in Stopwatch ticks.
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][string]$RelativePath,
        [long]$Bytes,
        [long]$Ticks
    )
    $Metrics.Slowest.Add([pscustomobject]@{ RelativePath = $RelativePath; Bytes = $Bytes; Ticks = $Ticks })
    if ($Metrics.Slowest.Count -gt 5) {
        $min = 0
        for ($i = 1; $i -lt $Metrics.Slowest.Count; $i++) { if ($Metrics.Slowest[$i].Ticks -lt $Metrics.Slowest[$min].Ticks) { $min = $i } }
        $Metrics.Slowest.RemoveAt($min)
    }
    if ($Metrics.Slowest.Count -ge 5) {
        $floor = [long]::MaxValue
        foreach ($s in $Metrics.Slowest) { if ($s.Ticks -lt $floor) { $floor = $s.Ticks } }
        $Metrics.SlowFloor = $floor
    }
}

function Format-RunByteCount {
    <#
    .SYNOPSIS
        A byte count as a short human figure (B, KB, MB, GB, TB).

    .PARAMETER Bytes
        The count.

    .OUTPUTS
        [string]
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    [OutputType([string])]
    param([long]$Bytes)
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $v = [double]$Bytes
    $u = 0
    while ($v -ge 1024 -and $u -lt $units.Count - 1) { $v /= 1024; $u++ }
    if ($u -eq 0) { return "$Bytes B" }
    return ('{0:N1} {1}' -f $v, $units[$u])
}

function Write-RunMetric {
    <#
    .SYNOPSIS
        Writes a run's metrics to its log: step timings, the work done per
        operation with its throughput, the slowest files, and one compact JSON
        line ('metrics {...}') to compare runs by.

    .PARAMETER Metrics
        New-RunMetric's set.

    .PARAMETER Extra
        Counters to add to the JSON line (files, objects stored, ...).

    .PARAMETER Label
        What the timings are of ('Timings' for a backup run).

    .PARAMETER Log
        The logger.
    #>
    # Implements: SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Metrics,
        [hashtable]$Extra = @{},
        [string]$Label = 'Timings',
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $total = [math]::Round($Metrics.Watch.Elapsed.TotalSeconds, 2)
    $steps = @($Metrics.Steps | ForEach-Object { '{0} {1:N1} s' -f $_.Name, $_.Seconds })
    & $Log ("${Label}: " + ($steps -join ', ') + "; total {0:N1} s." -f $total)

    $work = [System.Collections.Generic.List[string]]::new()
    if ($Metrics.Kept -gt 0) { $work.Add("unchanged, not read $($Metrics.Kept)") }
    $ops = [ordered]@{}
    foreach ($name in $Metrics.Ops.Keys) {
        $op = $Metrics.Ops[$name]
        $secs = [double]$op[2] / [System.Diagnostics.Stopwatch]::Frequency
        $line = "$name $($op[0])"
        if ($op[1] -gt 0) {
            $line += ", $(Format-RunByteCount $op[1])"
            if ($secs -gt 0.05 -and $op[1] -ge 1MB) { $line += (", {0:N0} MB/s" -f (($op[1] / 1MB) / $secs)) }
        }
        if ($name -eq 'compress' -and $Metrics.CompressedOut -gt 0) { $line += " -> $(Format-RunByteCount $Metrics.CompressedOut)" }
        $line += (", {0:N1} s" -f $secs)
        $work.Add($line)
        $ops[$name] = [ordered]@{ count = $op[0]; bytes = $op[1]; seconds = [math]::Round($secs, 2) }
    }
    if ($work.Count -gt 0) { & $Log ("Work: " + ($work -join '; ') + '.') }
    if ($Metrics.Slowest.Count -gt 0) {
        $slow = @($Metrics.Slowest | Sort-Object Ticks -Descending | ForEach-Object {
            "'{0}' ({1}, {2:N1} s)" -f $_.RelativePath, (Format-RunByteCount $_.Bytes), ([double]$_.Ticks / [System.Diagnostics.Stopwatch]::Frequency) })
        & $Log ("Slowest files: " + ($slow -join ', ') + '.')
    }
    $doc = [ordered]@{
        of           = $Label
        totalSeconds = $total
        steps        = [ordered]@{}
        kept         = $Metrics.Kept
        bytesRead    = $Metrics.BytesRead
        compressedOut = $Metrics.CompressedOut
        ops          = $ops
    }
    foreach ($s in $Metrics.Steps) { $doc.steps[$s.Name] = $s.Seconds }
    foreach ($k in $Extra.Keys) { $doc[$k] = $Extra[$k] }
    & $Log ('metrics ' + ($doc | ConvertTo-Json -Compress -Depth 5))
}

function Read-PriorStateForRun {
    <#
    .SYNOPSIS
        The refusals that need a person (plan step 2), then the latest
        manifest's rows; throws, naming the reason, when the set must be
        refused before anything changes (outcome 2).

    .DESCRIPTION
        Checks the CompressProbe vocabulary, that one rename crosses the
        backup and change roots (R8), that the latest manifest is a FileBackup
        manifest, and that the store is in the current form (SR-061).
        Import-Csv reads any text as rows, so a damaged manifest is caught by
        its header, as both restorers catch it. A 0-byte manifest is an empty
        backup an older build wrote.

    .PARAMETER Set
        The backup set.

    .PARAMETER Paths
        The set's resolved paths (Resolve-BackupSetPaths).

    .OUTPUTS
        [object[]] the latest manifest's rows.
    #>
    # Implements: SR-042, SR-061, SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][pscustomobject]$Paths
    )
    # The loader materializes CompressProbe in exact lowercase; a set built by
    # hand is held to the same vocabulary before anything is read (SR-042, R-10).
    $probeMode = [string]$Set.CompressProbe
    if (-not [string]::IsNullOrWhiteSpace($probeMode) -and $probeMode -cnotin @('off', 'excluded-extensions', 'always')) {
        throw "Backup set '$($Set.Name)' has invalid CompressProbe '$probeMode'. Expected 'off', 'excluded-extensions' or 'always' (exact lowercase)."
    }
    Assert-SingleStoreMount -BackupRoot $Paths.BkpPath -ChangeRoot $Paths.ChgPath
    $manifestPath = Join-Path $Paths.BkpPath $script:Def.DatabaseFilename
    if ((Test-Path -LiteralPath $manifestPath -PathType Leaf) -and (Get-Item -LiteralPath $manifestPath).Length -gt 0) {
        $header = ("$(Get-Content -LiteralPath $manifestPath -TotalCount 1)").TrimStart([char]0xFEFF)
        if ($header -notmatch 'RelativePath' -or $header -notmatch 'xxH2Hash') {
            throw "'$manifestPath' is not a FileBackup manifest (unexpected header). Move it aside to rebuild the latest state from the source; the snapshots are untouched."
        }
    }
    $rows = [object[]]@(Read-Manifest -FolderPath $Paths.BkpPath)
    Assert-CurrentStoreForm -BackupRoot $Paths.BkpPath -Rows $rows
    return , $rows
}

function New-BackupRunContext {
    <#
    .SYNOPSIS
        Builds what every capture of one run shares (plan step 4): the roots,
        the tools, the object index, whether unchanged files are re-read this
        run, and the two temp tiers.

    .DESCRIPTION
        The re-read decision follows HashRecalcFreq against LastHashRun (R11).
        The change root's Incoming folder is the on-volume temp tier; a
        per-run folder in the host or container temp is the local tier,
        capped at LocalTempMaxBytes or half its free space (plan section 4,
        C7). Without a local folder, files that are probably stored already
        are hashed in place.

    .PARAMETER Set
        The backup set.

    .PARAMETER Deps
        Resolved dependencies (7z, ffprobe).

    .PARAMETER Paths
        The set's resolved paths.

    .PARAMETER Index
        The object index (Get-StoreObjectIndex).

    .PARAMETER Metrics
        The run's metrics (New-RunMetric).

    .PARAMETER Log
        The set logger.

    .OUTPUTS
        [pscustomobject] the run context Invoke-SourceFileCapture reads.
    #>
    # Implements: SR-011, SR-081, LLR-014
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][hashtable]$Deps,
        [Parameter(Mandatory)][pscustomobject]$Paths,
        [Parameter(Mandatory)][pscustomobject]$Index,
        [Parameter(Mandatory)][hashtable]$Metrics,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $lastHashRun = $null
    try { $lastHashRun = Get-LastHashRun -BackupRoot $Paths.BkpPath } catch { & $Log "Could not read LastHashRun: $($_.Exception.Message)" 'WARN' }
    $recalc = if ($lastHashRun) { Test-HashRecalcDue -FreqCode $Set.HashRecalcFreq -LastHashRun $lastHashRun } else { Test-HashRecalcDue -FreqCode $Set.HashRecalcFreq }
    & $Log "HashRecalcFreq=$($Set.HashRecalcFreq), LastHashRun=$lastHashRun, Recalculate=$recalc"
    $incoming = Join-Path $Paths.ChgPath $script:IncomingFolderName
    [void][System.IO.Directory]::CreateDirectory($incoming)
    $localTemp = $null
    $localTempMax = 0
    try {
        $localTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("FileBackup-" + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($localTemp)
        $tempFree = Get-FreeSpaceBytes -Path $localTemp
        $localTempMax = if ($null -eq $tempFree) { $script:LocalTempMaxBytes } else { [math]::Min([long]$script:LocalTempMaxBytes, [long]($tempFree / 2)) }
    } catch {
        & $Log "No local temp folder ($($_.Exception.Message)); files that are probably stored already are hashed in place." 'DEBUG'
        $localTemp = $null
        $localTempMax = 0
    }
    return [pscustomobject]@{
        BackupRoot = $Paths.BkpPath; Incoming = $incoming; LocalTemp = $localTemp; LocalTempMax = [long]$localTempMax; Set = $Set
        SevenZip = $Deps['7z']; Ffprobe = $Deps['ffprobe']; Index = $Index; Recalc = [bool]$recalc
        ProbeStats = (New-ProbeStatistic); Log = $Log
        Stats = [pscustomobject]@{ Stored = 0; MovedBack = 0 }; KitRevisionOf = @{}; Metrics = $Metrics
    }
}

function Get-EmptySourceMessage {
    <#
    .SYNOPSIS
        The one message a run stops with when its source is empty while the
        latest state holds rows (review 2026-10-26 C2), whichever check finds it.

    .PARAMETER SourcePath
        The set's source root.

    .PARAMETER RowCount
        The rows the latest state holds.

    .OUTPUTS
        [string]
    #>
    # Implements: SR-036, LLR-036
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][int]$RowCount
    )
    return ("The source '$SourcePath' is empty while the latest state holds $RowCount file(s) - a missing mount or a failed drive looks like this; the latest state is left as it was. " +
            'If this source really is meant to be empty, remove the set from the configuration.')
}

function Assert-SourceNotEmpty {
    <#
    .SYNOPSIS
        Stops the run (throws, so the set returns 4) when the source root lists
        no entry at all while the latest state holds rows (review 2026-10-26 C2).

    .DESCRIPTION
        Runs before plan step 3, so the common case - an unmounted or failed
        source drive is an empty folder - stops before a snapshot of a state
        that did not change is published. The volume-root pseudo-folders are
        ignored exactly as the walk ignores them (SR-074), so a drive root that
        holds only them is empty here too. A root that cannot be listed passes:
        that is the walk's unlistable-root case (C24), which keeps every row.
        A source holding only empty folders passes as well; the walk's own
        check in Invoke-LibraryCapture stops that one.

    .PARAMETER SourcePath
        The set's source root.

    .PARAMETER PriorRowCount
        The rows the latest state holds; with none there is nothing to lose.
    #>
    # Implements: SR-036, LLR-036
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][int]$PriorRowCount
    )
    if ($PriorRowCount -eq 0) { return }
    try {
        # The .NET enumeration lists hidden and system entries, as the walk's -Force does.
        foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($SourcePath)) {
            if (-not (Test-IsVolumeRootPseudoPath -Root $SourcePath -FullPath $entry)) { return }
        }
    } catch {
        return
    }
    throw (Get-EmptySourceMessage -SourcePath $SourcePath -RowCount $PriorRowCount)
}

function Invoke-LibraryCapture {
    <#
    .SYNOPSIS
        Walks the source and captures every file into the latest state (plan
        steps 4-5), returning the final manifest rows.

    .DESCRIPTION
        The working rows start as the prior rows, so a progress checkpoint
        (R13) never drops a file the loop has not reached. A file that fails
        is retried in a pass after the loop, no sooner than the spacing after
        its last attempt and up to the attempt limit (R12); one that still
        fails keeps its prior row. Rows of files the walk cannot see - a name
        that is not portable, a folder that cannot be listed - stay as they
        were (SR-055, SR-057, SR-091); every other row the walk did not visit
        is a removal - unless the source root itself disappeared, or emptied,
        during the run, or was already empty when the walk began while the
        prior rows hold files, which throws so the set stops (4) before a
        latest state that lists nothing is written; a source root that cannot
        be listed keeps every row. The local temp folder is removed however the
        capture ends.

    .PARAMETER Context
        The run context (New-BackupRunContext).

    .PARAMETER Paths
        The set's resolved paths.

    .PARAMETER PriorRows
        The latest manifest's rows before this run.

    .OUTPUTS
        [pscustomobject] FinalRows (in manifest order), WalkPaths (every file
        the walk listed), NotCaptured (files and folders not captured).
    #>
    # Implements: SR-001, SR-055, SR-057, SR-067, SR-089, SR-091, LLR-091
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Context,
        [Parameter(Mandatory)][pscustomobject]$Paths,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PriorRows
    )
    $log = $Context.Log
    $priorMap = New-RelativePathMap
    foreach ($r in $PriorRows) { $priorMap[$r.RelativePath] = $r }
    if ($Paths.SrcStatePath -ne $Paths.SrcPath) {
        & $log "SourceStatePath '$($Paths.SrcStatePath)' is no longer used: the latest backup manifest is the change-detection record. Its old MANIFEST.csv can be deleted." 'WARN'
    } elseif (Test-Path -LiteralPath (Join-Path $Paths.SrcPath $script:Def.DatabaseFilename) -PathType Leaf) {
        & $log "The source-side record '$(Join-Path $Paths.SrcPath $script:Def.DatabaseFilename)' is no longer used; it stays out of the backup and can be deleted." 'WARN'
    }
    try {
        $walk = Get-SourceFileList -SourcePath $Paths.SrcPath -ExcludeOldSourceRecord ($Paths.SrcStatePath -eq $Paths.SrcPath)
        $walkPaths = [string[]]@($walk.Files | ForEach-Object { $_.RelativePath })
        $notCaptured = 0
        # Rows of files this run cannot see stay as they were (SR-055, SR-057, SR-091).
        $frozen = New-RelativePathMap
        foreach ($u in $walk.Unportable) {
            & $log "Not capturing '$($u.RelativePath)': $($u.Reason). Rename it at the source (SR-055)." 'WARN'
            $frozen[$u.RelativePath] = $true
            $notCaptured++
        }
        $unreadablePrefixes = [System.Collections.Generic.List[string]]::new()
        foreach ($bad in $walk.Unreadable) {
            & $log "Cannot list '$($bad.Path)': $($bad.Message). Files beneath it are not captured this run and keep their earlier copies (SR-057)." 'WARN'
            $notCaptured++
            if ("$($bad.Path)".StartsWith($Paths.SrcPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $prefix = "$($bad.Path)".Substring($Paths.SrcPath.Length).TrimStart('\', '/')
                # The source root itself: every row is beneath it.
                if ($prefix) { $unreadablePrefixes.Add($prefix + [System.IO.Path]::DirectorySeparatorChar) } else { $unreadablePrefixes.Add('') }
            }
        }
        Complete-RunStep -Metrics $Context.Metrics -Name 'walk source'

        # The working rows start as the prior rows, so a checkpoint never
        # drops a file the loop has not reached yet.
        $working = New-RelativePathMap
        foreach ($r in $PriorRows) { $working[$r.RelativePath] = $r }
        $visited = New-RelativePathMap
        $gone = 0
        $pending = [System.Collections.Generic.List[object]]::new()
        $dirty = $false
        $nextCheckpoint = [datetime]::UtcNow.AddSeconds($script:CheckpointMinSeconds)
        $nextProgress = [datetime]::UtcNow.AddSeconds($script:ProgressIntervalSeconds)
        $done = 0
        $metrics = $Context.Metrics
        $fileWatch = [System.Diagnostics.Stopwatch]::new()
        foreach ($item in $walk.Files) {
            $visited[$item.RelativePath] = $true
            $fileWatch.Restart()
            $result = Invoke-SourceFileCapture -Item $item -PriorRow $priorMap[$item.RelativePath] -Context $Context
            if ($fileWatch.ElapsedTicks -gt $metrics.SlowFloor) {
                Add-RunSlowFile -Metrics $metrics -RelativePath $item.RelativePath -Bytes $item.File.Length -Ticks $fileWatch.ElapsedTicks
            }
            $done++
            if ([datetime]::UtcNow -ge $nextProgress) {
                & $log ("Progress: $done of $($walk.Files.Count) file(s), $(Format-RunByteCount $metrics.BytesRead) read, " +
                        "{0:N0} s." -f $metrics.Watch.Elapsed.TotalSeconds)
                $nextProgress = [datetime]::UtcNow.AddSeconds($script:ProgressIntervalSeconds)
            }
            switch ($result.Status) {
                'Kept'     { $working[$item.RelativePath] = $result.Row }
                'Captured' { $working[$item.RelativePath] = $result.Row; $dirty = $true }
                'Gone'     { $visited.Remove($item.RelativePath); $gone++ }
                'Failed'   { $pending.Add([pscustomobject]@{ Item = $item; Attempts = 1; LastAttempt = [datetime]::UtcNow; Message = $result.Message }) }
            }
            Invoke-BackupRunTestHook -Stage 'AfterFileCaptured' -Context $item
            if ($dirty -and [datetime]::UtcNow -ge $nextCheckpoint) {
                $watch = [System.Diagnostics.Stopwatch]::StartNew()
                Write-Manifest -FolderPath $Paths.BkpPath -Records ([object[]]@($working.Values))
                $watch.Stop()
                Add-RunMetric -Metrics $metrics -Name 'progress checkpoint' -Ticks $watch.ElapsedTicks
                $dirty = $false
                $wait = [math]::Max($script:CheckpointMinSeconds, $script:CheckpointWriteFactor * $watch.Elapsed.TotalSeconds)
                $nextCheckpoint = [datetime]::UtcNow.AddSeconds($wait)
                & $log "Progress saved ($($working.Count) row(s), $([math]::Round($watch.Elapsed.TotalSeconds, 1)) s)." 'DEBUG'
            }
        }

        Complete-RunStep -Metrics $metrics -Name 'capture files'

        # 5. The retry pass (R12): each failed file again, no sooner than
        #    the spacing after its last attempt, up to the attempt limit.
        Invoke-BackupRunTestHook -Stage 'BeforeRetryPass' -Context $pending
        while ($pending.Count -gt 0) {
            $next = [System.Collections.Generic.List[object]]::new()
            foreach ($p in ($pending | Sort-Object LastAttempt)) {
                $due = $p.LastAttempt.AddSeconds($script:RetryMinSpacingSeconds)
                $sleep = ($due - [datetime]::UtcNow).TotalMilliseconds
                if ($sleep -gt 0) {
                    Start-Sleep -Milliseconds ([int][math]::Ceiling($sleep))
                    Add-RunMetric -Metrics $metrics -Name 'retry wait' -Ticks ([long]($sleep * [System.Diagnostics.Stopwatch]::Frequency / 1000))
                }
                $result = Invoke-SourceFileCapture -Item $p.Item -PriorRow $priorMap[$p.Item.RelativePath] -Context $Context
                $p.Attempts++
                $p.LastAttempt = [datetime]::UtcNow
                switch ($result.Status) {
                    { $_ -in 'Kept', 'Captured' } { $working[$p.Item.RelativePath] = $result.Row }
                    'Gone' { $visited.Remove($p.Item.RelativePath); $gone++ }
                    'Failed' {
                        $p.Message = $result.Message
                        if ($p.Attempts -lt $script:RetryMaxAttempts) { $next.Add($p) } else {
                            $kept = if ($priorMap.ContainsKey($p.Item.RelativePath)) { 'its earlier copy is kept' } else { 'it has no earlier copy' }
                            & $log "Not capturing '$($p.Item.RelativePath)' after $($p.Attempts) attempt(s): $($p.Message); $kept (R12, SR-091)." 'WARN'
                            $frozen[$p.Item.RelativePath] = $true
                            $notCaptured++
                        }
                    }
                }
            }
            $pending = $next
        }

        Complete-RunStep -Metrics $metrics -Name 'retry pass'

        # Files that vanished are removals - unless the source itself went
        # away (a share dropped, a drive unplugged): then this is no state of
        # the source at all, and the set stops before it is written (4).
        if ($gone -gt 0 -and -not [System.IO.Directory]::Exists($Paths.SrcPath)) {
            throw "The source root '$($Paths.SrcPath)' disappeared during the run ($gone file(s) vanished); the latest state is left as it was."
        }
        # A mount that drops on Linux leaves its empty mount-point folder behind
        # (plan C27): files vanished and the source is now empty.
        if ($gone -gt 0 -and @([System.IO.Directory]::EnumerateFileSystemEntries($Paths.SrcPath) | Select-Object -First 1).Count -eq 0) {
            throw "The source '$($Paths.SrcPath)' emptied during the run ($gone file(s) vanished) - a mount that dropped looks like this; the latest state is left as it was."
        }
        # The same stop for a source that was already empty when the walk began
        # (review 2026-10-26 C2, the Owner's option C): in the container an
        # unmounted or failed source drive is an empty folder, and carrying on
        # recorded the whole library as deleted with exit 0. Assert-SourceNotEmpty
        # stops a root that lists nothing before step 3; this is the backstop
        # for one that lists only empty folders. A source the walk saw anything
        # in - an unportable name, an unlistable folder (C24) - is not empty,
        # and a first backup (no prior rows) has nothing to lose.
        if ($walk.Files.Count -eq 0 -and $walk.Unportable.Count -eq 0 -and $walk.Unreadable.Count -eq 0 -and $PriorRows.Count -gt 0) {
            throw (Get-EmptySourceMessage -SourcePath $Paths.SrcPath -RowCount $PriorRows.Count)
        }

        # The final rows: what the loop captured, plus the prior rows of
        # files it could not see. Everything else was removed.
        $final = [System.Collections.Generic.List[object]]::new()
        foreach ($rel in $working.Keys) {
            $row = $working[$rel]
            if ($visited.ContainsKey($rel) -and -not $frozen.ContainsKey($rel)) { $final.Add($row); continue }
            $isFrozen = $frozen.ContainsKey($rel)
            if (-not $isFrozen) {
                foreach ($prefix in $unreadablePrefixes) {
                    if ($rel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $isFrozen = $true; break }
                }
            }
            if ($isFrozen -and $priorMap.ContainsKey($rel)) { $final.Add((ConvertTo-FrozenRow -PriorRow $priorMap[$rel] -Context $Context)) }
        }
        $finalRows = Get-SortedManifestRow -Rows $final.ToArray()
    } finally {
        if ($Context.LocalTemp) { Remove-Item -LiteralPath $Context.LocalTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ FinalRows = $finalRows; WalkPaths = $walkPaths; NotCaptured = $notCaptured }
}

function Publish-LatestState {
    <#
    .SYNOPSIS
        Finishes the latest state (plan step 6): the final manifest and the
        directory record, then this run's dates.

    .DESCRIPTION
        LastBackupRun is written right after the manifest, before the
        superseded move and the browse view, so a kill late in the run still
        dates the state it finished (defect review M-4); a kill between the two
        writes leaves that state unsnapshotted by the next run, losing no bytes
        (plan C17). A directory record that cannot be written is a warning: the
        files and manifest are unaffected. The Incoming temp folder goes last.

    .PARAMETER Context
        The run context.

    .PARAMETER Paths
        The set's resolved paths.

    .PARAMETER FinalRows
        The final manifest rows.

    .PARAMETER WalkPaths
        Every file the walk listed, for the directory record.

    .PARAMETER When
        This run's completion date.
    #>
    # Implements: SR-005, SR-011, SR-065, LLR-005
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Context,
        [Parameter(Mandatory)][pscustomobject]$Paths,
        [AllowNull()][AllowEmptyCollection()][object[]]$FinalRows,
        [AllowNull()][AllowEmptyCollection()][string[]]$WalkPaths,
        [Parameter(Mandatory)][datetime]$When
    )
    Invoke-BackupRunTestHook -Stage 'BeforeFinalManifest' -Context $FinalRows
    Write-Manifest -FolderPath $Paths.BkpPath -Records $FinalRows
    try {
        $dirRows = Get-SourceDirectoryRecord -SourcePath $Paths.SrcPath -FileRelativePath $WalkPaths -Log $Context.Log
        Write-DirectorySidecar -FolderPath $Paths.BkpPath -Records $dirRows
    } catch {
        & $Context.Log "Directory record not written: $($_.Exception.Message) (files and manifest are unaffected)." 'WARN'
    }
    if ($Context.Recalc) { Set-LastHashRun -BackupRoot $Paths.BkpPath -When $When }
    Set-LastBackupRun -BackupRoot $Paths.BkpPath -When $When
    Remove-Item -LiteralPath $Context.Incoming -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-BackupRunTestHook -Stage 'AfterFinalManifest' -Context $FinalRows
}

function Test-StateChanged {
    <#
    .SYNOPSIS
        Whether a run changed the latest state (plan step 7, R7): a row was
        added or removed, or a row's state key - path, length, time, content,
        SR-005's supersession criterion - differs.

    .PARAMETER PriorRows
        The latest manifest's rows before the run.

    .PARAMETER FinalRows
        The final manifest rows.

    .OUTPUTS
        [bool]
    #>
    # Implements: SR-005, SR-100, LLR-005
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PriorRows,
        [AllowNull()][AllowEmptyCollection()][object[]]$FinalRows
    )
    if ($null -eq $FinalRows) { $FinalRows = @() }
    # The key is inlined, because it is built twice per row.
    $dateFormat = $script:Def.CSVDateFormat
    $priorKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($r in $PriorRows) {
        [void]$priorKeys.Add("$($r.RelativePath)|$($r.Length)|$(([datetime]$r.LastWriteTime).ToString($dateFormat))|$($r.xxH2Hash)")
    }
    if ($priorKeys.Count -ne $FinalRows.Count) { return $true }
    foreach ($r in $FinalRows) {
        if (-not $priorKeys.Contains("$($r.RelativePath)|$($r.Length)|$(([datetime]$r.LastWriteTime).ToString($dateFormat))|$($r.xxH2Hash)")) { return $true }
    }
    return $false
}

function Invoke-BackupSet {
    <#
    .SYNOPSIS
        Runs one backup set (plan §3) and returns its outcome code: 0 every
        file captured, 1 completed with files not captured, 2 refused before
        anything changed, 4 stopped by a host problem or a held lock.

    .DESCRIPTION
        The bounded run. A corner case warns and the run carries on (R1); the
        run stops only where going on could store wrong content or lose a
        state. Every step is ordered so that a kill at any point leaves every
        visible state restorable, and the next run repairs from the files.

    .PARAMETER Set
        The backup set.

    .PARAMETER Deps
        Resolved dependencies (7z, ffprobe).

    .PARAMETER LogPaths
        Receives the set log's path.

    .PARAMETER BackupTime
        Test seam (SR-005): pins this run's completion date, which names the
        next run's snapshot. Defaults to now.

    .OUTPUTS
        [int] 0 | 1 | 2 | 4
    #>
    # Implements: SR-001, SR-005, SR-014, SR-036, SR-055, SR-057, SR-085, SR-086, SR-089, SR-091, SR-100, LLR-014, LLR-091
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][hashtable]$Deps,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$LogPaths,
        [AllowNull()][Nullable[datetime]]$BackupTime
    )

    # 1. Paths; then the lock, before any store state is read (SR-085). A
    #    store drive that is not attached is retry later (4, plan C25);
    #    anything else here needs a person (2).
    try { $paths = Resolve-BackupSetPaths -Set $Set } catch {
        Write-Warning $_.Exception.Message
        if ($_.Exception -is [System.IO.DriveNotFoundException]) { return 4 }
        return 2
    }
    $logPath = Join-Path $paths.ChgPath 'backup.log'
    try {
        $osLock = Enter-StagingOsLock -ChgPath $paths.ChgPath -Log $null
    } catch {
        # Appended, never through New-Logger (which truncates): backup.log
        # belongs to the run that holds the lock.
        $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') [ERROR] Refusing backup set '$($Set.Name)': $($_.Exception.Message)"
        try { Add-Content -LiteralPath $logPath -Value $line } catch { Write-Warning "Could not append to '$logPath': $($_.Exception.Message)" }
        Write-Host $line
        $LogPaths.Add($logPath)
        return 4
    }
    $log = $null
    $code = 0
    $metrics = New-RunMetric
    try {
        $log = New-Logger -LogFile $logPath
        $LogPaths.Add($logPath)
        & $log "----- Backup set '$($Set.Name)' starting -----"
        $thisBackupDate = if ($BackupTime) { [datetime]$BackupTime } else { Get-Date }

        # 2. Refusals that need a person, then the latest state.
        try { $priorRows = [object[]](Read-PriorStateForRun -Set $Set -Paths $paths) } catch {
            & $log "Refusing backup set '$($Set.Name)': $($_.Exception.Message)" 'ERROR'
            return 2
        }
        Complete-RunStep -Metrics $metrics -Name 'read latest state'
        # A source root that lists nothing while the latest state holds rows is
        # a missing mount or a failed drive: stop (4) before step 3 publishes a
        # snapshot of a state that did not change (review 2026-10-26 C2).
        Assert-SourceNotEmpty -SourcePath $paths.SrcPath -PriorRowCount $priorRows.Count
        Clear-InterruptedRunResidue -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath -Log $log
        $priorDate = Get-PriorBackupDate -BackupRoot $paths.BkpPath -PriorRowCount $priorRows.Count -Log $log
        Complete-RunStep -Metrics $metrics -Name 'clear residue'

        # 3. The index, the kit and the prior state's snapshot (plan steps 2-3).
        $index = Get-StoreObjectIndex -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
        & $log "Indexed $($index.Objects.Count) stored object(s); $($index.Duplicates.Count) duplicate cop(ies) left for -Action Verify."
        Complete-RunStep -Metrics $metrics -Name 'index the store'
        # Before the library loop, so no capture can find a damaged object at
        # its content's name (review 2026-10-26 G1).
        $damage = Move-DamagedStoreObject -Damaged $index.Damaged.ToArray() -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath `
                      -Metrics $metrics -Log $log
        New-ReconstructScript -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
        Complete-RunStep -Metrics $metrics -Name 'restore kit'
        $snapshot = $null
        if ($null -ne $priorDate) {
            $snapshot = Publish-PriorStateSnapshot -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath `
                            -PriorDate $priorDate -PriorRows $priorRows -Log $log
        }
        Invoke-BackupRunTestHook -Stage 'AfterSnapshotPublished' -Context $snapshot
        Complete-RunStep -Metrics $metrics -Name 'publish snapshot'

        # 4-5. The library loop and the retry pass (each marks its own steps).
        $context = New-BackupRunContext -Set $Set -Deps $Deps -Paths $paths -Index $index -Metrics $metrics -Log $log
        $capture = Invoke-LibraryCapture -Context $context -Paths $paths -PriorRows $priorRows
        $finalRows = $capture.FinalRows

        # 6. Finish the latest state, then record this run's date.
        Publish-LatestState -Context $context -Paths $paths -FinalRows $finalRows -WalkPaths $capture.WalkPaths -When $thisBackupDate
        Complete-RunStep -Metrics $metrics -Name 'finish latest state'

        # 7. A run that changed no row keeps no snapshot it built itself (SR-100).
        if ($null -ne $snapshot -and $snapshot.BuiltNow -and -not (Test-StateChanged -PriorRows $priorRows -FinalRows $finalRows)) {
            if (Remove-UnchangedSnapshot -SnapshotPath $snapshot.Path -ChangeRoot $paths.ChgPath -Log $log) { $snapshot = $null }
        }
        Complete-RunStep -Metrics $metrics -Name 'drop unneeded snapshot'

        # 8. Superseded content into the snapshot.
        $snapshotPath = if ($null -ne $snapshot) { $snapshot.Path } else { $null }
        $snapshotRows = if ($null -ne $snapshot -and $snapshot.BuiltNow) { $priorRows } else { @() }
        $moved = Move-SupersededObject -Index $index -FinalRows $finalRows -SnapshotPath $snapshotPath `
                     -SnapshotRows $snapshotRows -ChangeRoot $paths.ChgPath -Log $log
        Complete-RunStep -Metrics $metrics -Name 'move superseded'

        # 9. The browse view (SR-062), cosmetic: a failure is a warning.
        if ([string]$Set.BrowseView -eq 'index' -and $paths.ViewPath) {
            try { [void](New-BrowseViewIndex -BackupRoot $paths.BkpPath -ViewRoot $paths.ViewPath -Log $log) }
            catch { & $log "Browse view generation failed: $($_.Exception.Message) (the backup itself is unaffected; -Action View retries loudly)" 'WARN' }
            Complete-RunStep -Metrics $metrics -Name 'browse view'
        }

        Write-ProbeStatistic -Stats $context.ProbeStats -Log $log
        & $log ("Files: $($finalRows.Count) in the latest state, $($context.Stats.Stored) new object(s) stored, " +
                "$($context.Stats.MovedBack) moved back from snapshots, $moved superseded moved into the snapshot, $($capture.NotCaptured) not captured, " +
                "$($damage.Found) damaged object(s) set aside.")
        Write-RunMetric -Metrics $metrics -Log $log -Extra @{
            files = $finalRows.Count; stored = $context.Stats.Stored; movedBack = $context.Stats.MovedBack
            supersededMoved = $moved; notCaptured = $capture.NotCaptured; kitRevisionReads = $context.KitRevisionOf.Count
            damagedFound = $damage.Found; damagedSetAside = $damage.Moved
        }
        # A damaged object set aside reports 1, like a file not captured: the
        # run completed, and the scheduler and HomeHub must still see it.
        if ($capture.NotCaptured -gt 0 -or $damage.Found -gt 0) {
            $code = 1
            & $log ("----- Backup set '$($Set.Name)' completed; $($capture.NotCaptured) file(s) or folder(s) not captured, " +
                    "$($damage.Found) damaged stored object(s) set aside (see the warnings above) -----") 'WARN'
        } else {
            & $log "----- Backup set '$($Set.Name)' completed -----"
        }
    } catch {
        $why = if (Test-BackupDiskFull -ErrorRecord $_) { 'the backup volume is full' } else { 'it stopped' }
        $msg = "Backup set '$($Set.Name)' did not finish because ${why}: $($_.Exception.Message) Every state stays restorable; the next run carries on from the files."
        if ($null -ne $log) {
            & $log $msg 'ERROR'
            # What the run spent its time on before it stopped (a slow step is
            # often why a scheduled run was killed).
            try { Write-RunMetric -Metrics $metrics -Log $log -Extra @{ stopped = $true } } catch { Write-Verbose "metrics not written: $($_.Exception.Message)" }
        } else { Write-Warning $msg }
        $code = 4
    } finally {
        Exit-StagingOsLock -Lock $osLock -Log $log
    }
    return $code
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
                    'BrowseView', 'ViewPath', 'CompressProbe'
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
        # SR-081/SR-063 vocabulary: exact-lowercase 'off'|'excluded-extensions'|
        # 'always', matching the published schema's enum (TC-077 parity). The key
        # is OPTIONAL and defaults to 'always', but a PRESENT key must be one of
        # the three: a mixed-case "Always" or a "maybe" silently defaulting to
        # always is exactly the misconfiguration an operator would never see.
        # This runs for JSON and CLIXML alike - it is the only place a CLIXML
        # "maybe" is caught.
        if ($set.PSObject.Properties.Name -contains 'CompressProbe') {
            if ($StrictTypes) { Assert-ConfigValueType -Value $set.CompressProbe -JsonType 'string' -JsonPath "$setPath.CompressProbe" }
            # JSON is typed by Assert-ConfigValueType above; CLIXML is not, and
            # [string] on an ARRAY joins it - so @('off') would cast to 'off' and
            # pass the vocabulary check, giving the two formats different
            # contracts (R-3). Require a scalar string first, unwrapping the
            # PSObject deserialization puts around CLIXML values.
            $cpRaw = $set.CompressProbe
            if ($cpRaw -is [psobject]) { $cpRaw = $cpRaw.PSObject.BaseObject }
            if ($cpRaw -isnot [string]) {
                throw "Backup set '$($set.Name)' has invalid CompressProbe: it must be a single string ('off', 'excluded-extensions' or 'always'), not a list or another type."
            }
            $cp = [string]$cpRaw
            if ($cp -cnotin 'off', 'excluded-extensions', 'always') {
                throw "Backup set '$($set.Name)' has invalid CompressProbe '$cp'. Expected 'off', 'excluded-extensions' or 'always' (exact lowercase)."
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
        BrowseView = 'off', ViewPath = '<BackupPath>_View',
        CompressProbe = 'always') and normalizes
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
        # CompressProbe defaults to 'always' (Owner ruling Q4, SR-081): the name
        # is not evidence, so the default measures wherever a measurement is
        # available. Without this line a validated key would be silently dropped.
        $compressProbe = if ($set.PSObject.Properties.Name -contains 'CompressProbe' -and
                             -not [string]::IsNullOrWhiteSpace([string]$set.CompressProbe)) {
            [string]$set.CompressProbe
        } else { 'always' }
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
            CompressProbe      = $compressProbe
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
    'Test-IsInfrastructureFile', 'Test-PortableRelativePath', 'Get-CaseOnlyCollision', 'Get-DataFile',
    'Get-LastHashRun', 'Set-LastHashRun',
    'Get-LastBackupRun', 'Set-LastBackupRun',
    'Resolve-OptionalTool', 'Initialize-Dependencies', 'Get-MediaMBPerSec',
    'Get-SourceDirectoryRecord', 'Write-DirectorySidecar',
    'Test-HashRecalcDue',
    'Get-BackupContentIndex',
    'Get-SnapshotPrunePlan', 'Get-BackupSnapshot', 'Get-PoolSnapshotFolder',
    'Test-StorageFormAgreement', 'Test-PoolResolves', 'Assert-PrunePrecondition',
    'Get-PruneCapacityRefusal', 'Remove-CommittedPruneResidue',
    'Get-StoredFileForm', 'Get-StorageFormFinding', 'Get-BackupKitRevision',
    'Test-BackupStorageForm', 'Repair-BackupStorageForm', 'Update-BackupSnapshotKit',
    'Invoke-PruneEntrySweep', 'Copy-ReHomedDataFile', 'Publish-PruneManifest',
    'Complete-PruneDeletion', 'Remove-BackupSnapshot', 'Get-PruneBatchExitCode',
    'New-ReconstructScript',
    'Get-StagingOsLockPath', 'Enter-StagingOsLock', 'Exit-StagingOsLock',
    'Resolve-BackupSetPaths',
    'Get-StoredObjectVerdict', 'Get-StoreObjectFinding', 'Move-StoreObjectToVerify', 'Measure-DuplicateRepairCost',
    'New-RunMetric', 'Complete-RunStep', 'Write-RunMetric', 'Format-RunByteCount',
    'Get-StoreObjectIndex', 'ConvertFrom-StoredObjectName', 'Get-StoredObjectPrefix', 'Assert-SingleStoreMount',
    'Copy-FileWithHash', 'Get-SourceFileList', 'Invoke-SourceFileCapture', 'Publish-PriorStateSnapshot',
    'Move-SupersededObject', 'Get-SortedManifestRow',
    'Invoke-BackupSet',
    'New-BrowseViewIndex',
    'Import-BackupConfiguration'
)
