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
        "$($script:Def.WitnessFilename).tmp"
    )
    return ($infra -contains $rel)
}

function Get-DataFile {
    <#
    .SYNOPSIS
        Enumerates real data files under a root, skipping root-level infrastructure.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    Get-ChildItem -LiteralPath $resolved -Recurse -File |
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
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
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
        $deps['7z'] = $null
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
    # Implements: SR-001, SR-013, SR-024, LLR-001, LLR-013, LLR-024
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$ManifestFolderPath,
        [string]$FfprobePath,
        [switch]$ForceRehash
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

    $existingMap = @{}
    foreach ($row in $existing) { $existingMap[$row.RelativePath] = $row }

    # With the legacy in-source cache, skip only root-level infrastructure and
    # keep nested files with those names. With an external cache every source
    # file is user data, including a root-level MANIFEST.csv.
    $files = if ($manifestFolder -eq $sourcePath) {
        Get-DataFile -Root $sourcePath
    } else {
        Get-ChildItem -LiteralPath $sourcePath -Recurse -File
    }

    $updated = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        $rel  = $f.FullName.Substring($sourcePath.Length).TrimStart('\','/')
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

# region Backup copy

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
        if ($ShouldCompress -and $SevenZipPath) {
            Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $SourceFilePath -Destination7z $BackupFilePath
        } else {
            $dir = [System.IO.Path]::GetDirectoryName($BackupFilePath)
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Copy-Item -LiteralPath $SourceFilePath -Destination $BackupFilePath -Force
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
        Blanks DataPaths whose files are missing; warns about unreferenced files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderRoot,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $db = Read-Manifest -FolderPath $FolderRoot

    $existingPaths = @{}
    Get-DataFile -Root $FolderRoot |
        ForEach-Object { $existingPaths[$_.FullName.Substring((Resolve-Path -LiteralPath $FolderRoot).Path.Length).TrimStart('\','/')] = $true }

    foreach ($row in $db) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $rel  = $row.DataPath.TrimStart('\','/')
        $full = Join-Path $FolderRoot $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            & $Log "Datapath missing in backup DB: $rel" 'WARN'
            $row.DataPath = ''
        }
    }

    foreach ($rel in $existingPaths.Keys) {
        if (-not ($db | Where-Object { $_.DataPath -eq $rel })) {
            & $Log "File exists in backup folder but not in DB: $rel" 'WARN'
        }
    }

    Write-Manifest -FolderPath $FolderRoot -Records $db
    return $db
}

function Sync-BackupStorageLayout {
    <#
    .SYNOPSIS
        Migrates backup data files to match the current PreserveFolderTree /
        CompressEnabled configuration (e.g. Mirror <-> HashAddressed, compress
        on/off).
    .NOTES
        B7: copies every transformed file to its new location and persists the
        manifest BEFORE deleting any old file, so an interruption can never leave
        the manifest pointing at a deleted path.
    #>
    # Implements: SR-012, SR-013, LLR-012, LLR-013
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][bool]$PreserveFolderTree,
        [Parameter(Mandatory)][bool]$CompressEnabled,
        [string]$SevenZipPath,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    $db = Test-BackupManifest -FolderRoot $BackupRoot -Log $Log

    $expectedStoredAs = if ($PreserveFolderTree) { 'Original' } else { 'Hash' }

    # Identify rows needing transformation.
    $rowsNeedingTransform = foreach ($row in $db) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $shouldCompress = Test-ShouldCompress -FileName $row.RelativePath -CompressEnabled $CompressEnabled
        $needsTransform = ($row.StoredAsHashSize -ne $expectedStoredAs) -or (($row.Compressed -eq 'Yes') -ne $shouldCompress)
        if ($needsTransform) { $row }
    }
    $rowsNeedingTransform = @($rowsNeedingTransform)

    # Phase 1: copy/compress each row to its new path, update metadata, remember old path.
    $oldPathsToDelete = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rowsNeedingTransform) {
        $currentDataFull = Join-Path $BackupRoot $row.DataPath
        $shouldCompress  = Test-ShouldCompress -FileName $row.RelativePath -CompressEnabled $CompressEnabled

        # Decompress to a temp file if it is compressed but should not be.
        $workingFile = $currentDataFull
        $tempWorking = $null
        if ($row.Compressed -eq 'Yes' -and -not $shouldCompress) {
            if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                & $Log "Cannot decompress '$($row.DataPath)': 7-Zip not found. Skipping transformation." 'WARN'
                continue
            }
            $tempWorking = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
            try {
                Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $currentDataFull -DestinationFile $tempWorking
                $workingFile = $tempWorking
            } catch {
                & $Log "Failed to decompress '$($row.DataPath)': $($_.Exception.Message)" 'ERROR'
                continue
            }
        }

        # Compute the new DataPath.
        if ($expectedStoredAs -eq 'Hash') {
            $ext = if ($shouldCompress) { '.7z' } else { [IO.Path]::GetExtension($row.RelativePath) }
            $newDataPath = Get-HashSizeFileName -HashHex $row.xxH2Hash -Length $row.Length -Extension $ext
        } else {
            $newDataPath = $row.RelativePath
            if ($shouldCompress) { $newDataPath = $row.RelativePath + '.7z' }
        }
        $newDataFull = Join-Path $BackupRoot $newDataPath

        if ($newDataFull -eq $currentDataFull) {
            & $Log "Row '$($row.RelativePath)' already at correct path '$newDataPath'." 'DEBUG'
            if ($tempWorking) { Remove-Item -LiteralPath $tempWorking -Force -ErrorAction SilentlyContinue }
            continue
        }

        try {
            if ($shouldCompress -and $row.Compressed -ne 'Yes') {
                & $Log "Compressing '$($row.DataPath)' -> '$newDataPath'" 'INFO'
                Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $workingFile -Destination7z $newDataFull
            } else {
                & $Log "Copying '$($row.DataPath)' -> '$newDataPath'" 'INFO'
                $newDir = [System.IO.Path]::GetDirectoryName($newDataFull)
                if (-not (Test-Path -LiteralPath $newDir)) {
                    New-Item -ItemType Directory -Path $newDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $workingFile -Destination $newDataFull -Force
            }

            $oldPathsToDelete.Add($currentDataFull)
            $row.DataPath         = $newDataPath
            $row.Compressed       = if ($shouldCompress) { 'Yes' } else { 'No' }
            $row.StoredAsHashSize = $expectedStoredAs
        } catch {
            & $Log "Failed to transform '$($row.RelativePath)': $($_.Exception.Message)" 'ERROR'
        } finally {
            if ($tempWorking) { Remove-Item -LiteralPath $tempWorking -Force -ErrorAction SilentlyContinue }
        }
    }

    # Persist the manifest pointing at the NEW files before deleting any OLD file (B7).
    Write-Manifest -FolderPath $BackupRoot -Records $db

    # Phase 2: now it is safe to remove the superseded data files.
    foreach ($old in $oldPathsToDelete) {
        if (Test-Path -LiteralPath $old -PathType Leaf) {
            Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
            & $Log "Removed old datapath '$old' after transformation." 'INFO'
        }
    }

    # Warn about orphaned data files.
    $referencedPaths = @{}
    foreach ($row in $db) { if ($row.DataPath) { $referencedPaths[$row.DataPath] = $true } }
    foreach ($dataFile in (Get-DataFile -Root $BackupRoot)) {
        $rel = $dataFile.FullName.Substring((Resolve-Path -LiteralPath $BackupRoot).Path.Length).TrimStart('\','/')
        if (-not $referencedPaths[$rel]) {
            & $Log "Orphaned datapath file found (not referenced by manifest): '$rel'" 'WARN'
        }
    }

    & $Log "Sync-BackupStorageLayout completed. Transformed $($rowsNeedingTransform.Count) rows." 'INFO'
    return $db
}

# endregion

# region Change-folder de-duplication

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

    $changeDirs = Get-ChildItem -LiteralPath $ChangeRoot -Directory |
                  Where-Object { $_.Name -match $changeFolderRegex } |
                  Sort-Object Name
    if (-not $changeDirs -or $changeDirs.Count -eq 0) {
        & $Log "No change folders found under '$ChangeRoot'." 'INFO'
        return
    }

    $globalMap = @{}   # "<hash>|<len>" -> list of location records

    $addToGlobalMap = {
        param([string]$LocationType, [string]$Folder, [object]$Row, [int]$FolderOrder)
        if ([string]::IsNullOrWhiteSpace($Row.DataPath)) { return }
        if ([string]::IsNullOrWhiteSpace($Row.xxH2Hash)) { return }
        $key  = "$($Row.xxH2Hash)|$($Row.Length)"
        $full = Join-Path $Folder $Row.DataPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
        if (-not $globalMap.ContainsKey($key)) {
            $globalMap[$key] = New-Object System.Collections.Generic.List[object]
        }
        $globalMap[$key].Add([pscustomobject]@{
            LocationType = $LocationType
            Folder       = $Folder
            DataPath     = $Row.DataPath
            FullPath     = $full
            IsBackup     = ($LocationType -eq 'Backup')
            FolderOrder  = $FolderOrder
        })
    }

    if (Test-Path -LiteralPath (Join-Path $BackupRoot $script:Def.DatabaseFilename) -PathType Leaf) {
        foreach ($row in (Read-Manifest -FolderPath $BackupRoot)) {
            & $addToGlobalMap 'Backup' $BackupRoot $row -1
        }
    }

    $changeManifests = @()
    $folderOrder = 0
    foreach ($dir in $changeDirs) {
        $folderOrder++
        $manifest = Read-Manifest -FolderPath $dir.FullName
        $changeManifests += [pscustomobject]@{ Folder = $dir.FullName; Name = $dir.Name; Order = $folderOrder; Manifest = $manifest }
        foreach ($row in $manifest) { & $addToGlobalMap 'Change' $dir.FullName $row $folderOrder }
    }

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
    #>
    # Implements: SR-014, LLR-014
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Set)

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

    if ($srcStatePath -ne $srcPath) {
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
    }
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
    if (Test-Path -LiteralPath $stagingFolder -PathType Container) {
        & $Log "Staging folder '$stagingFolder' already exists. Previous run may have failed." 'ERROR'
        throw "Cannot initialize staging folder; Temp already exists at '$stagingFolder'"
    }
    New-Item -ItemType Directory -Path $stagingFolder -Force | Out-Null
    return $stagingFolder
}

function Compare-SourceToBackup {
    <#
    .SYNOPSIS
        Pure diff: returns NewOrChanged (source rows) and RemovedFromSource
        (backup rows) by RelativePath. No I/O — unit-testable.
    #>
    # Implements: SR-001, LLR-001
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$SourceDb,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb
    )
    $sourceMap = @{}; foreach ($row in $SourceDb) { $sourceMap[$row.RelativePath] = $row }
    $backupMap = @{}; foreach ($row in $BackupDb) { $backupMap[$row.RelativePath] = $row }

    $newOrChanged      = New-Object System.Collections.Generic.List[object]
    $removedFromSource = New-Object System.Collections.Generic.List[object]

    foreach ($rel in $sourceMap.Keys) {
        $s = $sourceMap[$rel]
        $b = $backupMap[$rel]
        if (-not $b) {
            $newOrChanged.Add($s)
        } elseif ($s.Length -ne $b.Length -or $s.LastWriteTime -ne $b.LastWriteTime -or $s.xxH2Hash -ne $b.xxH2Hash) {
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
    #>
    # Implements: SR-003, LLR-003
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Group,
        [Parameter(Mandatory)][string]$SrcPath,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][bool]$PreserveFolderTree,
        [Parameter(Mandatory)][bool]$CompressEnabled,
        [string]$SevenZipPath,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][ref]$BackupMap,
        [Parameter(Mandatory)][ref]$ChangedCount,
        [Parameter(Mandatory)][scriptblock]$Log,
        [Parameter(Mandatory)][ref]$OverallSuccess
    )
    $hash = $Group[0].xxH2Hash
    $len  = $Group[0].Length
    $exts = ($Group | ForEach-Object { [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() } | Select-Object -Unique)
    if ($exts.Count -gt 1) {
        & $Log "Multiple extensions for hash=$hash len=$len : $($exts -join ', ')" 'WARN'
    }

    # B8: force an array so [0] is always valid even for a single match.
    $existingBackupWithHash = @($BackupDb | Where-Object { $_.xxH2Hash -eq $hash -and $_.Length -eq $len })
    $storedAsHash = -not $PreserveFolderTree

    foreach ($entry in $Group) {
        $rel          = $entry.RelativePath
        $ext          = [IO.Path]::GetExtension($rel)
        $compressFlag = Test-ShouldCompress -FileName (Join-Path $SrcPath $rel) -CompressEnabled $CompressEnabled

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
            $dataPath = if ($storedAsHash) {
                $dataExt = if ($compressFlag) { '.7z' } else { $ext }
                Get-HashSizeFileName -HashHex $hash -Length $len -Extension $dataExt
            } elseif ($compressFlag) {
                # Mirror mode + compression: the data file holds 7z bytes, so it
                # must carry the .7z extension (matches Sync-BackupStorageLayout
                # and lets hash-recovery detect that it needs decompression).
                "$rel.7z"
            } else {
                $rel
            }
            $srcFull  = Join-Path $SrcPath $rel
            $destFull = Join-Path $BkpPath $dataPath

            $result = Copy-SourceFileToBackup -SourceFilePath $srcFull -BackupFilePath $destFull -ShouldCompress:$compressFlag -SevenZipPath $SevenZipPath
            if ($result -is [string]) {
                & $Log "Failed to copy/compress '$rel' -> '$dataPath' : $result" 'ERROR'
                $OverallSuccess.Value = $false
                continue
            }

            $BackupMap.Value[$rel] = [pscustomobject]@{
                DataPath         = $dataPath
                RelativePath     = $rel
                Length           = $len
                LastWriteTime    = $entry.LastWriteTime
                xxH2Hash         = $hash
                Compressed       = if ($compressFlag) { 'Yes' } else { 'No' }
                StoredAsHashSize = if ($storedAsHash) { 'Hash' } else { 'Original' }
                Duplicate        = $entry.Duplicate
                MediaMBPerSec    = $entry.MediaMBPerSec
            }
            $ChangedCount.Value++
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
        Preserves the prior bytes of files whose content is being replaced this
        run, into the staging snapshot, BEFORE Invoke-BackupFileGroup overwrites
        (Mirror) or orphans (HashAddressed) them.
    .DESCRIPTION
        For each changed file that already existed in the backup with different
        content, the old data file is moved into staging IF that exact content
        ((hash,length)) is not present anywhere in the new source state. When the
        old content still exists elsewhere (e.g. a surviving duplicate), it stays
        in the backup and the snapshot recovers it by hash. This is what makes a
        point-in-time restore reproduce old content in every storage mode.

        A failed move does NOT abort the run (SR-041): it is logged as an ERROR,
        counted, and the loop continues, so the run still finalizes its staging
        folder instead of orphaning it (SR-017). Same shape as
        Invoke-BackupFileGroup's existing per-entry handling.
    #>
    # Implements: SR-010, SR-028, SR-041, LLR-010, LLR-028, LLR-041
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$NewOrChanged,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$SourceDb,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][scriptblock]$Log,
        [Parameter(Mandatory)][ref]$OverallSuccess
    )
    if (-not $NewOrChanged) { return }
    $failures = 0
    $backupByRel = @{}; foreach ($b in $BackupDb) { if ($b.RelativePath) { $backupByRel[$b.RelativePath] = $b } }
    # Content (hash|length) present in the NEW source state survives in the backup.
    $survivingContent = @{}; foreach ($s in $SourceDb) { $survivingContent["$($s.xxH2Hash)|$($s.Length)"] = $true }

    foreach ($chg in $NewOrChanged) {
        $old = $backupByRel[$chg.RelativePath]
        if (-not $old) { continue }                                  # brand-new file: nothing superseded
        if ($old.xxH2Hash -eq $chg.xxH2Hash -and $old.Length -eq $chg.Length) { continue }  # same content
        if ([string]::IsNullOrWhiteSpace($old.DataPath)) { continue }
        if ($survivingContent["$($old.xxH2Hash)|$($old.Length)"]) { continue }  # old content still live elsewhere
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

    # Copy the full reconstruct kit (incl. the path sidecar) so a snapshot restore
    # is self-contained and can resolve unchanged bytes by hash from the backup root.
    foreach ($artifact in @($script:Def.ReconstructPs1Name, $script:Def.ReconstructBatName, $script:Def.ReconstructShName, $script:Def.CommonModuleName, 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')) {
        $src = Join-Path $BkpPath $artifact
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination $finalSnapshot -Force
        }
    }

    & $Log "Snapshot finalized: $finalSnapshot"
    return $finalSnapshot
}

# endregion

# region Per-set orchestrator

function Invoke-BackupSet {
    <#
    .SYNOPSIS
        Orchestrates the full backup pipeline for one set (AGENTS.md §2): walk +
        hash the source, sync storage layout, preserve superseded bytes, copy new
        data, evict removed files, finalize the dated snapshot, persist run state.
    #>
    # Implements: SR-014, SR-017, SR-035, SR-036, LLR-014, LLR-017, LLR-035, LLR-036
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
    $sourceDb = Update-SourceManifest -SourcePath $paths.SrcPath -ManifestFolderPath $paths.SrcStatePath `
        -FfprobePath $Deps['ffprobe'] -ForceRehash:$recalc

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

    # 6. Sanitize / migrate backup storage layout
    & $log "Sanitizing backup manifest at '$($paths.BkpPath)'."
    $backupDb = Sync-BackupStorageLayout -BackupRoot $paths.BkpPath -PreserveFolderTree ([bool]$Set.PreserveFolderTree) -CompressEnabled ([bool]$Set.CompressEnabled) -SevenZipPath $Deps['7z'] -Log $log

    # 7. Pre-backup snapshot into staging
    & $log "Saving pre-backup manifest to staging '$stagingFolder'."
    Write-Manifest -FolderPath $stagingFolder -Records $backupDb

    # 8. Diff
    $diff = Compare-SourceToBackup -SourceDb $sourceDb -BackupDb $backupDb
    & $log "New or changed files: $($diff.NewOrChanged.Count)"
    & $log "Removed files: $($diff.RemovedFromSource.Count)"
    # SR-005 supersession criterion: the manifest state changed. A dedup-served
    # add or shared-content removal moves no bytes but still changes the state.
    # (.Count direct — Compare-SourceToBackup always returns real lists, and
    # @() around a List reached via a PSObject property throws on PS 7.5.)
    $manifestChanged = ($diff.NewOrChanged.Count -gt 0) -or ($diff.RemovedFromSource.Count -gt 0)

    # 9. Working backup map
    $backupMap = @{}
    foreach ($row in $backupDb) { $backupMap[$row.RelativePath] = $row }
    $changedCount = 0

    # 9.5 Preserve superseded bytes into the snapshot BEFORE they are overwritten
    # (Mirror) or orphaned (HashAddressed) — required for point-in-time restore.
    # A move failure here is aggregated, not thrown (SR-041): the run must reach
    # step 13 so the staging folder is finalized or discarded rather than
    # orphaned for the next run's SR-017 guard.
    Save-SupersededData -NewOrChanged $diff.NewOrChanged -BackupDb $backupDb -SourceDb $sourceDb `
        -BkpPath $paths.BkpPath -StagingFolder $stagingFolder -Log $log -OverallSuccess $OverallSuccess

    # 10. Copy new/changed files
    foreach ($grp in ($diff.NewOrChanged | Group-Object xxH2Hash, Length)) {
        Invoke-BackupFileGroup `
            -Group $grp.Group `
            -SrcPath $paths.SrcPath -BkpPath $paths.BkpPath `
            -PreserveFolderTree ([bool]$Set.PreserveFolderTree) -CompressEnabled ([bool]$Set.CompressEnabled) `
            -SevenZipPath $Deps['7z'] -BackupDb $backupDb `
            -BackupMap ([ref]$backupMap) -ChangedCount ([ref]$changedCount) `
            -Log $log -OverallSuccess $OverallSuccess
    }

    # 11. Evict removed files to staging
    Move-RemovedFilesToStaging `
        -RemovedFromSource $diff.RemovedFromSource `
        -BkpPath $paths.BkpPath -StagingFolder $stagingFolder `
        -BackupMap ([ref]$backupMap) -ChangedCount ([ref]$changedCount) -Log $log `
        -OverallSuccess $OverallSuccess

    # 12. Save updated backup manifest
    $backupDbFinal = $backupMap.Values | Sort-Object { $_.RelativePath.Length } -Descending
    Write-Manifest -FolderPath $paths.BkpPath -Records $backupDbFinal

    # 13. Finalize the dated snapshot (of the PRIOR state) + reconstruct scripts
    New-ReconstructScript -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
    [void](Complete-ChangeFolder -ChgPath $paths.ChgPath -StagingFolder $stagingFolder -BkpPath $paths.BkpPath -ManifestChanged $manifestChanged -Log $log -SnapshotDate $priorBackupDate)

    # 14. De-duplicate data shared across snapshots
    Optimize-ChangeFolders -ChangeRoot $paths.ChgPath -BackupRoot $paths.BkpPath -Log $log

    # 15. Record state: hashes ran (B3) + this backup's completion date (dates the next snapshot)
    if ($recalc) { Set-LastHashRun -BackupRoot $paths.BkpPath -When $thisBackupDate }
    Set-LastBackupRun -BackupRoot $paths.BkpPath -When $thisBackupDate

    & $log "Changed files count = $changedCount"
    & $log "----- Backup set '$($Set.Name)' completed -----"
}

# endregion

# region Configuration loading (SR-042, SR-043)

# Highest ConfigVersion this build understands (SR-042). A JSON config
# declaring a higher version is refused by name rather than half-understood.
# JSON has ONE number type, so an integral-valued number is that integer:
# "ConfigVersion": 1.0 is the same document as "ConfigVersion": 1 and is
# accepted; 1.5 is not. The published schema's `const: 1` agrees (TC-077).
$script:ConfigSchemaVersion = 1

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
                    'CompressEnabled', 'PreserveFolderTree', 'SourceStatePath', 'AllowEmptySource'
    $toolsKeys    = 'SevenZipPath', 'FfprobePath'
    $secretsKeys  = 'ToEmail', 'FromEmail', 'SmtpServer', 'SmtpPort', 'Credential'

    function Test-ConfigKeySet {
        param($Obj, [string[]]$Allowed, [string]$ObjJsonPath)
        foreach ($prop in $Obj.PSObject.Properties.Name) {
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
        presence of the two boolean fields, and a recognized HashRecalcFreq.
        Message wording matches the pre-SR-042 checks verbatim so existing
        callers and tests are unaffected.
    .PARAMETER StrictTypes
        JSON only. Additionally type-checks EVERY schema-defined value against
        its JSON type before any coercion runs, so none of PowerShell's silent
        conversions can change the meaning of the document: [bool]'false' is
        $true (a quoted "false" for CompressEnabled/PreserveFolderTree/
        AllowEmptySource would enable the feature the operator disabled — and
        for AllowEmptySource that disarms the SR-036 delete-all refusal), and
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
        foreach ($field in 'CompressEnabled', 'PreserveFolderTree') {
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
        defaults (SourceStatePath = SourcePath, AllowEmptySource = $false) and
        normalizes casing/types, so the engine's own [bool] / ToUpperInvariant
        casts at point of use become belt-and-braces (SR-042).
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

        [pscustomobject]@{
            Name               = [string]$set.Name
            SourcePath         = [string]$set.SourcePath
            SourceStatePath    = $sourceStatePath
            BackupPath         = [string]$set.BackupPath
            ChangePath         = [string]$set.ChangePath
            HashRecalcFreq     = ([string]$set.HashRecalcFreq).ToUpperInvariant()
            CompressEnabled    = [bool]$set.CompressEnabled
            PreserveFolderTree = [bool]$set.PreserveFolderTree
            AllowEmptySource   = $allowEmptySource
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
    'Test-IsInfrastructureFile', 'Get-DataFile',
    'Get-LastHashRun', 'Set-LastHashRun',
    'Get-LastBackupRun', 'Set-LastBackupRun',
    'Resolve-OptionalTool', 'Initialize-Dependencies', 'Get-MediaMBPerSec',
    'Test-HashRecalcDue', 'Update-SourceManifest', 'Copy-SourceFileToBackup',
    'Test-BackupManifest', 'Sync-BackupStorageLayout', 'Optimize-ChangeFolders',
    'New-ReconstructScript', 'Resolve-BackupSetPaths', 'Initialize-StagingFolder',
    'Compare-SourceToBackup', 'Invoke-BackupFileGroup', 'Move-RemovedFilesToStaging',
    'Save-SupersededData', 'Complete-ChangeFolder', 'Invoke-BackupSet',
    'Import-BackupConfiguration'
)
