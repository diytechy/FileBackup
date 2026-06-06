<#
.SYNOPSIS
    Reconstructs a source tree from MANIFEST.csv and the available data files.

.DESCRIPTION
    Deployed (by New-ReconstructScript) into the backup root and each change
    folder, alongside FileBackup.Common.psm1, System.IO.Hashing.dll, and a
    RECONSTRUCT.paths.json sidecar. Runs standalone — no repository required.

        * From the backup root: uses that folder's MANIFEST.csv only.
        * From a dated snapshot folder (name starts with "Snapshot_"): that
          snapshot's own manifest is the authoritative point-in-time state, with
          bytes resolved by hash from the backup root + sibling snapshots.

    When a row's DataPath is blank/missing, the file is recovered by scanning the
    search folders for a file whose length and xxHash128 match.

.NOTES
    Requires PowerShell 7+ (pwsh). Logs to RECONSTRUCT.log in the target root.
#>

param(
    [string]$TargetRoot,
    [string]$BackupRootOverride,
    [string]$ChangeRootOverride
)

$ErrorActionPreference = 'Stop'
$here = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)

# ---- Load shared primitives (hashing, manifest I/O, 7-Zip, defaults) ----
$commonModule = Join-Path $here 'FileBackup.Common.psm1'
if (-not (Test-Path -LiteralPath $commonModule -PathType Leaf)) {
    throw "FileBackup.Common.psm1 not found next to Reconstruct.ps1 at '$here'. The backup folder is incomplete."
}
Import-Module $commonModule -Force
$Def = Get-FileBackupDefaults

$DatabaseFilename    = $Def.DatabaseFilename
$ReconstructLogName  = $Def.ReconstructLogName
$ChangeFolderPattern = '^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}'

$folderName = [System.IO.Path]::GetFileName($here)

function Find-DataFileByHash {
    <#
        Locates a data file matching the original (hash,length). Uncompressed
        candidates are filtered by length then hashed; .7z candidates are
        decompressed to a temp file and hashed (their on-disk size/hash differ
        from the original), so recovery works for compressed backups too.
        Returns the path to use as the data source (the archive path for .7z).
    #>
    param([string]$Hash, [long]$Length, [string[]]$SearchFolders, [string]$SevenZipPath)
    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    foreach ($folder in $SearchFolders) {
        $candidates = Get-ChildItem -LiteralPath $folder -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch $skip }
        foreach ($f in $candidates) {
            if ($f.Extension -ieq '.7z') {
                if (-not $SevenZipPath -or -not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) { continue }
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $f.FullName -DestinationFile $tmp
                    if ((Get-Item -LiteralPath $tmp).Length -eq $Length -and (Get-FileXxHash -FilePath $tmp) -eq $Hash) {
                        return $f.FullName
                    }
                } catch {
                    Write-Verbose "Skipping archive candidate '$($f.FullName)': $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            } elseif ($f.Length -eq $Length) {
                if ((Get-FileXxHash -FilePath $f.FullName) -eq $Hash) { return $f.FullName }
            }
        }
    }
    return $null
}

# ---- Resolve backup/change roots ----
$isChangeFolder = $folderName -match $ChangeFolderPattern

# Sidecar written by New-ReconstructScript takes precedence over auto-detection (B10).
$sidecar = Join-Path $here 'RECONSTRUCT.paths.json'
if (-not $BackupRootOverride -and (Test-Path -LiteralPath $sidecar -PathType Leaf)) {
    try {
        $paths = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json
        if (-not $BackupRootOverride) { $BackupRootOverride = $paths.BackupRoot }
        if (-not $ChangeRootOverride) { $ChangeRootOverride = $paths.ChangeRoot }
    } catch {
        Write-Warning "Could not read path sidecar '$sidecar'; falling back to auto-detection. $($_.Exception.Message)"
    }
}

if ($isChangeFolder) {
    $changeRoot = [System.IO.Path]::GetDirectoryName($here)
    $backupRoot = [System.IO.Path]::GetDirectoryName($changeRoot)
} else {
    $backupRoot = $here
    $changeRoot = $null     # B10: no assumed CHANGES sibling; only used if known.
}

if ($BackupRootOverride) { $backupRoot = $BackupRootOverride }
if ($ChangeRootOverride) { $changeRoot = $ChangeRootOverride }

if (-not $TargetRoot) {
    $TargetRoot = Read-Host 'Enter target folder to reconstruct into'
}

if ($TargetRoot -like "$backupRoot*") { throw 'TargetRoot must be outside the backup root.' }
if ($changeRoot -and (Test-Path -LiteralPath $changeRoot -PathType Container) -and ($TargetRoot -like "$changeRoot*")) {
    throw 'TargetRoot must be outside the change folder root.'
}

if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
}

$logPath = Join-Path $TargetRoot $ReconstructLogName
"$(Get-Date -Format 'O') - Reconstruction starting" | Out-File -LiteralPath $logPath -Encoding UTF8

function Read-RawManifest {
    param([string]$Folder)
    $path = Join-Path $Folder $DatabaseFilename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    Import-Csv -LiteralPath $path
}

# ---- Build main dictionary (SR-010 authority rule) ----
# From a dated snapshot folder, that snapshot's OWN manifest is the sole
# point-in-time authority (no newer manifest is overlaid). From the backup root,
# the live backup manifest is the latest state. In both cases the bytes are
# resolved later from the data pool by hash where a DataPath is blank.
$main = @{}
$haveSnapshotTree = $changeRoot -and (Test-Path -LiteralPath $changeRoot -PathType Container)
$authorityFolder  = if ($isChangeFolder) { $here } else { $backupRoot }

foreach ($row in (Read-RawManifest -Folder $authorityFolder)) {
    if (-not $row.RelativePath) { continue }
    $row | Add-Member -NotePropertyName SourceFolder -NotePropertyValue $authorityFolder -Force
    $main[$row.RelativePath] = $row
}

# ---- Capacity pre-check (B11: skip compressed rows; lengths are uncompressed) ----
$totalBytes = 0L
$anyCompressed = $false
foreach ($rel in $main.Keys) {
    $row = $main[$rel]
    if ($row.Compressed -eq 'Yes') { $anyCompressed = $true; continue }
    if ($row.Length) { $totalBytes += [long]$row.Length }
}
# Resolve the drive separately so a resolution failure is non-fatal, but an
# actual insufficient-space verdict still aborts (previously the throw was
# swallowed by the same catch that handled drive resolution — SR-023 / B11).
$drive = $null
try {
    $drive = Get-PSDrive -Name (Split-Path -Qualifier $TargetRoot).TrimEnd(':')
} catch {
    Write-Verbose "Capacity pre-check skipped (could not resolve target drive): $($_.Exception.Message)"
}
if ($drive) {
    if ($drive.Free -lt $totalBytes) {
        $msg = "Not enough free space on target drive. Required (uncompressed rows only): $totalBytes, Free: $($drive.Free)"
        $msg | Out-File -LiteralPath $logPath -Append
        throw $msg
    }
    if ($anyCompressed) {
        "$(Get-Date -Format 'O') - NOTE: backup contains compressed rows; capacity check excluded them (true need is higher)." |
            Out-File -LiteralPath $logPath -Append
    }
}

# ---- Data pool for hash recovery (SR-010): backup root + every snapshot ----
# A blank/relocated DataPath resolves its bytes by (hash,length) wherever they
# survived: unchanged files from the live backup, superseded versions from the
# snapshot that retained them. Built as a list so an empty snapshot set never
# injects a $null folder.
$searchFolders = New-Object System.Collections.Generic.List[string]
if ($haveSnapshotTree) {
    Get-ChildItem -LiteralPath $changeRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $ChangeFolderPattern } |
        Sort-Object Name -Descending |
        ForEach-Object { $searchFolders.Add($_.FullName) }
}
$searchFolders.Add($backupRoot)

$sevenZipPath = $Def.SevenZipDefaultPath

# ---- Reconstruct ----
foreach ($rel in $main.Keys) {
    $row     = $main[$rel]
    $destFull = Join-Path $TargetRoot $rel
    $destDir  = [System.IO.Path]::GetDirectoryName($destFull)
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $srcFolder = $row.SourceFolder
    $dataPath  = $row.DataPath

    if ([string]::IsNullOrWhiteSpace($dataPath)) {
        if ($row.xxH2Hash -and $row.Length) {
            "$(Get-Date -Format 'O') - No datapath for $rel; attempting hash scan..." | Out-File -LiteralPath $logPath -Append
            $found = Find-DataFileByHash -Hash $row.xxH2Hash -Length ([long]$row.Length) -SearchFolders $searchFolders -SevenZipPath $sevenZipPath
            if ($found) {
                "$(Get-Date -Format 'O') - Hash-recovered $rel from '$found'" | Out-File -LiteralPath $logPath -Append
                $srcFull = $found
            } else {
                "$(Get-Date -Format 'O') - WARN: cannot recover $rel by hash; skipping." | Out-File -LiteralPath $logPath -Append
                continue
            }
        } else {
            "$(Get-Date -Format 'O') - No datapath or hash for $rel; skipping." | Out-File -LiteralPath $logPath -Append
            continue
        }
    } else {
        $srcFull = Join-Path $srcFolder $dataPath
    }

    if (-not (Test-Path -LiteralPath $srcFull -PathType Leaf)) {
        "$(Get-Date -Format 'O') - Missing datapath $dataPath for $rel" | Out-File -LiteralPath $logPath -Append
        continue
    }

    if ($row.Compressed -eq 'Yes' -and (Test-Path -LiteralPath $sevenZipPath -PathType Leaf)) {
        try {
            Expand-FileWithSevenZip -SevenZipPath $sevenZipPath -Archive $srcFull -DestinationFile $destFull
        } catch {
            "$(Get-Date -Format 'O') - 7-Zip extraction failed for $rel : $($_.Exception.Message)" | Out-File -LiteralPath $logPath -Append
            continue
        }
    } else {
        Copy-Item -LiteralPath $srcFull -Destination $destFull -Force
    }
}

"$(Get-Date -Format 'O') - Reconstruction complete" | Out-File -LiteralPath $logPath -Append
Write-Host "Reconstruction finished. See log: $logPath"
