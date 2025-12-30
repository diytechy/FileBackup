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
    [string]$TargetRoot
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
    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        "$(Get-Date -Format 'O') - No datapath for $rel" | Out-File -LiteralPath $logPath -Append
        continue
    }
    $srcFull = Join-Path $srcFolder $dataPath
    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) {
        "$(Get-Date -Format 'O') - Missing datapath $dataPath for $rel" | Out-File -LiteralPath $logPath -Append
        continue
    }

    # TODO: handle decompression if Compressed flag says so (7z)
    Copy-Item -LiteralPath $srcFull -Destination $destFull -Force
}

"$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath $logPath -Append
Write-Host "Reconstruction finished. See log: $logPath"