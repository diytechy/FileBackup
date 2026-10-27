param([string]$Dir, [int]$Count = 1000, [int]$Size = 65536)
New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$buf = [byte[]]::new($Size); [System.Random]::new(1).NextBytes($buf)
foreach ($mode in 'no-flush', 'flush-to-disk') {
    $sub = Join-Path $Dir $mode; New-Item -ItemType Directory -Path $sub -Force | Out-Null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $Count; $i++) {
        $p = Join-Path $sub "f$i.tmp"
        $fs = [System.IO.FileStream]::new($p, 'CreateNew', 'Write', 'None', 1MB)
        $fs.Write($buf, 0, $buf.Length)
        if ($mode -eq 'flush-to-disk') { $fs.Flush($true) }
        $fs.Dispose()
        [System.IO.File]::Move($p, (Join-Path $sub "f$i.obj"))
    }
    $sw.Stop()
    '{0,-14} {1} files x {2} KiB: {3:N2} s ({4:N2} ms/file)' -f $mode, $Count, ($Size/1KB), $sw.Elapsed.TotalSeconds, ($sw.Elapsed.TotalMilliseconds / $Count)
}
Remove-Item -LiteralPath $Dir -Recurse -Force
