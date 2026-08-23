<#
.SYNOPSIS  G4 - SanitizeBackupDatabase / config migration.
.NOTES     Always runs - changes config between two backup runs.
           G4.2 is TC-097: the SR-004 extension-list merge at scale.
#>
function Invoke-G4 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G4-Sanitization'
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'

    # Seed in Mirror, Compress=Off
    Reset-TestEnvironment $Env
    $cfgMirror = Join-Path $Env.Root 'cfg-g4-mirror.xml'
    Write-TestConfig $cfgMirror $Env.SrcPath $Env.BkpPath $Env.ChgPath $false $false
    New-TestFile (Join-Path $Env.SrcPath 'doc.txt')      'document content'
    New-TestFile (Join-Path $Env.SrcPath 'sub\img.bin')  'binary blob'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfgMirror | Out-Null

    Assert-True $suite $group 'G4.1' 'AfterMirror_filesAtOriginalPath' {
        (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'doc.txt')) -and
        (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'sub\img.bin'))
    }

    # Migrate to HashAddressed
    $cfgHash = Join-Path $Env.Root 'cfg-g4-hash.xml'
    Write-TestConfig $cfgHash $Env.SrcPath $Env.BkpPath $Env.ChgPath $false $true
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfgHash | Out-Null

    Assert-True $suite $group 'G4.1' 'AfterMigrate_originalNamesGone' {
        # In hash-addressed mode files should NOT live at the original paths anymore.
        -not (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'doc.txt'))
    }
    Assert-True $suite $group 'G4.1' 'AfterMigrate_manifestStoredAsHash' {
        $row = Get-ManifestRow $manifest 'doc.txt'
        $row -and $row.StoredAsHashSize -eq 'Hash'
    }

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
        actually does to a real backup: Sync-BackupStorageLayout decompresses
        every affected root row.

        Then the properties that matter: nothing dangles, EVERY state (both
        snapshots and the latest) restores byte-exact with exit 0, a third run is
        idempotent (SR-024 - run2 = run3, never run1 = run2, because run1 IS the
        migration), and storage-form verification (SR-049) reports zero findings.

        The bash restorer's half of "both restorers" is TC-099 / TC-054 under
        bats; this Windows suite cannot drive it.
    #>
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G4-Sanitization'
    $sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
    if (-not $sevenZip -or -not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
        Add-TestResult $suite $group 'G4.2' 'ExtensionMerge_requires7Zip' 'SKIP' '7-Zip not available'
        return
    }

    Reset-TestEnvironment $Env
    # Compression must be ON - the merge only means anything for a compressing
    # backup. The storage-mode axis still varies with $Mode.
    $contentAddressed = ($Mode -ne 'Mirror')
    $cfg = Join-Path $Env.Root 'cfg-g4-extmerge.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $true $contentAddressed

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

    Assert-True $suite $group 'G4.2' 'ExtMerge_preMergeStateBuilt' { $converted -eq $merged.Count }

    # --- The merge-triggered migration: run on the MERGED list ---
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -BackupTime ([datetime]'2025-04-04 00:00:04') | Out-Null

    Assert-True $suite $group 'G4.2' 'ExtMerge_rootRowsDecompressed' {
        $after = @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv'))
        $affected = @($after | Where-Object { $merged -contains [IO.Path]::GetExtension($_.RelativePath).ToLowerInvariant() })
        $affected.Count -eq $merged.Count -and
        @($affected | Where-Object { $_.Compressed -ne 'No' }).Count -eq 0 -and
        @($affected | Where-Object { $_.DataPath -like '*.7z' }).Count -eq 0
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

    # --- SR-024: run1 IS the migration, so the property is run2 = run3 ---
    # Row CONTENT ordered by RelativePath: manifest row ORDER is not a documented
    # contract (G7 owns determinism), and the migration run legitimately reorders.
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
