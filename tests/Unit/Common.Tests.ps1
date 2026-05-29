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
