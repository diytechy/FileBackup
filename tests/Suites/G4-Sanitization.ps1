<#
.SYNOPSIS  G4 - manifest sanitization and the no-re-forming contract.
.NOTES     Always runs - changes config between two backup runs.
           SR-061 (WP9): there is NO storage-layout migration. A configuration
           change governs content written AFTER it; nothing already stored is
           ever re-formed. These cases assert that, where they used to assert
           the migration.
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

    # Switch the configuration to HashAddressed. SR-061: this re-forms NOTHING
    # that is already stored - it governs content written from here on.
    $cfgHash = Join-Path $Env.Root 'cfg-g4-hash.xml'
    Write-TestConfig $cfgHash $Env.SrcPath $Env.BkpPath $Env.ChgPath $false $true
    New-TestFile (Join-Path $Env.SrcPath 'after.txt') 'written after the switch'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfgHash | Out-Null

    Assert-True $suite $group 'G4.1' 'AfterSwitch_storedRowsUntouched' {
        # The pre-switch rows keep their form AND their bytes: no re-forming.
        $row = Get-ManifestRow $manifest 'doc.txt'
        (Test-Path -LiteralPath (Join-Path $Env.BkpPath 'doc.txt')) -and
        $row -and $row.StoredAsHashSize -eq 'Original' -and $row.DataPath -eq 'doc.txt'
    }
    Assert-True $suite $group 'G4.1' 'AfterSwitch_newContentFollowsConfig' {
        # ...while content written AFTER the switch is content-addressed.
        $row = Get-ManifestRow $manifest 'after.txt'
        $row -and $row.StoredAsHashSize -eq 'Hash' -and $row.DataPath -ne 'after.txt'
    }
    Assert-True $suite $group 'G4.1' 'AfterSwitch_mixedStoreRestores' {
        # A mixed-form store is normal, and every row still restores byte-exact.
        $target = Join-Path $Env.Root 'g4-mixed-restore'
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        $failed = $null
        try { Invoke-Reconstruct -ReconstructScript (Join-Path $Env.BkpPath 'RECONSTRUCT.ps1') -TargetRoot $target }
        catch { $failed = $_.Exception.Message }
        if ($failed) { return $false }
        $bad = 0
        foreach ($row in @(Import-Csv -LiteralPath $manifest)) {
            $restored = Join-Path $target $row.RelativePath
            if (-not (Test-Path -LiteralPath $restored -PathType Leaf)) { $bad++; continue }
            if ((Get-FileXxHash -FilePath $restored) -ne $row.xxH2Hash) { $bad++ }
        }
        $bad -eq 0
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
