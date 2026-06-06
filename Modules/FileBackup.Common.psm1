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

    It must stay dependency-free beyond the K4os.Hash.xxHash NuGet package and
    7-Zip, because New-ReconstructScript (in FileBackup.Engine.psm1) copies this
    file alongside Reconstruct.ps1 into every backup/change folder so that a
    restore works with nothing but the backup folder present.

    Anything specific to *producing* a backup lives in FileBackup.Engine.psm1.
#>

# region Shared defaults

$script:DatabaseFilename      = 'MANIFEST.csv'
$script:ReconstructPs1Name    = 'RECONSTRUCT.ps1'
$script:ReconstructBatName    = 'RECONSTRUCT.bat'
$script:ReconstructLogName    = 'RECONSTRUCT.log'
$script:CommonModuleName      = 'FileBackup.Common.psm1'

$script:CSVDateFormat         = 'O'                       # ISO 8601 round-trip
$script:FileLabelDateFormat   = 'yyyy_MM_dd_HH_mm_ss'     # label in folder/manifest names (no ':' — invalid in Windows paths)
$script:ChangeFolderDateMask  = 'yyyy_MM_dd_HH_mm_ss'     # pattern used in change-folder names
$script:ChangeFolderRegex     = '^Pre_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_.*_Changes$'

# Alphabet for short-name encoding (base-N over these glyphs)
$script:Alphabet = @(
    '!', '#', '$', '%', '&', '''', '(', ')', '+', ',', '-', '.', ';', '=', '@',
    '[', ']', '^', '_', '`', '{', '}', '~',
    '0','1','2','3','4','5','6','7','8','9',
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z',
    'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z'
)

$script:NonCompressibleExtensions = @(
    '.zip', '.7z', '.rar',
    '.gz',  '.bz2', '.xz',
    '.mp4', '.mkv', '.mov', '.avi',
    '.mp3', '.aac', '.flac',
    '.jpg', '.jpeg', '.png', '.webp'
)

$script:SevenZipDefaultPath = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$script:FfprobePathDefault  = 'C:\ffmpeg\bin\ffprobe.exe'

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
        ReconstructPs1Name       = $script:ReconstructPs1Name
        ReconstructBatName       = $script:ReconstructBatName
        ReconstructLogName       = $script:ReconstructLogName
        CommonModuleName         = $script:CommonModuleName
        CSVDateFormat            = $script:CSVDateFormat
        FileLabelDateFormat      = $script:FileLabelDateFormat
        ChangeFolderDateMask     = $script:ChangeFolderDateMask
        ChangeFolderRegex        = $script:ChangeFolderRegex
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
    # Implements: SR-002, SR-019, LLR-002
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
    # Implements: SR-007, LLR-007
    <#
    .SYNOPSIS
        Resolves the path to a System.IO.Hashing.dll to bundle into a backup
        folder for standalone restore. Returns $null if it cannot be located.
    #>
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
    # Implements: SR-002, LLR-002
    <#
    .SYNOPSIS
        Computes the xxHash128 of a file as a 32-char uppercase hex string
        (big-endian, matching System.IO.Hashing's canonical output).
    #>
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
    # Implements: SR-003, SR-021, LLR-003, LLR-021
    <#
    .SYNOPSIS
        Builds the content-addressed data filename "<hashShort> <lenShort><ext>".
    #>
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
    # Implements: SR-004, LLR-004
    <#
    .SYNOPSIS
        True when compression is enabled and the file's extension is not already
        a compressed/opaque format. Only the extension of -FileName is inspected.
    #>
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
    # Implements: SR-008, LLR-008
    <#
    .SYNOPSIS
        Extracts the single payload file from a .7z archive to -DestinationFile.
    #>
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

function Read-Manifest {
    # Implements: SR-025, LLR-025
    <#
    .SYNOPSIS
        Reads MANIFEST.csv from a folder, typing Length as [long] and adding a
        parsed [datetime] LastWriteTime member. Returns @() when absent.
    #>
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
    # Implements: SR-025, LLR-025
    <#
    .SYNOPSIS
        Writes the canonical 9-column MANIFEST.csv to a folder.
    #>
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
    'Read-Manifest',
    'Write-Manifest'
)
