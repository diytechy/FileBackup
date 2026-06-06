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
    # Implements: SR-022, LLR-022
    <#
    .SYNOPSIS
        True when a file is a FileBackup-managed artifact sitting at the *root* of
        a backup/source tree (manifest, reconstruct scripts, bundled module/DLL,
        state file). Nested user files that happen to share those names are NOT
        treated as infrastructure — that is the B6 fix.
    #>
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
        $script:Def.ReconstructLogName,
        $script:Def.CommonModuleName,
        'System.IO.Hashing.dll',
        'FileBackupState.json',
        'backup.log'
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
    # Implements: SR-011, SR-028, LLR-011, LLR-028
    # Reads FileBackupState.json as a hashtable, tolerating a missing/corrupt file.
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
        Write-Verbose "Could not parse state file '$statePath': $($_.Exception.Message)"
        return @{}
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
    # Implements: SR-011, LLR-011
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupRoot)
    $v = (Read-BackupState -BackupRoot $BackupRoot)['LastHashRun']
    if ($v) { return [datetime]::Parse($v) }
    return $null
}

function Set-LastHashRun {
    # Implements: SR-011, LLR-011
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [datetime]$When = (Get-Date)
    )
    Set-BackupStateField -BackupRoot $BackupRoot -Name 'LastHashRun' -Value $When.ToString('O')
}

function Get-LastBackupRun {
    # Implements: SR-005, SR-028, LLR-005, LLR-028
    # The completion date of the most recent backup; used to date the *next*
    # run's point-in-time snapshot. $null until the first backup has run.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BackupRoot)
    $v = (Read-BackupState -BackupRoot $BackupRoot)['LastBackupRun']
    if ($v) { return [datetime]::Parse($v) }
    return $null
}

function Set-LastBackupRun {
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
        [switch]$NonInteractive
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }

    Write-Warning "$Name not found at '$Path'."
    if ($InstallHint) { & $InstallHint }
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
        [switch]$AutoInstall
    )
    $deps = [ordered]@{}

    if ($AnyCompressionNeeded) {
        $deps['7z'] = Resolve-OptionalTool -Name '7-Zip' -Path $script:Def.SevenZipDefaultPath -NonInteractive:$NonInteractive -InstallHint {
            & $Log 'Please install 7-Zip from https://www.7-zip.org/ and adjust the path if needed.' 'WARN'
        }
    } else {
        $deps['7z'] = $null
    }

    if ($AnyMediaMetricsNeeded) {
        $deps['ffprobe'] = Resolve-OptionalTool -Name 'ffprobe' -Path $script:Def.FfprobePathDefault -NonInteractive:$NonInteractive -InstallHint {
            & $Log 'Please install ffmpeg/ffprobe into C:\ffmpeg\bin or adjust the path.' 'WARN'
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
    # Implements: SR-011, LLR-011
    <#
    .SYNOPSIS
        Decides whether untouched files should be re-hashed this run, given the
        frequency code and the timestamp of the last hash run.
    .NOTES
        B2: DateTime.MinValue (the unbound default) means "never run" -> recalc.
    #>
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
    # Implements: SR-001, SR-013, SR-024, LLR-001, LLR-013, LLR-024
    <#
    .SYNOPSIS
        Walks the source tree, (re)hashes new/changed files (and all files when
        -ForceRehash), marks (hash,length) duplicates, and writes the source
        MANIFEST.csv. Returns the rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$FfprobePath,
        [switch]$ForceRehash
    )
    $sourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $existing   = Read-Manifest -FolderPath $sourcePath

    $existingMap = @{}
    foreach ($row in $existing) { $existingMap[$row.RelativePath] = $row }

    # B6: skip only the root manifest, keep nested files named MANIFEST.csv.
    $files = Get-DataFile -Root $sourcePath

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

    Write-Manifest -FolderPath $sourcePath -Records $sorted
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
    # Implements: SR-012, SR-013, LLR-012, LLR-013
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
    # Implements: SR-026, LLR-026
    <#
    .SYNOPSIS
        Collapses duplicate (hash,length) data files across change folders,
        preferring the backup copy then the newest change folder, and blanks
        DataPaths whose files were removed (reconstruct recovers them by hash).
    #>
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
    # Implements: SR-007, LLR-007
    <#
    .SYNOPSIS
        Copies RECONSTRUCT.ps1/.bat into the backup root, writes a path sidecar,
        and bundles the runtime dependencies (FileBackup.Common.psm1 +
        System.IO.Hashing.dll) so a restore works from the backup folder alone.
    .NOTES
        Earlier versions prepended "$BackupRootOverride = ..." lines ahead of the
        script's param() block, which is invalid PowerShell. Paths are now passed
        via a JSON sidecar that Reconstruct.ps1 reads from its own folder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ChangeRoot
    )
    $templatePs1 = Join-Path (Split-Path $PSScriptRoot -Parent) $script:Def.ReconstructPs1Name
    if (-not (Test-Path -LiteralPath $templatePs1 -PathType Leaf)) {
        throw "Reconstruct.ps1 not found at '$(Split-Path $PSScriptRoot -Parent)'"
    }

    # Copy the reconstruct script verbatim.
    Copy-Item -LiteralPath $templatePs1 -Destination (Join-Path $BackupRoot $script:Def.ReconstructPs1Name) -Force

    # Path bindings as a sidecar (read by Reconstruct.ps1 from $PSScriptRoot).
    @{ BackupRoot = $BackupRoot; ChangeRoot = $ChangeRoot } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupRoot 'RECONSTRUCT.paths.json') -Encoding UTF8

    $bat = "@echo off`r`npwsh -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$($script:Def.ReconstructPs1Name)`" %*"
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

    return [pscustomobject]@{ SrcPath = $srcPath; BkpPath = $bkpPath; ChgPath = $chgPath }
}

function Initialize-StagingFolder {
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
    # Implements: SR-001, LLR-001
    <#
    .SYNOPSIS
        Pure diff: returns NewOrChanged (source rows) and RemovedFromSource
        (backup rows) by RelativePath. No I/O — unit-testable.
    #>
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
    # Implements: SR-003, LLR-003
    <#
    .SYNOPSIS
        Backs up one (hash,length) group: reuses an existing backup data file if
        present, otherwise copies/compresses once and points every logical name
        at it.
    #>
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
    # Implements: SR-006, LLR-006
    <#
    .SYNOPSIS
        Evicts data files for source-removed entries into the staging folder.
    .NOTES
        B9: only moves a data file out when no surviving backup entry still
        references it (shared hash/size dedup). When it is still referenced, the
        file is left in the backup root and the change manifest blanks the
        DataPath (reconstruct recovers it by hash).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$RemovedFromSource,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][ref]$BackupMap,
        [Parameter(Mandatory)][ref]$ChangedCount,
        [Parameter(Mandatory)][scriptblock]$Log
    )
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
            $destDir = [System.IO.Path]::GetDirectoryName($destDataFull)
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Move-Item -LiteralPath $srcDataFull -Destination $destDataFull -Force
            $ChangedCount.Value++
        }
    }
}

function Save-SupersededData {
    # Implements: SR-010, SR-028, LLR-010, LLR-028
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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$NewOrChanged,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$BackupDb,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$SourceDb,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][scriptblock]$Log
    )
    if (-not $NewOrChanged) { return }
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
        $destDir  = [System.IO.Path]::GetDirectoryName($destFull)
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Move-Item -LiteralPath $srcDataFull -Destination $destFull -Force
        & $Log "Preserved superseded data for '$($chg.RelativePath)' into the snapshot."
    }
}

function Complete-ChangeFolder {
    # Implements: SR-005, SR-028, LLR-005, LLR-028
    <#
    .SYNOPSIS
        Finalizes the staging folder into a dated point-in-time snapshot, or
        discards it when nothing was superseded.
    .DESCRIPTION
        When this run superseded earlier content ($ChangedCount > 0) and a prior
        backup date is known ($SnapshotDate), the staging folder becomes
        Snapshot_<SnapshotDate> — the state of the superseded backup, named by
        that backup's completion date (SR-005). Otherwise (a no-op run, or the
        very first backup) the staging folder is discarded: the live backup root
        is itself the latest state, so it needs no snapshot.

        On finalize, stale DataPaths are blanked (the bytes live in the backup
        root or a sibling snapshot and are recovered by hash at restore), and the
        full reconstruct kit — including the RECONSTRUCT.paths.json sidecar — is
        copied in so a snapshot restore can locate the data pool.
    .PARAMETER SnapshotDate
        Completion date of the backup whose state this snapshot preserves (the
        previous run). $null on the first backup ⇒ no snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChgPath,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][string]$BkpPath,
        [Parameter(Mandatory)][int]$ChangedCount,
        [Parameter(Mandatory)][scriptblock]$Log,
        [AllowNull()][Nullable[datetime]]$SnapshotDate
    )
    if ($ChangedCount -le 0 -or $null -eq $SnapshotDate) {
        Remove-Item -LiteralPath $StagingFolder -Recurse -Force -ErrorAction SilentlyContinue
        & $Log "No prior state superseded; no snapshot created (the live backup is the latest state)."
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
    foreach ($artifact in @($script:Def.ReconstructPs1Name, $script:Def.ReconstructBatName, $script:Def.CommonModuleName, 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')) {
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
    # Implements: SR-014, SR-017, LLR-014, LLR-017
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
    & $log "Updating source manifest at '$($paths.SrcPath)'."
    $sourceDb = Update-SourceManifest -SourcePath $paths.SrcPath -FfprobePath $Deps['ffprobe'] -ForceRehash:$recalc

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

    # 9. Working backup map
    $backupMap = @{}
    foreach ($row in $backupDb) { $backupMap[$row.RelativePath] = $row }
    $changedCount = 0

    # 9.5 Preserve superseded bytes into the snapshot BEFORE they are overwritten
    # (Mirror) or orphaned (HashAddressed) — required for point-in-time restore.
    Save-SupersededData -NewOrChanged $diff.NewOrChanged -BackupDb $backupDb -SourceDb $sourceDb `
        -BkpPath $paths.BkpPath -StagingFolder $stagingFolder -Log $log

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
        -BackupMap ([ref]$backupMap) -ChangedCount ([ref]$changedCount) -Log $log

    # 12. Save updated backup manifest
    $backupDbFinal = $backupMap.Values | Sort-Object { $_.RelativePath.Length } -Descending
    Write-Manifest -FolderPath $paths.BkpPath -Records $backupDbFinal

    # 13. Finalize the dated snapshot (of the PRIOR state) + reconstruct scripts
    New-ReconstructScript -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
    [void](Complete-ChangeFolder -ChgPath $paths.ChgPath -StagingFolder $stagingFolder -BkpPath $paths.BkpPath -ChangedCount $changedCount -Log $log -SnapshotDate $priorBackupDate)

    # 14. De-duplicate data shared across snapshots
    Optimize-ChangeFolders -ChangeRoot $paths.ChgPath -BackupRoot $paths.BkpPath -Log $log

    # 15. Record state: hashes ran (B3) + this backup's completion date (dates the next snapshot)
    if ($recalc) { Set-LastHashRun -BackupRoot $paths.BkpPath -When $thisBackupDate }
    Set-LastBackupRun -BackupRoot $paths.BkpPath -When $thisBackupDate

    & $log "Changed files count = $changedCount"
    & $log "----- Backup set '$($Set.Name)' completed -----"
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
    'Save-SupersededData', 'Complete-ChangeFolder', 'Invoke-BackupSet'
)
