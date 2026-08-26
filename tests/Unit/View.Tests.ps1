<#
.SYNOPSIS  Pester 5 unit tests for the browse view (SR-062, LLR-061, LLR-064;
           TC-129, TC-130, TC-131, TC-133).
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry   = Join-Path $repo 'FileBackup.ps1'
    $script:pwshExe = (Get-Process -Id $PID).Path

    function New-ViewConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $false, [string]$BrowseView = 'index', [string]$ViewPath = '')
        $set = [ordered]@{
            Name = 'V'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress; BrowseView = $BrowseView
        }
        if ($ViewPath) { $set['ViewPath'] = $ViewPath }
        @{ Secrets = $null; BackupSets = @([pscustomobject]$set) } | Export-Clixml -LiteralPath $Path
    }
    function Invoke-VB { param([string]$Cfg) & $entry -ConfigPath $Cfg -NoMail -NonInteractive *>&1 | Out-Null }
    function Invoke-VBExit {
        param([string]$Cfg, [string[]]$Extra = @())
        & $script:pwshExe -NoProfile -File $entry -ConfigPath $Cfg -NoMail -NonInteractive -ExitCode @Extra *>&1 | Out-Null
        return $LASTEXITCODE
    }

    function New-ViewStore {
        <#
        .SYNOPSIS
            One backup run over a tree with a dedup pair split across folders
            (the borrower Mirror used to OMIT), a nested-deep file, and an
            already-compressed extension (a mixed tree under +Compress).
        #>
        param([string]$Root, [bool]$Compress = $false)
        $src = Join-Path $Root 'src'; $bkp = Join-Path $Root 'bkp'; $chg = Join-Path $Root 'chg'
        $cfg = Join-Path $Root 'c.xml'
        New-Item -ItemType Directory -Path (Join-Path $src 'sub\deep') -Force | Out-Null
        New-ViewConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $Compress
        [IO.File]::WriteAllText((Join-Path $src 'a.bin'), ('SHARED ' * 50))
        [IO.File]::WriteAllText((Join-Path $src 'sub\pair.bin'), ('SHARED ' * 50))
        [IO.File]::WriteAllText((Join-Path $src 'sub\deep\note.txt'), 'DEEP NOTE')
        [IO.File]::WriteAllText((Join-Path $src 'pic.jpg'), 'pretend-jpeg')
        Invoke-VB $cfg
        return [pscustomobject]@{ Src = $src; Bkp = $bkp; Chg = $chg; Cfg = $cfg; View = ($bkp + '_View') }
    }

    function Get-PagePoolLink {
        # Every non-page href on a page, decoded and resolved to a full path
        # from the page's own folder — the link-integrity oracle.
        param([string]$PagePath)
        $dir  = Split-Path $PagePath -Parent
        $html = Get-Content -LiteralPath $PagePath -Raw
        foreach ($m in [regex]::Matches($html, 'href="([^"]+)"')) {
            $h = $m.Groups[1].Value
            if ($h -like '*INDEX.html') { continue }
            $decoded = [Uri]::UnescapeDataString($h) -replace '/', '\'
            [IO.Path]::GetFullPath((Join-Path $dir $decoded))
        }
    }
}

Describe 'The view mirrors the manifest exactly (SR-062, TC-129)' {
    It 'lists every logical path incl. dedup siblings, names entries from the ROW, and every href resolves to its object (<Mode>)' -ForEach @(
        @{ Mode = 'Plain';    Compress = $false }
        @{ Mode = 'Compress'; Compress = $true }
    ) {
        $t = New-ViewStore -Root (Join-Path $TestDrive ('v129\' + $Mode)) -Compress $Compress
        $manifestRows = @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv'))

        # INDEX.tsv is the authoritative mirror: one line per manifest row.
        $tsvLines = @(Get-Content -LiteralPath (Join-Path $t.View 'INDEX.tsv') | Select-Object -Skip 1)
        $tsvLines.Count | Should -Be $manifestRows.Count
        $tsvRel = @($tsvLines | ForEach-Object { ($_ -split "`t")[0] })
        foreach ($row in $manifestRows) { $tsvRel | Should -Contain $row.RelativePath }

        # One page per folder, mirrored as PAGES.
        foreach ($page in 'INDEX.html', 'sub\INDEX.html', 'sub\deep\INDEX.html') {
            Test-Path -LiteralPath (Join-Path $t.View $page) -PathType Leaf | Should -BeTrue
        }

        # BOTH dedup siblings appear — the borrower path Mirror used to omit —
        # and their links land on the SAME pool object.
        $rootLinks = @(Get-PagePoolLink -PagePath (Join-Path $t.View 'INDEX.html') | Where-Object { $_ -notmatch 'INDEX\.tsv$' })
        $subLinks  = @(Get-PagePoolLink -PagePath (Join-Path $t.View 'sub\INDEX.html'))
        $aRow    = @($manifestRows | Where-Object RelativePath -eq 'a.bin')[0]
        $pairRow = @($manifestRows | Where-Object RelativePath -eq 'sub\pair.bin')[0]
        $pairRow.DataPath | Should -Be $aRow.DataPath
        $rootLinks | Should -Contain ([IO.Path]::GetFullPath((Join-Path $t.Bkp $aRow.DataPath)))
        $subLinks  | Should -Contain ([IO.Path]::GetFullPath((Join-Path $t.Bkp $pairRow.DataPath)))

        # EVERY pool link on every page resolves to a real file.
        foreach ($page in @(Get-ChildItem -LiteralPath $t.View -Recurse -Filter 'INDEX.html')) {
            foreach ($link in @(Get-PagePoolLink -PagePath $page.FullName)) {
                Test-Path -LiteralPath $link -PathType Leaf | Should -BeTrue -Because "'$($page.FullName)' links '$link'"
            }
        }

        # Entry names come from the ROW: '.7z' exactly when that row is
        # compressed — a mixed tree under +Compress (pic.jpg stays raw).
        $rootHtml = Get-Content -LiteralPath (Join-Path $t.View 'INDEX.html') -Raw
        if ($Compress) {
            $rootHtml | Should -Match '>a\.bin\.7z<'
            $rootHtml | Should -Match '>pic\.jpg<'
            $rootHtml | Should -Not -Match '>pic\.jpg\.7z<'
        } else {
            $rootHtml | Should -Match '>a\.bin<'
            $rootHtml | Should -Not -Match '>a\.bin\.7z<'
        }

        # The root page embeds the search index below the threshold.
        $rootHtml | Should -Match 'id="q"'
        $rootHtml | Should -Match 'sub\\\\pair\.bin'
    }

    It 'prints the grep fallback instead of embedding search above the row threshold' {
        $t = New-ViewStore -Root (Join-Path $TestDrive 'v129thr')
        $log = { param($m, $l) }
        $result = New-BrowseViewIndex -BackupRoot $t.Bkp -ViewRoot $t.View -Log $log -Force -SearchRowThreshold 2
        $result.Regenerated | Should -BeTrue
        $rootHtml = Get-Content -LiteralPath (Join-Path $t.View 'INDEX.html') -Raw
        $rootHtml | Should -Not -Match 'id="q"'
        $rootHtml | Should -Match 'Select-String'
        $rootHtml | Should -Match 'grep'
    }
}

Describe 'Freshness, idempotence, torn views (SR-062, TC-131)' {
    It 'skips when the manifest is unchanged, rebuilds on change dropping stale entries, and never trusts a torn view' {
        $t = New-ViewStore -Root (Join-Path $TestDrive 'v131')
        $rootPage = Join-Path $t.View 'INDEX.html'
        $stamp    = Join-Path $t.View '.viewstamp'
        $writeTime = (Get-Item -LiteralPath $rootPage).LastWriteTimeUtc

        # 1. A manifest-identical run leaves the view untouched (stamp match).
        Invoke-VB $t.Cfg
        (Get-Item -LiteralPath $rootPage).LastWriteTimeUtc | Should -Be $writeTime

        # 2. A source change regenerates, ADDING the new entry and DROPPING the
        # removed one (regeneration wipes, so stale entries cannot linger).
        [IO.File]::WriteAllText((Join-Path $t.Src 'fresh.txt'), 'FRESH')
        Remove-Item -LiteralPath (Join-Path $t.Src 'pic.jpg') -Force
        Invoke-VB $t.Cfg
        $tsv = Get-Content -LiteralPath (Join-Path $t.View 'INDEX.tsv') -Raw
        $tsv | Should -Match 'fresh\.txt'
        $tsv | Should -Not -Match 'pic\.jpg'

        # 3. A TORN view (stamp gone — it is written LAST, so a torn run never
        # has a current one) is rebuilt, never trusted.
        Remove-Item -LiteralPath $stamp -Force
        $tornPageTime = (Get-Item -LiteralPath $rootPage).LastWriteTimeUtc
        Invoke-VB $t.Cfg
        Test-Path -LiteralPath $stamp -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $stamp -Raw).Trim() | Should -Match '^RowsSHA256=[0-9A-F]{64}$'
        (Get-Item -LiteralPath $rootPage).LastWriteTimeUtc |
            Should -Not -Be $tornPageTime -Because 'a torn view must be regenerated, not trusted'
    }

    It '-Action View rebuilds loudly and idempotently; a set without a view refuses with 2 (LLR-064)' {
        $t = New-ViewStore -Root (Join-Path $TestDrive 'v131a')
        (Invoke-VBExit -Cfg $t.Cfg -Extra @('-Action', 'View')) | Should -Be 0
        (Invoke-VBExit -Cfg $t.Cfg -Extra @('-Action', 'View')) | Should -Be 0 -Because 'a forced rebuild is idempotent'
        Test-Path -LiteralPath (Join-Path $t.View 'INDEX.tsv') | Should -BeTrue

        $offCfg = Join-Path $TestDrive 'v131a\off.xml'
        New-ViewConfig -Path $offCfg -Src $t.Src -Bkp $t.Bkp -Chg $t.Chg -BrowseView 'off'
        (Invoke-VBExit -Cfg $offCfg -Extra @('-Action', 'View')) | Should -Be 2
    }

    It 'refuses to overwrite a view root that holds a MANIFEST.csv (a STORE, not a view); the backup itself still succeeds' {
        $root = Join-Path $TestDrive 'v131b'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        $cfg = Join-Path $root 'c.xml'
        New-Item -ItemType Directory -Path $src, ($bkp + '_View') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path ($bkp + '_View') 'MANIFEST.csv'), 'looks like a store')
        New-ViewConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg
        [IO.File]::WriteAllText((Join-Path $src 'f.txt'), 'DATA')

        # The backup completes (the view is cosmetic; failure is a WARNING)...
        (Invoke-VBExit -Cfg $cfg) | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $chg 'backup.log') -Raw) | Should -Match 'Browse view generation failed'
        # ...the impostor store is untouched...
        (Get-Content -LiteralPath (Join-Path ($bkp + '_View') 'MANIFEST.csv') -Raw) | Should -Be 'looks like a store'
        # ...and the loud path reports 2.
        (Invoke-VBExit -Cfg $cfg -Extra @('-Action', 'View')) | Should -Be 2
    }
}

Describe 'The view is invisible to the engine and the restorers (SR-062, TC-130)' {
    It 'Verify is clean with a view present, restore is byte-exact, and a further run changes no manifest row' {
        $t = New-ViewStore -Root (Join-Path $TestDrive 'v130')
        (Invoke-VBExit -Cfg $t.Cfg -Extra @('-Action', 'Verify')) | Should -Be 0

        $target = Join-Path $TestDrive 'v130\restored'
        & (Join-Path $t.Bkp 'RECONSTRUCT.ps1') -TargetRoot $target *>&1 | Out-Null
        [IO.File]::ReadAllText((Join-Path $target 'a.bin')) | Should -Be ('SHARED ' * 50)
        Test-Path -LiteralPath (Join-Path $target 'INDEX.html') | Should -BeFalse

        # Row CONTENT, not raw bytes: a manifest-identical run may rewrite the
        # CSV with different quoting (the step-8 determinism item owns byte
        # stability; sorted row content is the documented contract here).
        $digest = { @(Import-Csv -LiteralPath (Join-Path $t.Bkp 'MANIFEST.csv') | Sort-Object RelativePath |
                      ForEach-Object { "$($_.RelativePath)|$($_.DataPath)|$($_.Length)|$($_.xxH2Hash)|$($_.Compressed)|$($_.Duplicate)" }) -join "`n" }
        $before = & $digest
        Invoke-VB $t.Cfg
        (& $digest) | Should -Be $before
    }
}

Describe 'Snapshots get no view (SR-062, TC-133)' {
    It 'no snapshot folder ever contains view artifacts' {
        $t = New-ViewStore -Root (Join-Path $TestDrive 'v133')
        [IO.File]::WriteAllText((Join-Path $t.Src 'a.bin'), ('CHANGED ' * 50))
        Invoke-VB $t.Cfg    # second run => a snapshot exists

        $snaps = @(Get-ChildItem -LiteralPath $t.Chg -Directory | Where-Object Name -match '^Snapshot_')
        $snaps.Count | Should -BeGreaterThan 0
        foreach ($snap in $snaps) {
            @(Get-ChildItem -LiteralPath $snap.FullName -Recurse -Force |
              Where-Object { $_.Name -in 'INDEX.html', 'INDEX.tsv', '.viewstamp' }) |
                Should -BeNullOrEmpty -Because "snapshot '$($snap.Name)' must stay view-free"
        }
    }
}
