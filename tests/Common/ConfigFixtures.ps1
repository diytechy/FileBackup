<#
.SYNOPSIS
    The ONE configuration-fixture corpus (SR-042). TC-074 and TC-075 drive the
    runtime validator (Import-BackupConfiguration) with it; TC-077 drives the
    published container/FileBackup.schema.json with the same list. Because both
    read this file, the schema and the validator cannot drift apart, and a new
    defect only has to be written down once.

.DESCRIPTION
    Dot-source this file, then call Get-ConfigFixtureCorpus. It returns

        @{
          Accepted = @( @{ Name = '<id>'; Json = '<document>' }, ... )
          Rejected = @( @{ Name = '<id>'; Json = '<document>'; Message = '<wildcard>' }, ... )
        }

    Every Accepted fixture must load without error AND validate against the
    schema; every Rejected fixture must throw a terminating error matching
    Message AND fail schema validation. Fixtures reference no real filesystem
    path -- the loader never touches the paths it validates (SR-014 does that
    later), so the corpus is pure and fast.
#>

function Get-ConfigFixtureCorpus {
    <#
    .SYNOPSIS
        Returns the shared accepted/rejected JSON configuration fixtures
        (SR-042) consumed by TC-074, TC-075 and TC-077.
    .PARAMETER RepoRoot
        Repository root; defaults to two levels above this file. Used only to
        read container/FileBackup.example.json, which is itself a fixture so
        the shipped example is proven against both the validator and the
        schema.
    .OUTPUTS
        [hashtable] with Accepted and Rejected arrays (see the file synopsis).
    #>
    [CmdletBinding()]
    param([string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))

    $validSet = '"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":true'
    $wrap = { param([string]$Sets, [string]$Extra = '') "{`"ConfigVersion`":3,`"BackupSets`":[{$Sets}]$Extra}" }
    $exampleJson = Get-Content -LiteralPath (Join-Path $RepoRoot 'container\FileBackup.example.json') -Raw

    $accepted = @(
        @{ Name = 'shipped-example'
           Json = $exampleJson }
        @{ Name = 'minimal-required-keys-only'
           Json = (& $wrap $validSet) }
        @{ Name = 'every-optional-key-present'
           Json = '{"ConfigVersion":3,"Tools":{"SevenZipPath":"/usr/bin/7z","FfprobePath":"/usr/bin/ffprobe"},"Secrets":{"ToEmail":"a@b.c","FromEmail":"d@e.f","SmtpServer":"smtp","SmtpPort":587},"BackupSets":[{"Name":"a","SourcePath":"s","SourceStatePath":"st","StorePath":"st0","HashRecalcFreq":"W","CompressEnabled":true,"AllowEmptySource":true,"BrowseView":"index","ViewPath":"v","CompressProbe":"excluded-extensions"}]}' }
        @{ Name = 'browse-view-off'
           Json = (& $wrap "$validSet,`"BrowseView`":`"off`"") }
        # SR-081's CompressProbe: the three exact-lowercase values are accepted
        # and the key is OPTIONAL - every other fixture here omits it, which is
        # the "absent key" case (it resolves to 'always', TC-227).
        @{ Name = 'compress-probe-off'
           Json = (& $wrap "$validSet,`"CompressProbe`":`"off`"") }
        @{ Name = 'compress-probe-excluded-extensions'
           Json = (& $wrap "$validSet,`"CompressProbe`":`"excluded-extensions`"") }
        @{ Name = 'compress-probe-always'
           Json = (& $wrap "$validSet,`"CompressProbe`":`"always`"") }
        @{ Name = 'lowercase-hash-recalc-freq'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"n","CompressEnabled":false}]}' }
        # JSON has one number type: an integral-valued number IS that integer,
        # for the validator and for the schema's `const: 2` alike.
        @{ Name = 'integral-float-config-version'
           Json = '{"ConfigVersion":3.0,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":true}]}' }
        # A single bare set object (not wrapped in an array) is accepted and
        # wrapped by the loader; the schema's BackupSets anyOf says the same.
        @{ Name = 'bare-single-set-object'
           Json = "{`"ConfigVersion`":3,`"BackupSets`":{$validSet}}" }
        @{ Name = 'two-sets-warns-but-loads'
           Json = "{`"ConfigVersion`":3,`"BackupSets`":[{$validSet},{`"Name`":`"b`",`"SourcePath`":`"s2`",`"StorePath`":`"st2`",`"HashRecalcFreq`":`"A`",`"CompressEnabled`":false}]}" }
    )

    $rejected = @(
        # --- ConfigVersion ---------------------------------------------------
        @{ Name = 'missing-version'
           Json = "{`"BackupSets`":[{$validSet}]}"
           Message = '*ConfigVersion*missing*' }
        @{ Name = 'future-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":4')
           Message = '*declares version 4*supports up to 3*' }
        # SR-063: version 1 is refused as TOO OLD, not half-understood -- its
        # key set carried the removed PreserveFolderTree selector.
        @{ Name = 'version-1-too-old'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":1')
           Message = '*declares version 1*too old*ConfigVersion to 3*' }
        # Plan C44 (L1): version 2 is refused as TOO OLD as well -- its sets
        # named BackupPath and ChangePath, which StorePath replaced.
        @{ Name = 'version-2-too-old'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":2')
           Message = '*declares version 2*too old*StorePath*ConfigVersion to 3*' }
        # Out of Int32 range: refused as an unsupported VERSION, not by luck of
        # the fractional-part test (which cannot even run on a BigInteger).
        @{ Name = 'out-of-range-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":99999999999999999999')
           Message = '*supports up to 3*' }
        @{ Name = 'fractional-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":3.5')
           Message = '*ConfigVersion*fractional part*' }
        @{ Name = 'string-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":"3"')
           Message = '*ConfigVersion*' }
        @{ Name = 'zero-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":3', '"ConfigVersion":0')
           Message = '*ConfigVersion*>= 1*' }

        # --- closed schema ---------------------------------------------------
        @{ Name = 'unknown-key-top'
           Json = (& $wrap $validSet ',"Bogus":1')
           Message = '*$.Bogus*unrecognized key*' }
        @{ Name = 'unknown-key-set-typo'
           Json = (& $wrap "$validSet,`"AllowEmptySources`":true")
           Message = '*AllowEmptySources*unrecognized key*' }
        # SR-063 (TC-125): the retired PreserveFolderTree key gets a NAMED
        # removal diagnostic, not the generic unknown-key message -- an author
        # coming from v1 must be told the selector is GONE, not misspelled.
        @{ Name = 'retired-key-preserve-folder-tree'
           Json = (& $wrap "$validSet,`"PreserveFolderTree`":false")
           Message = '*PreserveFolderTree*removed in ConfigVersion 2*' }
        # Plan C44 (L1, S1): BackupPath and ChangePath are refused BY NAME, with
        # the conversion in the message -- not as unknown keys, and not as a
        # missing StorePath. Alone or beside a StorePath, each one.
        @{ Name = 'retired-key-backup-path'
           Json = (& $wrap "$validSet,`"BackupPath`":`"b`"")
           Message = '*BackupPath and ChangePath were replaced in ConfigVersion 3 by StorePath*' }
        @{ Name = 'retired-key-change-path'
           Json = (& $wrap "$validSet,`"ChangePath`":`"c`"")
           Message = '*BackupPath and ChangePath were replaced in ConfigVersion 3 by StorePath*' }
        @{ Name = 'retired-keys-v2-shaped-set'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = '*BackupPath and ChangePath were replaced in ConfigVersion 3 by StorePath*' }

        # --- BrowseView / ViewPath (SR-063, TC-127) --------------------------
        @{ Name = 'browse-view-link-reserved'
           Json = (& $wrap "$validSet,`"BrowseView`":`"link`"")
           Message = '*BrowseView*link*reserved*' }
        @{ Name = 'browse-view-invalid'
           Json = (& $wrap "$validSet,`"BrowseView`":`"sideways`"")
           Message = '*invalid BrowseView*' }
        @{ Name = 'browse-view-wrong-case'
           Json = (& $wrap "$validSet,`"BrowseView`":`"Index`"")
           Message = '*invalid BrowseView*' }
        @{ Name = 'number-browse-view'
           Json = (& $wrap "$validSet,`"BrowseView`":5")
           Message = '*BrowseView*JSON string*' }
        @{ Name = 'number-view-path'
           Json = (& $wrap "$validSet,`"ViewPath`":7")
           Message = '*ViewPath*JSON string*' }
        # --- CompressProbe (SR-081, TC-227) ----------------------------------
        # The vocabulary is EXACT lowercase, so a mixed-case "Always" is a
        # refusal and not a silent default: an operator who typed it must be
        # told, in both configuration formats.
        @{ Name = 'compress-probe-wrong-case'
           Json = (& $wrap "$validSet,`"CompressProbe`":`"Always`"")
           Message = '*invalid CompressProbe*' }
        @{ Name = 'compress-probe-invalid'
           Json = (& $wrap "$validSet,`"CompressProbe`":`"maybe`"")
           Message = '*invalid CompressProbe*' }
        @{ Name = 'null-compress-probe'
           Json = (& $wrap "$validSet,`"CompressProbe`":null")
           Message = '*CompressProbe*JSON string*' }
        @{ Name = 'number-compress-probe'
           Json = (& $wrap "$validSet,`"CompressProbe`":1")
           Message = '*CompressProbe*JSON string*' }

        @{ Name = 'unknown-key-tools'
           Json = (& $wrap $validSet ',"Tools":{"Bogus":"x"}')
           Message = '*$.Tools.Bogus*unrecognized key*' }
        @{ Name = 'json-credential'
           Json = (& $wrap $validSet ',"Secrets":{"Credential":"x"}')
           Message = '*Secrets.Credential*PSCredential*' }

        # --- wrong JSON type (a coercion would silently change the meaning) ---
        @{ Name = 'string-boolean-compress-enabled'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":"false"}]}'
           Message = '*CompressEnabled*JSON boolean*' }
        # The proven exploit: [bool]'false' is $true, so a quoted "false" here
        # used to DISARM the SR-036 delete-all refusal.
        @{ Name = 'string-boolean-allow-empty-source'
           Json = (& $wrap "$validSet,`"AllowEmptySource`":`"false`"")
           Message = '*AllowEmptySource*JSON boolean*' }
        # [string]@('x','y') is 'x y' -- an array used to become a literal path.
        @{ Name = 'array-source-path'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":["x","y"],"StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = '*SourcePath*JSON string*' }
        @{ Name = 'number-name'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":5,"SourcePath":"s","StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = '*Name*JSON string*' }
        @{ Name = 'number-source-state-path'
           Json = (& $wrap "$validSet,`"SourceStatePath`":7")
           Message = '*SourceStatePath*JSON string*' }
        @{ Name = 'number-tools-seven-zip-path'
           Json = (& $wrap $validSet ',"Tools":{"SevenZipPath":7}')
           Message = '*Tools.SevenZipPath*JSON string*' }
        # [string]@('A') is 'A', so an array used to pass the enum check.
        @{ Name = 'array-hash-recalc-freq'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":["A"],"CompressEnabled":true}]}'
           Message = '*HashRecalcFreq*JSON string*' }
        @{ Name = 'number-secrets-to-email'
           Json = (& $wrap $validSet ',"Secrets":{"ToEmail":5}')
           Message = '*Secrets.ToEmail*JSON string*' }
        @{ Name = 'non-integer-smtp-port'
           Json = (& $wrap $validSet ',"Secrets":{"SmtpPort":"abc"}')
           Message = '*Secrets.SmtpPort*integer*' }
        @{ Name = 'string-backup-sets'
           Json = '{"ConfigVersion":3,"BackupSets":"x"}'
           Message = '*BackupSets*' }

        # --- shape / value constraints ---------------------------------------
        @{ Name = 'bad-enum-hash-recalc-freq'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"Q","CompressEnabled":true}]}'
           Message = '*invalid HashRecalcFreq*' }
        @{ Name = 'empty-backup-sets'
           Json = '{"ConfigVersion":3,"BackupSets":[]}'
           Message = '*at least one BackupSets entry*' }
        @{ Name = 'missing-store-path'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = "*non-empty 'StorePath'*" }
        @{ Name = 'empty-store-path'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = "*non-empty 'StorePath'*" }
        @{ Name = 'empty-source-path'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"","StorePath":"st0","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = "*non-empty 'SourcePath'*" }
        @{ Name = 'missing-compress-enabled'
           Json = '{"ConfigVersion":3,"BackupSets":[{"Name":"a","SourcePath":"s","StorePath":"st0","HashRecalcFreq":"N"}]}'
           Message = "*must define 'CompressEnabled'*" }
        @{ Name = 'not-json-at-all'
           Json = 'not json at all'
           Message = '*not valid JSON*' }
    )

    return @{ Accepted = $accepted; Rejected = $rejected }
}
