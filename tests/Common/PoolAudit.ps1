<#
.SYNOPSIS  Pool-audit harness tooling (TC-116): the orphan-detection SECOND
           PASS — the HomeHub drill assertion that caught D-1 — plus the
           physical-copy counter behind the de-vacuumed G2.8 (TC-019).

.NOTES     Dot-sourced by Run-All.ps1 next to Harness.ps1. Deliberately
           STRONGER than -Action Verify and SR-054's Test-PoolResolves, which
           resolve blank rows through the in-memory content index: everything
           here is proven by READING BYTES — hashing every pool file, and the
           expanded payload of every .7z — the same proof Find-DataFileByHash
           uses. Requires FileBackup.Common.psm1 (Get-FileXxHash,
           Expand-FileWithSevenZip, Get-FileBackupDefaults) to be loaded.
#>

function Get-PoolByteVerifiedHashes {
    <#
    .SYNOPSIS
        Walks the given pool folders and returns a hashtable keyed
        "HASH|Length" -> count of physical files whose BYTES reproduce that
        content (raw files by their own hash; .7z files additionally by their
        expanded payload's hash). Root-level infrastructure names are skipped,
        nested ones are data (B6).
    #>
    param([string[]]$Folders, [string]$SevenZipPath)
    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    $set = @{}
    foreach ($folder in $Folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        $root = (Resolve-Path -LiteralPath $folder).Path.TrimEnd('\', '/')
        foreach ($f in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
            if ($f.Name -match $skip -and [IO.Path]::GetDirectoryName($f.FullName) -eq $root) { continue }
            try {
                $key = "$(Get-FileXxHash -FilePath $f.FullName)|$($f.Length)"
                $set[$key] = 1 + [int]$set[$key]
            } catch { }
            if ($f.Extension -ieq '.7z' -and $SevenZipPath -and (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $f.FullName -DestinationFile $tmp
                    $key = "$(Get-FileXxHash -FilePath $tmp)|$((Get-Item -LiteralPath $tmp -Force).Length)"
                    $set[$key] = 1 + [int]$set[$key]
                } catch { } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    return $set
}

function Get-PoolFolderList {
    # The audit pool: the backup root plus every Snapshot_* sibling.
    param([string]$BackupRoot, [string]$ChangeRoot)
    $folders = New-Object System.Collections.Generic.List[string]
    $folders.Add($BackupRoot)
    if ($ChangeRoot -and (Test-Path -LiteralPath $ChangeRoot -PathType Container)) {
        foreach ($d in @(Get-ChildItem -LiteralPath $ChangeRoot -Directory -Force |
                         Where-Object { $_.Name -match '^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}' })) {
            $folders.Add($d.FullName)
        }
    }
    return $folders
}

function Get-BlankRowPoolViolations {
    <#
    .SYNOPSIS
        TC-116: after a timeline, EVERY blank-DataPath row in every manifest
        (backup root and every snapshot) must have its (xxH2Hash, Length)
        among the hashes byte-verified this pass — not merely Test-Path
        resolved. Returns one violation string per failing row (empty = clean).
    #>
    param([string]$BackupRoot, [string]$ChangeRoot, [string]$SevenZipPath)
    if (-not $SevenZipPath) { $SevenZipPath = (Get-FileBackupDefaults).SevenZipDefaultPath }
    $folders  = Get-PoolFolderList -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot
    $verified = Get-PoolByteVerifiedHashes -Folders $folders -SevenZipPath $SevenZipPath
    $violations = @()
    foreach ($folder in $folders) {
        $manifest = Join-Path $folder 'MANIFEST.csv'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        foreach ($row in @(Import-Csv -LiteralPath $manifest)) {
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
            if ([string]::IsNullOrWhiteSpace($row.xxH2Hash)) { continue }
            if (-not $verified.ContainsKey("$($row.xxH2Hash)|$($row.Length)")) {
                $violations += "'$($row.RelativePath)' in '$folder': blank row (hash=$($row.xxH2Hash), len=$($row.Length)) has NO byte-verified pool copy"
            }
        }
    }
    return $violations
}

function Get-PoolContentCopyCount {
    <#
    .SYNOPSIS
        Physical pool files whose bytes (raw, or expanded .7z payload)
        reproduce one (hash,length) — the exact-count half of the de-vacuumed
        G2.8 dedup assertion (TC-019).
    #>
    param([string[]]$Folders, [string]$Hash, [long]$Length, [string]$SevenZipPath)
    if (-not $SevenZipPath) { $SevenZipPath = (Get-FileBackupDefaults).SevenZipDefaultPath }
    $verified = Get-PoolByteVerifiedHashes -Folders $Folders -SevenZipPath $SevenZipPath
    return [int]$verified["$Hash|$Length"]
}
