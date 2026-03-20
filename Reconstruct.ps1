<#
.SYNOPSIS
    Reconstructs a source tree from MANIFEST.csv and available data files.

.DESCRIPTION
    - Intended to be placed in either:
        * backup root, or
        * a specific change folder.
    - Uses MANIFEST.csv in the current folder.
    - If running from a change folder (name starts with "Pre_"), it will:
        * Aggregate manifests from this change folder, any newer change folders,
          and the backup root, preferring newest info.
    - If running from backup root, uses only that manifest.

.NOTES
    - Logs to RECONSTRUCT.log in target root.
#>

param(
    [string]$TargetRoot,
    [string]$BackupRootOverride,
    [string]$ChangeRootOverride
)

$ErrorActionPreference = 'Stop'

$DatabaseFilename     = 'MANIFEST.csv'
$ReconstructLogName   = 'RECONSTRUCT.log'
$ChangeFolderPattern  = '^Pre_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}'

$here = Split-Path -LiteralPath $MyInvocation.MyCommand.Path -Parent
$folderName = Split-Path -Leaf $here

function Read-Manifest {
    param([string]$Folder)
    $path = Join-Path $Folder $DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    Import-Csv -LiteralPath $path
}

function Ensure-K4osHashLibrary {
    param(
        [string]$RequiredVersion = "1.0.8"
    )

    if ("K4os.Hash.xxHash.XXH128" -as [type]) {
        return $true
    }

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

    $pkg = Get-Package -Name "K4os.Hash.xxHash" -ErrorAction Stop
    $installDir = Split-Path $pkg.Source -Parent
    $dll = Get-ChildItem -Path $installDir -Recurse -Filter "K4os.Hash.xxHash.dll" | Select-Object -First 1

    if (-not $dll) {
        throw "K4os.Hash.xxHash.dll not found in installed package."
    }

    if (-not ("K4os.Hash.xxHash.XXH128" -as [type])) {
        Add-Type -Path $dll.FullName
    }

    return $true
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

function Find-DataFileByHash {
    param([string]$Hash, [long]$Length, [string[]]$SearchFolders)
    foreach ($folder in $SearchFolders) {
        Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -eq $Length -and $_.Name -notmatch '^(MANIFEST|RECONSTRUCT)' } |
            ForEach-Object {
                if ((CalculateFileHash $_.FullName) -eq $Hash) { return $_.FullName }
            }
    }
    return $null
}

# Detect if we are in backup root or change folder
$isChangeFolder = $folderName -match $ChangeFolderPattern

# Find backup root and change root
if ($isChangeFolder) {
    $changeRoot = Split-Path -LiteralPath $here -Parent
    $backupRoot = Split-Path -LiteralPath $changeRoot -Parent
} else {
    $backupRoot = $here
    $changeRoot = Join-Path $backupRoot 'CHANGES' # or adjust if you keep same root
}

# Override with auto-generated path bindings if provided
if ($BackupRootOverride) { $backupRoot = $BackupRootOverride }
if ($ChangeRootOverride)  { $changeRoot = $ChangeRootOverride }

if (-not $TargetRoot) {
    $TargetRoot = Read-Host 'Enter target folder to reconstruct into'
}

if ($TargetRoot -like "$backupRoot*") {
    throw 'TargetRoot must be outside the backup root.'
}
if (Test-Path -LiteralPath $changeRoot -PathType Container) {
    if ($TargetRoot -like "$changeRoot*") {
        throw 'TargetRoot must be outside the change folder root.'
    }
}

if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$logPath = Join-Path $TargetRoot $ReconstructLogName
"$(Get-Date -Format 'O') - Reconstruction starting" | Out-File -LiteralPath $logPath -Encoding UTF8

# Build main dictionary: RelativePath -> best row (preferring newest source)
$main = @{}

if ($isChangeFolder -and (Test-Path -LiteralPath $changeRoot)) {
    $changeDirs = Get-ChildItem -LiteralPath $changeRoot -Directory |
                  Where-Object { $_.Name -match $ChangeFolderPattern } |
                  Sort-Object Name   # oldest -> newest

    foreach ($dir in $changeDirs) {
        $db = Read-Manifest -Folder $dir.FullName
        foreach ($row in $db) {
            $rel = $row.RelativePath
            if (-not $rel) { continue }
            $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $dir.FullName -Force
            $main[$rel] = $row
        }
    }

    # Finally overlay with backup root manifest
    $bkpDb = Read-Manifest -Folder $backupRoot
    foreach ($row in $bkpDb) {
        $rel = $row.RelativePath
        if (-not $rel) { continue }
        $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $backupRoot -Force
        $main[$rel] = $row
    }
}
else {
    # Only backup root
    $bkpDb = Read-Manifest -Folder $backupRoot
    foreach ($row in $bkpDb) {
        $rel = $row.RelativePath
        if (-not $rel) { continue }
        $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $backupRoot -Force
        $main[$rel] = $row
    }
}

# Check capacity (approximate)
$totalBytes = 0L
foreach ($rel in $main.Keys) {
    $row = $main[$rel]
    if ($row.Length) {
        $totalBytes += [long]$row.Length
    }
}
try {
    $drive = Get-PSDrive -Name (Split-Path -Qualifier $TargetRoot)
    if ($drive.Free -lt $totalBytes) {
        "Not enough free space on target drive. Required: $totalBytes, Free: $($drive.Free)" |
            Out-File -LiteralPath $logPath -Append
        throw "Not enough free space on target drive."
    }
} catch {
    # Non-critical; continue if we can't determine
}

# Build search folders for hash-based recovery
$searchFolders = @()
if ($isChangeFolder -and (Test-Path -LiteralPath $changeRoot)) {
    $searchFolders += (Get-ChildItem -LiteralPath $changeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $ChangeFolderPattern } |
        Sort-Object Name -Descending).FullName   # newest first
}
$searchFolders += $backupRoot

# Reconstruct
foreach ($rel in $main.Keys) {
    $row = $main[$rel]
    $destFull = Join-Path $TargetRoot $rel
    $destDir  = Split-Path -LiteralPath $destFull -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $srcFolder = $row.SourceFolder
    $dataPath  = $row.DataPath

    # Handle missing or blank DataPath with hash-based recovery
    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        if ($row.xxH2Hash -and $row.Length) {
            "$(Get-Date -Format 'O') - No datapath for $rel; attempting hash scan..." |
                Out-File -LiteralPath $logPath -Append
            $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders
            if ($found) {
                "$(Get-Date -Format 'O') - Hash-recovered $rel from '$found'" |
                    Out-File -LiteralPath $logPath -Append
                $srcFull   = $found
                $dataPath  = $found
            } else {
                "$(Get-Date -Format 'O') - WARN: cannot recover $rel by hash; skipping." |
                    Out-File -LiteralPath $logPath -Append
                continue
            }
        } else {
            "$(Get-Date -Format 'O') - No datapath or hash for $rel; skipping." |
                Out-File -LiteralPath $logPath -Append
            continue
        }
    } else {
        $srcFull = Join-Path $srcFolder $dataPath
    }

    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) {
        "$(Get-Date -Format 'O') - Missing datapath $dataPath for $rel" |
            Out-File -LiteralPath $logPath -Append
        continue
    }

    # Handle decompression if needed
    $sevenZipPath = Join-Path $env:ProgramFiles '7-Zip\7z.exe'

    if ($row.Compressed -eq 'Yes' -and (Test-Path -LiteralPath $sevenZipPath -PathType Leaf)) {
        # Decompress .7z archive
        $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $sevenZipPath
            $psi.Arguments = "e `"$srcFull`" -o`"$tempDir`" -y"
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit()
            if ($p.ExitCode -ne 0) {
                $err = $p.StandardError.ReadToEnd()
                "$(Get-Date -Format 'O') - 7-Zip extraction failed for $rel : $err" |
                    Out-File -LiteralPath $logPath -Append
                continue
            }
            $extracted = Get-ChildItem -LiteralPath $tempDir -File | Select-Object -First 1
            if (-not $extracted) {
                "$(Get-Date -Format 'O') - No file extracted from archive for $rel" |
                    Out-File -LiteralPath $logPath -Append
                continue
            }
            Move-Item -LiteralPath $extracted.FullName -Destination $destFull -Force
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Copy-Item -LiteralPath $srcFull -Destination $destFull -Force
    }
}

"$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath $logPath -Append
Write-Host "Reconstruction finished. See log: $logPath"