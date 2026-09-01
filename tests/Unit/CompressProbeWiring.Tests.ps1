<#
.SYNOPSIS  WP17 Part B2: the compressibility probe WIRED into the write path -
           laziness, the group memo, the candidate walk, the CompressProbe
           configuration key and the rule-0 dominance of CompressEnabled=false
           (SR-081, SR-042, SR-063, LLR-042, LLR-058, LLR-063, LLR-086).
.NOTES     TC-224, TC-225, TC-226, TC-227, TC-228 and TC-231's rule-0 arm
           (TC-231's Part-A arm lives in StorageForm.Tests.ps1).

           HOW THESE CASES REACH THE ENGINE (plan section 5). The suites drive
           backups through FileBackup.ps1, which re-imports both modules with
           -Force and thereby discards any Mock -ModuleName injected earlier.
           Cases that need a seam therefore call Invoke-BackupFileGroup
           DIRECTLY in-process, where Mock -ModuleName FileBackup.Engine has
           precedent (Coverage.Tests.ps1:1862); cases about the whole run
           (TC-224's Q7 pin, TC-227's exit codes) go through the entry point
           and assert on the manifest and the process status instead.

           Every fixture is built from a SEEDED Random and fixed text, so the
           measured ratios are deterministic on a given runtime: random 1.000,
           text 0.000, mixed-head 0.917 (raw, above the 0.90 threshold),
           mixed-third 0.667 (compress). No test sleeps.
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:entry    = Join-Path $repo 'FileBackup.ps1'
    $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath
    # Comfortably above the 256 KiB floor and an exact multiple of it, so the
    # probe takes its three-window geometry rather than the whole-file path.
    $script:AboveFloor = 1MB
    $script:BelowFloor = 4096

    function New-ProbeContent {
        <#
        .SYNOPSIS
            Deterministic fixture bytes of a named compressibility class.
        #>
        param(
            [ValidateSet('random', 'text', 'mixed-head', 'mixed-third')][string]$Kind,
            [int]$Size = 1MB, [int]$Seed = 20260901)
        $rand = { param([int]$n) $b = [byte[]]::new($n); [Random]::new($Seed).NextBytes($b); , $b }
        $text = {
            param([int]$n)
            # The seed rides in the repeated unit too, so two text fixtures with
            # different seeds are DIFFERENT content: identical bytes would form
            # one (hash,length) group and be stored under one owner's form.
            $unit = "The quick brown fox jumps over the lazy dog. COMPRESSIBLE TEXT PAYLOAD $Seed. "
            $sb = [Text.StringBuilder]::new()
            while ($sb.Length -lt $n) { [void]$sb.Append($unit) }
            , [Text.Encoding]::ASCII.GetBytes($sb.ToString().Substring(0, $n))
        }
        switch ($Kind) {
            'random' { return (& $rand $Size) }
            'text'   { return (& $text $Size) }
            # 64 KiB of text at the head of an otherwise random file: the defect
            # review's own failure mode, which an ANY-sample rule would send to
            # -mx=9 whole. Aggregate 0.917 -> raw.
            'mixed-head'  { return ([byte[]]@((& $text 65536)  + (& $rand ($Size - 65536)))) }
            # A third of the file compresses: aggregate 0.667 -> compress.
            'mixed-third' { return ([byte[]]@((& $text 393216) + (& $rand ($Size - 393216)))) }
        }
    }

    function New-ProbeGroup {
        <#
        .SYNOPSIS
            Builds src/bkp roots plus the (hash,length) group rows for one
            content, under one or more member names, ready for a direct
            Invoke-BackupFileGroup call.
        #>
        param([string]$Label, [string[]]$Name, [byte[]]$Bytes)
        $root = Join-Path $TestDrive ($Label + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'
        New-Item -ItemType Directory -Path $src, $bkp -Force | Out-Null
        $rows = foreach ($n in $Name) {
            $file = Join-Path $src $n
            [IO.File]::WriteAllBytes($file, $Bytes)
            [pscustomobject]@{
                RelativePath = $n; Length = $Bytes.LongLength
                xxH2Hash = (Get-FileXxHash -FilePath $file)
                LastWriteTime = [datetime]'2024-01-01'; Duplicate = 'No'; MediaMBPerSec = ''
            }
        }
        [pscustomobject]@{ Root = $root; Src = $src; Bkp = $bkp; Group = @($rows) }
    }

    function Invoke-ProbeGroup {
        <#
        .SYNOPSIS
            Calls Invoke-BackupFileGroup directly and returns the resulting map,
            the success flag and every log line (so a test can count WARNs and
            read the compress-decision DEBUG line).
        #>
        param([pscustomobject]$Fixture, [string]$Mode = 'always',
              [bool]$CompressEnabled = $true, [object[]]$BackupDb = @(),
              [hashtable]$Stats, [Nullable[int]]$RetryBudgetMs)
        $logs = [System.Collections.Generic.List[object]]::new()
        $log = { param($m, $l = 'INFO') $logs.Add([pscustomobject]@{ Message = $m; Level = $l }) }.GetNewClosure()
        $map = @{}; $changed = 0; $ok = $true
        $extra = @{}
        if ($Stats) { $extra['ProbeStats'] = $Stats }
        # A zero budget makes an unreadable source fail on its first attempt:
        # the engine's retry waits are real Start-Sleep calls, and a test must
        # not synchronize on them (or pay for them).
        if ($null -ne $RetryBudgetMs) { $budget = [int]$RetryBudgetMs; $extra['RetryBudgetMs'] = [ref]$budget }
        Invoke-BackupFileGroup -Group $Fixture.Group -SrcPath $Fixture.Src -BkpPath $Fixture.Bkp `
            -CompressEnabled $CompressEnabled -SevenZipPath $script:sevenZip -BackupDb $BackupDb `
            -BackupMap ([ref]$map) -ChangedCount ([ref]$changed) -Log $log `
            -OverallSuccess ([ref]$ok) -CompressProbe $Mode @extra
        [pscustomobject]@{ Map = $map; Ok = $ok; Changed = $changed; Logs = $logs }
    }

    function New-ProbeClixmlConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $true, [hashtable]$Extra = @{})
        $set = [ordered]@{
            Name = 'S'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
        }
        foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
        @{ Secrets = $null; BackupSets = @([pscustomobject]$set) } | Export-Clixml -LiteralPath $Path
    }

    function New-ProbeJsonConfig {
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg,
              [bool]$Compress = $true, [string]$ProbeLiteral)
        $probe = if ($PSBoundParameters.ContainsKey('ProbeLiteral')) { ",`n    `"CompressProbe`": $ProbeLiteral" } else { '' }
        $json = @"
{
  "ConfigVersion": 2,
  "BackupSets": [{
    "Name": "S",
    "SourcePath": $($Src | ConvertTo-Json),
    "BackupPath": $($Bkp | ConvertTo-Json),
    "ChangePath": $($Chg | ConvertTo-Json),
    "HashRecalcFreq": "A",
    "CompressEnabled": $($Compress.ToString().ToLowerInvariant())$probe
  }]
}
"@
        [IO.File]::WriteAllText($Path, $json)
    }

    function Invoke-ProbeRun {
        # The whole entry point, in-process; returns the transcript.
        param([string]$Cfg)
        (& $script:entry -ConfigPath $Cfg -NoMail -NonInteractive *>&1) | Out-String
    }

    function Invoke-ProbeRunExitCode {
        # Child process, so the entry point's `exit` is observable (TC-034's
        # pattern) and a refused configuration's status 2 can be asserted.
        param([string]$Cfg)
        & (Get-Process -Id $PID).Path -NoProfile -File $script:entry -ConfigPath $Cfg `
            -NoMail -NonInteractive -ExitCode *>&1 | Out-Null
        return $LASTEXITCODE
    }

    function Get-ManifestRow {
        param([string]$Bkp)
        $out = @{}
        foreach ($r in @(Import-Csv -LiteralPath (Join-Path $Bkp 'MANIFEST.csv'))) { $out[$r.RelativePath] = $r }
        return $out
    }

}

Describe 'Q7: the bytes decide, not the name (SR-004, SR-081, TC-224)' {
    # The Owner's ruling under test, through the WHOLE entry point: SN-003's
    # acceptance extensions are EXAMPLES of the need ("save more space"), not
    # rulings on those formats. Under the default mode a .docx of random bytes
    # is stored raw and a .jpg of text bytes is stored .7z - and mode off still
    # reproduces SN-003's illustration exactly, on demand.
    BeforeAll {
        $script:tc224 = @{}
        foreach ($mode in 'always', 'off') {
            $root = Join-Path $TestDrive "tc224-$mode"
            $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
            New-Item -ItemType Directory -Path $src -Force | Out-Null
            # Distinct seeds: identical bytes would dedup into ONE content group
            # and take one owner's storage form, which would prove nothing.
            [IO.File]::WriteAllBytes((Join-Path $src 'paper.docx'), (New-ProbeContent -Kind random -Seed 1))
            [IO.File]::WriteAllBytes((Join-Path $src 'photo.jpg'),  (New-ProbeContent -Kind text -Seed 2))
            [IO.File]::WriteAllBytes((Join-Path $src 'notes.txt'),  (New-ProbeContent -Kind text -Seed 3))
            $cfg = Join-Path $root 'c.xml'
            New-ProbeClixmlConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true `
                -Extra @{ CompressProbe = $mode }
            $script:tc224[$mode] = [pscustomobject]@{
                Bkp = $bkp; Transcript = (Invoke-ProbeRun -Cfg $cfg)
            }
        }
    }

    It 'under <Mode> stores <Name> as <Ext> with Compressed=<Compressed> (TC-224)' -ForEach @(
        # always: the measurement decides, and it contradicts BOTH example names.
        @{ Mode = 'always'; Name = 'paper.docx'; Ext = '.docx'; Compressed = 'No' }
        @{ Mode = 'always'; Name = 'photo.jpg';  Ext = '.7z';   Compressed = 'Yes' }
        @{ Mode = 'always'; Name = 'notes.txt';  Ext = '.7z';   Compressed = 'Yes' }
        # off: today's list answer, i.e. SN-003's illustration, unchanged.
        @{ Mode = 'off';    Name = 'paper.docx'; Ext = '.7z';   Compressed = 'Yes' }
        @{ Mode = 'off';    Name = 'photo.jpg';  Ext = '.jpg';  Compressed = 'No' }
        @{ Mode = 'off';    Name = 'notes.txt';  Ext = '.7z';   Compressed = 'Yes' }
    ) {
        $rows = Get-ManifestRow -Bkp $script:tc224[$Mode].Bkp
        $row = $rows[$Name]
        $row | Should -Not -BeNullOrEmpty -Because 'the run must have stored every file'
        [IO.Path]::GetExtension($row.DataPath) | Should -Be $Ext
        $row.Compressed | Should -Be $Compressed
        # I-1: the filename and the column are the SAME boolean, never two.
        Test-StorageFormAgreement -Compressed $row.Compressed -RelativePath $row.RelativePath -DataPath $row.DataPath |
            Should -BeTrue
    }

    It 'names no Reason after a file format - the ruled list is gone (TC-224, Q7)' {
        # Derived, not restated: the vocabulary is whatever the pure core can
        # actually emit over the full input grid.
        $reasons = InModuleScope FileBackup.Engine {
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($enabled in $true, $false) {
                foreach ($mode in 'off', 'excluded-extensions', 'always') {
                    foreach ($list in $true, $false) {
                        foreach ($len in 1024, 1048576) {
                            foreach ($sampled in 0, 786432) {
                                foreach ($ratio in 0.0, 1.0) {
                                    [void]$seen.Add((Resolve-CompressionDecision -CompressEnabled $enabled `
                                        -Mode $mode -ListSaysCompress $list -Length $len `
                                        -SampledBytes $sampled -CompressedBytes ([long](786432 * $ratio))).Reason)
                                }
                            }
                        }
                    }
                }
            }
            @($seen) | Sort-Object
        }
        @($reasons) | Should -Be @('BelowFloor', 'CompressDisabled', 'ListExempt', 'ModeOff',
                                   'ProbeCompressible', 'ProbeIncompressible', 'ProbeUnavailable')
        foreach ($r in $reasons) {
            $r | Should -Not -Match '(?i)docx|xlsx|txt|jpe?g|mp4|mkv|zip|7z|office|document|image|video|audio'
        }
        # And nothing in the run's own output names a format either. The line is
        # '<date> <time> [DEBUG] compress-decision: <rel> <Reason> ratio=...', so
        # the REASON is captured by name: indexing token 3 read the literal
        # 'compress-decision:' and could never fail (review R-11).
        $lines = ($script:tc224['always'].Transcript -split "`r?`n") | Where-Object { $_ -match 'compress-decision:' }
        @($lines).Count | Should -BeGreaterThan 0
        foreach ($l in $lines) {
            $m = [regex]::Match($l, 'compress-decision:\s+\S+\s+(\S+)')
            $m.Success | Should -BeTrue -Because 'the assertion must read the Reason, not a literal'
            # The captured token really is the Reason - the same vocabulary the
            # pure core emits above - and it names no file format.
            $m.Groups[1].Value | Should -BeIn @('BelowFloor', 'CompressDisabled', 'ListExempt', 'ModeOff',
                                                'ProbeCompressible', 'ProbeIncompressible', 'ProbeUnavailable')
            $m.Groups[1].Value | Should -Not -Match '(?i)docx|jpe?g|mp4|zip'
        }
    }
}

Describe 'Mode always measures every name above the floor (SR-081, TC-225)' {
    # The finding itself. Driven at Invoke-BackupFileGroup: the negative control
    # needs the probe seam, and FileBackup.ps1 re-imports the modules with
    # -Force, discarding any module mock (plan section 5).
    It 'stores <Kind> under <Name> as <Ext> (<Compressed>) (TC-225)' -ForEach @(
        # Unlisted extension: the list would compress ALL of these; the bytes
        # overrule it for random and mixed-head.
        @{ Name = 'a.qqq'; Kind = 'random';      Ext = '.qqq'; Compressed = 'No' }
        @{ Name = 'a.qqq'; Kind = 'text';        Ext = '.7z';  Compressed = 'Yes' }
        @{ Name = 'a.qqq'; Kind = 'mixed-head';  Ext = '.qqq'; Compressed = 'No' }
        @{ Name = 'a.qqq'; Kind = 'mixed-third'; Ext = '.7z';  Compressed = 'Yes' }
        # No extension at all.
        @{ Name = 'plain'; Kind = 'random';      Ext = '';     Compressed = 'No' }
        @{ Name = 'plain'; Kind = 'text';        Ext = '.7z';  Compressed = 'Yes' }
        @{ Name = 'plain'; Kind = 'mixed-head';  Ext = '';     Compressed = 'No' }
        @{ Name = 'plain'; Kind = 'mixed-third'; Ext = '.7z';  Compressed = 'Yes' }
        # A LISTED extension: above the floor under `always` the list is not
        # consulted at all, so a store-mode-style .zip over text IS compressed
        # - the review's second direction, which the list can never recover.
        @{ Name = 'a.zip'; Kind = 'text';        Ext = '.7z';  Compressed = 'Yes' }
        @{ Name = 'a.zip'; Kind = 'random';      Ext = '.zip'; Compressed = 'No' }
    ) {
        $fx = New-ProbeGroup -Label 'tc225' -Name @($Name) -Bytes (New-ProbeContent -Kind $Kind)
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
        $r.Ok | Should -BeTrue
        $row = $r.Map[$Name]
        [IO.Path]::GetExtension($row.DataPath) | Should -Be $Ext
        $row.Compressed | Should -Be $Compressed
        # I-1, through the repo's own predicate.
        Test-StorageFormAgreement -Compressed $row.Compressed -RelativePath $row.RelativePath -DataPath $row.DataPath |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Bkp $row.DataPath) | Should -BeTrue
    }

    It 'NEGATIVE CONTROL: with the probe bypassed the random .qqq compresses again (TC-225)' {
        # This is the fix-removed behaviour, asserted as the OPPOSITE outcome so
        # the control is live rather than decorative: with no measurement the
        # decision falls back to the extension list, which says "compress" for
        # an unlisted name - exactly the defect WP17 exists to remove.
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility { $null }
        $fx = New-ProbeGroup -Label 'tc225-ctl' -Name @('a.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
        [IO.Path]::GetExtension($r.Map['a.qqq'].DataPath) | Should -Be '.7z'
        $r.Map['a.qqq'].Compressed | Should -Be 'Yes'
    }
}

Describe 'The probe is lazy and memoized at group scope (SR-081, LLR-058, TC-226)' {
    BeforeEach {
        # Incompressible: the arms below assert CALL COUNTS, so the verdict only
        # has to be stable. The literal is inline because a -ModuleName mock body
        # executes in the MODULE's scope and cannot see a test-scope helper.
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility {
            [pscustomobject]@{ SampledBytes = [long]786432; CompressedBytes = [long]786432
                               Windows = @(1.0, 1.0, 1.0); Ratio = 1.0 }
        }
    }

    It 'never probes for a prior-backup dedup hit (TC-226)' {
        $fx = New-ProbeGroup -Label 'tc226-hit' -Name @('a.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $existing = @([pscustomobject]@{
            DataPath = 'already.qqq'; RelativePath = 'a.qqq'; Length = $fx.Group[0].Length
            xxH2Hash = $fx.Group[0].xxH2Hash; Compressed = 'No'; StoredAsHashSize = 'Hash'
            Duplicate = 'No'; MediaMBPerSec = '' })
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always' -BackupDb $existing
        $r.Map['a.qqq'].DataPath | Should -Be 'already.qqq'
        # I-3: an object dedup already located is adopted BEFORE the probe is
        # ever consulted, so no stored object's form is re-decided.
        Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 0 -Exactly
    }

    It 'probes exactly once for a group of in-run twins (TC-226)' {
        $fx = New-ProbeGroup -Label 'tc226-twin' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
        $r.Map['a.qqq'].DataPath | Should -Be $r.Map['b.qqq'].DataPath
        Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 1 -Exactly
    }

    It 'probes ONCE and warns at most once when the first member''s copy fails and the second succeeds (TC-226)' {
        # The memo is what makes this true: the write branch is INSIDE the member
        # loop and a failed member `continue`s with the written-object memo still
        # null, so a naive lazy expression would re-probe and re-WARN per member.
        # The copy mock fails BOTH candidates for the first member (a
        # NON-transient message, so no retry and no sleep) and succeeds after.
        $env:FB_TC226_COPYCALLS = '0'
        try {
            Mock -ModuleName FileBackup.Engine Copy-SourceFileToBackup {
                $n = [int]$env:FB_TC226_COPYCALLS + 1
                $env:FB_TC226_COPYCALLS = "$n"
                if ($n -le 2) { return "destination '$BackupFilePath' is a directory; refusing to copy into it" }
                Copy-Item -LiteralPath $SourceFilePath -Destination $BackupFilePath -Force
                return 0
            }
            $fx = New-ProbeGroup -Label 'tc226-fail' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
            $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
            # The first member failed (no row); the second wrote the object.
            $r.Map.ContainsKey('a.qqq') | Should -BeFalse
            $r.Map['b.qqq'] | Should -Not -BeNullOrEmpty
            Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 1 -Exactly
            # (The WARN count is not asserted here: this arm's probe always
            # yields a measurement, so ProbeUnavailable never fires and "at most
            # one" would pass on zero. The honest one-WARN arm is the next
            # Describe - review R-12.)
            # One decision line for the one group that was written.
            @($r.Logs | Where-Object { $_.Message -like 'compress-decision:*' }).Count | Should -Be 1
        } finally { Remove-Item Env:\FB_TC226_COPYCALLS -ErrorAction SilentlyContinue }
    }

}

Describe 'The memo warns ONCE even when a member''s copy fails (SR-081, LLR-058, TC-226)' {
    # R-12's honest arm: the previous Describe's probe always measures, so
    # "at most one WARN" there passes on zero. Here the probe yields NO
    # measurement for every call, so the ProbeUnavailable WARN really is
    # reachable - and the group-scope memo is what keeps it to exactly one
    # across a failing member and a succeeding twin.
    It 'emits exactly one probe WARN and one ProbeUnavailable line across a failed member and its twin (TC-226, R-12)' {
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility { $null }
        $env:FB_TC226_COPYCALLS = '0'
        try {
            # Fails BOTH candidates of the first member (a NON-transient message,
            # so no retry and no sleep), then succeeds - the same mechanism the
            # laziness arm uses.
            Mock -ModuleName FileBackup.Engine Copy-SourceFileToBackup {
                $n = [int]$env:FB_TC226_COPYCALLS + 1
                $env:FB_TC226_COPYCALLS = "$n"
                if ($n -le 2) { return "destination '$BackupFilePath' is a directory; refusing to copy into it" }
                Copy-Item -LiteralPath $SourceFilePath -Destination $BackupFilePath -Force
                return 0
            }
            $fx = New-ProbeGroup -Label 'tc226-warnonce' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
            $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
            $r.Map.ContainsKey('a.qqq') | Should -BeFalse
            $r.Map['b.qqq'] | Should -Not -BeNullOrEmpty
            @($r.Logs | Where-Object { $_.Level -eq 'WARN' -and $_.Message -like '*compressibility probe*' }).Count |
                Should -Be 1 -Because 'the memo survives the failing member''s continue'
            @($r.Logs | Where-Object { $_.Message -like 'compress-decision:*ProbeUnavailable*' }).Count |
                Should -Be 1
        } finally { Remove-Item Env:\FB_TC226_COPYCALLS -ErrorAction SilentlyContinue }
    }
}

Describe 'A non-lowercase mode is refused before anything is read (SR-042, SR-081, R-10)' {
    # The three ValidateSets are case-INSENSITIVE, so a hand-built set could
    # reach the write path with 'Always', read the bytes, and only then have the
    # pure core throw - mid-loop, after partial writes, naming a private helper.
    # Resolve-GroupStorageForm now refuses first, before any probe.
    It 'throws for CompressProbe ''Always'' without opening a single source byte (TC-227, R-10)' {
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility {
            [pscustomobject]@{ SampledBytes = [long]786432; CompressedBytes = [long]786432
                               Windows = @(1.0, 1.0, 1.0); Ratio = 1.0 }
        }
        $fx = New-ProbeGroup -Label 'r10-case' -Name @('a.qqq') -Bytes (New-ProbeContent -Kind 'random')
        { Invoke-ProbeGroup -Fixture $fx -Mode 'Always' } |
            Should -Throw -ExpectedMessage '*CompressProbe*'
        Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 0 -Exactly `
            -Because 'the vocabulary is checked before the probe, not after it'
    }

    It 'refuses a hand-built set at step 10, before the group loop (TC-227, R-10)' {
        # Invoke-BackupSet directly (the entry point re-imports the module and
        # would tear down the mock, plan section 5): a set object that never went
        # through the config validator carries 'Always', and step 10 refuses it
        # with the SR-042 wording BEFORE a single group is copied.
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility {
            [pscustomobject]@{ SampledBytes = [long]786432; CompressedBytes = [long]786432
                               Windows = @(1.0, 1.0, 1.0); Ratio = 1.0 }
        }
        $root = Join-Path $TestDrive 'r10-set'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $src 'a.qqq'), (New-ProbeContent -Kind 'text'))
        $set = [pscustomobject]@{
            Name = 'R10'; SourcePath = $src; SourceStatePath = ''; BackupPath = $bkp; ChangePath = $chg
            HashRecalcFreq = 'A'; CompressEnabled = $true; AllowEmptySource = $false
            BrowseView = 'off'; ViewPath = ''; CompressProbe = 'Always'
        }
        $ok = $true; $logs = New-Object System.Collections.Generic.List[string]
        { Invoke-BackupSet -Set $set -Deps @{ '7z' = $script:sevenZip; 'ffprobe' = $null } `
            -OverallSuccess ([ref]$ok) -LogPaths $logs -BackupTime ([datetime]'2024-01-01 00:00:01') } |
            Should -Throw -ExpectedMessage "*Backup set 'R10' has invalid CompressProbe 'Always'*"
        Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 0 -Exactly
        @(Get-ChildItem -LiteralPath $bkp -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like '*.qqq' -or $_.Name -like '*.7z' }) |
            Should -BeNullOrEmpty -Because 'nothing is written before the mode is checked'
    }
}

Describe 'A locked owner does not cost the group its measurement (SR-081, TC-226)' {
    # The candidate walk (WP9 MIN-1, applied to the probe). No mock here: only
    # the REAL probe can tell a locked handle from a readable one, so this arm
    # proves the walk end to end rather than through a stub.
    It 'samples the readable twin and does not report ProbeUnavailable (TC-226)' {
        $fx = New-ProbeGroup -Label 'tc226-lock' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $hold = [IO.FileStream]::new((Join-Path $fx.Src 'a.qqq'), [IO.FileMode]::Open,
                                     [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
            $r.Ok | Should -BeTrue
            $line = @($r.Logs | Where-Object { $_.Message -like 'compress-decision:*' })[0].Message
            $line | Should -Not -Match 'ProbeUnavailable'
            # Random bytes: the twin really was measured, not defaulted.
            $line | Should -Match 'ProbeIncompressible'
            $r.Map['a.qqq'].Compressed | Should -Be 'No'
            @($r.Logs | Where-Object { $_.Level -eq 'WARN' -and $_.Message -like '*compressibility probe*' }) |
                Should -BeNullOrEmpty
        } finally { $hold.Dispose() }
    }
}

Describe 'A group nothing can sample falls back to the list, never to a failure (SR-081, TC-228)' {
    It 'takes the LIST''S answer with exactly one WARN, and the write still succeeds (TC-228)' {
        # The fail-toward-today half of I-6, isolated from the copy: the probe
        # returns no measurement for every candidate while the bytes remain
        # readable, so the decision - not the file - is what the failure costs.
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility { $null }
        $fx = New-ProbeGroup -Label 'tc228-mock' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'always'
        $r.Ok | Should -BeTrue
        # The list says compress for an unlisted name - today's answer, not a
        # guess, and not the measurement's answer for random bytes.
        $r.Map['a.qqq'].Compressed | Should -Be 'Yes'
        [IO.Path]::GetExtension($r.Map['a.qqq'].DataPath) | Should -Be '.7z'
        @($r.Logs | Where-Object { $_.Level -eq 'WARN' -and $_.Message -like '*compressibility probe*' }).Count |
            Should -Be 1
        @($r.Logs | Where-Object { $_.Message -like 'compress-decision:*ProbeUnavailable*' }).Count | Should -Be 1
    }

    It 'holds a REAL FileShare.None handle on every member: one probe WARN, no probe exception (TC-228)' {
        # The honest end of the real-lock case. If NO member can be opened then
        # the copy cannot read them either, so this group legitimately fails to
        # copy (SR-067's ordinary ERROR, which marks the set failed). What
        # TC-228 pins is that the PROBE contributes exactly one WARN and no
        # exception, and that the copy's failure is the ordinary one.
        $fx = New-ProbeGroup -Label 'tc228-lock' -Name @('a.qqq', 'b.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $holds = foreach ($n in 'a.qqq', 'b.qqq') {
            [IO.FileStream]::new((Join-Path $fx.Src $n), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        }
        try {
            $r = $null
            { $script:tc228 = Invoke-ProbeGroup -Fixture $fx -Mode 'always' -RetryBudgetMs 0 } | Should -Not -Throw
            $r = $script:tc228
            @($r.Logs | Where-Object { $_.Level -eq 'WARN' -and $_.Message -like '*compressibility probe*' }).Count |
                Should -Be 1
            # The decision took the list's answer, and it is the ONLY probe
            # verdict this group produced.
            @($r.Logs | Where-Object { $_.Message -like '*compressibility probe*' -and $_.Message -like '*extension list*' }).Count |
                Should -Be 1
            # The copy failed the ordinary way: SR-067's ERROR naming the copy,
            # not a probe error, and the set is marked failed rather than the
            # run throwing.
            $err = @($r.Logs | Where-Object { $_.Level -eq 'ERROR' })
            $err.Count | Should -Be 2
            foreach ($e in $err) { $e.Message | Should -Match 'Failed to copy/compress' }
            $r.Ok | Should -BeFalse
        } finally { foreach ($h in $holds) { $h.Dispose() } }
    }
}

Describe 'The CompressProbe configuration key (SR-042, SR-063, SR-081, TC-227)' {
    It 'mode off reproduces the pre-WP17 list decision for <Name>/<Kind> (TC-227)' -ForEach @(
        @{ Name = 'a.qqq'; Kind = 'random'; Ext = '.7z';  Compressed = 'Yes' }
        @{ Name = 'a.zip'; Kind = 'text';   Ext = '.zip'; Compressed = 'No' }
    ) {
        $fx = New-ProbeGroup -Label 'tc227-off' -Name @($Name) -Bytes (New-ProbeContent -Kind $Kind)
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'off'
        [IO.Path]::GetExtension($r.Map[$Name].DataPath) | Should -Be $Ext
        $r.Map[$Name].Compressed | Should -Be $Compressed
    }

    It 'mode excluded-extensions exempts the listed name but probes the unlisted one (<Name>/<Kind>) (TC-227)' -ForEach @(
        # The list still exempts .zip even over perfectly compressible text...
        @{ Name = 'a.zip'; Kind = 'text';   Ext = '.zip'; Compressed = 'No' }
        # ...while everything it would compress is measured.
        @{ Name = 'a.qqq'; Kind = 'random'; Ext = '.qqq'; Compressed = 'No' }
        @{ Name = 'a.qqq'; Kind = 'text';   Ext = '.7z';  Compressed = 'Yes' }
    ) {
        $fx = New-ProbeGroup -Label 'tc227-ee' -Name @($Name) -Bytes (New-ProbeContent -Kind $Kind)
        $r = Invoke-ProbeGroup -Fixture $fx -Mode 'excluded-extensions'
        [IO.Path]::GetExtension($r.Map[$Name].DataPath) | Should -Be $Ext
        $r.Map[$Name].Compressed | Should -Be $Compressed
    }

    It 'resolves an ABSENT key to always in both formats - an unchanged v2 document still loads (TC-227)' {
        $root = Join-Path $TestDrive 'tc227-absent'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $xml = Join-Path $root 'c.xml'; $json = Join-Path $root 'c.json'
        New-ProbeClixmlConfig -Path $xml -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg'
        New-ProbeJsonConfig -Path $json -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg'
        (Import-BackupConfiguration -Path $xml).Sets[0].CompressProbe  | Should -Be 'always'
        (Import-BackupConfiguration -Path $json).Sets[0].CompressProbe | Should -Be 'always'
    }

    It 'carries a PRESENT <Value> through Resolve-BackupSetDefaults onto the resolved set (TC-227)' -ForEach @(
        @{ Value = 'off' }, @{ Value = 'excluded-extensions' }, @{ Value = 'always' }
    ) {
        $root = Join-Path $TestDrive ('tc227-carry-' + $Value)
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $xml = Join-Path $root 'c.xml'; $json = Join-Path $root 'c.json'
        New-ProbeClixmlConfig -Path $xml -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg' -Extra @{ CompressProbe = $Value }
        New-ProbeJsonConfig -Path $json -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg' -ProbeLiteral "`"$Value`""
        (Import-BackupConfiguration -Path $xml).Sets[0].CompressProbe  | Should -Be $Value
        (Import-BackupConfiguration -Path $json).Sets[0].CompressProbe | Should -Be $Value
    }

    It 'refuses <Case> in JSON and CLIXML alike, naming the key (TC-227)' -ForEach @(
        @{ Case = 'a mixed-case "Always"'; Json = '"Always"'; Clixml = 'Always' }
        @{ Case = 'an unknown "maybe"';    Json = '"maybe"';  Clixml = 'maybe' }
        @{ Case = 'a null';                Json = 'null';     Clixml = $null }
        @{ Case = 'a number';              Json = '1';        Clixml = 1 }
    ) {
        $root = Join-Path $TestDrive ('tc227-bad-' + ($Case -replace '\W', ''))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $xml = Join-Path $root 'c.xml'; $json = Join-Path $root 'c.json'
        New-ProbeClixmlConfig -Path $xml -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg' -Extra @{ CompressProbe = $Clixml }
        New-ProbeJsonConfig -Path $json -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg' -ProbeLiteral $Json
        foreach ($p in $xml, $json) {
            $err = { Import-BackupConfiguration -Path $p } | Should -Throw -PassThru
            $err.Exception.Message | Should -Match 'CompressProbe'
        }
    }

    It 'refuses a CLIXML CompressProbe that is an ARRAY rather than a scalar string (<Case>) (TC-227, R-3)' -ForEach @(
        # JSON rejects both of these by TYPE (Assert-ConfigValueType). CLIXML is
        # untyped, and [string] on an array JOINS it - so @('off') used to cast
        # to 'off' and pass the vocabulary check, giving the two formats
        # different contracts (review R-3).
        @{ Case = 'one element';  Clixml = [object[]]@('off') }
        @{ Case = 'two elements'; Clixml = [object[]]@('off', 'always') }
    ) {
        $root = Join-Path $TestDrive ('tc227-array-' + ($Case -replace '\W', ''))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $xml = Join-Path $root 'c.xml'
        New-ProbeClixmlConfig -Path $xml -Src 'C:\src' -Bkp 'C:\bkp' -Chg 'C:\chg' -Extra @{ CompressProbe = $Clixml }
        $err = { Import-BackupConfiguration -Path $xml } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'CompressProbe'
    }

    It 'publishes ONE CompressProbe vocabulary: schema enum = validator = every ValidateSet (TC-227, TC-077, R-6)' {
        # TC-077 proves schema/validator parity only over hand-picked fixtures,
        # so adding a fourth word to the schema enum alone would go unnoticed.
        # This derives the vocabulary from each surface and compares them.
        $expected = @('off', 'excluded-extensions', 'always')
        $schema = Get-Content -Raw -LiteralPath (Join-Path $script:repo 'container\FileBackup.schema.json') |
                  ConvertFrom-Json
        $schemaEnum = @($schema.definitions.backupSet.properties.CompressProbe.enum)
        ($schemaEnum -join '|') | Should -BeExactly ($expected -join '|')

        $sets = InModuleScope FileBackup.Engine {
            $read = {
                param([string]$Command, [string]$Parameter)
                @((Get-Command $Command).Parameters[$Parameter].Attributes |
                  Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })[0].ValidValues
            }
            [pscustomobject]@{
                Group    = @(& $read 'Invoke-BackupFileGroup' 'CompressProbe')
                Decision = @(& $read 'Resolve-CompressionDecision' 'Mode')
                Form     = @(& $read 'Resolve-GroupStorageForm' 'Mode')
            }
        }
        foreach ($v in $sets.Group, $sets.Decision, $sets.Form) {
            (@($v) -join '|') | Should -BeExactly ($expected -join '|')
        }
    }

    It 'refuses a bad CompressProbe at the process boundary with status 2 and creates nothing (SR-043, TC-227)' {
        $root = Join-Path $TestDrive 'tc227-exit2'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'x')
        $json = Join-Path $root 'c.json'
        New-ProbeJsonConfig -Path $json -Src $src -Bkp $bkp -Chg $chg -ProbeLiteral '"maybe"'
        Invoke-ProbeRunExitCode -Cfg $json | Should -Be 2
        Test-Path -LiteralPath $bkp | Should -BeFalse
        Test-Path -LiteralPath $chg | Should -BeFalse
    }
}

Describe 'CompressEnabled=false dominates every mode and every name (SR-004, SR-081, TC-231)' {
    # Rule 0, both cross-reviewers' P0: a rule that consulted the probe first
    # would name a .7z object and record Compressed=Yes on a Plain set for which
    # 7-Zip is not even resolved.
    BeforeEach {
        # Would say "compress" for anything, if rule 0 ever let it be asked.
        Mock -ModuleName FileBackup.Engine Measure-SampleCompressibility {
            [pscustomobject]@{ SampledBytes = [long]786432; CompressedBytes = [long]0
                               Windows = @(0.0, 0.0, 0.0); Ratio = 0.0 }
        }
    }

    It 'stores <Name> raw under mode <Mode> at <Size> bytes with no probe (TC-231)' -ForEach @(
        $names = 'paper.docx', 'notes.txt', 'photo.jpg', 'clip.mp4', 'a.zip', 'a.qqq', 'plain'
        foreach ($m in 'off', 'excluded-extensions', 'always') {
            foreach ($s in 1MB, 4096) {
                foreach ($n in $names) { @{ Mode = $m; Name = $n; Size = $s } }
            }
        }
    ) {
        # Text bytes: every one of these WOULD be compressed by the list or by
        # the measurement if either were consulted.
        $fx = New-ProbeGroup -Label 'tc231' -Name @($Name) -Bytes (New-ProbeContent -Kind 'text' -Size $Size)
        $r = Invoke-ProbeGroup -Fixture $fx -Mode $Mode -CompressEnabled $false
        $r.Ok | Should -BeTrue
        $row = $r.Map[$Name]
        $row.Compressed | Should -Be 'No'
        [IO.Path]::GetExtension($row.DataPath) | Should -Be ([IO.Path]::GetExtension($Name))
        @(Get-ChildItem -LiteralPath $fx.Bkp -Filter '*.7z') | Should -BeNullOrEmpty
        Should -Invoke Measure-SampleCompressibility -ModuleName FileBackup.Engine -Times 0 -Exactly
    }
}

Describe 'Per-set probe telemetry (SR-081, LLR-086)' {
    It 'counts raw/compressed objects and sampled bytes only for probes that ran' {
        $stats = InModuleScope FileBackup.Engine { New-ProbeStatistic }
        $raw  = New-ProbeGroup -Label 'stats-raw'  -Name @('a.qqq') -Bytes (New-ProbeContent -Kind 'random')
        $zip  = New-ProbeGroup -Label 'stats-zip'  -Name @('b.qqq') -Bytes (New-ProbeContent -Kind 'text')
        $tiny = New-ProbeGroup -Label 'stats-tiny' -Name @('c.qqq') -Bytes (New-ProbeContent -Kind 'text' -Size 4096)
        Invoke-ProbeGroup -Fixture $raw  -Mode 'always' -Stats $stats | Out-Null
        Invoke-ProbeGroup -Fixture $zip  -Mode 'always' -Stats $stats | Out-Null
        Invoke-ProbeGroup -Fixture $tiny -Mode 'always' -Stats $stats | Out-Null
        $stats.RawObjects        | Should -Be 1
        $stats.RawBytes          | Should -Be 1MB
        $stats.CompressedObjects | Should -Be 1
        # Two probes of three windows each; the below-floor group is never read.
        $stats.ReadBytes         | Should -Be (2 * 3 * 262144)
    }

    It 'reports the three counter lines in the set summary of a real run' {
        $root = Join-Path $TestDrive 'probe-summary'
        $src = Join-Path $root 'src'; $bkp = Join-Path $root 'bkp'; $chg = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $src 'a.qqq'), (New-ProbeContent -Kind 'random'))
        $cfg = Join-Path $root 'c.xml'
        New-ProbeClixmlConfig -Path $cfg -Src $src -Bkp $bkp -Chg $chg -Compress $true
        $out = Invoke-ProbeRun -Cfg $cfg
        $out | Should -Match 'Probe stored raw: 1 objects, 1048576 bytes'
        $out | Should -Match 'Probe compressed: 0'
        $out | Should -Match 'Probe reads: 786432 bytes'
    }
}
