<#
.SYNOPSIS  WP17 Part B1: the sampled compressibility probe and the pure
           storage-form decision core (SR-081, LLR-086).
.NOTES     TC-223. Both helpers are module-INTERNAL, so every call goes through
           InModuleScope FileBackup.Engine. Every corpus file is built IN THE
           TEST under TestDrive - nothing here reads the repo or the machine.
           Run: Invoke-Pester -Path tests\Unit\CompressProbe.Tests.ps1
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force

    function New-ProbeTextBytes {
        # English-like text with real variation, not one repeated byte: a single
        # repeated byte would compress to nothing and prove less than nothing.
        param([int]$Size)
        $words = @('backup','manifest','snapshot','engine','compression','probe','sample',
                   'the','of','and','entropy','brotli','window','ratio','decision',
                   'storage','filename','integrity','restore','checksum','dictionary')
        $rnd = [Random]::new(20260901)
        $sb  = [System.Text.StringBuilder]::new()
        while ($sb.Length -lt $Size + 32) {
            $null = $sb.Append($words[$rnd.Next(0, $words.Count)]).Append(' ')
            if ($rnd.Next(0, 14) -eq 0) { $null = $sb.Append("`n") }
        }
        return [System.Text.Encoding]::ASCII.GetBytes($sb.ToString().Substring(0, $Size))
    }

    function New-ProbeRandomBytes {
        param([int]$Size)
        $b = [byte[]]::new($Size)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($b)
        return $b
    }

    function New-ProbeFile {
        # Writes the concatenation of the given byte arrays and returns the path.
        param([string]$Path, [byte[][]]$Parts)
        $out = [System.IO.File]::Create($Path)
        try { foreach ($p in $Parts) { $out.Write($p, 0, $p.Length) } } finally { $out.Dispose() }
        return $Path
    }

    function Invoke-Probe {
        # The one seam into the module-internal I/O shell.
        param([string]$Path)
        InModuleScope FileBackup.Engine -Parameters @{ P = $Path } {
            param($P)
            Measure-SampleCompressibility -Path $P
        }
    }

    function Invoke-Decision {
        param([hashtable]$Ask)
        InModuleScope FileBackup.Engine -Parameters @{ A = $Ask } {
            param($A)
            Resolve-CompressionDecision @A
        }
    }
}

Describe 'Measure-SampleCompressibility - the I/O shell (TC-223, SR-081, LLR-086)' {

    BeforeAll {
        $script:corpus = Join-Path $TestDrive 'corpus'
        New-Item -ItemType Directory -Path $script:corpus -Force | Out-Null
        $script:pathRandom = New-ProbeFile (Join-Path $corpus 'random.bin')      @(, (New-ProbeRandomBytes -Size 4MB))
        $script:pathText   = New-ProbeFile (Join-Path $corpus 'text.txt')        @(, (New-ProbeTextBytes   -Size 4MB))
        $script:pathHead   = New-ProbeFile (Join-Path $corpus 'mixed-head.bin')  @((New-ProbeTextBytes -Size 64KB), (New-ProbeRandomBytes -Size 4MB))
        $script:pathThird  = New-ProbeFile (Join-Path $corpus 'mixed-third.bin') @((New-ProbeRandomBytes -Size 1MB), (New-ProbeTextBytes -Size 1MB), (New-ProbeRandomBytes -Size 1MB))
        $script:path500K   = New-ProbeFile (Join-Path $corpus 'small-500k.bin')  @(, (New-ProbeRandomBytes -Size 512000))
        $script:path4K     = New-ProbeFile (Join-Path $corpus 'tiny-4k.bin')     @(, (New-ProbeRandomBytes -Size 4096))
        $script:pathEmpty  = New-ProbeFile (Join-Path $corpus 'empty.bin')       @(, ([byte[]]::new(0)))
        # Exactly 3 x SampleBytes + 1: the smallest file that takes three windows.
        $script:pathGeom   = New-ProbeFile (Join-Path $corpus 'geometry.bin')    @(, (New-ProbeRandomBytes -Size (3 * 262144 + 1)))
    }

    It 'reports the two ruled constants at their Owner-ruled values (TC-223)' {
        $c = InModuleScope FileBackup.Engine {
            [pscustomobject]@{
                Threshold  = $script:CompressProbeThreshold
                MinBytes   = $script:CompressProbeMinBytes
                SampleSize = $script:CompressProbeSampleBytes
                Count      = $script:CompressProbeSampleCount
            }
        }
        $c.Threshold  | Should -Be 0.10
        $c.MinBytes   | Should -Be 262144
        $c.SampleSize | Should -Be 262144
        $c.Count      | Should -Be 3
    }

    It 'measures pure random bytes at >= 0.98 - the dispose hazard is pinned here (TC-223)' {
        # A compressed count read BEFORE the encoder is disposed reads short and
        # would call random bytes compressible. This assertion is the pin: it
        # fails loudly the moment the count is taken before Dispose().
        $r = Invoke-Probe $script:pathRandom
        $r                 | Should -Not -BeNullOrEmpty
        $r.SampledBytes    | Should -Be (3 * 262144)
        $r.Windows.Count   | Should -Be 3
        $r.Ratio           | Should -BeGreaterOrEqual 0.98
        $d = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $true
                                Length = 4MB; SampledBytes = $r.SampledBytes; CompressedBytes = $r.CompressedBytes }
        $d.Compress | Should -BeFalse
        $d.Reason   | Should -Be 'ProbeIncompressible'
    }

    It 'measures repeated text far below 1 and decides ProbeCompressible (TC-223)' {
        $r = Invoke-Probe $script:pathText
        $r.Ratio | Should -BeLessThan 0.5
        $d = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $false
                                Length = 4MB; SampledBytes = $r.SampledBytes; CompressedBytes = $r.CompressedBytes }
        $d.Compress | Should -BeTrue
        $d.Reason   | Should -Be 'ProbeCompressible'
    }

    It 'keeps a random file with a 64 KiB text head RAW - the aggregate rule (TC-223)' {
        # The defect review's own failure mode: an any-sample rule would have
        # sent this whole multi-megabyte file to -mx=9 on its first window.
        $r = Invoke-Probe $script:pathHead
        $r.Ratio            | Should -BeGreaterThan 0.90
        $r.Ratio            | Should -BeLessThan 1.05
        $r.Windows[0]       | Should -BeLessThan $r.Windows[1]   # the head IS compressible
        $d = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $true
                                Length = (4MB + 64KB); SampledBytes = $r.SampledBytes; CompressedBytes = $r.CompressedBytes }
        $d.Compress | Should -BeFalse
        $d.Reason   | Should -Be 'ProbeIncompressible'
    }

    It 'compresses a file one third text - aggregate ~0.7 (TC-223)' {
        $r = Invoke-Probe $script:pathThird
        $r.Ratio | Should -BeGreaterThan 0.5
        $r.Ratio | Should -BeLessThan 0.85
        $d = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $false
                                Length = 3MB; SampledBytes = $r.SampledBytes; CompressedBytes = $r.CompressedBytes }
        $d.Compress | Should -BeTrue
        $d.Reason   | Should -Be 'ProbeCompressible'
    }

    It 'reads a 500 KiB file exactly ONCE, whole, as a single sample (TC-223)' {
        $r = Invoke-Probe $script:path500K
        $r.Windows.Count | Should -Be 1
        $r.SampledBytes  | Should -Be 512000
    }

    It 'reads a 4 KiB file as one 4096-byte sample - the floor is the caller''s business (TC-223)' {
        $r = Invoke-Probe $script:path4K
        $r.Windows.Count | Should -Be 1
        $r.SampledBytes  | Should -Be 4096
    }

    It 'takes three windows totalling 3 x SampleBytes for a file of 3 x SampleBytes + 1 (TC-223)' {
        $r = Invoke-Probe $script:pathGeom
        $r.Windows.Count | Should -Be 3
        $r.SampledBytes  | Should -Be (3 * 262144)
    }

    It 'returns $null for an empty file, and does not throw (TC-223)' {
        { Invoke-Probe $script:pathEmpty } | Should -Not -Throw
        Invoke-Probe $script:pathEmpty | Should -BeNullOrEmpty
    }

    It 'returns $null for a vanished path, and does not throw (TC-223)' {
        $gone = Join-Path $TestDrive 'never-existed.bin'
        { Invoke-Probe $gone } | Should -Not -Throw
        Invoke-Probe $gone | Should -BeNullOrEmpty
    }

    It 'returns $null for a path held open with FileShare.None, and does not throw (TC-223)' {
        # The probe opens with FileShare.Read (the same share the hasher uses),
        # so an exclusive hold is a share violation, which must cost a decision
        # and never a file.
        $locked = New-ProbeFile (Join-Path $script:corpus 'locked.bin') @(, (New-ProbeRandomBytes -Size 1MB))
        $hold = [System.IO.FileStream]::new($locked, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Invoke-Probe $locked } | Should -Not -Throw
            Invoke-Probe $locked | Should -BeNullOrEmpty
        } finally { $hold.Dispose() }
        # ...and it is readable again the moment the hold goes away.
        Invoke-Probe $locked | Should -Not -BeNullOrEmpty
    }
}

Describe 'Resolve-CompressionDecision - the pure core (TC-223, SR-081, LLR-086)' {

    It 'decides <Enabled>/<Mode>/list=<List>/<Floor>/probe=<Probe> as <XCompress>/<XReason> (TC-223)' -ForEach @(
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $true; XReason = 'ModeOff' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'off'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $true; XReason = 'ProbeUnavailable' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $true; XReason = 'ProbeCompressible' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'ProbeIncompressible' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'ListExempt' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $true; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $true; XReason = 'ProbeUnavailable' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $true; XReason = 'ProbeCompressible' }
        @{ Enabled = $true; Mode = 'always'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'ProbeIncompressible' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'BelowFloor' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'ProbeUnavailable' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $true; XReason = 'ProbeCompressible' }
        @{ Enabled = $true; Mode = 'always'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'ProbeIncompressible' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'off'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'excluded-extensions'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $true; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 65536; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 65536; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 65536; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'below'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 4194304; Sampled = 0; Compressed = 0; Probe = 'none'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 500; Probe = 'compressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
        @{ Enabled = $false; Mode = 'always'; List = $false; Length = 4194304; Sampled = 1000; Compressed = 950; Probe = 'incompressible'; Floor = 'above'; XCompress = $false; XReason = 'CompressDisabled' }
    ) {
        $d = Invoke-Decision @{
            CompressEnabled = $Enabled; Mode = $Mode; ListSaysCompress = $List
            Length = $Length; SampledBytes = $Sampled; CompressedBytes = $Compressed
        }
        $d.Compress | Should -Be $XCompress
        $d.Reason   | Should -Be $XReason
    }

    It 'treats CompressedBytes exactly at (1 - Threshold) x SampledBytes as compressible (TC-223)' {
        $at = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $false
                                 Length = 4MB; SampledBytes = 1000; CompressedBytes = 900 }
        $at.Compress | Should -BeTrue
        $at.Reason   | Should -Be 'ProbeCompressible'
    }

    It 'treats one byte more than the boundary as incompressible (TC-223)' {
        $over = Invoke-Decision @{ CompressEnabled = $true; Mode = 'always'; ListSaysCompress = $false
                                   Length = 4MB; SampledBytes = 1000; CompressedBytes = 901 }
        $over.Compress | Should -BeFalse
        $over.Reason   | Should -Be 'ProbeIncompressible'
    }

    It 'rejects a mode outside the exact-lowercase vocabulary (TC-223)' {
        { Invoke-Decision @{ CompressEnabled = $true; Mode = 'Always'; ListSaysCompress = $true; Length = 4MB } } |
            Should -Throw
        { Invoke-Decision @{ CompressEnabled = $true; Mode = 'maybe'; ListSaysCompress = $true; Length = 4MB } } |
            Should -Throw
    }

    It 'has no name-based override: no parameter and no Reason is named after a format (TC-223, Q7)' {
        $cmd = InModuleScope FileBackup.Engine { Get-Command Resolve-CompressionDecision }
        $names = @($cmd.Parameters.Keys)
        $names | Should -Not -Contain 'Ruled'
        $names | Should -Not -Contain 'Extension'
        $names | Should -Not -Contain 'Name'
        $names | Should -Not -Contain 'Path'
    }
}
