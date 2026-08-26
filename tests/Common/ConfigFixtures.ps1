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

    $validSet = '"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true'
    $wrap = { param([string]$Sets, [string]$Extra = '') "{`"ConfigVersion`":1,`"BackupSets`":[{$Sets}]$Extra}" }
    $exampleJson = Get-Content -LiteralPath (Join-Path $RepoRoot 'container\FileBackup.example.json') -Raw

    $accepted = @(
        @{ Name = 'shipped-example'
           Json = $exampleJson }
        @{ Name = 'minimal-required-keys-only'
           Json = (& $wrap $validSet) }
        @{ Name = 'every-optional-key-present'
           Json = '{"ConfigVersion":1,"Tools":{"SevenZipPath":"/usr/bin/7z","FfprobePath":"/usr/bin/ffprobe"},"Secrets":{"ToEmail":"a@b.c","FromEmail":"d@e.f","SmtpServer":"smtp","SmtpPort":587},"BackupSets":[{"Name":"a","SourcePath":"s","SourceStatePath":"st","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"W","CompressEnabled":true,"AllowEmptySource":true}]}' }
        @{ Name = 'lowercase-hash-recalc-freq'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"n","CompressEnabled":false}]}' }
        # JSON has one number type: an integral-valued number IS that integer,
        # for the validator and for the schema's `const: 1` alike.
        @{ Name = 'integral-float-config-version'
           Json = '{"ConfigVersion":1.0,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true}]}' }
        # A single bare set object (not wrapped in an array) is accepted and
        # wrapped by the loader; the schema's BackupSets anyOf says the same.
        @{ Name = 'bare-single-set-object'
           Json = "{`"ConfigVersion`":1,`"BackupSets`":{$validSet}}" }
        @{ Name = 'two-sets-warns-but-loads'
           Json = "{`"ConfigVersion`":1,`"BackupSets`":[{$validSet},{`"Name`":`"b`",`"SourcePath`":`"s2`",`"BackupPath`":`"b2`",`"ChangePath`":`"c2`",`"HashRecalcFreq`":`"A`",`"CompressEnabled`":false}]}" }
    )

    $rejected = @(
        # --- ConfigVersion ---------------------------------------------------
        @{ Name = 'missing-version'
           Json = "{`"BackupSets`":[{$validSet}]}"
           Message = '*ConfigVersion*missing*' }
        @{ Name = 'future-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":1', '"ConfigVersion":2')
           Message = '*declares version 2*supports up to 1*' }
        # Out of Int32 range: refused as an unsupported VERSION, not by luck of
        # the fractional-part test (which cannot even run on a BigInteger).
        @{ Name = 'out-of-range-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":1', '"ConfigVersion":99999999999999999999')
           Message = '*supports up to 1*' }
        @{ Name = 'fractional-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":1', '"ConfigVersion":1.5')
           Message = '*ConfigVersion*fractional part*' }
        @{ Name = 'string-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":1', '"ConfigVersion":"1"')
           Message = '*ConfigVersion*' }
        @{ Name = 'zero-version'
           Json = (& $wrap $validSet).Replace('"ConfigVersion":1', '"ConfigVersion":0')
           Message = '*ConfigVersion*>= 1*' }

        # --- closed schema ---------------------------------------------------
        @{ Name = 'unknown-key-top'
           Json = (& $wrap $validSet ',"Bogus":1')
           Message = '*$.Bogus*unrecognized key*' }
        @{ Name = 'unknown-key-set-typo'
           Json = (& $wrap "$validSet,`"AllowEmptySources`":true")
           Message = '*AllowEmptySources*unrecognized key*' }
        # WP9 step 5: storage is always content-addressed, so the retired
        # PreserveFolderTree key is not "ignored" -- a config still carrying it
        # is refused by the closed schema, naming $.BackupSets[0].
        # PreserveFolderTree (the glob cannot spell the [0]: brackets are a
        # wildcard character class).
        @{ Name = 'retired-key-preserve-folder-tree'
           Json = (& $wrap "$validSet,`"PreserveFolderTree`":false")
           Message = '*PreserveFolderTree*unrecognized key*' }
        @{ Name = 'unknown-key-tools'
           Json = (& $wrap $validSet ',"Tools":{"Bogus":"x"}')
           Message = '*$.Tools.Bogus*unrecognized key*' }
        @{ Name = 'json-credential'
           Json = (& $wrap $validSet ',"Secrets":{"Credential":"x"}')
           Message = '*Secrets.Credential*PSCredential*' }

        # --- wrong JSON type (a coercion would silently change the meaning) ---
        @{ Name = 'string-boolean-compress-enabled'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":"false"}]}'
           Message = '*CompressEnabled*JSON boolean*' }
        # The proven exploit: [bool]'false' is $true, so a quoted "false" here
        # used to DISARM the SR-036 delete-all refusal.
        @{ Name = 'string-boolean-allow-empty-source'
           Json = (& $wrap "$validSet,`"AllowEmptySource`":`"false`"")
           Message = '*AllowEmptySource*JSON boolean*' }
        # [string]@('x','y') is 'x y' -- an array used to become a literal path.
        @{ Name = 'array-source-path'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":["x","y"],"BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = '*SourcePath*JSON string*' }
        @{ Name = 'number-name'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":5,"SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = '*Name*JSON string*' }
        @{ Name = 'number-source-state-path'
           Json = (& $wrap "$validSet,`"SourceStatePath`":7")
           Message = '*SourceStatePath*JSON string*' }
        @{ Name = 'number-tools-seven-zip-path'
           Json = (& $wrap $validSet ',"Tools":{"SevenZipPath":7}')
           Message = '*Tools.SevenZipPath*JSON string*' }
        # [string]@('A') is 'A', so an array used to pass the enum check.
        @{ Name = 'array-hash-recalc-freq'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":["A"],"CompressEnabled":true}]}'
           Message = '*HashRecalcFreq*JSON string*' }
        @{ Name = 'number-secrets-to-email'
           Json = (& $wrap $validSet ',"Secrets":{"ToEmail":5}')
           Message = '*Secrets.ToEmail*JSON string*' }
        @{ Name = 'non-integer-smtp-port'
           Json = (& $wrap $validSet ',"Secrets":{"SmtpPort":"abc"}')
           Message = '*Secrets.SmtpPort*integer*' }
        @{ Name = 'string-backup-sets'
           Json = '{"ConfigVersion":1,"BackupSets":"x"}'
           Message = '*BackupSets*' }

        # --- shape / value constraints ---------------------------------------
        @{ Name = 'bad-enum-hash-recalc-freq'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"Q","CompressEnabled":true}]}'
           Message = '*invalid HashRecalcFreq*' }
        @{ Name = 'empty-backup-sets'
           Json = '{"ConfigVersion":1,"BackupSets":[]}'
           Message = '*at least one BackupSets entry*' }
        @{ Name = 'missing-change-path'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = "*non-empty 'ChangePath'*" }
        @{ Name = 'empty-source-path'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N","CompressEnabled":true}]}'
           Message = "*non-empty 'SourcePath'*" }
        @{ Name = 'missing-compress-enabled'
           Json = '{"ConfigVersion":1,"BackupSets":[{"Name":"a","SourcePath":"s","BackupPath":"b","ChangePath":"c","HashRecalcFreq":"N"}]}'
           Message = "*must define 'CompressEnabled'*" }
        @{ Name = 'not-json-at-all'
           Json = 'not json at all'
           Message = '*not valid JSON*' }
    )

    return @{ Accepted = $accepted; Rejected = $rejected }
}
