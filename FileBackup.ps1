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
    - Avoids copying duplicates by hash+size (xxHash128).
    - Optional compression and content-addressed naming.
    - Sends email on success/failure.

.CONFIG FORMAT (CLIXML)
    Backup config file (default: $HOME\BackupConfig.xml) must contain:
        @{ 
            Secrets = @{
                ToEmail     = 'you@example.com'
                FromEmail   = 'backup@example.com'
                SmtpServer  = 'smtp.server'
                SmtpPort    = 587
                Credential  = <PSCredential>  # created elsewhere
            }
            BackupSets = @(
                [pscustomobject]@{
                    Name               = 'MainData'
                    SourcePath         = 'D:\Data'
                    BackupPath         = 'E:\Backups\DataStore'
                    ChangePath         = 'E:\Backups\DataChanges'
                    HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
                    CompressEnabled    = $true
                    PreserveFolderTree = $false   # If $true, mirror tree instead of hash+size naming
                }
            )
        } | Export-Clixml -LiteralPath "$HOME\BackupConfig.xml"

.NOTES
    Dependencies:
        - PowerShellGet / PackageManagement working (for Install-Package).
        - NuGet package K4os.Hash.xxHash (version 1.0.8) – script will prompt to install.
        - 7-Zip at %ProgramFiles%\7-Zip\7z.exe if compression is enabled.
        - ffprobe at C:\ffmpeg\bin\ffprobe.exe for media metrics (optional).
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
$FileLabelDateFormat    = 'yyyy_MM_dd_HH_mm_ss'  # label in folder and manifest names (no zone — Windows paths can't contain ':')
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

$SevenZipDefaultPath = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$FfprobePathDefault  = 'C:\ffmpeg\bin\ffprobe.exe'

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

# region Dependency loading (7z, ffprobe, xxHash via NuGet)

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

function Ensure-K4osHashLibrary {
    param(
        [string]$RequiredVersion = "1.0.8"
    )

    # If already loaded, nothing to do
    if ("K4os.Hash.xxHash.XXH128" -as [type]) {
        return $true
    }

    # Check if package is installed
    $pkg = Get-Package -Name "K4os.Hash.xxHash" -ErrorAction SilentlyContinue

    if (-not $pkg) {
        Write-Host "K4os.Hash.xxHash $RequiredVersion is not installed."
        $resp = Read-Host "Install it now via Install-Package K4os.Hash.xxHash -Version $RequiredVersion? (Y/N)"
        if ($resp -match '^[Yy]') {
            Install-Package K4os.Hash.xxHash -RequiredVersion $RequiredVersion -Force -Scope CurrentUser
        }
        else {
            throw "K4os.Hash.xxHash is required for xxHash128 hashing. Aborting."
        }
    }

    # Re-query after install
    $pkg = Get-Package -Name "K4os.Hash.xxHash" -ErrorAction Stop

    # Locate DLL inside the NuGet package directory
    $installDir = Split-Path $pkg.Source -Parent

    $dll = Get-ChildItem -Path $installDir -Recurse -Filter "K4os.Hash.xxHash.dll" |
           Select-Object -First 1

    if (-not $dll) {
        throw "K4os.Hash.xxHash.dll not found in installed package."
    }

    # Load DLL if not already loaded
    if (-not ("K4os.Hash.xxHash.XXH128" -as [type])) {
        Add-Type -Path $dll.FullName
    }

    return $true
}

function Initialize-Dependencies {
    param(
        [bool]$AnyCompressionNeeded,
        [bool]$AnyMediaMetricsNeeded,
        [scriptblock]$Log
    )

    $deps = [ordered]@{}

    if ($AnyCompressionNeeded) {
        $deps['7z'] = Ensure-Dependency -Name '7-Zip' -Path $SevenZipDefaultPath -InstallHint {
            & $Log "Please install 7-Zip from https://www.7-zip.org/ and adjust the path if needed." 'WARN'
        }
    } else {
        $deps['7z'] = $null
    }

    if ($AnyMediaMetricsNeeded) {
        $deps['ffprobe'] = Ensure-Dependency -Name 'ffprobe' -Path $FfprobePathDefault -InstallHint {
            & $Log "Please install ffmpeg/ffprobe into C:\ffmpeg\bin or adjust the path." 'WARN'
        }
    } else {
        $deps['ffprobe'] = $null
    }

    # Load xxHash library (will prompt if package not installed)
    Ensure-K4osHashLibrary | Out-Null
    $deps['xxhash'] = $true

    return $deps
}

# endregion

# region Short name encoding (hash/size to filename)

function Convert-HexToShortName {
    param(
        [Parameter(Mandatory)]
        [string]$Hex,
        [Parameter(Mandatory)]
        [int]$OutputLength
    )
    $base = $Alphabet.Count
    $value = [System.Numerics.BigInteger]::Parse("0$Hex", [System.Globalization.NumberStyles]::AllowHexSpecifier)

    $chars = New-Object System.Collections.Generic.List[string]
    while ($value -gt 0) {
        $remainder = [int]($value % $base)
        $chars.Add($Alphabet[$remainder])
        $value = $value / $base
    }
    if ($chars.Count -eq 0) { $chars.Add($Alphabet[0]) }
    $array = $chars.ToArray()
    [array]::Reverse($array)
    $shortName = -join $array

    if ($shortName.Length -lt $OutputLength) {
        $shortName = $shortName.PadLeft($OutputLength, $Alphabet[0])
    } elseif ($shortName.Length -gt $OutputLength) {
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

    $hashShort = Convert-HexToShortName -Hex $HashHex -OutputLength 16
    $lenHex    = ('{0:X}' -f $Length)
    $lenShort  = Convert-HexToShortName -Hex $lenHex -OutputLength 10

    return "$hashShort $lenShort$Extension"
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

    if (-not ("K4os.Hash.xxHash.XXH128" -as [type])) {
        Ensure-K4osHashLibrary | Out-Null
    }

    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        $digest = [K4os.Hash.xxHash.XXH128]::DigestOf($stream)
        $hex = '{0:x16}{1:x16}' -f $digest.High, $digest.Low
        return $hex.ToUpperInvariant()
    }
    finally {
        $stream.Dispose()
    }
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
        [string]$FfprobePath
    )

    if (-not $FfprobePath -or -not (Test-Path -LiteralPath $FfprobePath -PathType Leaf)) {
        return $null
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FfprobePath
    $psi.Arguments = "-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 `"$FilePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $output = $p.StandardOutput.ReadToEnd().Trim()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0 -or -not $output) {
        return $null
    }

    [double]$duration = 0
    if (-not [double]::TryParse($output, [ref]$duration)) {
        return $null
    }

    if ($duration -le 0) { return $null }

    $info = Get-Item -LiteralPath $FilePath
    $sizeMB = $info.Length / 1MB
    $mbPerSec = $sizeMB / $duration
    return [Math]::Round($mbPerSec, 3)
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
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        $err = $p.StandardError.ReadToEnd()
        throw "7-Zip compression failed for '$SourceFile' -> '$Destination7z'. Error: $err"
    }
}

function Expand-FileWithSevenZip {
    param(
        [Parameter(Mandatory)]
        [string]$SevenZipPath,
        [Parameter(Mandatory)]
        [string]$Archive,
        [Parameter(Mandatory)]
        [string]$DestinationFile
    )

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $SevenZipPath
        $psi.Arguments = "e `"$Archive`" -o`"$tempDir`" -y"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) {
            $err = $p.StandardError.ReadToEnd()
            throw "7-Zip extraction failed for '$Archive'. Error: $err"
        }

        $extracted = Get-ChildItem -LiteralPath $tempDir -File | Select-Object -First 1
        if (-not $extracted) {
            throw "No file extracted from archive '$Archive'"
        }

        $destDir = Split-Path -LiteralPath $DestinationFile -Parent
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Move-Item -LiteralPath $extracted.FullName -Destination $DestinationFile -Force
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
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
        $r | Add-Member -NotePropertyName Length        -NotePropertyValue ([long]$r.Length) -Force
        $r | Add-Member -NotePropertyName LastWriteTime -NotePropertyValue (Convert-StringToLastWriteTime $r.LastWriteTimeStr) -Force
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
        [string]$FfprobePath
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
            } else {
                $hashValue = $prev.xxH2Hash
                $mediaMB   = $prev.MediaMBPerSec
            }
        } else {
            $needsHash = $true
        }

        if ($needsHash) {
            $hashValue = CalculateFileHash -FilePath $f.FullName
            $mediaMB   = Get-MediaMBPerSec -FilePath $f.FullName -FfprobePath $FfprobePath
        }

        $updated.Add([pscustomobject]@{
            DataPath        = ''
            RelativePath    = $rel
            Length          = $f.Length
            LastWriteTime   = $f.LastWriteTime
            xxH2Hash        = $hashValue
            Compressed      = ''
            StoredAsHashSize= ''
            Duplicate       = 0
            MediaMBPerSec   = $mediaMB
        })
    }

    $sorted = $updated | Sort-Object { $_.RelativePath.Length } -Descending

    $groups = $sorted | Group-Object xxH2Hash, Length
    foreach ($grp in $groups) {
        if ($grp.Count -gt 1) {
            $gSorted = $grp.Group | Sort-Object { $_.RelativePath.Length }
            $others  = $gSorted[1..($gSorted.Count-1)]
            foreach ($o in $others) {
                $o.Duplicate = 1
            }
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
        } else {
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

# region Backup DB maintenance (simplified sanitization)

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

    if (-not (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
        & $Log "Change root '$ChangeRoot' does not exist. Skipping sanitize." 'INFO'
        return
    }

    & $Log "Starting SanitizeChangeDatabase for '$ChangeRoot' and backup '$BackupRoot'." 'INFO'

    $changeFolderRegex = '^Pre_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_.*_Changes$'

    # 1. Discover all change folders
    $changeDirs = Get-ChildItem -LiteralPath $ChangeRoot -Directory |
                  Where-Object { $_.Name -match $changeFolderRegex } |
                  Sort-Object Name  # oldest -> newest

    if (-not $changeDirs -or $changeDirs.Count -eq 0) {
        & $Log "No change folders found under '$ChangeRoot'." 'INFO'
        return
    }

    # 2. Build global index of datapaths by (hash,length)
    $globalMap = @{}  # key: "<hash>|<length>" → list of [pscustomobject]{LocationType, Folder, DataPath, FullPath, IsBackup, FolderOrder}

    $folderOrder = 0
    $backupManifest = @()

    # Helper to add entries to global map
    function Add-ToGlobalMap {
        param(
            [string]$LocationType,  # 'Backup' or 'Change'
            [string]$Folder,
            [object]$Row,
            [int]$FolderOrder
        )
        if ([string]::IsNullOrWhiteSpace($Row.DataPath)) { return }
        if ([string]::IsNullOrWhiteSpace($Row.xxH2Hash)) { return }

        $key = "$($Row.xxH2Hash)|$($Row.Length)"
        $full = Join-Path $Folder $Row.DataPath

        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return
        }

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

    # 2a. Load backup manifest (if any) and index its datapaths
    if (Test-Path -LiteralPath (Join-Path $BackupRoot $DatabaseFilename) -PathType Leaf) {
        $backupManifest = Read-Manifest -FolderPath $BackupRoot
        foreach ($row in $backupManifest) {
            Add-ToGlobalMap -LocationType 'Backup' -Folder $BackupRoot -Row $row -FolderOrder -1
        }
    }

    # 2b. Load each change folder manifest and index datapaths
    $changeManifests = @()
    foreach ($dir in $changeDirs) {
        $folderOrder++
        $manifest = Read-Manifest -FolderPath $dir.FullName
        $changeManifests += [pscustomobject]@{
            Folder   = $dir.FullName
            Name     = $dir.Name
            Order    = $folderOrder     # increasing → newer
            Manifest = $manifest
        }
        foreach ($row in $manifest) {
            Add-ToGlobalMap -LocationType 'Change' -Folder $dir.FullName -Row $row -FolderOrder $folderOrder
        }
    }

    # 3. For each (hash,length) group, select datapath to keep
    foreach ($key in $globalMap.Keys) {
        $entries = $globalMap[$key]

        if ($entries.Count -le 1) {
            continue
        }

        # Prefer backup copy if present
        $backupEntry = $entries | Where-Object { $_.IsBackup } | Select-Object -First 1
        if ($backupEntry) {
            $keeper = $backupEntry
        }
        else {
            # Else keep the newest change-folder copy (highest FolderOrder)
            $keeper = $entries | Where-Object { -not $_.IsBackup } | Sort-Object FolderOrder -Descending | Select-Object -First 1
        }

        # All others are redundant and should be deleted from change folders
        $toDelete = $entries | Where-Object {
            # Never delete the chosen keeper
            $_.FullPath -ne $keeper.FullPath -and -not $_.IsBackup
        }

        foreach ($del in $toDelete) {
            if (Test-Path -LiteralPath $del.FullPath -PathType Leaf) {
                try {
                    Remove-Item -LiteralPath $del.FullPath -Force
                    & $Log "Removed duplicate datapath '$($del.DataPath)' from change folder '$($del.Folder)' (hash/len: $key)." 'INFO'
                }
                catch {
                    & $Log "Failed to remove duplicate datapath '$($del.DataPath)' from '$($del.Folder)': $($_.Exception.Message)" 'ERROR'
                }
            }
        }
    }

    # 4. For each change folder manifest, blank DataPath if file no longer exists in that folder
    foreach ($cm in $changeManifests) {
        $folder   = $cm.Folder
        $manifest = $cm.Manifest
        $changed  = $false

        foreach ($row in $manifest) {
            if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
            $full = Join-Path $folder $row.DataPath
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $row.DataPath = ''   # It exists either in backup folder or newer change folder - reconstruct will use hash
                $changed = $true
            }
        }

        if ($changed) {
            & $Log "Updating MANIFEST in change folder '$folder' after datapath cleanup." 'INFO'
            Write-Manifest -FolderPath $folder -Records $manifest
        }
    }

    & $Log "SanitizeChangeDatabase completed for '$ChangeRoot'." 'INFO'
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

    $db = CheckBackedUpDatabase -FolderRoot $BackupRoot -Log $Log

    # Step 2: Identify rows needing transformation
    $expectedStoredAs = if ($PreserveFolderTree) { 'Original' } else { 'Hash' }
    $rowsNeedingTransform = @()

    foreach ($row in $db) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }

        $shouldCompress = Should-CompressFile -FullPath (Join-Path $BackupRoot $row.RelativePath) -CompressEnabled $CompressEnabled
        $needsTransform = ($row.StoredAsHashSize -ne $expectedStoredAs) -or (($row.Compressed -eq 'Yes') -ne $shouldCompress)

        if ($needsTransform) {
            $rowsNeedingTransform += $row
        }
    }

    # Step 3: Transform each mismatched row
    foreach ($row in $rowsNeedingTransform) {
        $currentDataFull = Join-Path $BackupRoot $row.DataPath
        $shouldCompress = Should-CompressFile -FullPath (Join-Path $BackupRoot $row.RelativePath) -CompressEnabled $CompressEnabled

        # Decompress if currently compressed but should not be
        $workingFile = $currentDataFull
        if ($row.Compressed -eq 'Yes' -and -not $shouldCompress) {
            if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                & $Log "Cannot decompress '$($row.DataPath)': 7-Zip not found. Skipping transformation." 'WARN'
                continue
            }
            $tempDecompressed = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
            try {
                Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $currentDataFull -DestinationFile $tempDecompressed
                $workingFile = $tempDecompressed
            } catch {
                & $Log "Failed to decompress '$($row.DataPath)': $($_.Exception.Message)" 'ERROR'
                continue
            }
        }

        # Compute new DataPath
        if ($expectedStoredAs -eq 'Hash') {
            $ext = if ($shouldCompress) { '.7z' } else { [IO.Path]::GetExtension($row.RelativePath) }
            $newDataPath = GetFilenameAsHashAndSize -HashHex $row.xxH2Hash -Length $row.Length -Extension $ext
        } else {
            $newDataPath = $row.RelativePath
            if ($shouldCompress) { $newDataPath = $row.RelativePath + '.7z' }
        }

        $newDataFull = Join-Path $BackupRoot $newDataPath

        # Skip if already at correct path
        if ($newDataFull -eq $currentDataFull) {
            & $Log "Row '$($row.RelativePath)' already at correct path '$newDataPath'." 'DEBUG'
            continue
        }

        # Copy/compress to new location
        try {
            if ($shouldCompress -and $row.Compressed -ne 'Yes') {
                & $Log "Compressing '$($row.DataPath)' -> '$newDataPath'" 'INFO'
                Compress-FileWithSevenZip -SevenZipPath $SevenZipPath -SourceFile $workingFile -Destination7z $newDataFull
            } else {
                & $Log "Copying '$($row.DataPath)' -> '$newDataPath'" 'INFO'
                $newDir = Split-Path -LiteralPath $newDataFull -Parent
                if (-not (Test-Path -LiteralPath $newDir)) {
                    New-Item -ItemType Directory -Path $newDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $workingFile -Destination $newDataFull -Force
            }

            # Remove old file
            Remove-Item -LiteralPath $currentDataFull -Force
            & $Log "Removed old datapath '$($row.DataPath)' after transformation." 'INFO'

            # Remove temp decompressed file if it was created
            if ($workingFile -ne $currentDataFull) {
                Remove-Item -LiteralPath $workingFile -Force -ErrorAction SilentlyContinue
            }

            # Update row metadata
            $row.DataPath = $newDataPath
            $row.Compressed = if ($shouldCompress) { 'Yes' } else { 'No' }
            $row.StoredAsHashSize = $expectedStoredAs
        } catch {
            & $Log "Failed to transform '$($row.RelativePath)': $($_.Exception.Message)" 'ERROR'
        }
    }

    # Step 4: Log warnings for orphaned data files
    $referencedPaths = @{}
    foreach ($row in $db) {
        if ($row.DataPath) { $referencedPaths[$row.DataPath] = $true }
    }

    $allDataFiles = Get-ChildItem -LiteralPath $BackupRoot -File -Recurse |
        Where-Object { $_.Name -ne $DatabaseFilename -and $_.Name -notmatch '^RECONSTRUCT' }

    foreach ($dataFile in $allDataFiles) {
        $rel = $dataFile.FullName.Substring($BackupRoot.Length).TrimStart('\','/')
        if (-not $referencedPaths[$rel]) {
            & $Log "Orphaned datapath file found (not referenced by manifest): '$rel'" 'WARN'
        }
    }

    # Step 5: Write updated manifest
    Write-Manifest -FolderPath $BackupRoot -Records $db

    & $Log "SanitizeBackupDatabase completed. Transformed $($rowsNeedingTransform.Count) rows." 'INFO'
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

    # Locate Reconstruct.ps1 alongside FileBackup.ps1
    $templatePs1 = Join-Path $PSScriptRoot 'Reconstruct.ps1'
    if (-not (Test-Path -LiteralPath $templatePs1 -PathType Leaf)) {
        throw "Reconstruct.ps1 not found at '$PSScriptRoot'"
    }

    # Prepend hardcoded path bindings to the copy
    $overrides = @(
        "# Auto-generated path bindings (do not edit manually)",
        "`$BackupRootOverride = '$BackupRoot'",
        "`$ChangeRootOverride  = '$ChangeRoot'"
    ) -join "`r`n"

    $content = $overrides + "`r`n`r`n" + (Get-Content -LiteralPath $templatePs1 -Raw)

    $ps1Path = Join-Path $BackupRoot $ReconstructPs1Name
    Set-Content -LiteralPath $ps1Path -Value $content -Encoding UTF8

    $bat = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0$ReconstructPs1Name`" %*"
    Set-Content -LiteralPath (Join-Path $BackupRoot $ReconstructBatName) -Value $bat -Encoding ASCII
}

# endregion

# region Core backup routine per set

function Resolve-BackupSetPaths {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Set
    )

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

    return [pscustomobject]@{
        SrcPath = $srcPath
        BkpPath = $bkpPath
        ChgPath = $chgPath
    }
}

function Initialize-StagingFolder {
    param(
        [Parameter(Mandatory)]
        [string]$ChgPath,
        [Parameter(Mandatory)]
        [scriptblock]$Log
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
    param(
        [Parameter(Mandatory)]
        [object[]]$SourceDb,
        [Parameter(Mandatory)]
        [object[]]$BackupDb
    )

    $sourceMap = @{}
    foreach ($row in $SourceDb) {
        $sourceMap[$row.RelativePath] = $row
    }

    $backupMap = @{}
    foreach ($row in $BackupDb) {
        $backupMap[$row.RelativePath] = $row
    }

    $newOrChanged = New-Object System.Collections.Generic.List[object]
    $removedFromSource = New-Object System.Collections.Generic.List[object]

    foreach ($rel in $sourceMap.Keys) {
        $s = $sourceMap[$rel]
        $b = $backupMap[$rel]
        if (-not $b) {
            $newOrChanged.Add($s)
        } else {
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

    return [pscustomobject]@{
        NewOrChanged = $newOrChanged
        RemovedFromSource = $removedFromSource
    }
}

function Invoke-BackupFileGroup {
    param(
        [Parameter(Mandatory)]
        [object[]]$Group,
        [Parameter(Mandatory)]
        [string]$SrcPath,
        [Parameter(Mandatory)]
        [string]$BkpPath,
        [Parameter(Mandatory)]
        [bool]$PreserveFolderTree,
        [Parameter(Mandatory)]
        [bool]$CompressEnabled,
        [string]$SevenZipPath,
        [Parameter(Mandatory)]
        [object[]]$BackupDb,
        [Parameter(Mandatory)]
        [ref]$BackupMap,
        [Parameter(Mandatory)]
        [ref]$ChangedCount,
        [Parameter(Mandatory)]
        [scriptblock]$Log,
        [Parameter(Mandatory)]
        [ref]$OverallSuccess
    )

    $hash = $Group[0].xxH2Hash
    $len = $Group[0].Length
    $exts = ($Group | ForEach-Object { [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() } | Select-Object -Unique)
    if ($exts.Count -gt 1) {
        & $Log "Multiple extensions for hash=$hash len=$len : $($exts -join ', ')" 'WARN'
    }

    $existingBackupWithHash = $BackupDb | Where-Object { $_.xxH2Hash -eq $hash -and $_.Length -eq $len }

    foreach ($entry in $Group) {
        $rel = $entry.RelativePath
        $ext = [IO.Path]::GetExtension($rel)

        $storedAsHash = -not $PreserveFolderTree
        $compressFlag = Should-CompressFile -FullPath (Join-Path $SrcPath $rel) -CompressEnabled $CompressEnabled

        $dataPath = if ($storedAsHash) {
            $baseName = GetFilenameAsHashAndSize -HashHex $hash -Length $len -Extension (if ($compressFlag) { '.7z' } else { $ext })
            $baseName
        } else {
            $rel
        }

        if ($existingBackupWithHash) {
            $existingDataPath = $existingBackupWithHash[0].DataPath
            $entryForBackup = [pscustomobject]@{
                DataPath = $existingDataPath
                RelativePath = $rel
                Length = $len
                LastWriteTime = $entry.LastWriteTime
                xxH2Hash = $hash
                Compressed = $existingBackupWithHash[0].Compressed
                StoredAsHashSize = $existingBackupWithHash[0].StoredAsHashSize
                Duplicate = $entry.Duplicate
                MediaMBPerSec = $entry.MediaMBPerSec
            }
            $BackupMap.Value[$rel] = $entryForBackup
        } else {
            $srcFull = Join-Path $SrcPath $rel
            $destDataRel = $dataPath
            $destDataFull = Join-Path $BkpPath $destDataRel

            $result = CopySourceFileDataToBackup -SourceFilePath $srcFull -BackupFilePath $destDataFull -ShouldCompress:$compressFlag -SevenZipPath $SevenZipPath
            if ($result -is [string]) {
                & $Log "Failed to copy/compress '$rel' -> '$destDataRel' : $result" 'ERROR'
                $OverallSuccess.Value = $false
                continue
            }

            $entryForBackup = [pscustomobject]@{
                DataPath = $destDataRel
                RelativePath = $rel
                Length = $len
                LastWriteTime = $entry.LastWriteTime
                xxH2Hash = $hash
                Compressed = if ($compressFlag) { 'Yes' } else { 'No' }
                StoredAsHashSize = if ($storedAsHash) { 'Hash' } else { 'Original' }
                Duplicate = $entry.Duplicate
                MediaMBPerSec = $entry.MediaMBPerSec
            }
            $BackupMap.Value[$rel] = $entryForBackup
            $ChangedCount.Value++
        }
    }
}

function Move-RemovedFilesToStaging {
    param(
        [Parameter(Mandatory)]
        [object[]]$RemovedFromSource,
        [Parameter(Mandatory)]
        [string]$BkpPath,
        [Parameter(Mandatory)]
        [string]$StagingFolder,
        [Parameter(Mandatory)]
        [ref]$BackupMap,
        [Parameter(Mandatory)]
        [ref]$ChangedCount,
        [Parameter(Mandatory)]
        [scriptblock]$Log
    )

    foreach ($bk in $RemovedFromSource) {
        $rel = $bk.RelativePath
        $data = $bk.DataPath
        $entry = $BackupMap.Value[$rel]
        if ($entry) {
            $BackupMap.Value.Remove($rel)
        }

        if (-not [string]::IsNullOrWhiteSpace($data)) {
            $srcDataFull = Join-Path $BkpPath $data
            if (Test-Path -LiteralPath $srcDataFull -PathType Leaf) {
                $destDataFull = Join-Path $StagingFolder $data
                $destDir = Split-Path -LiteralPath $destDataFull -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Move-Item -LiteralPath $srcDataFull -Destination $destDataFull -Force
                $ChangedCount.Value++
            }
        }
    }
}

function Finalize-ChangeFolder {
    param(
        [Parameter(Mandatory)]
        [string]$ChgPath,
        [Parameter(Mandatory)]
        [string]$StagingFolder,
        [Parameter(Mandatory)]
        [string]$BkpPath,
        [Parameter(Mandatory)]
        [int]$ChangedCount,
        [Parameter(Mandatory)]
        [scriptblock]$Log
    )

    # Blank DataPaths for files no longer in staging
    $stagingDb = Read-Manifest -FolderPath $StagingFolder
    foreach ($row in $stagingDb) {
        if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
        $full = Join-Path $StagingFolder $row.DataPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            $row.DataPath = ''
        }
    }
    Write-Manifest -FolderPath $StagingFolder -Records $stagingDb

    # Rename staging to final change folder
    $label = Get-Date -Format $FileLabelDateFormat
    $countLabel = ('{0:D6}' -f [Math]::Min($ChangedCount, 999999))
    $finalName = "Pre_$label`_${countLabel}_Changes"
    $finalChangeFolder = Join-Path $ChgPath $finalName
    Rename-Item -LiteralPath $StagingFolder -NewName $finalName

    # Copy reconstruct scripts to change folder
    Copy-Item -LiteralPath (Join-Path $BkpPath $ReconstructPs1Name) -Destination $finalChangeFolder -Force
    Copy-Item -LiteralPath (Join-Path $BkpPath $ReconstructBatName) -Destination $finalChangeFolder -Force

    & $Log "Change folder finalized: $finalChangeFolder"
    return $finalChangeFolder
}

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

    # 1. Resolve paths
    try {
        $paths = Resolve-BackupSetPaths -Set $Set
    } catch {
        Write-Warning $_.Exception.Message
        return
    }

    # 2. Create logger
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

    # 4. Update source manifest
    & $log "Updating source manifest at '$($paths.SrcPath)'."
    $sourceDb = UpdateSourceDatabase -SourcePath $paths.SrcPath -FfprobePath $Deps['ffprobe']

    # 5. Sanitize backup manifest
    & $log "Sanitizing backup manifest at '$($paths.BkpPath)'."
    $backupDb = SanitizeBackupDatabase -BackupRoot $paths.BkpPath -PreserveFolderTree ([bool]$Set.PreserveFolderTree) -CompressEnabled ([bool]$Set.CompressEnabled) -SevenZipPath $Deps['7z'] -Log $log

    # 6. Hash recalc decision
    $lastHashRun = $null
    if ($backupDb -and $backupDb.Count -gt 0) {
        $lastHashRun = ($backupDb | ForEach-Object { $_.LastWriteTime } | Measure-Object -Maximum).Maximum
    }
    $recalc = Should-RecalculateHashes -FreqCode $Set.HashRecalcFreq -LastHashRun $lastHashRun
    & $log "HashRecalcFreq=$($Set.HashRecalcFreq), LastHashRun=$lastHashRun, Recalculate=$recalc"

    # 7. Write pre-backup manifest to staging
    & $log "Saving pre-backup manifest to staging '$stagingFolder'."
    Write-Manifest -FolderPath $stagingFolder -Records $backupDb

    # 8. Diff
    $diff = Compare-SourceToBackup -SourceDb $sourceDb -BackupDb $backupDb
    & $log "New or changed files: $($diff.NewOrChanged.Count)"
    & $log "Removed files: $($diff.RemovedFromSource.Count)"

    # 9. Build working backup map
    $backupMap = @{}
    foreach ($row in $backupDb) { $backupMap[$row.RelativePath] = $row }
    $changedCount = 0

    # 10. Copy new/changed files
    $groups = $diff.NewOrChanged | Group-Object xxH2Hash, Length
    foreach ($grp in $groups) {
        Invoke-BackupFileGroup `
            -Group $grp.Group `
            -SrcPath $paths.SrcPath `
            -BkpPath $paths.BkpPath `
            -PreserveFolderTree ([bool]$Set.PreserveFolderTree) `
            -CompressEnabled ([bool]$Set.CompressEnabled) `
            -SevenZipPath $Deps['7z'] `
            -BackupDb $backupDb `
            -BackupMap ([ref]$backupMap) `
            -ChangedCount ([ref]$changedCount) `
            -Log $log `
            -OverallSuccess $OverallSuccess
    }

    # 11. Move removed files to staging
    Move-RemovedFilesToStaging `
        -RemovedFromSource $diff.RemovedFromSource `
        -BkpPath $paths.BkpPath `
        -StagingFolder $stagingFolder `
        -BackupMap ([ref]$backupMap) `
        -ChangedCount ([ref]$changedCount) `
        -Log $log

    # 12. Save updated backup manifest
    $backupDbFinal = $backupMap.Values | Sort-Object { $_.RelativePath.Length } -Descending
    Write-Manifest -FolderPath $paths.BkpPath -Records $backupDbFinal

    # 13. Finalize change folder
    GenerateReconstructScript -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath
    $finalChangeFolder = Finalize-ChangeFolder `
        -ChgPath $paths.ChgPath `
        -StagingFolder $stagingFolder `
        -BkpPath $paths.BkpPath `
        -ChangedCount $changedCount `
        -Log $log

    # 14. Sanitize change databases
    SanitizeChangeDatabase -ChangeRoot $paths.ChgPath -BackupRoot $paths.BkpPath -Log $log

    & $log "Changed files count = $changedCount"
    & $log "----- Backup set '$($Set.Name)' completed -----"
}

# endregion

# region Entry point

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file '$ConfigPath' not found."
}

$cfg      = Import-Clixml -LiteralPath $ConfigPath
$Secrets  = $cfg.Secrets
$Sets     = $cfg.BackupSets

# Temporary logger just for dependency messages
$globalLogPath = Join-Path ([IO.Path]::GetDirectoryName($ConfigPath)) 'Backup_Global.log'
$globalLog     = New-Logger -LogFile $globalLogPath

$anyCompress = $false
$anyMedia   = $false
foreach ($s in $Sets) {
    if ($s.CompressEnabled) { $anyCompress = $true }
    # If you want ffprobe always active, set $anyMedia = $true
}

$deps = Initialize-Dependencies -AnyCompressionNeeded:$anyCompress -AnyMediaMetricsNeeded:$anyMedia -Log $globalLog

$overallSuccess = $true
$logPaths = New-Object System.Collections.Generic.List[string]

foreach ($set in $Sets) {
    Run-BackupSet -Set $set -Deps $deps -Secrets $Secrets -OverallSuccess ([ref]$overallSuccess) -LogPaths $logPaths
}

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