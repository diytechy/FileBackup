<#
.SYNOPSIS  Kit revision 14: the restore resolves a blank or stale DataPath through
           a NAME INDEX built once per restore, falls back to the content scan
           only when the index has no usable candidate, and no longer reads the
           MANIFEST.csv.meta witness (bounded-run-loop section 7, R5, R6).
.NOTES     The end-to-end cases drive real backup runs and restore through the
           DEPLOYED kit, so the restorer under test is the one a user gets. The
           unit cases lift the two index functions out of Reconstruct.ps1's AST
           (it is a script, and dot-sourcing it would start a restore).
           The bats twin is tests/bash/restore_index.bats.
           Run: Invoke-Pester -Path tests\Unit\RestoreIndex.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry   = Join-Path $repo 'FileBackup.ps1'
    $script:pwshExe = (Get-Process -Id $PID).Path

    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repo 'Reconstruct.ps1'), [ref]$null, [ref]$null)
    $all = $ast.FindAll({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($name in 'New-StoredObjectNameIndex', 'Find-DataFileByName', 'Show-ReconstructUsage') {
        $fn = $all | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $fn) { throw "Reconstruct.ps1 no longer defines $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    function New-IndexConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg, [bool]$Compress = $false)
        $set = [pscustomobject]@{
            Name = 'I'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function New-IndexStore {
        <#
        .SYNOPSIS
            A real store with ONE snapshot: a first backup, then a second run
            that changes one file and deletes another, so the snapshot holds
            the superseded objects and latest holds the rest. Returns the paths
            a test needs plus the snapshot folder.
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub'), $bkp, $chg -Force | Out-Null
        # Large and repetitive so a Compress-mode store really stores a .7z.
        Set-Content -LiteralPath (Join-Path $src 'keep.txt')     -Value ('KEEP-CONTENT-' * 3000) -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'change.txt')   -Value ('OLD-VERSION-' * 3000) -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'gone.txt')     -Value ('DELETED-LATER-' * 3000) -NoNewline
        Set-Content -LiteralPath (Join-Path $src 'sub\twin.txt') -Value ('KEEP-CONTENT-' * 3000) -NoNewline
        $cfg = Join-Path $Root 'cfg.xml'
        New-IndexConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null

        Set-Content -LiteralPath (Join-Path $src 'change.txt') -Value ('NEW-VERSION-' * 3000) -NoNewline
        Remove-Item -LiteralPath (Join-Path $src 'gone.txt') -Force
        & $entry -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null

        $snap = @(Get-ChildItem -LiteralPath $chg -Directory -Force |
                    Where-Object { $_.Name -like 'Snapshot_*' } | Sort-Object Name)[-1]
        [pscustomobject]@{
            Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg
            Snap      = $snap.FullName
            Manifest  = Join-Path $bkp 'MANIFEST.csv'
            Recon     = Join-Path $bkp 'RECONSTRUCT.ps1'
            SnapRecon = Join-Path $snap.FullName 'RECONSTRUCT.ps1'
        }
    }

    function Invoke-IndexRestore {
        # Child process so RECONSTRUCT.ps1's -ExitCode `exit` is observable at
        # the process boundary - the same numbers reconstruct.sh returns.
        param([string]$Recon, [string]$TargetRoot, [string[]]$Extra = @())
        $out = & $pwshExe -NoProfile -File $Recon -TargetRoot $TargetRoot -ExitCode -NonInteractive @Extra *>&1 |
            Out-String
        $logFile = Join-Path $TargetRoot 'RECONSTRUCT.log'
        $log = if (Test-Path -LiteralPath $logFile) { Get-Content -LiteralPath $logFile -Raw } else { '' }
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out; Log = $log }
    }

    function Assert-RestoredFromManifest {
        # Byte-exact against the AUTHORITY: every row of the manifest that was
        # restored must hash to that row's own (Length, xxH2Hash).
        param([string]$Manifest, [string]$TargetRoot)
        $rows = @(Import-Csv -LiteralPath $Manifest)
        $rows.Count | Should -BeGreaterThan 0
        foreach ($r in $rows) {
            $f = Join-Path $TargetRoot $r.RelativePath
            Test-Path -LiteralPath $f -PathType Leaf | Should -BeTrue -Because "$($r.RelativePath) must be restored"
            (Get-Item -LiteralPath $f).Length | Should -Be ([long]$r.Length)
            Get-FileXxHash -FilePath $f | Should -Be $r.xxH2Hash -Because "$($r.RelativePath) must be byte-exact"
        }
    }
}

Describe 'The name index (kit revision 14, SR-069)' {
    BeforeAll {
        $script:ix = Join-Path $TestDrive 'ix'
        $script:origin = Join-Path $ix 'Snapshot_2024_01_02_00_00_00'
        $script:root   = Join-Path $ix 'root'
        $script:older  = Join-Path $ix 'Snapshot_2024_01_01_00_00_00'
        New-Item -ItemType Directory -Path $origin, $root, $older -Force | Out-Null
        $script:hashA = 'BE20CA004CC2993A396345E0D52DF013'
        $script:nameA = Get-HashSizeFileName -HashHex $hashA -Length 42 -Extension '.txt'
        # The same key in all three folders, so the ORDER is observable.
        foreach ($d in $origin, $root, $older) { [IO.File]::WriteAllText((Join-Path $d $nameA), 'x') }
        # One key only in the oldest snapshot, under a compressed name.
        $script:hashB = '00000000000000000000000000000001'
        $script:nameB = Get-HashSizeFileName -HashHex $hashB -Length 7 -Extension '.7z'
        [IO.File]::WriteAllText((Join-Path $older $nameB), 'y')
        # Things that are NOT objects: infrastructure, debris, a pre-WP12 name,
        # and an object-shaped name nested one level down (objects never nest).
        foreach ($junk in 'MANIFEST.csv', 'MANIFEST.csv.meta', 'notes.txt', 'lii`7EXH@[hgD!I= !!!!!!=X&K.7z') {
            [IO.File]::WriteAllText((Join-Path $root $junk), 'j')
        }
        New-Item -ItemType Directory -Path (Join-Path $root 'nested') -Force | Out-Null
        $script:nameC = Get-HashSizeFileName -HashHex 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' -Length 1 -Extension ''
        [IO.File]::WriteAllText((Join-Path $root "nested\$nameC"), 'n')

        $script:index = New-StoredObjectNameIndex -Folders @($origin, $root, $older)
    }

    It 'keys every SR-069 name by the (hash, length) it carries, and nothing else' {
        @($index.Keys) | Sort-Object | Should -Be (@("$($hashA):42", "$($hashB):7") | Sort-Object)
    }

    It 'lists candidates in folder order: origin, then backup root, then older snapshots' {
        @($index["$($hashA):42"]) | Should -Be @(
            (Join-Path $origin $nameA), (Join-Path $root $nameA), (Join-Path $older $nameA))
    }

    It 'resolves a row to the first candidate, matching the hash case-insensitively' {
        Find-DataFileByName -Index $index -Hash $hashA.ToLowerInvariant() -Length 42 |
            Should -Be (Join-Path $origin $nameA)
        Find-DataFileByName -Index $index -Hash $hashB -Length 7 | Should -Be (Join-Path $older $nameB)
    }

    It 'skips a candidate that has gone since the listing' {
        $gone = Join-Path $ix 'gone'
        New-Item -ItemType Directory -Path $gone -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $gone $nameA), 'x')
        $local = New-StoredObjectNameIndex -Folders @($gone, $root)
        Remove-Item -LiteralPath (Join-Path $gone $nameA) -Force
        Find-DataFileByName -Index $local -Hash $hashA -Length 42 | Should -Be (Join-Path $root $nameA)
    }

    It 'answers $null for a key it does not hold, a wrong length, or an empty index' {
        Find-DataFileByName -Index $index -Hash $hashA -Length 43 | Should -BeNullOrEmpty
        Find-DataFileByName -Index $index -Hash 'DEADBEEFDEADBEEFDEADBEEFDEADBEEF' -Length 42 | Should -BeNullOrEmpty
        Find-DataFileByName -Index @{} -Hash $hashA -Length 42 | Should -BeNullOrEmpty
    }

    It 'ignores a folder that does not exist rather than failing' {
        $local = New-StoredObjectNameIndex -Folders @((Join-Path $ix 'no-such-folder'), $older)
        @($local.Keys).Count | Should -Be 2
    }
}

Describe 'The bash decoder''s conformance corpus agrees with the PowerShell parser (kit revision 14, SR-069)' {
    # tests/fixtures/name-grammar/decode.tsv is what tests/bash/name_grammar.bats
    # holds decode_hash_size_names to. Re-deriving every row from the ONE parser
    # here means the corpus cannot drift from the grammar it pins - the same
    # arrangement Common.Tests.ps1 keeps for cases.tsv.
    It 'records, for every name, exactly what ConvertFrom-HashSizeFileName answers' {
        $path = Join-Path $repo 'tests\fixtures\name-grammar\decode.tsv'
        $lines = @([IO.File]::ReadAllLines($path, [Text.UTF8Encoding]::new($false)) | Where-Object { $_ })
        $lines[0] | Should -Be "Name`tHashHex`tLength"
        $rows = @($lines | Select-Object -Skip 1)
        $rows.Count | Should -BeGreaterOrEqual 120
        $bad = foreach ($line in $rows) {
            $name, $hash, $len = $line -split "`t"
            $p = ConvertFrom-HashSizeFileName -Name $name
            $want = if ($p) { "$($p.HashHex)`t$($p.Length)" } else { "-`t-" }
            if ("$hash`t$len" -ne $want) { "'$name': corpus says '$hash $len', the parser says '$want'" }
        }
        $bad | Should -BeNullOrEmpty
        @($rows | Where-Object { $_ -match "`t-`t-$" }).Count | Should -BeGreaterOrEqual 15 -Because 'the rejects are half the point'
    }
}

Describe 'Snapshot restore resolves blank rows through the name index (kit revision 14)' -ForEach @(
    @{ Mode = 'Plain'; Compress = $false }, @{ Mode = 'Compress'; Compress = $true }
) {
    It 'restores a snapshot whose rows are ALL blank byte-exact, without the content scan (<Mode>)' {
        $root = Join-Path $TestDrive ('blank-' + $Mode)
        $s = New-IndexStore -Root $root -Compress $Compress
        $snapManifest = Join-Path $s.Snap 'MANIFEST.csv'
        $rows = @(Import-Csv -LiteralPath $snapManifest)
        @($rows | Where-Object RelativePath -eq 'gone.txt').Count | Should -Be 1 -Because 'the snapshot preserves the deleted file'
        # The worst case the field sees (about 96% of real snapshot rows are
        # blank): EVERY DataPath blank, so every byte has to be found by key -
        # in the snapshot itself (change.txt's old version, gone.txt) and in
        # latest (keep.txt and its twin).
        foreach ($r in $rows) { $r.DataPath = '' }
        $rows | Export-Csv -LiteralPath $snapManifest -NoTypeInformation

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.SnapRecon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest $snapManifest -TargetRoot $t
        Get-Content -LiteralPath (Join-Path $t 'change.txt') -Raw | Should -Be ('OLD-VERSION-' * 3000)

        # The proof that the scan did not run: every row says it was resolved
        # by name, and the content scan's own lines never appear.
        ([regex]::Matches($r.Log, 'resolved by name index')).Count | Should -Be $rows.Count
        $r.Log | Should -Match 'Name index built'
        $r.Log | Should -Not -Match 'attempting hash scan'
        $r.Log | Should -Not -Match 'Hash-recovered'
    }
}

Describe 'A snapshot finds its backup root beside its change root (one-mount layout, plan R8)' {
    It 'indexes the sibling backup root of a copied store (store\bkp beside store\chg), so no row needs the content scan' {
        $root = Join-Path $TestDrive 'onemount'
        $made = New-IndexStore -Root (Join-Path $root 'store')
        # A copy, so the path sidecar's recorded roots no longer hold the origin
        # and the kit falls back to auto-detection - the host's view of a store
        # the container wrote under /store.
        $copy = Join-Path $root 'copied'
        Copy-Item -LiteralPath (Join-Path $root 'store') -Destination $copy -Recurse
        $snap = Join-Path (Join-Path $copy 'chg') (Split-Path $made.Snap -Leaf)
        $rows = @(Import-Csv -LiteralPath (Join-Path $snap 'MANIFEST.csv'))
        @($rows | Where-Object { -not (Test-Path -LiteralPath (Join-Path $snap $_.DataPath) -PathType Leaf) }).Count |
            Should -BeGreaterThan 0 -Because 'some rows must name objects that live in the backup root'

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon (Join-Path $snap 'RECONSTRUCT.ps1') -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest (Join-Path $snap 'MANIFEST.csv') -TargetRoot $t
        $r.Log | Should -Not -Match 'attempting hash scan' -Because 'the backup root beside the change root is indexed by name'
        $r.Log | Should -Not -Match 'Hash-recovered'
    }

    It 'restores the latest state of a copied store whose row names an object still in a snapshot (plan C32)' {
        # A move back that failed (or call C19) leaves a latest row naming an
        # object inside a snapshot. With no change root recorded for the copy,
        # the kit finds the change folder beside the backup folder.
        $root = Join-Path $TestDrive 'latest-in-snapshot'
        $made = New-IndexStore -Root (Join-Path $root 'store')
        $copy = Join-Path $root 'copied'
        Copy-Item -LiteralPath (Join-Path $root 'store') -Destination $copy -Recurse
        $bkp = Join-Path $copy 'bkp'
        $snap = Join-Path (Join-Path $copy 'chg') (Split-Path $made.Snap -Leaf)
        $keep = @(Import-Csv -LiteralPath (Join-Path $bkp 'MANIFEST.csv') | Where-Object RelativePath -eq 'keep.txt')[0]
        Move-Item -LiteralPath (Join-Path $bkp $keep.DataPath) -Destination (Join-Path $snap $keep.DataPath)

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon (Join-Path $bkp 'RECONSTRUCT.ps1') -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest (Join-Path $bkp 'MANIFEST.csv') -TargetRoot $t
    }
}

Describe 'A stale DataPath resolves through the name index (kit revision 14, R6)' {
    It 'finds an object that was moved to another pool folder (Plain)' {
        $root = Join-Path $TestDrive 'moved'
        $s = New-IndexStore -Root $root
        # Latest's keep.txt object moves into the snapshot - the shape a
        # write-once snapshot manifest goes stale with, seen from the other
        # side. Its row still names it in latest.
        $row = @(Import-Csv -LiteralPath $s.Manifest | Where-Object RelativePath -eq 'keep.txt')[0]
        $row.DataPath | Should -Not -BeNullOrEmpty
        Move-Item -LiteralPath (Join-Path $s.Bkp $row.DataPath) -Destination (Join-Path $s.Snap $row.DataPath)

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest $s.Manifest -TargetRoot $t
        $r.Log | Should -Match ("Data file '" + [regex]::Escape($row.DataPath) + "' missing for keep\.txt; resolved by name index")
        $r.Log | Should -Not -Match 'attempting hash scan'
    }

    It 'falls back to the content scan only when the index has no usable candidate' {
        $root = Join-Path $TestDrive 'fallback'
        $s = New-IndexStore -Root $root
        # The object survives under a name that is not an object name: the
        # index cannot see it, so the last-resort scan must.
        $row = @(Import-Csv -LiteralPath $s.Manifest | Where-Object RelativePath -eq 'change.txt')[0]
        Move-Item -LiteralPath (Join-Path $s.Bkp $row.DataPath) -Destination (Join-Path $s.Bkp 'renamed-by-hand.bin')

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Get-Content -LiteralPath (Join-Path $t 'change.txt') -Raw | Should -Be ('NEW-VERSION-' * 3000)
        $r.Log | Should -Match 'missing for change\.txt; attempting hash scan'
        $r.Log | Should -Match "Hash-recovered change\.txt from '.*renamed-by-hand\.bin'"
    }

    It 'treats an index hit like a DataPath file: wrong bytes under the right name are verified and healed' {
        $root = Join-Path $TestDrive 'lying-name'
        $s = New-IndexStore -Root $root
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        $row = @($rows | Where-Object RelativePath -eq 'change.txt')[0]
        $obj = Join-Path $s.Bkp $row.DataPath
        # A good copy survives under a non-object name; the object the index
        # will pick carries same-length WRONG bytes, and the row is blank.
        Copy-Item -LiteralPath $obj -Destination (Join-Path $s.Bkp 'spare.bin')
        Set-Content -LiteralPath $obj -Value ('BAD-VERSION-' * 3000) -NoNewline
        $row.DataPath = ''
        $rows | Export-Csv -LiteralPath $s.Manifest -NoTypeInformation

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Get-Content -LiteralPath (Join-Path $t 'change.txt') -Raw | Should -Be ('NEW-VERSION-' * 3000)
        $r.Log | Should -Match 'No datapath for change\.txt; resolved by name index'
        $r.Log | Should -Match '\[ContentMismatch\]'
        $r.Log | Should -Match 'after a verify mismatch'
    }
}

Describe 'The restorer no longer reads MANIFEST.csv.meta (kit revision 14, R5)' {
    It 'a witness that DISAGREES with its manifest no longer refuses: exit 0, not 3' {
        $root = Join-Path $TestDrive 'stale-meta'
        $s = New-IndexStore -Root $root
        # Edit the manifest WITHOUT re-stamping: before revision 14 this was
        # exit 3 ("the index is damaged; nothing was restored").
        $rows = @(Import-Csv -LiteralPath $s.Manifest)
        foreach ($r in $rows) { $r.DataPath = '' }
        $rows | Export-Csv -LiteralPath $s.Manifest -NoTypeInformation
        (Test-ManifestWitness -FolderPath $s.Bkp).Status | Should -Not -Be 'Verified' -Because 'the witness must really be stale'

        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest $s.Manifest -TargetRoot $t
        $r.Output + $r.Log | Should -Not -Match '(?i)witness'
    }

    It 'a GARBAGE witness, or one declaring the pre-WP12 format version, is ignored' {
        $root = Join-Path $TestDrive 'garbage-meta'
        $s = New-IndexStore -Root $root
        $meta = Join-Path $s.Bkp 'MANIFEST.csv.meta'
        [IO.File]::WriteAllText($meta, "garbage sidecar, no keys here`n")
        $t1 = Join-Path $root 'restored1'
        (Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t1).Code | Should -Be 0

        # Version=1 was the witness marker for a pre-WP12 store (exit 2). The
        # name-grammar markers still refuse such a store; the witness does not.
        [IO.File]::WriteAllText($meta, "Version=1`nRows=1`nBytes=1`nXxH128=00`n")
        $t2 = Join-Path $root 'restored2'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t2
        $r.Code | Should -Be 0 -Because $r.Output
        Assert-RestoredFromManifest -Manifest $s.Manifest -TargetRoot $t2
    }

    It 'an ABSENT witness restores with no "unverified index" warning' {
        $root = Join-Path $TestDrive 'no-meta'
        $s = New-IndexStore -Root $root
        Test-Path -LiteralPath (Join-Path $s.Bkp 'MANIFEST.csv.meta') | Should -BeFalse -Because 'no witness is written (plan R5)'
        $t = Join-Path $root 'restored'
        $r = Invoke-IndexRestore -Recon $s.Recon -TargetRoot $t
        $r.Code | Should -Be 0 -Because $r.Output
        $r.Output + $r.Log | Should -Not -Match '(?i)unverified'
    }

    It 'has no -RequireWitness parameter, and the usage text no longer offers it or exit 3' {
        $params = (Get-Command (Join-Path $repo 'Reconstruct.ps1')).Parameters.Keys
        $params | Should -Not -Contain 'RequireWitness'
        $params | Should -Contain 'ExitCode' -Because 'the parameter list really was read'
        $usage = Show-ReconstructUsage
        $usage | Should -Match 'Usage: RECONSTRUCT\.ps1'
        $usage | Should -Not -Match 'RequireWitness'
        $usage | Should -Match '2 > 4 > 1'
    }

    It 'does not call Test-ManifestWitness anywhere' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repo 'Reconstruct.ps1'), [ref]$null, [ref]$null)
        $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and
                                $n.GetCommandName() -eq 'Test-ManifestWitness' }, $true)
        @($calls).Count | Should -Be 0
    }
}
