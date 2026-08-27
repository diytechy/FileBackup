<#
.SYNOPSIS  Pester 5 unit tests for FileBackup.Common pure functions.
.NOTES     Run:  Invoke-Pester -Path tests\Unit
#>
BeforeAll {
    # $PSScriptRoot here is tests\Unit; repo root is two levels up.
    $repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
}

Describe 'Short-name encoding' {
    # The base-57 grammar: "<hash22>_<len><ext>" (SR-069). WP12 replaced a
    # base-85, space-separated, hash-truncating grammar.

    It 'round-trips a full 128-bit hash EXACTLY, all 32 hex digits (SR-069, TC-004)' {
        # Exactness, not BigInteger equivalence. The old test compared numeric
        # values, which hid two real defects: the hash was truncated to its low
        # ~102 bits, and ToString('X') returns 31, 32 or 33 characters depending
        # on leading zeros and the sign nibble.
        foreach ($hex in '00000000000000000000000000000000',
                         'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
                         '80000000000000000000000000000000',  # high bit set: sign nibble
                         '00000000000000000000000000000001',  # leading zeros
                         'BE20CA004CC2993A396345E0D52DF013') {
            $short = Convert-HexToShortName -Hex $hex -OutputLength 22
            $short.Length | Should -Be 22
            Convert-ShortNameToHex -ShortName $short -HexWidth 32 | Should -BeExactly $hex
        }
    }

    It 'uses exactly 57 glyphs and excludes the ambiguous 0 O I l 1 (SR-069, TC-142)' {
        $alpha = (Get-FileBackupDefaults).Alphabet
        $alpha.Count | Should -Be 57
        ($alpha | Select-Object -Unique).Count | Should -Be 57
        # -CContain, not -Contain: PowerShell's default comparison is
        # case-INSENSITIVE, so a plain -Not -Contain 'O' fails on the perfectly
        # legitimate lowercase 'o' and proves nothing about the exclusion.
        foreach ($c in '0', 'O', 'I', 'l', '1') { ($alpha -ccontains $c) | Should -BeFalse }
        foreach ($c in $alpha) { $c | Should -Match '^[0-9A-Za-z]$' }
        $alpha[0] | Should -BeExactly '2'   # the zero digit, and the pad character
    }

    It 'produces a "<hash22>_<len><ext>" name with an UNPADDED length (SR-069, TC-143)' {
        $name = Get-HashSizeFileName -HashHex 'ABCDEF0123456789ABCDEF0123456789' -Length 5120 -Extension '.7z'
        $name | Should -Match '^[2-9A-HJ-NP-Za-km-z]{22}_[2-9A-HJ-NP-Za-km-z]+\.7z$'
        # Unpadded is the whole point of WP12: 5120 is three base-57 digits and
        # the field must be three characters, not a fixed width padded with the
        # zero digit.
        (ConvertFrom-HashSizeFileName -Name $name).Length | Should -Be 5120
        $name.Substring(23, $name.Length - 26).Length | Should -Be 3
    }

    It 'encodes a zero-length object as the zero digit (SR-069, TC-144)' {
        $name = Get-HashSizeFileName -HashHex 'BE20CA004CC2993A396345E0D52DF013' -Length 0 -Extension '.bin'
        $name | Should -Match '_2\.bin$'
        (ConvertFrom-HashSizeFileName -Name $name).Length | Should -Be 0
    }

    It 'treats the extension as OPAQUE and round-trips a hostile one (SR-070, TC-146)' {
        # T2 from the 2026-08-27 independent review. The extension is the
        # source file's own - 'signed.foo bar' is a portable name - so a guard
        # that blacklisted characters would refuse VALID stores.
        $hash = 'BE20CA004CC2993A396345E0D52DF013'
        foreach ($ext in '.7z', '.txt', '.foo bar', '.a_b', '.[x]', '.7Z', '.MiXeD') {
            $name = Get-HashSizeFileName -HashHex $hash -Length 8388608 -Extension $ext
            $p = ConvertFrom-HashSizeFileName -Name $name
            $p | Should -Not -BeNullOrEmpty
            $p.HashHex   | Should -BeExactly $hash
            $p.Length    | Should -Be 8388608
            $p.Extension | Should -BeExactly $ext
        }
    }

    It 'accepts an EMPTY extension - an extensionless source file (SR-070, TC-148)' {
        # Regression for the WP12 review probe: -Extension was
        # [Parameter(Mandatory)], which rejects '', so an extensionless file in
        # a Plain-mode set failed the whole backup set.
        $name = Get-HashSizeFileName -HashHex 'BE20CA004CC2993A396345E0D52DF013' -Length 3 -Extension ''
        $name | Should -Match '^[2-9A-HJ-NP-Za-km-z]{22}_[2-9A-HJ-NP-Za-km-z]+$'
        (ConvertFrom-HashSizeFileName -Name $name).Extension | Should -BeExactly ''
    }

    It 'THROWS rather than truncating a value too wide for the field (SR-069, TC-145)' {
        { Convert-HexToShortName -Hex ('F' * 40) -OutputLength 22 } | Should -Throw
        # 57^22 exceeds 2^128, so a syntactically valid field can decode out of
        # range; that must be rejected, never silently cut to 32 hex digits.
        { Convert-ShortNameToHex -ShortName ('z' * 22) -HexWidth 32 } | Should -Throw
        ConvertFrom-HashSizeFileName -Name (('z' * 22) + '_2.7z') | Should -BeNullOrEmpty
    }

    It 'refuses to parse a PRE-WP12 base-85 name (SR-061, SR-069, TC-147)' {
        # These are real names: the first two are from the committed WP11-era
        # fixtures, the third from a live pool. Every one carries a space at
        # index 16, and a space is not in the base-57 alphabet.
        foreach ($legacy in 'lii`7EXH@[hgD!I= !!!!!!=X&K.7z',
                            '.nArDBFwE!yq[FFf !!!!!!!!#..bin',
                            'f7(#5C=v.uYfdGbp !!!!!!!!!%.foo bar') {
            Test-HashSizeFileName -Name $legacy | Should -BeFalse
        }
    }

    It 'returns $null for a malformed name instead of throwing (SR-069)' {
        foreach ($bad in '', 'short', ('2' * 22), ('2' * 22 + '_'), ('2' * 22 + 'x2'),
                         ('2' * 22 + '_2junk.7z/x'), 'MANIFEST.csv', 'RECONSTRUCT.ps1') {
            ConvertFrom-HashSizeFileName -Name $bad | Should -BeNullOrEmpty
        }
    }
}

Describe 'Legacy vs current are different questions (SR-061, SR-069)' {
    # The T7 regression pin. WP12's SR-061 gate was first written as "anything
    # that does not parse under SR-069 is a legacy store". Five unit tests and
    # six integration assertions failed on it, correctly: a merely DAMAGED
    # DataPath parses under NEITHER grammar, and SR-049/SR-053/SR-056 exist to
    # audit, heal and verify those PER ROW. The negative test refused the whole
    # store instead - one repairable row made a backup unrestorable and locked
    # out -RepairStorage entirely.
    #
    # These tests exist so nobody re-derives one predicate from the other.

    It 'does NOT classify a damaged or foreign DataPath as legacy (TC-150, SR-049)' {
        # Every one of these is a shape a damaged, hand-built or
        # third-party-rewritten row actually takes. None is a retired GRAMMAR,
        # so none may condemn its store.
        foreach ($n in 'data.bin', 'obj00000.bin', 'd.txt', 'c.txt.7z',
                       'restored.txt', 'shared.bin', 'missing.bin', 'x',
                       ('2' * 22), ('2' * 22 + '_'), ('z' * 22 + '_2.7z')) {
            Test-LegacyStoredObjectName -Name $n | Should -BeFalse -Because "'$n' is damaged or foreign, not a retired grammar"
        }
    }

    It 'DOES classify both retired grammars as legacy (TC-150, SR-061)' {
        foreach ($n in 'lii`7EXH@[hgD!I= !!!!!!=X&K.7z',      # base-85, live pool
                       '.nArDBFwE!yq[FFf !!!!!!!!#..bin',     # base-85, dot-leading
                       'f7(#5C=v.uYfdGbp !!!!!!!!!%.foo bar', # base-85, space in ext
                       'sub\uniq.txt', 'sub/old.txt') {       # pre-WP9 path-addressed
            Test-LegacyStoredObjectName -Name $n | Should -BeTrue -Because "'$n' is a retired grammar"
        }
    }

    It 'never treats a blank DataPath as legacy - it means "recover by hash" (TC-150)' {
        Test-LegacyStoredObjectName -Name '' | Should -BeFalse
    }

    It 'has a NON-EMPTY "neither" class, and nothing is ever both (TC-150)' {
        # If the two predicates ever become complements this is what fails.
        $neither = 0
        foreach ($n in 'data.bin', 'd.txt', 'restored.txt', 'MANIFEST.csv', ('2' * 22)) {
            $cur = Test-HashSizeFileName -Name $n
            $leg = Test-LegacyStoredObjectName -Name $n
            ($cur -and $leg) | Should -BeFalse -Because "'$n' cannot be both grammars"
            if (-not $cur -and -not $leg) { $neither++ }
        }
        $neither | Should -BeGreaterOrEqual 5
    }
}

Describe 'Name-grammar conformance corpus (SR-069, SR-061)' {
    # The shared corpus tests/bash/name_grammar.bats holds the bash twins to.
    # Re-derived here so the committed file cannot silently rot: if these
    # functions change and the fixture is not regenerated, this fails BEFORE the
    # bash suite starts checking against a stale oracle.
    BeforeAll {
        $script:casesPath = Join-Path $repo 'tests\fixtures\name-grammar\cases.tsv'
    }

    It 'is committed and non-trivial (TC-151)' {
        Test-Path -LiteralPath $script:casesPath | Should -BeTrue
        @(Get-Content -LiteralPath $script:casesPath).Count | Should -BeGreaterThan 20
    }

    It 'still describes what these functions actually answer (TC-151)' {
        $lines = @(Get-Content -LiteralPath $script:casesPath)
        $lines[0] | Should -BeExactly "Name`tIsCurrent`tIsLegacy"
        foreach ($line in $lines[1..($lines.Count - 1)]) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # Split on the LAST two tabs: a stored name may contain anything
            # except a tab, including spaces and quotes (SR-070).
            $i = $line.LastIndexOf("`t")
            $j = $line.LastIndexOf("`t", $i - 1)
            $name = $line.Substring(0, $j)
            $wantCurrent = $line.Substring($j + 1, $i - $j - 1)
            $wantLegacy  = $line.Substring($i + 1)

            $gotCurrent = if (Test-HashSizeFileName -Name $name) { '1' } else { '0' }
            $gotLegacy  = if (Test-LegacyStoredObjectName -Name $name) { '1' } else { '0' }
            $gotCurrent | Should -BeExactly $wantCurrent -Because "IsCurrent for '$name' (regenerate with scripts/gen_bash_fixtures.ps1)"
            $gotLegacy  | Should -BeExactly $wantLegacy  -Because "IsLegacy for '$name' (regenerate with scripts/gen_bash_fixtures.ps1)"
        }
    }

    It 'covers all three classes, so the bash parity check is meaningful (TC-151)' {
        $rows = @(Get-Content -LiteralPath $script:casesPath) | Select-Object -Skip 1 |
                Where-Object { $_ } | ForEach-Object {
                    $i = $_.LastIndexOf("`t"); $j = $_.LastIndexOf("`t", $i - 1)
                    [pscustomobject]@{ Current = $_.Substring($j + 1, $i - $j - 1); Legacy = $_.Substring($i + 1) }
                }
        @($rows | Where-Object { $_.Current -eq '1' }).Count | Should -BeGreaterOrEqual 5
        @($rows | Where-Object { $_.Legacy  -eq '1' }).Count | Should -BeGreaterOrEqual 5
        @($rows | Where-Object { $_.Current -eq '0' -and $_.Legacy -eq '0' }).Count | Should -BeGreaterOrEqual 5
    }
}

Describe 'The alphabet keeps the properties WP12 chose it for (SR-069)' {
    It 'folds to exactly 34 case-insensitive classes on NTFS (TC-153)' {
        # The 2026-08-27 review (T1) was right that a mixed-case alphabet is not
        # injective on a case-insensitive volume, and the decision to keep
        # base-57 rests on the ARITHMETIC: 34 classes over 22 characters is
        # 111.92 bits, well above the 94.12 the old base-85 grammar gave. Anyone
        # "improving" the alphabet must not quietly erode that, so the property
        # is pinned rather than left in a comment.
        $alpha = (Get-FileBackupDefaults).Alphabet
        $folded = @($alpha | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        $folded.Count | Should -Be 34

        $bits = 22 * [Math]::Log($folded.Count, 2)
        $bits | Should -BeGreaterThan 111
        # And strictly better than what WP12 replaced (59 folded classes, 16 chars).
        $bits | Should -BeGreaterThan (16 * [Math]::Log(59, 2))
    }

    It 'still holds a 128-bit hash in its 22-character field (TC-153)' {
        $alpha = (Get-FileBackupDefaults).Alphabet
        [Math]::Ceiling(128 / [Math]::Log($alpha.Count, 2)) | Should -BeLessOrEqual 22
    }
}

Describe 'Test-ShouldCompress' {
    It 'is false when compression disabled' {
        Test-ShouldCompress -FileName 'x.txt' -CompressEnabled $false | Should -BeFalse
    }
    It 'is true for compressible extensions' {
        Test-ShouldCompress -FileName 'doc.txt' -CompressEnabled $true | Should -BeTrue
    }
    It 'is false for already-compressed extensions' {
        foreach ($ext in '.zip','.7z','.jpg','.mp4','.png') {
            Test-ShouldCompress -FileName "f$ext" -CompressEnabled $true | Should -BeFalse
        }
    }
    It 'inspects only the extension, not the path' {
        Test-ShouldCompress -FileName 'C:\a\b\report.docx' -CompressEnabled $true | Should -BeTrue
    }
}

Describe 'Manifest date round-trip' {
    It 'survives ConvertTo/ConvertFrom' {
        $dt = Get-Date '2026-03-19T22:50:06.1234567'
        $s  = ConvertTo-ManifestDateString -LastWriteTime $dt
        (ConvertFrom-ManifestDateString -LastWriteTimeStr $s) | Should -Be $dt
    }
}

Describe 'Get-FileXxHash' {
    It 'returns a 32-char uppercase hex string and is deterministic' {
        $tmp = Join-Path $TestDrive 'h.bin'
        [System.IO.File]::WriteAllBytes($tmp, [byte[]](1..50))
        $h1 = Get-FileXxHash -FilePath $tmp
        $h2 = Get-FileXxHash -FilePath $tmp
        $h1 | Should -Match '^[0-9A-F]{32}$'
        $h1 | Should -Be $h2
    }
    It 'differs for different content' {
        $a = Join-Path $TestDrive 'a.bin'; [System.IO.File]::WriteAllBytes($a, [byte[]](1..10))
        $b = Join-Path $TestDrive 'b.bin'; [System.IO.File]::WriteAllBytes($b, [byte[]](11..20))
        (Get-FileXxHash -FilePath $a) | Should -Not -Be (Get-FileXxHash -FilePath $b)
    }
}

Describe 'Read/Write-Manifest' {
    It 'round-trips rows with typed Length and LastWriteTime' {
        $folder = Join-Path $TestDrive 'm'
        New-Item -ItemType Directory -Path $folder | Out-Null
        $rows = @(
            [pscustomobject]@{ DataPath='a.txt'; RelativePath='a.txt'; Length=5; LastWriteTime=(Get-Date '2026-01-02T03:04:05'); xxH2Hash='H1'; Compressed='No'; StoredAsHashSize='Original'; Duplicate=0; MediaMBPerSec=$null }
        )
        Write-Manifest -FolderPath $folder -Records $rows
        $back = Read-Manifest -FolderPath $folder
        $back[0].RelativePath | Should -Be 'a.txt'
        $back[0].Length | Should -BeOfType [long]
        $back[0].LastWriteTime | Should -BeOfType [datetime]
    }
    It 'tolerates a null/empty record set' {
        $folder = Join-Path $TestDrive 'm2'
        New-Item -ItemType Directory -Path $folder | Out-Null
        { Write-Manifest -FolderPath $folder -Records $null } | Should -Not -Throw
    }
    It 'returns @() for a missing manifest' {
        $folder = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $folder | Out-Null
        @(Read-Manifest -FolderPath $folder).Count | Should -Be 0
    }
}

Describe 'Manifest witness sidecar (SR-038)' {
    # TC-066. Write-Manifest is the ONLY writer of the witness, so every origin
    # (backup root, staging, snapshot, source hash cache) is covered by one path.
    BeforeAll {
        $script:witnessName = (Get-FileBackupDefaults).WitnessFilename
        function New-WitnessRow {
            param([string]$Name = 'a.txt', [int]$Length = 5)
            [pscustomobject]@{ DataPath=$Name; RelativePath=$Name; Length=$Length
                LastWriteTime=(Get-Date '2026-01-02T03:04:05'); xxH2Hash='H1'; Compressed='No'
                StoredAsHashSize='Original'; Duplicate=0; MediaMBPerSec=$null }
        }
        function Get-WitnessMap {
            param([string]$Folder)
            $map = @{}
            foreach ($line in [IO.File]::ReadAllLines((Join-Path $Folder $script:witnessName))) {
                if ($line -match '^([^=]+)=(.*)$') { $map[$Matches[1]] = $Matches[2] }
            }
            return $map
        }
    }

    It 'writes a sidecar whose Rows/Bytes/XxH128 describe the manifest as written (SR-038)' {
        $folder = Join-Path $TestDrive 'w1'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @((New-WitnessRow 'a.txt'), (New-WitnessRow 'b.txt' 9))

        $manifest = Join-Path $folder 'MANIFEST.csv'
        $map = Get-WitnessMap $folder
        $map['Version'] | Should -Be '2'   # 2 = the SR-069 base-57 name grammar (WP12)
        $map['Rows']    | Should -Be '2'
        $map['Bytes']   | Should -Be ([string]([IO.FileInfo]$manifest).Length)
        $map['XxH128']  | Should -Be (Get-FileXxHash -FilePath $manifest)
        $map['Written'] | Should -Not -BeNullOrEmpty
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Verified'
    }

    It 'is UTF-8 without BOM and LF-terminated so the bash reader can parse it (SR-038)' {
        $folder = Join-Path $TestDrive 'w-enc'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @(New-WitnessRow)

        $bytes = [IO.File]::ReadAllBytes((Join-Path $folder $script:witnessName))
        # No UTF-8 BOM...
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        # ...no CR anywhere, and a trailing newline.
        ($bytes -contains 0x0D) | Should -BeFalse
        $bytes[-1] | Should -Be 0x0A
    }

    It 'records Rows=0 for an empty record set (SR-038)' {
        $folder = Join-Path $TestDrive 'w2'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records $null
        (Get-WitnessMap $folder)['Rows'] | Should -Be '0'
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Verified'
    }

    It 'republishes the sidecar atomically on rewrite, leaving no .tmp behind (SR-038)' {
        $folder = Join-Path $TestDrive 'w3'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @(New-WitnessRow)
        $first = (Get-WitnessMap $folder)['XxH128']

        Write-Manifest -FolderPath $folder -Records @((New-WitnessRow 'a.txt'), (New-WitnessRow 'c.txt' 12))
        $second = Get-WitnessMap $folder
        $second['Rows'] | Should -Be '2'
        $second['XxH128'] | Should -Not -Be $first
        @(Get-ChildItem -LiteralPath $folder -Filter '*.tmp').Count | Should -Be 0
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Verified'
    }

    It 'reports Absent, Mismatch and Malformed distinctly (SR-039)' {
        $folder = Join-Path $TestDrive 'w4'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @(New-WitnessRow)
        $manifest = Join-Path $folder 'MANIFEST.csv'
        $witness  = Join-Path $folder $script:witnessName

        # Truncating the manifest is caught by Bytes (the cheap precise pre-check).
        $keep = [IO.File]::ReadAllBytes($manifest)
        [IO.File]::WriteAllBytes($manifest, $keep[0..($keep.Length - 20)])
        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status | Should -Be 'Mismatch'
        $v.Field  | Should -Be 'Bytes'

        # A same-length byte edit slips past Bytes/Rows and is caught by the digest.
        $keep[$keep.Length - 5] = [byte]0x41
        [IO.File]::WriteAllBytes($manifest, $keep)
        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status | Should -Be 'Mismatch'
        $v.Field  | Should -Be 'XxH128'

        # Re-stamping makes the same manifest verify again.
        Write-ManifestWitness -FolderPath $folder | Out-Null
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Verified'

        # An unparseable sidecar is Malformed, not Mismatch.
        [IO.File]::WriteAllText($witness, "this is not a witness`n")
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Malformed'

        # A legacy (sidecar-less) origin reports Absent — never a failure here.
        Remove-Item -LiteralPath $witness -Force
        Test-ManifestWitness -FolderPath $folder | Select-Object -ExpandProperty Status | Should -Be 'Absent'
    }

    It 'verifies only the understood keys when the sidecar is from the future (SR-039)' {
        $folder = Join-Path $TestDrive 'w5'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @(New-WitnessRow)
        $witness = Join-Path $folder $script:witnessName

        $text = [IO.File]::ReadAllText($witness) -replace 'Version=\d+', 'Version=99'
        [IO.File]::WriteAllText($witness, $text + "SomeFutureKey=whatever`n")
        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status         | Should -Be 'Verified'   # a newer witness must never condemn a good manifest
        $v.VersionUnknown | Should -BeTrue
    }

    It 'accepts a Rows-only disagreement with a warning, because the digest is authoritative (SR-039)' {
        # WP1 plan sec.6 decision 3: Rows is the operator-legible number, XxH128
        # is the authority. If the bytes and the digest both match, the manifest
        # is exactly the one that was witnessed — a differing count is a
        # counting-semantics divergence, not damage, and must not condemn it.
        $folder = Join-Path $TestDrive 'w6'
        New-Item -ItemType Directory -Path $folder | Out-Null
        Write-Manifest -FolderPath $folder -Records @((New-WitnessRow 'a.txt'), (New-WitnessRow 'b.txt' 9))
        $witness = Join-Path $folder $script:witnessName

        # Rewrite ONLY the Rows line; Bytes and XxH128 still describe the manifest.
        $text = [IO.File]::ReadAllText($witness) -replace 'Rows=2', 'Rows=7'
        [IO.File]::WriteAllText($witness, $text)

        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status  | Should -Be 'Verified'
        $v.Field   | Should -Be 'Rows'
        $v.Warning | Should -Match 'expected 7 row\(s\), found 2'

        # ...but with no digest to defer to, the count is all there is: refuse.
        $noDigest = ([IO.File]::ReadAllLines($witness) |
            Where-Object { $_ -notmatch '^XxH128=' }) -join "`n"
        [IO.File]::WriteAllText($witness, $noDigest + "`n")
        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status | Should -Be 'Mismatch'
        $v.Field  | Should -Be 'Rows'
    }
}

Describe 'Common does not depend on Engine (SR-007)' {
    # Load-bearing split: the restore kit bundles only Common, so Common must
    # never import or load Engine (AGENTS.md sec.2). AST guard over real import
    # statements only — doc comments that mention Engine by name are fine.
    It 'FileBackup.Common.psm1 imports no Engine module (SR-007)' {
        $common = Join-Path $repo 'Modules\FileBackup.Common.psm1'
        $tokens = $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($common, [ref]$tokens, [ref]$errs)
        $imports = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.GetCommandName() -in 'Import-Module','Add-Type' }, $true)
        $offenders = $imports | Where-Object { $_.Extent.Text -match 'Engine' }
        $usingEngine = $ast.UsingStatements | Where-Object { $_.Name.Value -match 'Engine' }
        @($offenders).Count + @($usingEngine).Count | Should -Be 0
    }

    # The sibling invariant: Reconstruct.ps1 runs from a backup folder where only
    # the bundled Common module exists, so any call into an Engine function would
    # break standalone restore (AGENTS.md sec.2 "anything Reconstruct.ps1 calls
    # must live in Common").
    It 'Reconstruct.ps1 calls no Engine function and imports no Engine module (SR-007)' {
        $tokens = $errs = $null
        $engineAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repo 'Modules\FileBackup.Engine.psm1'), [ref]$tokens, [ref]$errs)
        $engineFns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($fn in $engineAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            [void]$engineFns.Add($fn.Name)
        }

        $recAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repo 'Reconstruct.ps1'), [ref]$tokens, [ref]$errs)
        $calls = $recAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        $engineCalls = $calls | Where-Object {
            $n = $_.GetCommandName(); $n -and $engineFns.Contains($n)
        }
        $engineImports = $calls | Where-Object {
            $_.GetCommandName() -eq 'Import-Module' -and $_.Extent.Text -match 'Engine'
        }
        @($engineCalls).Count + @($engineImports).Count | Should -Be 0
    }
}

Describe 'New-RelativePathMap keys compare like the local filesystem (SR-034)' {
    # The Linux half — Ordinal keys keeping 'Readme.txt' and 'readme.txt' as
    # two rows — runs where $IsWindows is false (WSL/container CI); on Windows
    # the map must stay case-insensitive so a case-only rename is NOT a new file.
    It 'merges case-differing keys on Windows and keeps them distinct elsewhere' {
        $map = New-RelativePathMap
        $map['Readme.txt'] = 1
        $map['readme.txt'] = 2
        if ($IsWindows) {
            $map.Count | Should -Be 1
            $map['README.TXT'] | Should -Be 2
        } else {
            $map.Count | Should -Be 2
            $map['Readme.txt'] | Should -Be 1
        }
    }
}
