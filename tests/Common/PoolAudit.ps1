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
            } catch {
                # An unreadable pool file simply contributes no verified hash —
                # any blank row depending on it then FAILS the audit, which is
                # the honest outcome; the audit itself must not die here.
                Write-Verbose "PoolAudit: could not hash '$($f.FullName)': $($_.Exception.Message)"
            }
            if ($f.Extension -ieq '.7z' -and $SevenZipPath -and (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $f.FullName -DestinationFile $tmp
                    $key = "$(Get-FileXxHash -FilePath $tmp)|$((Get-Item -LiteralPath $tmp -Force).Length)"
                    $set[$key] = 1 + [int]$set[$key]
                } catch {
                    # A .7z that will not expand contributes only its raw hash
                    # (already recorded above) — same rationale as the raw arm.
                    Write-Verbose "PoolAudit: could not expand '$($f.FullName)': $($_.Exception.Message)"
                } finally {
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

function Get-ClaimedRowViolations {
    <#
    .SYNOPSIS
        TC-118/TC-122 (SR-059): every NON-blank-DataPath row in every manifest
        (backup root and every snapshot) must find, at its own DataPath, bytes
        that reproduce that row's (xxH2Hash, Length). Returns one violation
        string per failing row (empty = clean).

    .DESCRIPTION
        The companion to Get-BlankRowPoolViolations, and the detector the
        HomeHub drill did NOT have: D-1 damage leaves the row's file PRESENT
        (so nothing blanks it) while its bytes now belong to a different
        (hash,length) — invisible to Test-Path, to Test-PoolResolves and to a
        non-Deep -Action Verify.

        Form is PROVEN from the bytes, never taken from the Compressed column,
        exactly as Find-DataFileByHash does: the file's own bytes are hashed
        first (which is the answer for raw storage, including a source file
        that genuinely IS an archive), and only if that fails is the file
        expanded and its payload hashed.
    #>
    param([string]$BackupRoot, [string]$ChangeRoot, [string]$SevenZipPath)
    if (-not $SevenZipPath) { $SevenZipPath = (Get-FileBackupDefaults).SevenZipDefaultPath }
    $folders    = Get-PoolFolderList -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot
    $violations = @()
    foreach ($folder in $folders) {
        $manifest = Join-Path $folder 'MANIFEST.csv'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        foreach ($row in @(Import-Csv -LiteralPath $manifest)) {
            if ([string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
            if ([string]::IsNullOrWhiteSpace($row.xxH2Hash)) { continue }
            $full = Join-Path $folder $row.DataPath
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $violations += "'$($row.RelativePath)' in '$folder': DataPath '$($row.DataPath)' names no file"
                continue
            }
            $want = "$($row.xxH2Hash)|$($row.Length)"
            $got  = $null
            try { $got = "$(Get-FileXxHash -FilePath $full)|$((Get-Item -LiteralPath $full -Force).Length)" }
            catch {
                $violations += "'$($row.RelativePath)' in '$folder': DataPath '$($row.DataPath)' could not be read: $($_.Exception.Message)"
                continue
            }
            if ($got -eq $want) { continue }
            # Not raw storage of this row's content — try it as an archive.
            $expanded = $null
            if ($SevenZipPath -and (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $full -DestinationFile $tmp
                    $expanded = "$(Get-FileXxHash -FilePath $tmp)|$((Get-Item -LiteralPath $tmp -Force).Length)"
                } catch {
                    Write-Verbose "PoolAudit: '$full' is neither this row's raw bytes nor an expandable archive: $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
            if ($expanded -eq $want) { continue }
            $violations += ("'$($row.RelativePath)' in '$folder': DataPath '$($row.DataPath)' holds " +
                            "$(if ($expanded) { "payload $expanded" } else { "bytes $got" }) but the row claims $want")
        }
    }
    return $violations
}
