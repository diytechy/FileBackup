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
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force)) {
            # Trimmed both sides: at a bare drive root GetDirectoryName keeps
            # the trailing slash the resolved root trims (WP9 step-5 finding).
            if ($f.Name -match $skip -and ([IO.Path]::GetDirectoryName($f.FullName)).TrimEnd('\', '/') -eq $root) { continue }
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

function Get-HashNameGrammarViolations {
    <#
    .SYNOPSIS
        TC-123 (SR-058): every non-infrastructure file at the backup root must
        carry the content-addressed name grammar "<hash16> <len10><ext>" —
        16 alphabet glyphs, one space, 10 alphabet glyphs, then the extension —
        and pool objects are flat at the root, never nested.

    .DESCRIPTION
        The work-order §3.1 compensating control for the deleted SR-022
        copy-branch refusal: a grammar name can never spell a root-level
        infrastructure name, so proving the grammar at the root proves that
        collision class stays dead. Assumes ChangePath lies OUTSIDE the backup
        root (the harness default) — snapshot folders are not walked here.
    #>
    param([string]$BackupRoot)
    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    $violations = @()
    $root = (Resolve-Path -LiteralPath $BackupRoot).Path.TrimEnd('\', '/')
    foreach ($f in @(Get-ChildItem -LiteralPath $BackupRoot -File -Recurse -Force)) {
        # Trim BOTH sides: at a bare drive root (the subst harness),
        # GetDirectoryName returns 'X:\' while the resolved root trims to 'X:'.
        $isRootLevel = (([IO.Path]::GetDirectoryName($f.FullName)).TrimEnd('\', '/') -eq $root)
        if ($isRootLevel -and $f.Name -match $skip) { continue }
        if (-not $isRootLevel) {
            $violations += "'$($f.FullName)': pool objects are flat at the backup root; nothing may nest below it"
            continue
        }
        $name = $f.Name
        $ok = $false
        if ($name.Length -ge 27 -and $name[16] -eq ' ') {
            # Both encoded halves must decode under the short-name alphabet;
            # whatever follows position 27 is the extension.
            try {
                [void](Convert-ShortNameToHex -ShortName $name.Substring(0, 16))
                [void](Convert-ShortNameToHex -ShortName $name.Substring(17, 10))
                $ok = $true
            } catch { $ok = $false }
        }
        if (-not $ok) { $violations += "'$name' at the backup root does not match the content-addressed name grammar" }
    }
    return $violations
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

function Get-UnjustifiedPoolNames {
    <#
    .SYNOPSIS
        TC-122 (SR-059, "name-proven"): every pool object in the backup root and
        in every snapshot must carry a name whose encoded (hash, length) halves
        are the ones its OWN CONTENT produces. Returns one violation string per
        failing file (empty = clean).

    .DESCRIPTION
        Get-ClaimedRowViolations asks the question from the manifest's side -
        does the row's DataPath hold the row's bytes. This asks it from the
        POOL's side, so an object no live row happens to claim is still held to
        the naming contract: a file called "<hash16> <len10><ext>" that does not
        hash to that (hash, length) is a name that lies, and hash recovery
        (SR-050) would hand it to a row that asked for those bytes.

        Form is proven from the bytes, never from a column: the raw file is
        tried first (which is the answer for raw storage, including a source
        file that genuinely IS an archive), and only if the raw name does not
        justify itself is the file expanded and its payload tried. Root-level
        infrastructure names are skipped; nested ones are data (B6).
    #>
    param([string]$BackupRoot, [string]$ChangeRoot, [string]$SevenZipPath)
    if (-not $SevenZipPath) { $SevenZipPath = (Get-FileBackupDefaults).SevenZipDefaultPath }
    $skip = '^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
    $violations = @()

    $expectedPrefix = {
        param([string]$HashHex, [long]$Len)
        "$(Convert-HexToShortName -Hex $HashHex -OutputLength 16) " +
        "$(Convert-HexToShortName -Hex ('{0:X}' -f $Len) -OutputLength 10)"
    }

    foreach ($folder in (Get-PoolFolderList -BackupRoot $BackupRoot -ChangeRoot $ChangeRoot)) {
        $root = (Resolve-Path -LiteralPath $folder).Path.TrimEnd('\', '/')
        # -Recurse (WP9 review, nit-3): pool objects are flat at a folder's
        # root today, but an audit that cannot SEE a nested object cannot
        # hold it to the naming contract either.
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Recurse -Force)) {
            if ($file.Name -match $skip -and
                ([IO.Path]::GetDirectoryName($file.FullName)).TrimEnd('\', '/') -eq $root) { continue }

            $justified = $false
            try {
                $justified = $file.Name.StartsWith((& $expectedPrefix (Get-FileXxHash -FilePath $file.FullName) $file.Length), 'Ordinal')
            } catch {
                $violations += "'$($file.FullName)': could not be hashed: $($_.Exception.Message)"
                continue
            }
            if (-not $justified -and $SevenZipPath -and (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
                $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
                try {
                    Expand-FileWithSevenZip -SevenZipPath $SevenZipPath -Archive $file.FullName -DestinationFile $tmp
                    $payload = Get-Item -LiteralPath $tmp -Force
                    $justified = $file.Name.StartsWith((& $expectedPrefix (Get-FileXxHash -FilePath $tmp) $payload.Length), 'Ordinal')
                } catch {
                    Write-Verbose "PoolAudit: '$($file.FullName)' is neither raw content matching its name nor an expandable archive: $($_.Exception.Message)"
                } finally {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
            }
            if (-not $justified) {
                $violations += "'$($file.FullName)': the name encodes a (hash,length) its own content does not produce"
            }
        }
    }
    return $violations
}
