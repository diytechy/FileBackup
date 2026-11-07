<#
.SYNOPSIS
Regenerates the .NET Brotli size table that pins the Rust compression probe.

.DESCRIPTION
Builds the deterministic 256 KiB buffers defined below and records the exact
compressed size of each from .NET's BrotliEncoder.TryCompress at quality 1,
window 22 (the PowerShell probe's own settings). The Rust test
`rust/tests/probe.rs` builds the same buffers with the same generator and
requires its ratio to land within 0.005 of each recorded one (LLR-162).

The generator is defined here and again in rust/tests/probe.rs; the table
records its constants so a drift in either is visible. Run it only to change
the buffer set; the checked-in table is the artifact the test reads.

.PARAMETER File
Instead of regenerating the table, print .NET quality-1/window-22 ratios for
each named file at the probe plan's offsets (same formula as
format::probe_plan), for comparison with `cargo run --example probe_windows`.
Read-only. Several paths may be given comma-separated.

.PARAMETER OutFile
Where to write the table (default: rust/tests/fixtures/brotli-reference.json).

.OUTPUTS
The table file; one summary line per buffer on the host.
#>
[CmdletBinding()]
param(
    [string[]]$File,
    [string]$OutFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'rust/tests/fixtures/brotli-reference.json')
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO.Compression;

public static class ProbeGen
{
    public const int Size = 256 * 1024;
    public const ulong BaseSeed = 0x123456789ABCDEF0UL;
    const string Phrase = "The quick brown fox jumps over the lazy dog. ";
    static ulong s;

    static void Seed(ulong v) { s = v == 0 ? 1UL : v; }
    static byte Next()
    {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        return (byte)(s >> 32);
    }
    static void Random(byte[] b, int from, int to) { for (int i = from; i < to; i++) b[i] = Next(); }
    static void Text(byte[] b, int from, int to)
    {
        for (int i = from; i < to; i++) b[i] = (byte)Phrase[(i - from) % Phrase.Length];
    }

    // name -> bytes; index is the buffer's position in Names (it seeds the generator).
    public static readonly string[] Names = {
        "zeros", "random", "text", "longrange-64KiB-x4",
        "block-mix-86", "block-mix-90", "block-mix-94",
        "alpha-200", "alpha-180", "alpha-170",
        "interleaved-9of10", "head-text-12"
    };

    public static byte[] Build(int index)
    {
        string name = Names[index];
        var b = new byte[Size];
        Seed(BaseSeed + (ulong)index);
        if (name == "zeros") { }
        else if (name == "random") Random(b, 0, Size);
        else if (name == "text") Text(b, 0, Size);
        else if (name == "longrange-64KiB-x4")
        {
            Random(b, 0, 65536);
            for (int i = 65536; i < Size; i++) b[i] = b[i - 65536];
        }
        else if (name.StartsWith("block-mix-"))
        {
            int p = int.Parse(name.Substring(10));
            Random(b, 0, (int)((long)Size * p / 100));
        }
        else if (name.StartsWith("alpha-"))
        {
            int m = int.Parse(name.Substring(6));
            for (int i = 0; i < Size; i++) b[i] = (byte)(Next() % m);
        }
        else if (name == "interleaved-9of10")
        {
            for (int blk = 0; blk < Size / 4096; blk++)
                if (blk % 10 != 9) Random(b, blk * 4096, (blk + 1) * 4096);
        }
        else if (name == "head-text-12")
        {
            int cut = (int)((long)Size * 12 / 100);
            Text(b, 0, cut);
            Random(b, cut, Size);
        }
        else throw new ArgumentException(name);
        return b;
    }

    public static int BrotliSize(byte[] data)
    {
        var dst = new byte[BrotliEncoder.GetMaxCompressedLength(data.Length)];
        int written;
        if (!BrotliEncoder.TryCompress(data, dst, out written, 1, 22))
            throw new InvalidOperationException("TryCompress failed");
        return written;
    }
}
'@

if ($File) {
    # `pwsh -File` passes one string, so accept a comma-separated list too.
    $File = @($File | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $win = 256KB
    foreach ($path in $File) {
        $length = (Get-Item -LiteralPath $path).Length
        Write-Host "$path`tlength=$length"
        if ($length -le $win) { Write-Host '  not measured (at or under 256 KiB)'; continue }
        if ($length -lt 9 * $win) { $plan = @(, @([long]0, [int]$length)) }
        else {
            $plan = foreach ($k in 1..7) { , @([long][math]::Floor([decimal]$k * ([decimal]($length - $win)) / 8), [int]$win) }
        }
        $stream = [IO.File]::OpenRead($path)
        $ratios = @(); $raw = 0; $packed = 0
        try {
            foreach ($w in $plan) {
                $buf = New-Object byte[] $w[1]
                [void]$stream.Seek($w[0], 'Begin')
                $got = 0
                while ($got -lt $buf.Length) { $n = $stream.Read($buf, $got, $buf.Length - $got); if ($n -le 0) { throw 'short read' }; $got += $n }
                $size = [ProbeGen]::BrotliSize($buf)
                $ratios += $size / $buf.Length; $raw += $buf.Length; $packed += $size
            }
        } finally { $stream.Dispose() }
        $sorted = @($ratios | Sort-Object)
        $mean = $packed / $raw
        $trim = if ($sorted.Count -gt 2) { ($sorted[1..($sorted.Count - 2)] | Measure-Object -Average).Average } else { $sorted[[int][math]::Floor($sorted.Count / 2)] }
        $med = $sorted[[int][math]::Floor($sorted.Count / 2)]
        $inv = [Globalization.CultureInfo]::InvariantCulture
        Write-Host ('  offsets=' + (($plan | ForEach-Object { $_[0] }) -join ','))
        Write-Host ('  ratios=' + (($ratios | ForEach-Object { $_.ToString('F4', $inv) }) -join ','))
        foreach ($c in @(@('mean', $mean), @('trimmed', $trim), @('median', $med))) {
            Write-Host ('  {0}={1} {2}' -f $c[0], ([double]$c[1]).ToString('F4', $inv), $(if ($c[1] -le 0.90) { 'compress' } else { 'raw' }))
        }
    }
    return
}

$entries = for ($i = 0; $i -lt [ProbeGen]::Names.Length; $i++) {
    $buffer = [ProbeGen]::Build($i)
    $size = [ProbeGen]::BrotliSize($buffer)
    $ratio = [math]::Round($size / $buffer.Length, 4)
    Write-Host ('{0,-22} raw={1} brotli={2} ratio={3}' -f [ProbeGen]::Names[$i], $buffer.Length, $size, $ratio)
    [ordered]@{ name = [ProbeGen]::Names[$i]; raw = $buffer.Length; size = $size }
}

$table = [ordered]@{
    how = 'Generated by scripts/gen_brotli_reference.ps1 with .NET BrotliEncoder.TryCompress, quality 1, window 22. Do not edit by hand.'
    dotnet = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    generator = [ordered]@{
        prng = 'xorshift64: s ^= s << 13; s ^= s >> 7; s ^= s << 17; byte = (s >> 32) & 0xFF'
        seed = ('buffer at position i in the list is seeded with 0x{0:X16} + i' -f [ProbeGen]::BaseSeed)
        buffer_bytes = [ProbeGen]::Size
        text = 'the phrase "The quick brown fox jumps over the lazy dog. " repeated from its start at the run start'
        shapes = [ordered]@{
            zeros = 'all zero bytes'
            random = 'PRNG bytes'
            text = 'repeated phrase'
            'longrange-64KiB-x4' = 'a 64 KiB PRNG block repeated four times (WP17 longrange shape)'
            'block-mix-P' = 'first P percent of the buffer PRNG bytes, the rest zeros'
            'alpha-M' = 'every byte is a PRNG byte modulo M'
            'interleaved-9of10' = '4 KiB blocks; block number mod 10 = 9 is zeros, the others PRNG bytes'
            'head-text-12' = 'first 12 percent repeated phrase, the rest PRNG bytes'
        }
    }
    entries = @($entries)
}
$json = $table | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($OutFile, $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutFile"
