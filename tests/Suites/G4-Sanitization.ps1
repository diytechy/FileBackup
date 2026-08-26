<#
.SYNOPSIS  G4 - manifest sanitization and the no-re-forming contract.
.NOTES     SR-061 (WP9): there is NO storage-layout migration and no layout
           axis at all - storage is always content-addressed. G4.1 is TC-124's
           refusal half: a store carrying the legacy path-addressed form can
           only come from a pre-WP9 build; -Action Backup refuses it before
           any mutation, -Action Verify reports it as a finding.
           G4.2 is TC-097: the SR-004 extension-list merge at scale.
#>
function Invoke-G4 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G4-Sanitization'
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    $pwshExe  = (Get-Process -Id $PID).Path

    # G4.1 - the SR-061 legacy-store contract (TC-124, refusal half). The
    # legacy shape is CONSTRUCTED - flip one row, re-stamp the witness (the
    # same honesty pattern as the other tampering fixtures) - because a
    # post-WP9 engine can no longer produce it.
    Reset-TestEnvironment $Env
    $cfg = Join-Path $Env.Root 'cfg-g4.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress
    New-TestFile (Join-Path $Env.SrcPath 'doc.txt')      'document content'
    New-TestFile (Join-Path $Env.SrcPath 'sub\img.bin')  'binary blob'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null

    $rows = @(Import-Csv -LiteralPath $manifest)
    @($rows | Where-Object RelativePath -eq 'doc.txt')[0].StoredAsHashSize = 'Original'
    $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
    Write-ManifestWitness -FolderPath $Env.BkpPath | Out-Null
    $manifestBefore  = Get-Content -LiteralPath $manifest -Raw
    $snapshotsBefore = @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue).Count

    # Backup must REFUSE, mutating nothing (SR-061): same manifest bytes, no
    # new snapshot, no stranded Temp for the next run's SR-017 guard.
    New-TestFile (Join-Path $Env.SrcPath 'doc.txt') 'edited after the store went legacy'
    $backupOut = (& $pwshExe -NoProfile -File $BackupScript -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-String)
    $backupCode = $LASTEXITCODE
    Assert-True $suite $group 'G4.1' 'Legacy_backupRefused' { $backupCode -eq 1 }
    Assert-True $suite $group 'G4.1' 'Legacy_refusalNamesRemedy' {
        $backupOut -match 'legacy path-addressed' -and $backupOut -match 'fresh BackupPath'
    }
    Assert-True $suite $group 'G4.1' 'Legacy_nothingMutated' {
        (Get-Content -LiteralPath $manifest -Raw) -eq $manifestBefore -and
        @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force -ErrorAction SilentlyContinue).Count -eq $snapshotsBefore -and
        -not (Test-Path -LiteralPath (Join-Path $Env.ChgPath 'Temp'))
    }

    # Verify must REPORT (exit 1, LegacyStoredForm finding), never refuse - an
    # audit action that cannot audit is useless.
    $verifyOut = (& $pwshExe -NoProfile -File $BackupScript -ConfigPath $cfg -NoMail -NonInteractive -Action Verify -ExitCode *>&1 | Out-String)
    $verifyCode = $LASTEXITCODE
    Assert-True $suite $group 'G4.1' 'Legacy_verifyReportsFinding' {
        $verifyCode -eq 1 -and $verifyOut -match 'LegacyStoredForm'
    }

    # The restore side REFUSES it too, and writes nothing (kit revision 7,
    # human ruling 2026-08-26). This inverts the old
    # 'Legacy_storeStillRestores' case: support for pre-content-addressed
    # stores is withdrawn deliberately, rather than claimed and left untested
    # on the bash half (WP9 review MIN-2, closed by withdrawal).
    $legacyTarget = Join-Path $Env.Root 'g4-legacy-restore'
    if (Test-Path -LiteralPath $legacyTarget) { Remove-Item -LiteralPath $legacyTarget -Recurse -Force }
    $restoreOut = (& $pwshExe -NoProfile -File (Join-Path $Env.BkpPath 'RECONSTRUCT.ps1') `
                      -TargetRoot $legacyTarget -ExitCode -NonInteractive *>&1 | Out-String)
    $restoreCode = $LASTEXITCODE
    Assert-True $suite $group 'G4.1' 'Legacy_restoreRefused' { $restoreCode -eq 2 }
    Assert-True $suite $group 'G4.1' 'Legacy_restoreRefusalNamesCause' {
        $restoreOut -match 'legacy path-addressed' -and $restoreOut -match 'StoredAsHashSize'
    }
    Assert-True $suite $group 'G4.1' 'Legacy_restoreWroteNothing' {
        -not (Test-Path -LiteralPath (Join-Path $legacyTarget 'doc.txt')) -and
        -not (Test-Path -LiteralPath (Join-Path $legacyTarget 'sub\img.bin'))
    }

    # Un-flip the row: the refusal is precise, and the healed store backs up.
    $rows = @(Import-Csv -LiteralPath $manifest)
    @($rows | Where-Object RelativePath -eq 'doc.txt')[0].StoredAsHashSize = 'Hash'
    $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation
    Write-ManifestWitness -FolderPath $Env.BkpPath | Out-Null
    & $pwshExe -NoProfile -File $BackupScript -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null
    Assert-True $suite $group 'G4.1' 'Legacy_unflippedStoreBacksUp' { $LASTEXITCODE -eq 0 }

    Invoke-G4ExtensionMerge -Env $Env -BackupScript $BackupScript -Mode $Mode -Compress $Compress
}

function Invoke-G4ExtensionMerge {
    <#
    .SYNOPSIS
        G4.2 / TC-097 - the SR-004 already-compressed extension-list merge at
        scale, and the migration it triggers.

    .DESCRIPTION
        The eight extensions WP5 merged in (.jar .tgz .zst .gif .webm .ogg .sav
        .pack) were compressible under the PRE-merge list, so an existing backup
        holds them as .7z with Compressed=Yes. That pre-merge state is
        constructed here as a genuinely well-formed store - real archives, real
        manifest rows, witness re-stamped - and the next run is what the merge
        actually does to a real backup: under SR-061, NOTHING. The merge changes
        which extensions get compressed on the way IN; it never re-packs what is
        already stored, so those rows stay exactly as they are.

        Then the properties that matter: nothing dangles, EVERY state (both
        snapshots and the latest) restores byte-exact with exit 0, runs stay
        idempotent (SR-024), and storage-form verification (SR-049) reports zero
        findings - a row whose Compressed=Yes claim matches genuine archive
        bytes is WELL-FORMED, whatever the current extension list says.

        The bash restorer's half of "both restorers" is TC-099 / TC-054 under
        bats; this Windows suite cannot drive it.
    #>
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G4-Sanitization'
    $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
    if (-not $sevenZip -or -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
        Add-TestResult $suite $group 'G4.2' 'ExtensionMerge_requires7Zip' 'SKIP' '7-Zip not available'
        return
    }

    Reset-TestEnvironment $Env
    # Compression must be ON - the merge only means anything for a compressing
    # backup - so this scenario is the same under both sweep labels.
    $cfg = Join-Path $Env.Root 'cfg-g4-extmerge.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $true

    $merged = @('.jar', '.tgz', '.zst', '.gif', '.webm', '.ogg', '.sav', '.pack')
    foreach ($ext in $merged) {
        New-TestFile (Join-Path $Env.SrcPath "media$ext") ("PAYLOAD-$ext " * 200)
    }
    New-TestFile (Join-Path $Env.SrcPath 'notes.txt') ('COMPRESSIBLE TEXT ' * 200)
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-01-01 00:00:01') | Out-Null

    # Two snapshots, produced the ordinary way.
    New-TestFile (Join-Path $Env.SrcPath 'notes.txt') ('CHANGED TEXT ONE ' * 200)
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-02-02 00:00:02') | Out-Null
    New-TestFile (Join-Path $Env.SrcPath 'notes.txt') ('CHANGED TEXT TWO ' * 200)
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-03-03 00:00:03') | Out-Null

    # --- Construct the PRE-merge state: the eight extensions stored as .7z ---
    $rows = @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv'))
    $converted = 0
    foreach ($row in $rows) {
        $ext = [IO.Path]::GetExtension($row.RelativePath).ToLowerInvariant()
        if ($merged -notcontains $ext) { continue }
        if ($row.Compressed -eq 'Yes') { continue }
        $current = Join-Path $Env.BkpPath $row.DataPath
        if (-not (Test-Path -LiteralPath $current -PathType Leaf)) { continue }
        $archive = "$current.7z"
        Compress-FileWithSevenZip -SevenZipPath $sevenZip -SourceFile $current -Destination7z $archive
        Remove-Item -LiteralPath $current -Force
        $row.DataPath   = "$($row.DataPath).7z"
        $row.Compressed = 'Yes'
        $converted++
    }
    $rows | Export-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv') -NoTypeInformation
    Write-ManifestWitness -FolderPath $Env.BkpPath | Out-Null

    # A snapshot's BLANK-DataPath row carries no bytes of its own: its Compressed
    # column describes the copy hash recovery would locate, which is the pool
    # copy just converted above. Leaving those rows saying 'No' would make the
    # fixture describe a store that is NOT well-formed, and -Action Verify says
    # so (BlankRowFormDisagreement). Before WP9 this went unnoticed: the layout
    # migration decompressed the root rows back to raw on the next run and
    # silently re-aligned the divergence the fixture had created. SR-061 deleted
    # that migration, so the fixture has to be honest about the state it builds.
    foreach ($snapDir in @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory -Force |
                           Where-Object Name -match '^Snapshot_')) {
        $snapRows = @(Import-Csv -LiteralPath (Join-Path $snapDir.FullName 'MANIFEST.csv'))
        $touched = 0
        foreach ($row in $snapRows) {
            if (-not [string]::IsNullOrWhiteSpace($row.DataPath)) { continue }
            if ($merged -notcontains [IO.Path]::GetExtension($row.RelativePath).ToLowerInvariant()) { continue }
            $row.Compressed = 'Yes'
            $touched++
        }
        if ($touched -gt 0) {
            $snapRows | Export-Csv -LiteralPath (Join-Path $snapDir.FullName 'MANIFEST.csv') -NoTypeInformation
            Write-ManifestWitness -FolderPath $snapDir.FullName | Out-Null
        }
    }

    Assert-True $suite $group 'G4.2' 'ExtMerge_preMergeStateBuilt' { $converted -eq $merged.Count }

    # --- The run on the MERGED list: it must re-form nothing (SR-061) ---
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-04-04 00:00:04') | Out-Null

    Assert-True $suite $group 'G4.2' 'ExtMerge_rootRowsUntouched' {
        $after = @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv'))
        $affected = @($after | Where-Object { $merged -contains [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() })
        # Every affected row is still exactly as the pre-merge state left it:
        # the extension-list change applies to new writes, never to stored bytes.
        $affected.Count -eq $merged.Count -and
        @($affected | Where-Object { $_.Compressed -ne 'Yes' }).Count -eq 0 -and
        @($affected | Where-Object { $_.DataPath -notlike '*.7z' }).Count -eq 0 -and
        @($affected | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Env.BkpPath $_.DataPath) -PathType Leaf) }).Count -eq 0
    }
    Assert-True $suite $group 'G4.2' 'ExtMerge_noDanglingReference' {
        @(Test-PoolResolves -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath |
          Where-Object Kind -eq 'broken-pool').Count -eq 0
    }
    Assert-True $suite $group 'G4.2' 'ExtMerge_verifiesClean' {
        @(Test-BackupStorageForm -BackupRoot $Env.BkpPath -ChangeRoot $Env.ChgPath).Count -eq 0
    }

    # --- Every state still restores byte-exact ---
    $origins = @([pscustomobject]@{ Name = 'latest'; Folder = $Env.BkpPath })
    foreach ($snap in @(Get-ChildItem -LiteralPath $Env.ChgPath -Directory | Where-Object Name -match '^Snapshot_')) {
        $origins += [pscustomobject]@{ Name = $snap.Name; Folder = $snap.FullName }
    }
    Assert-True $suite $group 'G4.2' 'ExtMerge_snapshotsPresent' { $origins.Count -ge 3 }

    foreach ($origin in $origins) {
        $target = Join-Path $Env.Root "g4-extmerge-restore-$($origin.Name)"
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        $failed = $null
        try {
            Invoke-Reconstruct -ReconstructScript (Join-Path $origin.Folder 'RECONSTRUCT.ps1') -TargetRoot $target
        } catch {
            $failed = $_.Exception.Message
        }
        Assert-True $suite $group 'G4.2' "ExtMerge_restore_$($origin.Name)_exit0" { -not $failed }

        # Every row of THAT origin's manifest reproduces its recorded hash.
        Assert-True $suite $group 'G4.2' "ExtMerge_restore_$($origin.Name)_byteExact" {
            $bad = 0
            foreach ($row in @(Import-Csv -LiteralPath (Join-Path $origin.Folder 'MANIFEST.csv'))) {
                $restored = Join-Path $target $row.RelativePath
                if (-not (Test-Path -LiteralPath $restored -PathType Leaf)) { $bad++; continue }
                if ((Get-FileXxHash -FilePath $restored) -ne $row.xxH2Hash) { $bad++ }
            }
            $bad -eq 0
        }
    }

    # --- SR-024 idempotence. Under SR-061 no run is "the migration" any more,
    # so run2 = run3 is now simply the steady state rather than a concession.
    # Row CONTENT ordered by RelativePath: manifest row ORDER is not a documented
    # contract (G7 owns determinism).
    $rowDigest = {
        @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv') | Sort-Object RelativePath |
          ForEach-Object { ($_.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '|' }) -join "`n"
    }
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-05-05 00:00:05') | Out-Null
    $run2 = & $rowDigest
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-06-06 00:00:06') | Out-Null
    $run3 = & $rowDigest
    Assert-True $suite $group 'G4.2' 'ExtMerge_thirdRunIdempotent' { $run3 -eq $run2 }
}
