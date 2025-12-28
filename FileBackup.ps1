<#
.SYNOPSIS
    Content-aware backup script with change tracking and restore helpers.

.DESCRIPTION
    - Backs up a source folder to a backup folder.
    - Tracks changes via hash/size/mtime and per-run change snapshots.
    - Supports two backup modes:
        * Mirror mode: original structure, uncompressed.
        * Content-addressed mode: files stored as Hash_Size.ext, optionally 7z compressed.
    - Maintains:
        * Root "current" index in change folder.
        * Per-run change folder with:
            - Previous versions of changed/removed files.
            - Snapshot DB for pre-run state.
            - Restore helper script.
    - Sends email on success/failure.

.NOTES
    - Requires a CLIXML config file providing Secrets and BackupSets.
    - Designed for periodic execution (Task Scheduler, etc.).
#>

# region Configuration

$ErrorActionPreference = 'Stop'

# Path to config file with Secrets and BackupSets (similar to your current model)
$ConfigPath = "$HOME\BackupConfig.xml"

# SMTP defaults (can be overridden in config if you prefer)
$SmtpServer = 'smtp.gmail.com'
$SmtpPort   = 587

# Hash and timestamp formats
$HashAlgorithm     = 'SHA256'
$HashTblDateFormat = 'O'     # ISO 8601, round-trip

# 7-Zip default path
$SevenZipPathDefault = Join-Path $env:ProgramFiles '7-Zip\7z.exe'

# endregion Configuration

# region Utility: Logging

function New-Logger {
    param(
        [Parameter(Mandatory)]
        [string]$LogFile
    )
    New-Item -ItemType File -Force -Path $LogFile | Out-Null

    return {
        param([string]$Message, [string]$Level = 'INFO')
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = "$timestamp [$Level] $Message"
        Add-Content -LiteralPath $LogFile -Value $line
        Write-Host $line
    }
}

# endregion Utility: Logging

# region Utility: Date handling (no rounding)

function Convert-LastWriteTimeToString {
    param(
        [Parameter(Mandatory)]
        [datetime]$LastWriteTime
    )
    return $LastWriteTime.ToString($HashTblDateFormat)
}

function Convert-StringToLastWriteTime {
    param(
        [Parameter(Mandatory)]
        [string]$LastWriteTimeStr
    )
    return [datetime]::ParseExact($LastWriteTimeStr, $HashTblDateFormat, $null)
}

# endregion Utility: Date handling

# region Utility: Hash filename + compression decision

function Get-ContentAddressedFileName {
    param(
        [Parameter(Mandatory)]
        [string]$Hash,

        [Parameter(Mandatory)]
        [long]$Length,

        [Parameter(Mandatory)]
        [string]$OriginalFullPath,

        [Parameter(Mandatory)]
        [bool]$Compress
    )

    $ext = [IO.Path]::GetExtension($OriginalFullPath)
    $base = "{0}_{1}" -f $Hash, $Length

    if ($Compress) {
        # Use .7z; extension of original is recoverable via DB
        return "$base.7z"
    }
    else {
        # Keep original extension
        return "$base$ext"
    }
}

function Should-CompressFile {
    param(
        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $ext = ([IO.Path]::GetExtension($FullPath)).ToLowerInvariant()

    # Common "already compressed" or poorly compressible formats
    $nonCompressible = @(
        '.zip', '.7z', '.rar',
        '.gz',  '.bz2', '.xz',
        '.mp4', '.mkv', '.mov', '.avi',
        '.mp3', '.aac', '.flac',
        '.jpg', '.jpeg', '.png', '.webp'
    )

    return -not ($nonCompressible -contains $ext)
}

# endregion Utility: Hash filename + compression decision

# region Utility: Hashing and hash recalc frequency

function Should-RecalculateHashes {
    param(
        [Parameter(Mandatory)]
        [string]$FreqCode,   # D/W/M
        [datetime]$LastHashRun
    )

    if (-not $LastHashRun) { return $true }

    $today = Get-Date

    switch ($FreqCode.ToUpperInvariant()) {
        'D' { return ($today.Date -gt $LastHashRun.Date) }
        'W' {
            # Rehash if different calendar week
            $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
            $weekNow  = $cal.GetWeekOfYear($today, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
            $weekLast = $cal.GetWeekOfYear($LastHashRun, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
            return ($today.Year -ne $LastHashRun.Year) -or ($weekNow -ne $weekLast)
        }
        'M' {
            return ($today.Year -ne $LastHashRun.Year) -or ($today.Month -ne $LastHashRun.Month)
        }
        default {
            # Unknown code -> be safe and rehash
            return $true
        }
    }
}

function Get-FileHashSafe {
    param(
        [Parameter(Mandatory)]
        [string]$FullPath
    )

    $h = Get-FileHash -LiteralPath $FullPath -Algorithm $HashAlgorithm
    return $h.Hash
}

# endregion Utility: Hashing

# region Utility: 7-Zip handling

function Ensure-SevenZip {
    param(
        [Parameter(Mandatory)]
        [bool]$Needed,
        [string]$SevenZipPath = $SevenZipPathDefault
    )

    if (-not $Needed) {
        return $null
    }

    if (Test-Path -LiteralPath $SevenZipPath -PathType Leaf) {
        return $SevenZipPath
    }

    Write-Warning "7-Zip not found at '$SevenZipPath'."
    Write-Host "Compression is enabled for at least one backup set."
    Write-Host "Either install 7-Zip or disable compression. Continue without compression? (Y/N)"
    $key = Read-Host
    if ($key -match '^[Yy]') {
        return $null
    }
    else {
        throw "7-Zip is required for compression but is not installed."
    }
}

function Compress-FileWithSevenZip {
    param(
        [Parameter(Mandatory)]
        [string]$SevenZipPath,
        [Parameter(Mandatory)]
        [string]$SourceFile,
        [Parameter(Mandatory)]
        [string]$Destination7z
    )

    $destDir = Split-Path -LiteralPath $Destination7z -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $args = @(
        'a', '-mx=9', '-bso0', '-bsp0',
        "`"$Destination7z`"",
        "`"$SourceFile`""
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SevenZipPath
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        $err = $p.StandardError.ReadToEnd()
        throw "7-Zip compression failed for '$SourceFile' -> '$Destination7z'. ExitCode=$($p.ExitCode). Error: $err"
    }
}

# endregion Utility: 7-Zip handling

# region Utility: DB read/write

function Read-IndexCsv {
    param(
        [Parameter(Mandatory)]
        [string]$IndexPath
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return @()
    }

    $rows = Import-Csv -LiteralPath $IndexPath
    foreach ($r in $rows) {
        if ($r.LastWriteTimeStr) {
            $r | Add-Member -NotePropertyName LastWriteTime -NotePropertyValue (Convert-StringToLastWriteTime $r.LastWriteTimeStr) -Force
        }
        $r | Add-Member -NotePropertyName Length -NotePropertyValue ([long]$r.Length) -Force
    }
    return $rows
}

function Write-IndexCsv {
    param(
        [Parameter(Mandatory)]
        [string]$IndexPath,
        [Parameter(Mandatory)]
        [IEnumerable[object]]$Records
    )

    $dir = Split-Path -LiteralPath $IndexPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $recordsWithStr = foreach ($r in $Records) {
        $clone = [pscustomobject]@{
            RelativePath    = $r.RelativePath
            Hash            = $r.Hash
            Length          = $r.Length
            LastWriteTimeStr= Convert-LastWriteTimeToString $r.LastWriteTime
            BackupFileName  = $r.BackupFileName
        }
        $clone
    }

    $recordsWithStr | Export-Csv -LiteralPath $IndexPath -NoTypeInformation
}

# endregion Utility: DB read/write

# region Core: Snapshot, diff, and backup

function Get-CurrentSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $files = Get-ChildItem -LiteralPath $SourcePath -Recurse -File
    $snapshot = foreach ($f in $files) {
        $rel = Resolve-Path -LiteralPath $f.FullName | ForEach-Object {
            $_.Path.Substring($SourcePath.TrimEnd('\','/') .Length).TrimStart('\','/')
        }

        [pscustomobject]@{
            RelativePath   = $rel
            Hash           = $null      # filled later
            Length         = $f.Length
            LastWriteTime  = $f.LastWriteTime
            BackupFileName = $null      # filled later
        }
    }
    return $snapshot
}

function Compute-HashesForSnapshot {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Snapshot,
        [bool]$ReuseExistingHashes,
        [IEnumerable[object]]$PreviousIndex
    )

    # Build lookup on previous index if reuse allowed
    $prevMap = @{}
    if ($ReuseExistingHashes -and $PreviousIndex) {
        foreach ($p in $PreviousIndex) {
            $key = "{0}|{1}|{2}" -f $p.RelativePath, $p.Length, (Convert-StringToLastWriteTime $p.LastWriteTimeStr).ToString($HashTblDateFormat)
            $prevMap[$key] = $p.Hash
        }
    }

    foreach ($entry in $Snapshot) {
        $key = "{0}|{1}|{2}" -f $entry.RelativePath, $entry.Length, $entry.LastWriteTime.ToString($HashTblDateFormat)
        if ($ReuseExistingHashes -and $prevMap.ContainsKey($key)) {
            $entry.Hash = $prevMap[$key]
        }
        else {
            $full = Join-Path $SourcePath $entry.RelativePath
            $entry.Hash = Get-FileHashSafe -FullPath $full
        }
    }
}

function Diff-Snapshots {
    param(
        [Parameter(Mandatory)]
        [IEnumerable[object]]$OldSnapshot,
        [Parameter(Mandatory)]
        [IEnumerable[object]]$NewSnapshot
    )

    $oldMap = @{}
    foreach ($o in $OldSnapshot) {
        $oldMap[$o.RelativePath] = $o
    }

    $newMap = @{}
    foreach ($n in $NewSnapshot) {
        $newMap[$n.RelativePath] = $n
    }

    $added    = New-Object System.Collections.Generic.List[object]
    $removed  = New-Object System.Collections.Generic.List[object]
    $modified = New-Object System.Collections.Generic.List[object]

    # New & modified
    foreach ($rel in $newMap.Keys) {
        if (-not $oldMap.ContainsKey($rel)) {
            $added.Add($newMap[$rel])
        }
        else {
            $o = $oldMap[$rel]
            $n = $newMap[$rel]

            # Use cheap checks first, then hash
            $changedMeta = ($o.Length -ne $n.Length) -or
                           ($o.LastWriteTime -ne $n.LastWriteTime)

            if ($changedMeta -or ($o.Hash -ne $n.Hash)) {
                $modified.Add($n)
            }
        }
    }

    # Removed
    foreach ($rel in $oldMap.Keys) {
        if (-not $newMap.ContainsKey($rel)) {
            $removed.Add($oldMap[$rel])
        }
    }

    return [pscustomobject]@{
        Added    = $added
        Removed  = $removed
        Modified = $modified
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Apply-BackupForSet {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Set,
        [Parameter(Mandatory)]
        [pscustomobject]$Secrets,
        [string]$SevenZipPathGlobal
    )

    $name        = $Set.Name
    $sourcePath  = (Resolve-Path -LiteralPath $Set.SourcePath).Path
    $backupPath  = (Resolve-Path -LiteralPath $Set.BackupPath).Path
    $changePath  = (Resolve-Path -LiteralPath $Set.ChangePath).Path
    $freq        = $Set.HashRecalcFreq
    $compressSet = [bool]$Set.CompressEnabled

    $logPath     = Join-Path $changePath 'backup.log'
    $log         = New-Logger -LogFile $logPath

    $log "=== Backup set '$name' starting ==="

    Ensure-Directory $backupPath
    Ensure-Directory $changePath

    $rootIndexPath  = Join-Path $changePath 'index.csv'
    $oldSnapshot    = Read-IndexCsv -IndexPath $rootIndexPath

    # Decide if we can reuse hashes
    $lastHashRun = $null
    if ($oldSnapshot -and $oldSnapshot.Count -gt 0) {
        # All share same "run" logically; use max LastWriteTime as heuristic
        $lastHashRun = ($oldSnapshot |
            ForEach-Object { Convert-StringToLastWriteTime $_.LastWriteTimeStr } |
            Measure-Object -Maximum).Maximum
    }
    $reuseHashes = -not (Should-RecalculateHashes -FreqCode $freq -LastHashRun $lastHashRun)
    $log "Reuse existing hashes: $reuseHashes (Freq=$freq, LastHashRun=$lastHashRun)"

    # Current snapshot
    $snapshot = [System.Collections.Generic.List[object]](Get-CurrentSnapshot -SourcePath $sourcePath)
    Compute-HashesForSnapshot -SourcePath $sourcePath -Snapshot $snapshot -ReuseExistingHashes:$reuseHashes -PreviousIndex $oldSnapshot

    # Decide backup filenames
    $needsAnyCompression = $false
    foreach ($entry in $snapshot) {
        if ($compressSet) {
            $compressThis = Should-CompressFile -FullPath (Join-Path $sourcePath $entry.RelativePath)
            if ($compressThis) { $needsAnyCompression = $true }
            $entry.BackupFileName = Get-ContentAddressedFileName -Hash $entry.Hash -Length $entry.Length -OriginalFullPath (Join-Path $sourcePath $entry.RelativePath) -Compress:$compressThis
        }
        else {
            # Mirror mode – use relative path as key; file in backup located at backupPath\RelativePath
            $entry.BackupFileName = $entry.RelativePath
        }
    }

    # Check 7-Zip if any compression is truly needed
    $sevenZipPathLocal = $SevenZipPathGlobal
    if (-not $sevenZipPathLocal -and $needsAnyCompression) {
        $sevenZipPathLocal = Ensure-SevenZip -Needed:$true
    }

    # Diff with old snapshot
    $diff = Diff-Snapshots -OldSnapshot $oldSnapshot -NewSnapshot $snapshot

    $log "Files added:    $($diff.Added.Count)"
    $log "Files modified: $($diff.Modified.Count)"
    $log "Files removed:  $($diff.Removed.Count)"

    # Per-run change folder
    $runStamp     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $runFolder    = Join-Path $changePath $runStamp
    Ensure-Directory $runFolder

    $preRunIndexPath = Join-Path $runFolder 'index_before.csv'
    if ($oldSnapshot) {
        # Preserve pre-run state for this snapshot
        $preRecords = foreach ($r in $oldSnapshot) {
            [pscustomobject]@{
                RelativePath    = $r.RelativePath
                Hash            = $r.Hash
                Length          = [long]$r.Length
                LastWriteTime   = Convert-StringToLastWriteTime $r.LastWriteTimeStr
                BackupFileName  = $r.BackupFileName
            }
        }
        $preRecords | ForEach-Object {
            $_.LastWriteTime = Convert-StringToLastWriteTime $_.LastWriteTime
        }
        # Slight conversion: we stored LastWriteTimeStr already, but for uniformity:
        $tmp = foreach ($r in $preRecords) {
            [pscustomobject]@{
                RelativePath    = $r.RelativePath
                Hash            = $r.Hash
                Length          = $r.Length
                LastWriteTime   = (Convert-StringToLastWriteTime $r.LastWriteTime)
                BackupFileName  = $r.BackupFileName
            }
        }
        # Use Write-IndexCsv expecting LastWriteTime property as datetime
        $tmp | ForEach-Object { $_.LastWriteTime = [datetime]::Parse($_.LastWriteTime) } | Write-IndexCsv -IndexPath $preRunIndexPath
    }

    # 2a: Archive changed/removed previous versions into runFolder
    $previousChangedOrRemoved = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $diff.Modified + $diff.Removed) {
        # Find entry in old snapshot by RelativePath
        $oldEntry = $oldSnapshot | Where-Object { $_.RelativePath -eq $entry.RelativePath }
        if (-not $oldEntry) { continue }

        $previousChangedOrRemoved.Add($oldEntry)
    }

    if ($previousChangedOrRemoved.Count -gt 0) {
        $log "Archiving $($previousChangedOrRemoved.Count) previous versions into change folder '$runFolder'."

        foreach ($e in $previousChangedOrRemoved) {
            $backupKey = $compressSet ? $e.BackupFileName : $e.RelativePath
            $backupFull = if ($compressSet) {
                Join-Path $backupPath $backupKey
            } else {
                Join-Path $backupPath $backupKey
            }

            if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf)) {
                $log "Expected previous backup file missing: $backupFull" 'WARN'
                continue
            }

            $destRel   = $e.RelativePath
            $destFull  = Join-Path $runFolder $destRel
            $destDir   = Split-Path -LiteralPath $destFull -Parent
            Ensure-Directory $destDir

            Copy-Item -LiteralPath $backupFull -Destination $destFull -Force
        }

        # DB for pre-run state is already written above; that plus these archived files allows reconstruction.
    }

    # 2c & 3b: Generate restore script for this run and for "current"
    $restoreScriptPath = Join-Path $runFolder 'Restore-FromSnapshot.ps1'
    $restoreScriptCurrent = Join-Path $backupPath 'Restore-Current.ps1'

    $restoreScriptContent = @"
param(
    [Parameter(Mandatory)]
    [string]`$TargetRoot
)

if (`$TargetRoot -match [regex]::Escape('$sourcePath') -or
    `$TargetRoot -match [regex]::Escape('$changePath') -or
    `$TargetRoot -match [regex]::Escape('$backupPath')) {
    throw 'TargetRoot cannot be inside source, change, or backup directories.'
}

`$indexPath = Join-Path '$runFolder' 'index_before.csv'
`$backupRoot = '$backupPath'
`$compressMode = `$(if ($compressSet) { `$true } else { `$false })

`$index = Import-Csv -LiteralPath `$indexPath

foreach (`$entry in `$index) {
    `$rel = `$entry.RelativePath
    `$destFull = Join-Path `$TargetRoot `$rel
    `$destDir  = Split-Path -LiteralPath `$destFull -Parent
    if (-not (Test-Path -LiteralPath `$destDir)) {
        New-Item -ItemType Directory -Path `$destDir -Force | Out-Null
    }

    if (`$compressMode) {
        `# Files may be compressed as .7z or stored uncompressed with hash_size.ext
        `$backupFileName = `$entry.BackupFileName
        `$backupFull = Join-Path `$backupRoot `$backupFileName
        if (-not (Test-Path -LiteralPath `$backupFull -PathType Leaf)) {
            throw "Missing backup content file: `$backupFull"
        }

        if (`$backupFull.ToLower().EndsWith('.7z')) {
            `# Expect 7z.exe in PATH; for safety, user can adjust this helper
            & 7z x "`$backupFull" -o"`$destDir" -y | Out-Null
            `# Assume single file extracted with correct name from metadata or original
        } else {
            Copy-Item -LiteralPath `$backupFull -Destination `$destFull -Force
        }
    }
    else {
        `$backupFull = Join-Path `$backupRoot `$rel
        if (-not (Test-Path -LiteralPath `$backupFull -PathType Leaf)) {
            throw "Missing backup content file: `$backupFull"
        }
        Copy-Item -LiteralPath `$backupFull -Destination `$destFull -Force
    }
}
"@

    Set-Content -LiteralPath $restoreScriptPath -Value $restoreScriptContent -Encoding UTF8
    Set-Content -LiteralPath $restoreScriptCurrent -Value $restoreScriptContent -Encoding UTF8

    # 3: Apply changes to backup folder to match new snapshot

    # Removed files -> delete from backup
    foreach ($entry in $diff.Removed) {
        $key = $compressSet ? $entry.BackupFileName : $entry.RelativePath
        $backupFull = Join-Path $backupPath $key
        if (Test-Path -LiteralPath $backupFull -PathType Leaf) {
            Remove-Item -LiteralPath $backupFull -Force
            $log "Removed backup file: $backupFull"
        }
    }

    # Added + Modified -> copy into backup
    $toCopy = New-Object System.Collections.Generic.List[object]
    $toCopy.AddRange($diff.Added)
    $toCopy.AddRange($diff.Modified)

    foreach ($entry in $toCopy) {
        $sourceFull = Join-Path $sourcePath $entry.RelativePath

        if ($compressSet) {
            $backupFull = Join-Path $backupPath $entry.BackupFileName
            $compressThis = Should-CompressFile -FullPath $sourceFull

            if ($compressThis -and $sevenZipPathLocal) {
                Compress-FileWithSevenZip -SevenZipPath $sevenZipPathLocal -SourceFile $sourceFull -Destination7z $backupFull
                $log "Compressed & stored: $sourceFull -> $backupFull"
            }
            else {
                Ensure-Directory (Split-Path -LiteralPath $backupFull -Parent)
                Copy-Item -LiteralPath $sourceFull -Destination $backupFull -Force
                $log "Stored (uncompressed CA): $sourceFull -> $backupFull"
            }
        }
        else {
            # Mirror mode
            $backupFull = Join-Path $backupPath $entry.RelativePath
            Ensure-Directory (Split-Path -LiteralPath $backupFull -Parent)
            Copy-Item -LiteralPath $sourceFull -Destination $backupFull -Force
            $log "Backed up: $sourceFull -> $backupFull"
        }
    }

    # 1 & 3a: Update "current" index in change folder root
    Write-IndexCsv -IndexPath $rootIndexPath -Records $snapshot

    $log "=== Backup set '$name' completed successfully ==="
    return $logPath
}

# endregion Core: Snapshot, diff, and backup

# region Entry point: config + email

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file '$ConfigPath' not found. Create it via Export-Clixml with Secrets and BackupSets."
}

$cfg = Import-Clixml -LiteralPath $ConfigPath
$Secrets    = $cfg.Secrets
$BackupSets = $cfg.BackupSets

# Pre-check: do we need 7-Zip for any set?
$needs7zGlobal = $false
foreach ($set in $BackupSets) {
    if ($set.CompressEnabled) { $needs7zGlobal = $true; break }
}
$SevenZipPathGlobal = if ($needs7zGlobal) {
    Ensure-SevenZip -Needed:$true -SevenZipPath $SevenZipPathDefault
} else {
    $null
}

$overallSuccess = $true
$allLogs = New-Object System.Collections.Generic.List[string]

try {
    foreach ($set in $BackupSets) {
        $logPath = Apply-BackupForSet -Set $set -Secrets $Secrets -SevenZipPathGlobal $SevenZipPathGlobal
        $allLogs.Add($logPath)
    }
}
catch {
    $overallSuccess = $false
    Write-Error $_
}

# Email notification
$subject = if ($overallSuccess) { 'Automatic Backup Successful' } else { 'Automatic Backup Failed' }
$body    = if ($overallSuccess) {
    "All backup sets completed successfully.`r`n`r`nLogs:`r`n" + ($allLogs -join "`r`n")
}
else {
    "One or more backup sets failed.`r`n`r`nError:`r`n$($_ | Out-String)"
}

$sendParams = @{
    To         = $Secrets.ToEmail
    From       = $Secrets.FromEmail
    SmtpServer = $SmtpServer
    Port       = $SmtpPort
    Credential = $Secrets.Credential
    Subject    = $subject
    Body       = $body
    UseSsl     = $true
}

Send-MailMessage @sendParams

# endregion Entry point