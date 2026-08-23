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
    It 'round-trips hex through Convert-HexToShortName/Convert-ShortNameToHex' {
        foreach ($hex in 'DEADBEEF','0','1','FFFFFFFFFFFFFFFF','ABCDEF0123456789') {
            $short = Convert-HexToShortName -Hex $hex -OutputLength 16
            $back  = Convert-ShortNameToHex -ShortName $short
            # Compare as BigInteger to ignore leading-zero padding differences.
            $a = [System.Numerics.BigInteger]::Parse("0$hex",  'AllowHexSpecifier')
            $b = [System.Numerics.BigInteger]::Parse("0$back", 'AllowHexSpecifier')
            $b | Should -Be $a
        }
    }

    It 'produces a stable "<hash> <size><ext>" data filename' {
        $name = Get-HashSizeFileName -HashHex 'ABCDEF0123456789ABCDEF0123456789' -Length 5120 -Extension '.7z'
        $name | Should -Match '\.7z$'
        $name | Should -Match '^\S{16} \S{10}\.7z$'
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
        $map['Version'] | Should -Be '1'
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

        $text = [IO.File]::ReadAllText($witness) -replace 'Version=1', 'Version=99'
        [IO.File]::WriteAllText($witness, $text + "SomeFutureKey=whatever`n")
        $v = Test-ManifestWitness -FolderPath $folder
        $v.Status         | Should -Be 'Verified'   # a newer witness must never condemn a good manifest
        $v.VersionUnknown | Should -BeTrue
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
