<#
.SYNOPSIS
    Periodic content-aware backup with change tracking and reconstruct scripts.

.DESCRIPTION
    - Backs up sourcePath to backupPath according to config.
    - Maintains MANIFEST.csv in:
        * sourcePath  (source manifest)
        * backupPath  (backup manifest)
        * each change folder (pre-backup snapshot)
    - For each run:
        * Creates a staging folder under changePath\Temp
        * Moves changed/removed previous data from backup into staging
        * Writes pre-backup MANIFEST.csv into staging
        * Renames staging to final change folder:
              Pre_<FileLabelDate>_<NNNNNN>_Changes
        * Generates RECONSTRUCT.ps1 and RECONSTRUCT.bat in backup and change folders.
    - Avoids copying duplicates by hash+size.
    - Optional compression and content-addressed naming.
    - Sends email on success/failure.

.NOTES
    - Config file: CLIXML with properties:
        * Secrets: ToEmail, FromEmail, Credential
        * BackupSets: array of:
            - Name
            - SourcePath
            - BackupPath
            - ChangePath
            - HashRecalcFreq  (A/E/D/W/M/Y/N)
            - CompressEnabled (bool)
            - PreserveFolderTree (bool)
    - xxHash128: this script includes a stub using SHA256.
      Replace in CalculateFileHash() with your xxHash library.
#>

param(
    [string]$ConfigPath = "$HOME\BackupConfig.xml"
)

$ErrorActionPreference = 'Stop'

# region Core constants

$DatabaseFilename       = 'MANIFEST.csv'
$ReconstructPs1Name     = 'RECONSTRUCT.ps1'
$ReconstructBatName     = 'RECONSTRUCT.bat'
$ReconstructLogName     = 'RECONSTRUCT.log'

$CSVDateFormat          = 'O'    # ISO 8601 round-trip
$FileLabelDateFormat    = "yyyy_MM_dd_HH_mm_ssK" # label in folder and manifest names
$ChangeFolderDateMask   = 'yyyy_MM_dd_HH_mm_ss'  # pattern we look for in change folder names

# Alphabet for short name encoding (base-N over this alphabet)
$Alphabet = @(
    '!', '#', '$', '%', '&', '''', '(', ')', '+', ',', '-', '.', ';', '=', '@',
    '[', ']', '^', '_', '`', '{', '}', '~',
    '0','1','2','3','4','5','6','7','8','9',
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
    'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z'
)

$NonCompressibleExtensions = @(
    '.zip', '.7z', '.rar',
    '.gz',  '.bz2', '.xz',
    '.mp4', '.mkv', '.mov', '.avi',
    '.mp3', '.aac', '.flac',
    '.jpg', '.jpeg', '.png', '.webp'
)

# Default paths for dependencies
$SevenZipDefaultPath = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$FfmpegDefaultPath   = 'ffmpeg.exe' # assume in PATH by default

# endregion

# region Logging

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

# endregion

# region Dependency checks

function Ensure-Dependency {
    param(
        [string]$Name,
        [string]$Path,
        [scriptblock]$InstallHint
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return $Path
    }

    Write-Warning "$Name not found at '$Path'."
    if ($InstallHint) {
        & $InstallHint
    }
    Write-Host "Press Enter to continue without $Name, or Ctrl+C to abort."
    [void](Read-Host)
    return $null
}

# You can extend this to check for xxHash .NET assembly etc.
function Initialize-Dependencies {
    param(
        [bool]$AnyCompressionNeeded,
        [bool]$AnyMediaMetricsNeeded
    )

    $deps = [ordered]@{}

    if ($AnyCompressionNeeded) {
        $deps['7z'] = Ensure-Dependency -Name '7-Zip' -Path $SevenZipDefaultPath -InstallHint {
            Write-Host "Please install 7-Zip from https://www.7-zip.org/ and adjust the path if needed."
        }
    }
    else {
        $deps['7z'] = $null
    }

    if ($AnyMediaMetricsNeeded) {
        $deps['ffmpeg'] = Ensure-Dependency -Name 'ffmpeg' -Path $FfmpegDefaultPath -InstallHint {
            Write-Host "Please install ffmpeg and ensure 'ffmpeg.exe' is in PATH or configure FfmpegDefaultPath."
        }
    }
    else {
        $deps['ffmpeg'] = $null
    }

    # TODO: xxHash .NET assembly check, e.g. K4os.Hash.xxHash
    $deps['xxhash'] = $true # placeholder – assume available or fallback

    return $deps
}

# endregion

# region Short name encoding

function Convert-HexToShortName {
    param(
        [Parameter(Mandatory)]
        [string]$Hex,
        [Parameter(Mandatory)]
        [int]$OutputLength
    )
    # Simplified: interpret hex as big integer, encode to base-$Alphabet.Length
    $base = $Alphabet.Count
    $value = [System.Numerics.BigInteger]::Parse("0$Hex", [System.Globalization.NumberStyles]::AllowHexSpecifier)

    $chars = New-Object System.Collections.Generic.List[string]
    while ($value -gt 0) {
        $remainder = [int]($value % $base)
        $chars.Add($Alphabet[$remainder])
        $value = $value / $base
    }
    if ($chars.Count -eq 0) { $chars.Add($Alphabet[0]) }
    $shortName = -join ($chars.ToArray() | [array]::Reverse([array]$chars.ToArray()))

    if ($shortName.Length -lt $OutputLength) {
        $shortName = $shortName.PadLeft($OutputLength, $Alphabet[0])
    }
    elseif ($shortName.Length -gt $OutputLength) {
        $shortName = $shortName.Substring($shortName.Length - $OutputLength)
    }
    return $shortName
}

function Convert-ShortNameToHex {
    param(
        [Parameter(Mandatory)]
        [string]$ShortName
    )

    $base = $Alphabet.Count
    $value = [System.Numerics.BigInteger]::Zero

    foreach ($ch in $ShortName.ToCharArray()) {
        $idx = $Alphabet.IndexOf($ch)
        if ($idx -lt 0) {
            throw "Invalid character '$ch' in short name."
        }
        $value = $value * $base + $idx
    }

    $hex = $value.ToString('X')
    return $hex
}

function GetFilenameAsHashAndSize {
    param(
        [Parameter(Mandatory)]
        [string]$HashHex,
        [Parameter(Mandatory)]
        [long]$Length,
        [Parameter(Mandatory)]
        [string]$Extension
    )

    # Encode hash as 16-character short name, length as 10-character short name
    $hashShort = Convert-HexToShortName -Hex $HashHex -OutputLength 16
    $lenHex    = ('{0:X}' -f $Length)
    $lenShort  = Convert-HexToShortName -Hex $lenHex -OutputLength 10

    return "$hashShort $lenShort$Extension"
}

function GetExpHashAndSizeFromFilename {
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $name = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $parts = $name -split ' '
    if ($parts.Count -lt 2) {
        throw "Filename '$FileName' does not match expected 'ABC XYZ.ext' format."
    }

    $hashShort = $parts[0]
    $lenShort  = $parts[1]

    $hashHex = Convert-ShortNameToHex -ShortName $hashShort
    $lenHex  = Convert-ShortNameToHex -ShortName $lenShort
    $length  = [System.Numerics.BigInteger]::Parse("0$lenHex", [System.Globalization.NumberStyles]::AllowHexSpecifier)
    return [pscustomobject]@{
        HashHex = $hashHex
        Length  = [long]$length
    }
}

# endregion

# region Hash + date helpers

function Convert-LastWriteTimeToString {
    param([datetime]$LastWriteTime)
    return $LastWriteTime.ToString($CSVDateFormat)
}

function Convert-StringToLastWriteTime {
    param([string]$LastWriteTimeStr)
    return [datetime]::ParseExact($LastWriteTimeStr, $CSVDateFormat, $null)
}

function CalculateFileHash {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    # TODO: Replace with xxHash128 from your chosen .NET library.
    # For now, use SHA256 as a placeholder.
    $h = Get-FileHash -LiteralPath $FilePath -Algorithm SHA256
    return $h.Hash
}

function Should-RecalculateHashes {
    param(
        [Parameter(Mandatory)]
        [string]$FreqCode,
        [datetime]$LastHashRun
    )

    if (-not $LastHashRun) { return $true }
    $today = Get-Date

    switch ($FreqCode.ToUpperInvariant()) {
        'A' { return $true }
        'E' { return $true }
        'D' { return $today.Date -gt $LastHashRun.Date }
        'W' {
            $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
            $weekNow  = $cal.GetWeekOfYear($today, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
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

# region Compression + media metrics

function Should-CompressFile {
    param(
        [Parameter(Mandatory)]
        [string]$FullPath,
        [Parameter(Mandatory)]
        [bool]$CompressEnabled
    )

    if (-not $CompressEnabled) { return $false }

    $ext = [IO.Path]::GetExtension($FullPath).ToLowerInvariant()
    return -not ($NonCompressibleExtensions -contains $ext)
}

function Get-MediaMBPerSec {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$FfmpegPath
    )

    # TODO: Implement actual ffmpeg call, parse duration, compute MB/s.
    # Placeholder: return $null to avoid blocking you.
    return $null
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

    $args = @('a', '-mx=9', '-bso0', '-bsp0', "`"$Destination7z`"", "`"$SourceFile`"")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SevenZipPath
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        $err = $p.StandardError.ReadToEnd()
        throw "7-Zip compression failed for '$SourceFile' -> '$Destination7z'. Error: $err"
    }
}

# endregion

# region Manifest I/O

function Read-Manifest {
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath
    )

    $path = Join-Path $FolderPath $DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }

    $rows = Import-Csv -LiteralPath $path
    foreach ($r in $rows) {
        $r | Add-Member -NotePropertyName Length         -NotePropertyValue ([long]$r.Length) -Force
        $r | Add-Member -NotePropertyName LastWriteTime  -NotePropertyValue (Convert-StringToLastWriteTime $r.LastWriteTimeStr) -Force
    }
    return $rows
}

function Write-Manifest {
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
        [Parameter(Mandatory)]
        [IEnumerable[object]]$Records
    )

    $path = Join-Path $FolderPath $DatabaseFilename
    $dir = Split-Path -LiteralPath $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $out = foreach ($r in $Records) {
        [pscustomobject]@{
            DataPath        = $r.DataPath
            RelativePath    = $r.RelativePath
            Length          = $r.Length
            LastWriteTimeStr= Convert-LastWriteTimeToString $r.LastWriteTime
            xxH2Hash        = $r.xxH2Hash
            Compressed      = $r.Compressed
            StoredAsHashSize= $r.StoredAsHashSize
            Duplicate       = $r.Duplicate
            MediaMBPerSec   = $r.MediaMBPerSec
        }
    }

    $out | Export-Csv -LiteralPath $path -NoTypeInformation
}

# endregion

# region Source database maintenance

function UpdateSourceDatabase {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [string]$FfmpegPath
    )

    $sourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
    $existing = Read-Manifest -FolderPath $sourcePath

    $existingMap = @{}
    foreach ($row in $existing) {
        $existingMap[$row.RelativePath] = $row
    }

    $files = Get-ChildItem -LiteralPath $sourcePath -Recurse -File |
             Where-Object { $_.Name -ne $DatabaseFilename }

    $updated = New-Object System.Collections.Generic.List[object]

    foreach ($f in $files) {
        $rel = $f.FullName.Substring($sourcePath.Length).TrimStart('\','/')
        $prev = $existingMap[$rel]

        $needsHash = $false
        $hashValue = $null
        $mediaMB   = $null

        if ($prev) {
            if ($prev.Length -ne $f.Length -or $prev.LastWriteTime -ne $f.LastWriteTime) {
                $needsHash = $true
            }
            else {
                $hashValue = $prev.xxH2Hash
                $mediaMB   = $prev.MediaMBPerSec
            }
        }
        else {
            $needsHash = $true
        }

        if ($needsHash) {
            $hashValue = CalculateFileHash -FilePath $f.FullName
            $mediaMB   = Get-MediaMBPerSec -FilePath $f.FullName -FfmpegPath $FfmpegPath
        }

        $updated.Add([pscustomobject]@{
            DataPath        = ''          # Not used at source
            RelativePath    = $rel
            Length          = $f.Length
            LastWriteTime   = $f.LastWriteTime
            xxH2Hash        = $hashValue
            Compressed      = ''          # N/A at source
            StoredAsHashSize= ''          # N/A at source
            Duplicate       = 0
            MediaMBPerSec   = $mediaMB
        })
    }

    # Remove entries that no longer exist: already handled by rebuilding from $files only.

    # Sort from longest relative path to shortest
    $sorted = $updated | Sort-Object { $_.RelativePath.Length } -Descending

    # Duplicate detection by hash+size
    $groups = $sorted | Group-Object xxH2Hash, Length
    $nextGroupId = 1
    foreach ($grp in $groups) {
        if ($grp.Count -gt 1) {
            # sort by shortest path first
            $gSorted = $grp.Group | Sort-Object { $_.RelativePath.Length }
            $first   = $gSorted[0]
            $others  = $gSorted[1..($gSorted.Count-1)]
            foreach ($o in $others) {
                $o.Duplicate = 1
            }
            $nextGroupId++
        }
    }

    Write-Manifest -FolderPath $sourcePath -Records $sorted
    return $sorted
}

# endregion

# region Backup copy helpers

function CopySourceFileDataToBackup {
    param(
        [Parameter(Mandatory)]
        [string]$SourceFilePath,
        [Parameter(Mandatory)]
        [string]$BackupFilePath,
        [Parameter(Mandatory)]
        [bool]$ShouldCompress,
        [string]$SevenZipPath
    )

    try {
        if ($ShouldCompress -and $SevenZipPath) {
            Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $SourceFilePath -Destination7z $BackupFilePath
        }
        else {
            $dir = Split-Path -LiteralPath $BackupFilePath -Parent
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

# region Backup DB maintenance & sanitization (skeletons)

function CheckBackedUpDatabase {
    param(
        [Parameter(Mandatory)]
        [string]$FolderRoot,
        [Parameter(Mandatory)]
        [scriptblock]$Log
    )

    $db = Read-Manifest -FolderPath $FolderRoot

    $existingPaths = @{}
    Get-ChildItem -LiteralPath $FolderRoot -Recurse -File |
        Where-Object { $_.Name -ne $DatabaseFilename -and $_.Name -notin @($ReconstructPs1Name,$ReconstructBatName,$ReconstructLogName) } |
        ForEach-Object { $existingPaths[$_.FullName.Substring($FolderRoot.Length).TrimStart('\','/')] = $true }

    foreach ($row in $db) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $rel = $row.DataPath.TrimStart('\','/')
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

function SanitizeChangeDatabase {
    param(
        [Parameter(Mandatory)]
        [string]$ChangeRoot,
        [Parameter(Mandatory)]
        [string]$BackupRoot,
        [Parameter(Mandatory)]
        [scriptblock]$Log
    )

    # For now this is a simple pass-through stub; full de-dup across all change folders
    # is complex and can be layered on later.
    & $Log "SanitizeChangeDatabase is currently a shallow check only." 'INFO'
}

function SanitizeBackupDatabase {
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,
        [Parameter(Mandatory)]
        [bool]$PreserveFolderTree,
        [Parameter(Mandatory)]
        [bool]$CompressEnabled,
        [Parameter(Mandatory)]
        [string]$SevenZipPath,
        [Parameter(Mandatory)]
        [scriptblock]$Log
    )

    # First basic consistency check
    $db = CheckBackedUpDatabase -FolderRoot $BackupRoot -Log $Log

    # TODO: Implement transformation to match current flags
    & $Log "SanitizeBackupDatabase transformation is not fully implemented yet." 'INFO'

    return $db
}

# endregion

# region Reconstruct script generator

function GenerateReconstructScript {
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,
        [Parameter(Mandatory)]
        [string]$ChangeRoot
    )

    $ps1Path = Join-Path $BackupRoot $ReconstructPs1Name
    $batPath = Join-Path $BackupRoot $ReconstructBatName

    $script = @"
param(
    [string]`$TargetRoot
)

if (-not `$TargetRoot) {
    `$TargetRoot = Read-Host 'Enter target folder to reconstruct into'
}

`$BackupRoot = '$BackupRoot'
`$ChangeRoot = '$ChangeRoot'

if (`$TargetRoot -like "`$BackupRoot*"`" -or
    `$TargetRoot -like "`$ChangeRoot*"`") {
    throw 'TargetRoot must be outside backup and change folders.'
}

`$logPath = Join-Path `$TargetRoot '$ReconstructLogName'
New-Item -ItemType Directory -Path `$TargetRoot -Force | Out-Null
"`$(Get-Date -Format 'O') - Reconstruction starting" | Out-File -LiteralPath `$logPath -Encoding UTF8

# TODO: full multi-folder history aggregation as per detailed design.
# For now, reconstruct current backup MANIFEST only.

`$manifestPath = Join-Path `$BackupRoot '$DatabaseFilename'
if (-not (Test-Path -LiteralPath `$manifestPath -PathType Leaf)) {
    throw 'MANIFEST.csv not found in backup root.'
}

`$db = Import-Csv -LiteralPath `$manifestPath

foreach (`$row in `$db) {
    `$rel = `$row.RelativePath
    `$srcData = `$row.DataPath
    if ([string]::IsNullOrWhiteSpace(`$rel)) { continue }

    `$destFull = Join-Path `$TargetRoot `$rel
    `$destDir  = Split-Path -LiteralPath `$destFull -Parent
    if (-not (Test-Path -LiteralPath `$destDir)) {
        New-Item -ItemType Directory -Path `$destDir -Force | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace(`$srcData)) {
        `$srcFull = Join-Path `$BackupRoot `$srcData
        if (-not (Test-Path -LiteralPath `$srcFull -PathType Leaf)) {
            "`$(Get-Date -Format 'O') - Missing data file: `$srcData" | Out-File -LiteralPath `$logPath -Append
            continue
        }
        Copy-Item -LiteralPath `$srcFull -Destination `$destFull -Force
    }
    else {
        "`$(Get-Date -Format 'O') - No data path for: `$rel" | Out-File -LiteralPath `$logPath -Append
    }
}

"`$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath `$logPath -Append
"@

    Set-Content -LiteralPath $ps1Path -Value $script -Encoding UTF8

    $bat = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$ReconstructPs1Name" %*
"@
    Set-Content -LiteralPath $batPath -Value $bat -Encoding ASCII
}

# endregion

# region Core backup routine per set

function Run-BackupSet {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Set,
        [Parameter(Mandatory)]
        [hashtable]$Deps,
        [Parameter(Mandatory)]
        [pscustomobject]$Secrets,
        [Parameter(Mandatory)]
        [ref]$OverallSuccess,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$LogPaths
    )

    $name   = $Set.Name
    $src    = $Set.SourcePath
    $bkp    = $Set.BackupPath
    $chg    = $Set.ChangePath
    $freq   = $Set.HashRecalcFreq
    $compress = [bool]$Set.CompressEnabled
    $preserveTree = [bool]$Set.PreserveFolderTree

    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        Write-Warning "Source path '$src' for set '$name' does not exist. Skipping."
        return
    }

    $srcPath = (Resolve-Path -LiteralPath $src).Path
    $bkpPath = (Resolve-Path -LiteralPath $bkp).Path
    $chgPath = (Resolve-Path -LiteralPath $chg).Path

    if (-not (Test-Path -LiteralPath $bkpPath)) {
        New-Item -ItemType Directory -Path $bkpPath -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $chgPath)) {
        New-Item -ItemType Directory -Path $chgPath -Force | Out-Null
    }

    $logPath = Join-Path $chgPath 'backup.log'
    $log = New-Logger -LogFile $logPath
    $LogPaths.Add($logPath)

    & $log "----- Backup set '$name' starting -----"

    $BackupStagingFolder = Join-Path $chgPath 'Temp'
    if (Test-Path -LiteralPath $BackupStagingFolder) {
        & $log "Staging folder '$BackupStagingFolder' already exists. Previous run may have failed. Skipping set." 'ERROR'
        $OverallSuccess.Value = $false
        return
    }

    $SevenZipPath = $Deps['7z']
    $FfmpegPath   = $Deps['ffmpeg']

    # 1–2: Update source manifest
    & $log "Updating source manifest at '$srcPath'."
    $sourceDb = UpdateSourceDatabase -SourcePath $srcPath -FfmpegPath $FfmpegPath

    # 3: Backup folder existence + DB
    & $log "Sanitizing backup manifest at '$bkpPath'."
    $backupDb = SanitizeBackupDatabase -BackupRoot $bkpPath -PreserveFolderTree $preserveTree -CompressEnabled $compress -SevenZipPath $SevenZipPath -Log $log

    # Determine last hash run (using max LastWriteTime in backup DB as heuristic)
    $lastHashRun = $null
    if ($backupDb -and $backupDb.Count -gt 0) {
        $lastHashRun = ($backupDb | ForEach-Object { $_.LastWriteTime } | Measure-Object -Maximum).Maximum
    }

    $recalc = Should-RecalculateHashes -FreqCode $freq -LastHashRun $lastHashRun
    & $log "HashRecalcFreq=$freq, LastHashRun=$lastHashRun, Recalculate=$recalc"

    # 3b: Create staging folder
    New-Item -ItemType Directory -Path $BackupStagingFolder -Force | Out-Null

    # Copy backup manifest into staging as pre-state
    & $log "Saving pre-backup manifest to staging."
    Write-Manifest -FolderPath $BackupStagingFolder -Records $backupDb

    # Map backup DB by RelativePath
    $backupMap = @{}
    foreach ($row in $backupDb) { $backupMap[$row.RelativePath] = $row }

    # 4: Find new/changed files in source relative to backup
    $sourceMap = @{}
    foreach ($row in $sourceDb) { $sourceMap[$row.RelativePath] = $row }

    $newOrChanged = New-Object System.Collections.Generic.List[object]
    $removedFromSource = New-Object System.Collections.Generic.List[object]

    foreach ($rel in $sourceMap.Keys) {
        $s = $sourceMap[$rel]
        $b = $backupMap[$rel]
        if (-not $b) {
            $newOrChanged.Add($s)
        }
        else {
            if ($s.Length -ne $b.Length -or $s.LastWriteTime -ne $b.LastWriteTime -or $s.xxH2Hash -ne $b.xxH2Hash) {
                $newOrChanged.Add($s)
            }
        }
    }

    foreach ($rel in $backupMap.Keys) {
        if (-not $sourceMap.ContainsKey($rel)) {
            $removedFromSource.Add($backupMap[$rel])
        }
    }

    & $log "New or changed files: $($newOrChanged.Count)"
    & $log "Removed files: $($removedFromSource.Count)"

    $changedCount = 0

    # 4a: Group new/changed by hash+size
    $groups = $newOrChanged | Group-Object xxH2Hash, Length

    foreach ($grp in $groups) {
        $hash = $grp.Group[0].xxH2Hash
        $len  = $grp.Group[0].Length
        $exts = ($grp.Group | ForEach-Object { [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() } | Select-Object -Unique)
        if ($exts.Count -gt 1) {
            & $log "Warning: multiple extensions for hash=$hash len=$len : $($exts -join ', ')" 'WARN'
        }

        $existingBackupWithHash = $backupDb | Where-Object { $_.xxH2Hash -eq $hash -and $_.Length -eq $len }

        foreach ($entry in $grp.Group) {
            $rel = $entry.RelativePath
            $ext = [IO.Path]::GetExtension($rel)

            $storedAsHash = -not $preserveTree
            $compressFlag = Should-CompressFile -FullPath (Join-Path $srcPath $rel) -CompressEnabled $compress

            $dataPath = if ($storedAsHash) {
                $baseName = GetFilenameAsHashAndSize -HashHex $hash -Length $len -Extension (if ($compressFlag) { '.7z' } else { $ext })
                $baseName
            }
            else {
                $rel
            }

            $bRow = $backupMap[$rel]

            if ($existingBackupWithHash) {
                # C: hash already exists in backup – reuse datapath, treat as move or duplicate
                $existingDataPath = $existingBackupWithHash[0].DataPath
                $entryForBackup = [pscustomobject]@{
                    DataPath        = $existingDataPath
                    RelativePath    = $rel
                    Length          = $len
                    LastWriteTime   = $entry.LastWriteTime
                    xxH2Hash        = $hash
                    Compressed      = $existingBackupWithHash[0].Compressed
                    StoredAsHashSize= $existingBackupWithHash[0].StoredAsHashSize
                    Duplicate       = $entry.Duplicate
                    MediaMBPerSec   = $entry.MediaMBPerSec
                }
                $backupMap[$rel] = $entryForBackup
            }
            else {
                # D/E: new content
                $srcFull = Join-Path $srcPath $rel
                $destDataRel = $dataPath
                $destDataFull = Join-Path $bkpPath $destDataRel

                $result = CopySourceFileDataToBackup -SourceFilePath $srcFull -BackupFilePath $destDataFull -ShouldCompress:$compressFlag -SevenZipPath $SevenZipPath
                if ($result -is [string]) {
                    & $log "Failed to copy/compress '$rel' -> '$destDataRel' : $result" 'ERROR'
                    $OverallSuccess.Value = $false
                    continue
                }

                $entryForBackup = [pscustomobject]@{
                    DataPath        = $destDataRel
                    RelativePath    = $rel
                    Length          = $len
                    LastWriteTime   = $entry.LastWriteTime
                    xxH2Hash        = $hash
                    Compressed      = if ($compressFlag) { 'Yes' } else { 'No' }
                    StoredAsHashSize= if ($storedAsHash) { 'Hash' } else { 'Original' }
                    Duplicate       = $entry.Duplicate
                    MediaMBPerSec   = $entry.MediaMBPerSec
                }
                $backupMap[$rel] = $entryForBackup
                $changedCount++
            }
        }
    }

    # F: entries in backup not in source -> move to staging
    foreach ($bk in $removedFromSource) {
        $rel   = $bk.RelativePath
        $data  = $bk.DataPath
        $entry = $backupMap[$rel]
        if ($entry) {
            $backupMap.Remove($rel)
        }

        if (-not [string]::IsNullOrWhiteSpace($data)) {
            $srcDataFull = Join-Path $bkpPath $data
            if (Test-Path -LiteralPath $srcDataFull -PathType Leaf) {
                $destDataFull = Join-Path $BackupStagingFolder $data
                $destDir = Split-Path -LiteralPath $destDataFull -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Move-Item -LiteralPath $srcDataFull -Destination $destDataFull -Force
                $changedCount++
            }
        }
    }

    # G: sort backup DB and save
    $backupDbFinal = $backupMap.Values | Sort-Object { $_.RelativePath.Length } -Descending
    Write-Manifest -FolderPath $bkpPath -Records $backupDbFinal

    # 5: Clean change folder – blank datapaths if files are not in staging
    $stagingDb = Read-Manifest -FolderPath $BackupStagingFolder
    foreach ($row in $stagingDb) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $full = Join-Path $BackupStagingFolder $row.DataPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $row.DataPath = ''
        }
    }
    Write-Manifest -FolderPath $BackupStagingFolder -Records $stagingDb

    # 5A: rename staging to final change folder
    $label = Get-Date -Format $FileLabelDateFormat
    $countLabel = ('{0:D6}' -f [Math]::Min($changedCount, 999999))
    $finalName = "Pre_$label`_${countLabel}_Changes"
    $finalChangeFolder = Join-Path $chgPath $finalName
    Rename-Item -LiteralPath $BackupStagingFolder -NewName $finalName

    # 5B: manifest file already has consistent name (MANIFEST.csv).
    # 5C: generate reconstruct script in backup root and copy into new change folder
    GenerateReconstructScript -BackupRoot $bkpPath -ChangeRoot $chgPath
    Copy-Item -LiteralPath (Join-Path $bkpPath $ReconstructPs1Name) -Destination $finalChangeFolder -Force
    Copy-Item -LiteralPath (Join-Path $bkpPath $ReconstructBatName) -Destination $finalChangeFolder -Force

    & $log "Changed files count = $changedCount"
    & $log "Change folder created: $finalChangeFolder"
    & $log "----- Backup set '$name' completed -----"
}

# endregion

# region Entry point

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file '$ConfigPath' not found."
}

$cfg      = Import-Clixml -LiteralPath $ConfigPath
$Secrets  = $cfg.Secrets
$Sets     = $cfg.BackupSets

$anyCompress = $false
$anyMedia   = $false
foreach ($s in $Sets) {
    if ($s.CompressEnabled) { $anyCompress = $true }
    # if you want ffmpeg metrics always: $anyMedia = $true
}
$deps = Initialize-Dependencies -AnyCompressionNeeded:$anyCompress -AnyMediaMetricsNeeded:$anyMedia

$overallSuccess = $true
$logPaths = New-Object System.Collections.Generic.List[string]

foreach ($set in $Sets) {
    Run-BackupSet -Set $set -Deps $deps -Secrets $Secrets -OverallSuccess ([ref]$overallSuccess) -LogPaths $logPaths
}

# Email notification
$subject = if ($overallSuccess) { 'Automatic Backup Successful' } else { 'Automatic Backup Failed' }
$body = if ($overallSuccess) {
    "All backup sets completed successfully.`r`n`r`nLogs:`r`n" + ($logPaths -join "`r`n")
} else {
    "One or more backup sets encountered errors.`r`n`r`nCheck logs:`r`n" + ($logPaths -join "`r`n")
}

$sendParams = @{
    To         = $Secrets.ToEmail
    From       = $Secrets.FromEmail
    SmtpServer = $Secrets.SmtpServer
    Port       = $Secrets.SmtpPort
    Credential = $Secrets.Credential
    Subject    = $subject
    Body       = $body
    UseSsl     = $true
}
Send-MailMessage @sendParams

# endregion