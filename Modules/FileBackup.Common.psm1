<#
.SYNOPSIS
    FileBackup shared core — restore-safe primitives.

.DESCRIPTION
    This module holds every primitive that BOTH the backup engine (FileBackup.ps1)
    and the standalone restore script (Reconstruct.ps1) need:

        * Logging
        * xxHash128 library loading + file hashing
        * Manifest date (de)serialization
        * Short-name (hash/size -> filename) encoding
        * 7-Zip compress / expand
        * MANIFEST.csv read / write
        * Shared defaults (filenames, alphabet, date formats, tool paths)

    It must stay dependency-free beyond the System.IO.Hashing NuGet package and
    7-Zip, because New-ReconstructScript (in FileBackup.Engine.psm1) copies this
    file alongside Reconstruct.ps1 into every backup/change folder so that a
    restore works with nothing but the backup folder present.

    Anything specific to *producing* a backup lives in FileBackup.Engine.psm1.
#>

# region Shared defaults

$script:DatabaseFilename      = 'MANIFEST.csv'
# Witness sidecar for the manifest (SR-038): row count + byte length + xxHash128 of
# MANIFEST.csv exactly as written, so a restore can tell a truncated/replaced index
# from a genuinely small job. Written only by Write-Manifest, so it cannot drift.
$script:WitnessFilename       = 'MANIFEST.csv.meta'
$script:WitnessFormatVersion  = 1
$script:ReconstructPs1Name    = 'RECONSTRUCT.ps1'
$script:ReconstructBatName    = 'RECONSTRUCT.bat'
$script:ReconstructShName     = 'reconstruct.sh'
$script:ReconstructLogName    = 'RECONSTRUCT.log'
$script:CommonModuleName      = 'FileBackup.Common.psm1'

$script:CSVDateFormat         = 'O'                       # ISO 8601 round-trip
$script:FileLabelDateFormat   = 'yyyy_MM_dd_HH_mm_ss'     # label in folder/manifest names (no ':' — invalid in Windows paths)
$script:ChangeFolderDateMask  = 'yyyy_MM_dd_HH_mm_ss'     # pattern used in snapshot-folder names
# Dated point-in-time snapshots (SR-005/SR-028): a folder Snapshot_<date> preserves
# the state of the backup whose completion date it is named for. The latest state
# is the live backup root (no snapshot folder). Replaces the previous change-folder model.
$script:SnapshotPrefix        = 'Snapshot_'
$script:ChangeFolderRegex     = '^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}'

# Alphabet for short-name encoding (base-N over these glyphs)
$script:Alphabet = @(
    '!', '#', '$', '%', '&', '''', '(', ')', '+', ',', '-', '.', ';', '=', '@',
    '[', ']', '^', '_', '`', '{', '}', '~',
    '0','1','2','3','4','5','6','7','8','9',
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
    'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z'
)

# The ONE definition of "already compressed / opaque" (SR-004). Test-ShouldCompress
# is its only reader, and README/AGENTS quote this list rather than restating it.
# Extended 2026-08-23 (WP5) with the eight entries the HomeHub deployer's list
# carried and this one did not. Office/text formats are deliberately NOT here:
# SN-003's acceptance line says a .docx / .txt IS stored as .7z, which is a
# stakeholder decision, not an oversight.
$script:NonCompressibleExtensions = @(
    '.zip', '.7z', '.rar',
    '.gz',  '.bz2', '.xz',  '.tgz', '.zst',
    '.mp4', '.mkv', '.mov', '.avi', '.webm',
    '.mp3', '.aac', '.flac', '.ogg',
    '.jpg', '.jpeg', '.png', '.webp', '.gif',
    # Container/archive formats that are already deflate-compressed inside.
    '.jar', '.pack',
    # Emulator/game save states — routinely already packed, and large.
    '.sav'
)

# Tool defaults are intentionally resolved at import time so callers receive one
# stable value for the run. Environment overrides are the container-friendly
# contract; platform defaults and PATH discovery keep local use zero-config.
# Implements: SR-037, LLR-037 (guarded — never throws on a non-Windows host)
$script:SevenZipDefaultPath = $env:FILEBACKUP_7ZIP_PATH
if ([string]::IsNullOrWhiteSpace($script:SevenZipDefaultPath) -and $IsWindows -and $env:ProgramFiles) {
    $script:SevenZipDefaultPath = [System.IO.Path]::Combine($env:ProgramFiles, '7-Zip', '7z.exe')
}
if ([string]::IsNullOrWhiteSpace($script:SevenZipDefaultPath) -or
    -not (Test-Path -LiteralPath $script:SevenZipDefaultPath -PathType Leaf)) {
    $sevenZipCommand = Get-Command -Name '7z','7zz','7za' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($sevenZipCommand) { $script:SevenZipDefaultPath = $sevenZipCommand.Path }
}

$script:FfprobePathDefault = $env:FILEBACKUP_FFPROBE_PATH
if ([string]::IsNullOrWhiteSpace($script:FfprobePathDefault) -and $IsWindows) {
    $script:FfprobePathDefault = 'C:\ffmpeg\bin\ffprobe.exe'
}
if ([string]::IsNullOrWhiteSpace($script:FfprobePathDefault) -or
    -not (Test-Path -LiteralPath $script:FfprobePathDefault -PathType Leaf)) {
    $ffprobeCommand = Get-Command -Name 'ffprobe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($ffprobeCommand) { $script:FfprobePathDefault = $ffprobeCommand.Path }
}

function Get-FileBackupDefaults {
    <#
    .SYNOPSIS
        Returns the shared constants as a hashtable so callers (engine, restore,
        tests) read them from one place instead of redefining them.
    #>
    [CmdletBinding()]
    param()
    return @{
        DatabaseFilename         = $script:DatabaseFilename
        WitnessFilename          = $script:WitnessFilename
        WitnessFormatVersion     = $script:WitnessFormatVersion
        ReconstructPs1Name       = $script:ReconstructPs1Name
        ReconstructBatName       = $script:ReconstructBatName
        ReconstructShName        = $script:ReconstructShName
        ReconstructLogName       = $script:ReconstructLogName
        CommonModuleName         = $script:CommonModuleName
        CSVDateFormat            = $script:CSVDateFormat
        FileLabelDateFormat      = $script:FileLabelDateFormat
        ChangeFolderDateMask     = $script:ChangeFolderDateMask
        ChangeFolderRegex        = $script:ChangeFolderRegex
        SnapshotPrefix           = $script:SnapshotPrefix
        Alphabet                 = $script:Alphabet
        NonCompressibleExtensions= $script:NonCompressibleExtensions
        SevenZipDefaultPath      = $script:SevenZipDefaultPath
        FfprobePathDefault       = $script:FfprobePathDefault
    }
}

# endregion

# region Logging

function New-Logger {
    <#
    .SYNOPSIS
        Returns a scriptblock logger that appends "<ts> [LEVEL] <msg>" to a file
        and echoes to the host. Call as: & $log 'message' 'LEVEL'.
    #>
    [CmdletBinding()]
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
    }.GetNewClosure()
}

# endregion

# region xxHash128 + file hashing
#
# Uses Microsoft's System.IO.Hashing.XxHash128 (NuGet). PowerShell 7+ only — on
# .NET Core the System.Memory dependency is built in, so no transitive DLLs are
# needed. The historical K4os.Hash.xxHash package never shipped an XXH128 type,
# so this is a deliberate replacement (see CHANGELOG).

$script:XxHashPackageName    = 'System.IO.Hashing'
$script:XxHashPackageVersion = '8.0.0'
$script:XxHashDllName        = 'System.IO.Hashing.dll'

function Initialize-XxHashLibrary {
    <#
    .SYNOPSIS
        Ensures System.IO.Hashing.XxHash128 is loaded. Prefers a DLL bundled next
        to this module (so a standalone restore from a backup folder works), then
        falls back to the NuGet package cache, installing it if needed.
    .PARAMETER BundledDllDir
        Directory to probe for a bundled System.IO.Hashing.dll. Defaults to the
        module's own folder.
    .PARAMETER NonInteractive
        Never prompt (scheduled/unattended runs). If the package is missing and
        -AutoInstall is not set, throw with remediation guidance instead of
        blocking on a Read-Host. Implements: SR-016, SR-019.
    .PARAMETER AutoInstall
        With -NonInteractive, install the missing package automatically rather
        than failing.
    #>
    # Implements: SR-002, SR-019, LLR-002
    [CmdletBinding()]
    param(
        [string]$BundledDllDir = $PSScriptRoot,
        [string]$RequiredVersion = $script:XxHashPackageVersion,
        [switch]$NonInteractive,
        [switch]$AutoInstall
    )

    if ('System.IO.Hashing.XxHash128' -as [type]) {
        return $true
    }

    # 1. Bundled DLL alongside the module (standalone restore path).
    if ($BundledDllDir) {
        $bundled = Join-Path $BundledDllDir $script:XxHashDllName
        if (Test-Path -LiteralPath $bundled -PathType Leaf) {
            Add-Type -Path $bundled
            if ('System.IO.Hashing.XxHash128' -as [type]) { return $true }
        }
    }

    # 2. NuGet package cache (install on first use if absent).
    $pkg = Get-Package -Name $script:XxHashPackageName -ErrorAction SilentlyContinue
    if (-not $pkg) {
        $installCmd = "Install-Package $($script:XxHashPackageName) -RequiredVersion $RequiredVersion -Scope CurrentUser"
        if ($NonInteractive) {
            # SR-016: an unattended run must never block on an interactive prompt.
            if ($AutoInstall) {
                Write-Host "$($script:XxHashPackageName) $RequiredVersion not installed; auto-installing (non-interactive)."
                Install-Package $script:XxHashPackageName -RequiredVersion $RequiredVersion -Force -Scope CurrentUser | Out-Null
            }
            else {
                throw ("$($script:XxHashPackageName) $RequiredVersion is required for xxHash128 hashing and is not " +
                    "installed. Run '$installCmd' (or tests\Setup.ps1 -InstallDeps -NonInteractive), bundle " +
                    "$($script:XxHashDllName) next to the module, or re-run with -AutoInstall.")
            }
        }
        else {
            Write-Host "$($script:XxHashPackageName) $RequiredVersion is not installed."
            $resp = Read-Host "Install it now via $installCmd ? (Y/N)"
            if ($resp -match '^[Yy]') {
                Install-Package $script:XxHashPackageName -RequiredVersion $RequiredVersion -Force -Scope CurrentUser | Out-Null
            }
            else {
                throw "$($script:XxHashPackageName) is required for xxHash128 hashing. Aborting."
            }
        }
    }

    $pkg     = Get-Package -Name $script:XxHashPackageName -ErrorAction Stop
    $libRoot = Join-Path (Split-Path $pkg.Source -Parent) 'lib'

    # Prefer a modern .NET build; netstandard2.0 is the universal fallback.
    $dll = $null
    foreach ($tfm in 'net8.0','net7.0','net6.0','netstandard2.0') {
        $candidate = Join-Path $libRoot (Join-Path $tfm $script:XxHashDllName)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $dll = $candidate; break }
    }
    if (-not $dll) {
        throw "$($script:XxHashDllName) not found in installed package under '$libRoot'."
    }

    Add-Type -Path $dll
    return $true
}

function Get-XxHashDllPath {
    <#
    .SYNOPSIS
        Resolves the path to a System.IO.Hashing.dll to bundle into a backup
        folder for standalone restore. Returns $null if it cannot be located.
    #>
    # Implements: SR-007, LLR-007
    [CmdletBinding()]
    param()

    # Prefer one already bundled next to the module.
    if ($PSScriptRoot) {
        $bundled = Join-Path $PSScriptRoot $script:XxHashDllName
        if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    }

    $pkg = Get-Package -Name $script:XxHashPackageName -ErrorAction SilentlyContinue
    if (-not $pkg) { return $null }
    $libRoot = Join-Path (Split-Path $pkg.Source -Parent) 'lib'
    foreach ($tfm in 'netstandard2.0','net6.0','net7.0','net8.0') {
        $candidate = Join-Path $libRoot (Join-Path $tfm $script:XxHashDllName)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-FileXxHash {
    <#
    .SYNOPSIS
        Computes the xxHash128 of a file as a 32-char uppercase hex string
        (big-endian, matching System.IO.Hashing's canonical output).
    #>
    # Implements: SR-002, LLR-002
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not ('System.IO.Hashing.XxHash128' -as [type])) {
        Initialize-XxHashLibrary | Out-Null
    }

    $hasher = [System.IO.Hashing.XxHash128]::new()
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
        $hasher.Append($stream)
    }
    finally {
        $stream.Dispose()
    }
    $bytes = $hasher.GetCurrentHash()
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToUpperInvariant()
}

# endregion

# region Manifest date (de)serialization

function ConvertTo-ManifestDateString {
    # Implements: SR-025, LLR-025
    [CmdletBinding()]
    param([datetime]$LastWriteTime)
    return $LastWriteTime.ToString($script:CSVDateFormat)
}

function ConvertFrom-ManifestDateString {
    [CmdletBinding()]
    param([string]$LastWriteTimeStr)
    return [datetime]::ParseExact($LastWriteTimeStr, $script:CSVDateFormat, $null)
}

# endregion

# region Short-name encoding (hash/size <-> filename)

function Convert-HexToShortName {
    # Implements: SR-003, LLR-003
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Hex,
        [Parameter(Mandatory)][int]$OutputLength
    )
    $base  = $script:Alphabet.Count
    $value = [System.Numerics.BigInteger]::Parse("0$Hex", [System.Globalization.NumberStyles]::AllowHexSpecifier)

    $chars = New-Object System.Collections.Generic.List[string]
    while ($value -gt 0) {
        $remainder = [int]($value % $base)
        $chars.Add($script:Alphabet[$remainder])
        $value = $value / $base
    }
    if ($chars.Count -eq 0) { $chars.Add($script:Alphabet[0]) }
    $array = $chars.ToArray()
    [array]::Reverse($array)
    $shortName = -join $array

    if ($shortName.Length -lt $OutputLength) {
        $shortName = $shortName.PadLeft($OutputLength, $script:Alphabet[0])
    } elseif ($shortName.Length -gt $OutputLength) {
        $shortName = $shortName.Substring($shortName.Length - $OutputLength)
    }
    return $shortName
}

function Convert-ShortNameToHex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ShortName)

    $base  = $script:Alphabet.Count
    $value = [System.Numerics.BigInteger]::Zero
    foreach ($ch in $ShortName.ToCharArray()) {
        $idx = $script:Alphabet.IndexOf([string]$ch)
        if ($idx -lt 0) { throw "Invalid character '$ch' in short name." }
        $value = $value * $base + $idx
    }
    return $value.ToString('X')
}

function Get-HashSizeFileName {
    <#
    .SYNOPSIS
        Builds the content-addressed data filename "<hashShort> <lenShort><ext>".
    #>
    # Implements: SR-003, SR-021, LLR-003, LLR-021
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HashHex,
        [Parameter(Mandatory)][long]$Length,
        [Parameter(Mandatory)][string]$Extension
    )
    $hashShort = Convert-HexToShortName -Hex $HashHex -OutputLength 16
    $lenHex    = ('{0:X}' -f $Length)
    $lenShort  = Convert-HexToShortName -Hex $lenHex -OutputLength 10
    return "$hashShort $lenShort$Extension"
}

# endregion

# region Compression + expansion

function Test-ShouldCompress {
    <#
    .SYNOPSIS
        True when compression is enabled and the file's extension is not already
        a compressed/opaque format. Only the extension of -FileName is inspected.
    #>
    # Implements: SR-004, LLR-004
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][bool]$CompressEnabled
    )
    if (-not $CompressEnabled) { return $false }
    $ext = [IO.Path]::GetExtension($FileName).ToLowerInvariant()
    return -not ($script:NonCompressibleExtensions -contains $ext)
}

function Compress-FileWithSevenZip {
    # Implements: SR-004, LLR-004
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SevenZipPath,
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter(Mandatory)][string]$Destination7z
    )
    $destDir = [System.IO.Path]::GetDirectoryName($Destination7z)
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $argList = @('a', '-mx=9', '-bso0', '-bsp0', "`"$Destination7z`"", "`"$SourceFile`"")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $SevenZipPath
    $psi.Arguments = $argList -join ' '
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        $err = $p.StandardError.ReadToEnd()
        throw "7-Zip compression failed for '$SourceFile' -> '$Destination7z'. Error: $err"
    }
}

function Expand-FileWithSevenZip {
    <#
    .SYNOPSIS
        Extracts the single payload file from a .7z archive to -DestinationFile.
    #>
    # Implements: SR-008, LLR-008
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SevenZipPath,
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$DestinationFile
    )
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = $SevenZipPath
        $psi.Arguments = "e `"$Archive`" -o`"$tempDir`" -y"
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow         = $true

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

        $destDir = [System.IO.Path]::GetDirectoryName($DestinationFile)
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

function Resolve-ExistingAncestor {
    <#
    .SYNOPSIS
        Returns the nearest existing ancestor of a path (the path itself when it
        exists), so a volume can be interrogated for a target that has not been
        created yet.
    .PARAMETER Path
        Any path, existing or not.
    .OUTPUTS
        [string] an existing path, or $null when even the root does not exist.
    #>
    # Implements: SR-052, SR-023, LLR-052
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    try { $probe = [System.IO.Path]::GetFullPath($Path) } catch { return $null }
    while ($probe) {
        if (Test-Path -LiteralPath $probe) { return $probe }
        $parent = [System.IO.Path]::GetDirectoryName($probe)
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $probe) { return $null }
        $probe = $parent
    }
    return $null
}

function Get-FreeSpaceBytes {
    <#
    .SYNOPSIS
        Free bytes on the volume that contains a path, measured the same way on
        Windows and on Linux (SR-052). Never throws.

    .DESCRIPTION
        Lives in Common because the restore kit consumes it and must stay
        self-contained (AGENTS.md §2).

        Replaces `Get-PSDrive -Name (Split-Path -Qualifier $path)`, which cannot
        resolve a rooted POSIX path: `Split-Path -Qualifier '/backup'` throws,
        and Reconstruct.ps1's adjacent catch swallowed it, so the SR-023 restore
        capacity check was SILENTLY INERT on Linux and in the container while
        bash/reconstruct.sh's `df -P -B1` worked.

        System.IO.DriveInfo answers for both platforms (a drive root on Windows,
        the containing mount on Unix). Get-PSDrive remains as the fallback for a
        drive-qualified Windows path. A path that does not exist yet is resolved
        to its nearest existing ancestor first, so a restore target can be
        measured before it is created.

    .PARAMETER Path
        The path whose volume is measured.

    .OUTPUTS
        [long] free bytes, or $null when neither mechanism can answer — the
        caller then SKIPS the check rather than refusing (an unmeasurable volume
        is not evidence of a full one).
    #>
    # Implements: SR-052, SR-023, LLR-052, LLR-023
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $probe = Resolve-ExistingAncestor -Path $Path
    if (-not $probe) { return $null }

    try {
        $drive = [System.IO.DriveInfo]::new($probe)
        if ($drive.IsReady) { return [long]$drive.AvailableFreeSpace }
    } catch {
        Write-Verbose "DriveInfo could not measure '$probe': $($_.Exception.Message)"
    }

    try {
        $root = [System.IO.Path]::GetPathRoot($probe)
        if ($root -match '^([A-Za-z]):') {
            $psDrive = Get-PSDrive -Name $Matches[1] -ErrorAction Stop
            if ($null -ne $psDrive.Free) { return [long]$psDrive.Free }
        }
    } catch {
        Write-Verbose "Get-PSDrive could not measure '$probe': $($_.Exception.Message)"
    }
    return $null
}

function Get-VolumeIdentity {
    <#
    .SYNOPSIS
        A stable key naming the volume that contains a path, so two paths can be
        told apart as "same volume" (a move is a rename) or "different volumes"
        (a move is a copy, and costs bytes) — SR-052. Never throws.
    .DESCRIPTION
        On Windows this is the drive root; on Linux it is the containing MOUNT
        POINT, which is what matters in the container where /backup and /changes
        are separate binds under one filesystem root.
    .PARAMETER Path
        The path whose volume is identified.
    .OUTPUTS
        [string] the volume key, or $null when it cannot be determined.
    #>
    # Implements: SR-052, LLR-052
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $probe = Resolve-ExistingAncestor -Path $Path
    if (-not $probe) { return $null }
    try { return [System.IO.DriveInfo]::new($probe).Name } catch { return $null }
}

function Read-Manifest {
    <#
    .SYNOPSIS
        Reads MANIFEST.csv from a folder, typing Length as [long] and adding a
        parsed [datetime] LastWriteTime member. Returns @() when absent.
    #>
    # Implements: SR-025, LLR-025
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath
    )
    $path = Join-Path $FolderPath $script:DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @()
    }

    $rows = Import-Csv -LiteralPath $path
    foreach ($r in $rows) {
        $r | Add-Member -NotePropertyName Length        -NotePropertyValue ([long]$r.Length) -Force
        $r | Add-Member -NotePropertyName LastWriteTime -NotePropertyValue (ConvertFrom-ManifestDateString $r.LastWriteTimeStr) -Force
    }
    return $rows
}

function Write-Manifest {
    <#
    .SYNOPSIS
        Writes the canonical 9-column MANIFEST.csv to a folder, then stamps its
        witness sidecar so the index can be proven intact at restore time.
    .NOTES
        Sole writer of MANIFEST.csv.meta (SR-038) — every origin is covered here
        rather than in the callers, so the witness cannot drift from its manifest.
    #>
    # Implements: SR-025, SR-038, LLR-025, LLR-038
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        # B5/found: was [IEnumerable[object]] (not a valid accelerator). [object[]]
        # coerces List<object>, arrays, and hashtable .Values alike. AllowNull
        # because a function returning @() yields $null when captured.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Records
    )
    if ($null -eq $Records) { $Records = @() }
    $path = Join-Path $FolderPath $script:DatabaseFilename
    $dir  = [System.IO.Path]::GetDirectoryName($path)
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $out = foreach ($r in $Records) {
        [pscustomobject]@{
            DataPath         = $r.DataPath
            RelativePath     = $r.RelativePath
            Length           = $r.Length
            LastWriteTimeStr = ConvertTo-ManifestDateString $r.LastWriteTime
            xxH2Hash         = $r.xxH2Hash
            Compressed       = $r.Compressed
            StoredAsHashSize = $r.StoredAsHashSize
            Duplicate        = $r.Duplicate
            MediaMBPerSec    = $r.MediaMBPerSec
        }
    }

    $out | Export-Csv -LiteralPath $path -NoTypeInformation

    # The row count is already known here (one CSV row per record, and an empty
    # set writes no rows), so the witness does not re-read the file to count it.
    Write-ManifestWitness -FolderPath $FolderPath -RowCount $Records.Count | Out-Null
}

function Get-ManifestWitnessPath {
    <#
    .SYNOPSIS
        Returns the full path of the manifest witness sidecar that belongs beside
        the MANIFEST.csv in the given folder.

    .PARAMETER FolderPath
        The folder holding the MANIFEST.csv. See SR-038 for the origins covered.

    .OUTPUTS
        [string] the sidecar path (whether or not the file exists).
    #>
    # Implements: SR-038, LLR-038
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath
    )
    return (Join-Path $FolderPath $script:WitnessFilename)
}

function Write-ManifestWitness {
    <#
    .SYNOPSIS
        Stamps the witness sidecar (MANIFEST.csv.meta) for the MANIFEST.csv in a
        folder: format version, data-row count, byte length, and the xxHash128 of
        the manifest's bytes exactly as they sit on disk.

    .DESCRIPTION
        Called at the end of Write-Manifest so every manifest the system writes —
        backup root, staging, dated snapshots, the source hash cache, and every
        rewrite — is witnessed by the one code path (SR-038). Tests that tamper
        with a manifest on purpose re-stamp with this function so the damage they
        mean to exercise is what the restorer reports.

        Rows counts data rows the way the verifier counts them (one per record /
        one per CSV row, header excluded). Write-Manifest passes -RowCount because
        it already holds the records it just wrote; a standalone caller (a test
        re-stamping a tampered manifest) omits it and the file is re-read.

    .PARAMETER FolderPath
        The folder holding the MANIFEST.csv to witness.

    .PARAMETER RowCount
        The manifest's data-row count when the caller already knows it. Omitted
        (or negative) means "count it by re-reading the written file".

    .OUTPUTS
        [string] the path of the published sidecar.

    .NOTES
        The SIDECAR is published by rename (write .tmp, Move-Item -Force), the
        repo's atomicity idiom — atomicity here covers the witness publish only;
        MANIFEST.csv itself is still written in place by Export-Csv. That is
        deliberate: the manifest is written BEFORE the witness, so a crash
        between the two leaves a *stale* witness that mismatches and the failure
        lands in the safe direction (a loud refusal) rather than a silent pass.
        The next successful run rewrites both.
    #>
    # Implements: SR-038, LLR-038
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [int]$RowCount = -1
    )
    $manifestPath = Join-Path $FolderPath $script:DatabaseFilename
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Cannot write a manifest witness: no $($script:DatabaseFilename) in '$FolderPath'."
    }

    $bytes = ([System.IO.FileInfo]$manifestPath).Length
    $rows  = if ($RowCount -ge 0) { $RowCount } else { @(Import-Csv -LiteralPath $manifestPath).Count }
    $hash  = Get-FileXxHash -FilePath $manifestPath

    $lines = @(
        "Version=$($script:WitnessFormatVersion)"
        "Rows=$rows"
        "Bytes=$bytes"
        "XxH128=$hash"
        "Written=$((Get-Date).ToString($script:CSVDateFormat))"
    )
    # UTF-8 without BOM, LF line endings, trailing newline — the bash reader is a
    # plain grep/cut and must not meet a BOM or a CR.
    $content  = ($lines -join "`n") + "`n"
    $encoding = [System.Text.UTF8Encoding]::new($false)

    $witnessPath = Get-ManifestWitnessPath -FolderPath $FolderPath
    $tempPath    = "$witnessPath.tmp"
    [System.IO.File]::WriteAllText($tempPath, $content, $encoding)
    Move-Item -LiteralPath $tempPath -Destination $witnessPath -Force

    return $witnessPath
}

function Test-ManifestWitness {
    <#
    .SYNOPSIS
        Verifies a folder's MANIFEST.csv against its witness sidecar and returns a
        verdict object rather than throwing, so each restorer can map the verdict
        onto its own exit code (SR-039, SR-040).

    .PARAMETER FolderPath
        The restore origin whose MANIFEST.csv is to be checked.

    .OUTPUTS
        [pscustomobject] with:
          Status  — Verified | Absent | Mismatch | Malformed
          Field   — the first field that disagreed (Bytes|Rows|XxH128), else $null
          Detail  — an operator-legible sentence naming expected vs. found
          Warning — a non-fatal discrepancy the caller should surface, else $null
          Version — the sidecar's declared format version (0 when unknown)
          Path    — the sidecar path

    .NOTES
        Absent is NOT a failure here: a backup written before SR-038 has no
        sidecar and must still restore. The caller decides whether absence is
        fatal (strict mode). A sidecar declaring a version newer than this build
        understands verifies only the keys it knows and reports VersionUnknown —
        a witness from the future must never condemn a good manifest.

        The DIGEST is authoritative (WP1 plan §6 decision 3). Fields are checked
        Bytes -> Rows -> XxH128, but a Rows-only disagreement — same bytes, same
        digest, different count — is a counting-semantics divergence between the
        writer and this reader, not damage: it reports Verified with a Warning
        instead of condemning a manifest the digest just proved intact. Bytes or
        digest disagreement still fails.
    #>
    # Implements: SR-039, LLR-039
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath
    )

    $witnessPath  = Get-ManifestWitnessPath -FolderPath $FolderPath
    $manifestPath = Join-Path $FolderPath $script:DatabaseFilename
    $rowsDisagreement = $null

    $verdict = [pscustomobject]@{
        Status         = 'Verified'
        Field          = $null
        Detail         = ''
        Warning        = $null
        Version        = 0
        VersionUnknown = $false
        Path           = $witnessPath
    }

    if (-not (Test-Path -LiteralPath $witnessPath -PathType Leaf)) {
        $verdict.Status = 'Absent'
        $verdict.Detail = "No $($script:WitnessFilename) beside the manifest; the index is unverified."
        return $verdict
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $verdict.Status = 'Malformed'
        $verdict.Detail = "A witness exists but there is no $($script:DatabaseFilename) to verify."
        return $verdict
    }

    $keys = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($witnessPath)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $split = $trimmed.IndexOf('=')
        if ($split -lt 1) { continue }
        # Unknown keys are ignored by design (forward compatibility).
        $keys[$trimmed.Substring(0, $split)] = $trimmed.Substring($split + 1)
    }

    $parsedVersion = 0
    if (-not $keys.ContainsKey('Version') -or -not [int]::TryParse($keys['Version'], [ref]$parsedVersion)) {
        $verdict.Status = 'Malformed'
        $verdict.Detail = "The witness sidecar has no readable Version line; it is not a $($script:WitnessFilename)."
        return $verdict
    }
    $verdict.Version = $parsedVersion
    if ($parsedVersion -gt $script:WitnessFormatVersion) {
        $verdict.VersionUnknown = $true
    }

    if (-not ($keys.ContainsKey('Bytes') -or $keys.ContainsKey('Rows') -or $keys.ContainsKey('XxH128'))) {
        $verdict.Status = 'Malformed'
        $verdict.Detail = 'The witness sidecar carries none of Bytes, Rows or XxH128 — nothing to verify against.'
        return $verdict
    }

    if ($keys.ContainsKey('Bytes')) {
        $expectedBytes = [long]0
        if (-not [long]::TryParse($keys['Bytes'], [ref]$expectedBytes)) {
            $verdict.Status = 'Malformed'
            $verdict.Field  = 'Bytes'
            $verdict.Detail = "The witness Bytes value '$($keys['Bytes'])' is not a number."
            return $verdict
        }
        $actualBytes = ([System.IO.FileInfo]$manifestPath).Length
        if ($actualBytes -ne $expectedBytes) {
            $verdict.Status = 'Mismatch'
            $verdict.Field  = 'Bytes'
            $verdict.Detail = "Manifest byte length disagrees with its witness: expected $expectedBytes, found $actualBytes."
            return $verdict
        }
    }

    if ($keys.ContainsKey('Rows')) {
        $expectedRows = 0
        if (-not [int]::TryParse($keys['Rows'], [ref]$expectedRows)) {
            $verdict.Status = 'Malformed'
            $verdict.Field  = 'Rows'
            $verdict.Detail = "The witness Rows value '$($keys['Rows'])' is not a number."
            return $verdict
        }
        $actualRows = 0
        try { $actualRows = @(Import-Csv -LiteralPath $manifestPath).Count }
        catch {
            $verdict.Status = 'Mismatch'
            $verdict.Field  = 'Rows'
            $verdict.Detail = "The manifest could not be parsed as CSV while its witness expects $expectedRows row(s): $($_.Exception.Message)"
            return $verdict
        }
        if ($actualRows -ne $expectedRows) {
            # Deferred: the digest gets the final say (see .NOTES).
            $rowsDisagreement = "Manifest row count disagrees with its witness: expected $expectedRows row(s), found $actualRows."
        }
    }

    if ($keys.ContainsKey('XxH128')) {
        $expectedHash = ("$($keys['XxH128'])").Trim().ToUpperInvariant()
        $actualHash   = Get-FileXxHash -FilePath $manifestPath
        if ($actualHash -ne $expectedHash) {
            $verdict.Status = 'Mismatch'
            $verdict.Field  = 'XxH128'
            $verdict.Detail = "Manifest digest disagrees with its witness: expected $expectedHash, found $actualHash."
            return $verdict
        }
    }

    if ($rowsDisagreement) {
        if ($keys.ContainsKey('XxH128')) {
            # Bytes and digest both matched: the manifest is byte-identical to
            # the one that was witnessed, so the count is the thing that is
            # wrong, not the index. Warn and accept.
            $verdict.Field   = 'Rows'
            $verdict.Warning = "$rowsDisagreement The byte length and digest both match, so the index is intact — this is a row-counting difference, not damage."
        } else {
            $verdict.Status = 'Mismatch'
            $verdict.Field  = 'Rows'
            $verdict.Detail = "$rowsDisagreement The witness carries no digest to defer to."
            return $verdict
        }
    }

    $verdict.Detail = "Manifest verified against its witness (version $parsedVersion)."
    return $verdict
}

# endregion

Export-ModuleMember -Function @(
    'Get-FileBackupDefaults',
    'New-Logger',
    'Initialize-XxHashLibrary',
    'Get-XxHashDllPath',
    'Get-FileXxHash',
    'ConvertTo-ManifestDateString',
    'ConvertFrom-ManifestDateString',
    'Convert-HexToShortName',
    'Convert-ShortNameToHex',
    'Get-HashSizeFileName',
    'Test-ShouldCompress',
    'Compress-FileWithSevenZip',
    'Expand-FileWithSevenZip',
    'Resolve-ExistingAncestor',
    'Get-FreeSpaceBytes',
    'Get-VolumeIdentity',
    'Read-Manifest',
    'Write-Manifest',
    'Get-ManifestWitnessPath',
    'Write-ManifestWitness',
    'Test-ManifestWitness'
)
