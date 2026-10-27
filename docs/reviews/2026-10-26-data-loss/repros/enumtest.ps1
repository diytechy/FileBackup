$root = Join-Path $PSScriptRoot 'enumsrc'
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory "$root\ok", "$root\locked\inner" -Force | Out-Null
Set-Content "$root\ok\a.txt" 'a'; Set-Content "$root\locked\inner\b.txt" 'b'
icacls "$root\locked" /deny "$($env:USERNAME):(RX)" | Out-Null
$err = $null
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable err
"files: " + (($files | ForEach-Object { $_.FullName.Substring($root.Length) }) -join ', ')
foreach ($e in $err) { "error TargetObject type=[{0}] value=[{1}] startsWithRoot={2}" -f $e.TargetObject.GetType().Name, $e.TargetObject, "$($e.TargetObject)".StartsWith($root, 'OrdinalIgnoreCase') }
icacls "$root\locked" /remove:d "$($env:USERNAME)" | Out-Null
Remove-Item $root -Recurse -Force
