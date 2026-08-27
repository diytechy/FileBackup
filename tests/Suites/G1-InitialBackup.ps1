<#
.SYNOPSIS  G1 - Initial-backup behaviours.
.NOTES     Invoked by Run-All.ps1. Expects $Env (backend), $BackupScript, $Mode, $Compress.
#>
function Invoke-G1 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G1-InitialBackup'

    # ---- G1.1 Empty source ----
    Reset-TestEnvironment $Env
    $cfg = Join-Path $Env.Root 'cfg-g1.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress

    Assert-True $suite $group 'G1.1' 'EmptySource_completes' {
        try { Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null; $true }
        catch { $script:G1_1_err = $_.Exception.Message; $false }
    }

    # ---- G1.2 Single file ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'single.txt') 'Hello'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.2' 'Single_present' (Join-Path $Env.BkpPath 'MANIFEST.csv') 'single.txt' $true

    # ---- G1.3 Many small files ----
    Reset-TestEnvironment $Env
    1..200 | ForEach-Object {
        New-TestFile (Join-Path $Env.SrcPath ("bulk\f{0:000}.txt" -f $_)) ("payload $_")
    }
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    Assert-True $suite $group 'G1.3' 'BulkFiles_200rows' {
        if (-not (Test-Path -LiteralPath $manifest)) { return $false }
        @(Import-Csv -LiteralPath $manifest).Count -ge 200
    }

    # ---- G1.6 Names the stored-object grammar has to survive (TC-148, SR-070) ----
    # An EXTENSIONLESS file is the regression that matters: until 2026-08-27
    # Get-HashSizeFileName's -Extension was [Parameter(Mandatory)], which in
    # PowerShell REJECTS the empty string, so a Plain-mode set containing any
    # extensionless file (README, LICENSE, Makefile) failed ENTIRELY - exit 1,
    # nothing stored. It was invisible in Compress mode, because an empty
    # extension is not in the non-compressible list so the name became '.7z'
    # before it ever reached the encoder. That asymmetry is why this case must
    # run in BOTH modes, and why the matrix never caught it.
    #
    # The rest pin SR-070's other half: the stored extension is the source's
    # own, so it is OPAQUE - a space, an underscore or brackets in it must
    # neither break the name grammar nor be mistaken for a legacy store.
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'README')          'no extension at all'
    New-TestFile (Join-Path $Env.SrcPath 'signed.foo bar')  'extension with a space'
    New-TestFile (Join-Path $Env.SrcPath 'archive.a_b')     'extension with the separator'
    New-TestFile (Join-Path $Env.SrcPath 'odd.[x]')         'extension with brackets'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg -ExpectSuccess `
        -Suite $suite -Group $group -ScenarioId 'G1.6' -Label 'awkward-extension set' | Out-Null

    foreach ($rel in 'README', 'signed.foo bar', 'archive.a_b', 'odd.[x]') {
        Assert-ManifestRow $suite $group 'G1.6' "Ext_rowPresent_$rel" $manifest $rel $true
    }

    # Every stored object must parse under SR-069 - which is exactly what the
    # SR-061 gate tests, so a name that fails here would make the next backup
    # of this store refuse it as legacy.
    Assert-True $suite $group 'G1.6' 'Ext_namesParseUnderGrammar' {
        $rows = @(Import-Csv -LiteralPath $manifest) | Where-Object { $_.DataPath }
        if ($rows.Count -lt 4) { return $false }
        foreach ($r in $rows) {
            if (-not (Test-HashSizeFileName -Name $r.DataPath)) { return $false }
            # The name carries the WHOLE hash since WP12: it must decode back to
            # the row's own xxH2Hash, all 32 digits.
            $parsed = ConvertFrom-HashSizeFileName -Name $r.DataPath
            if ($parsed.HashHex -ne $r.xxH2Hash) { return $false }
            if ($parsed.Length  -ne [long]$r.Length) { return $false }
        }
        $true
    }

    # The extensionless object must be named with NO extension, not '.7z',
    # whenever this mode stores it raw.
    Assert-True $suite $group 'G1.6' 'Ext_extensionlessKeepsNoExtension' {
        $row = Get-ManifestRow $manifest 'README'
        if (-not $row) { return $false }
        if ($Compress) { return $row.DataPath -match '\.7z$' }
        (ConvertFrom-HashSizeFileName -Name $row.DataPath).Extension -eq ''
    }

    # Round-trip: the whole point is that these restore byte-exact.
    $g16Restore = Join-Path $Env.Root 'restore-g1-6'
    Remove-Item -LiteralPath $g16Restore -Recurse -Force -ErrorAction SilentlyContinue
    Invoke-Reconstruct -ReconstructScript (Join-Path $Env.BkpPath 'RECONSTRUCT.ps1') -TargetRoot $g16Restore
    foreach ($rel in 'README', 'signed.foo bar', 'archive.a_b', 'odd.[x]') {
        Assert-FilesByteEqual $suite $group 'G1.6' "Ext_restored_$rel" `
            (Join-Path $Env.SrcPath $rel) (Join-Path $g16Restore $rel)
    }

    # ---- G1.5 Source contains a literal MANIFEST.csv at a sub-path (regression for B6) ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'sub\MANIFEST.csv') 'fake,manifest,row'
    New-TestFile (Join-Path $Env.SrcPath 'sub\other.txt')    'real payload'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    # NOTE: today FileBackup.ps1 filters by Name only — this assertion exposes bug B6.
    Assert-ManifestRow $suite $group 'G1.5' 'NestedManifest_preserved' $manifest 'sub\MANIFEST.csv' $true

    # ---- G1.6 Unicode filenames ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'Δοκιμή.txt') 'unicode-greek'
    New-TestFile (Join-Path $Env.SrcPath '测试.bin')   'unicode-chinese'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.6' 'Unicode_Greek'   $manifest 'Δοκιμή.txt' $true
    Assert-ManifestRow $suite $group 'G1.6' 'Unicode_Chinese' $manifest '测试.bin'  $true

    # ---- G1.8 Brackets/parentheses ----
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'folder[1]\file(2).txt') 'special-chars'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-ManifestRow $suite $group 'G1.8' 'SpecialChars_present' $manifest 'folder[1]\file(2).txt' $true
}
