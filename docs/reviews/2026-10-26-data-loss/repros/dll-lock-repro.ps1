# Repro: does a restore process that has loaded the kit's System.IO.Hashing.dll
# block the next backup's New-ReconstructScript overwrite (Copy-Item -Force)?
$ErrorActionPreference = 'Stop'
$pkg  = 'C:\Users\Peter\AppData\Local\PackageManagement\NuGet\Packages\System.IO.Hashing.8.0.0\lib'
$root = Join-Path $env:TEMP ('fb-dll-lock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$kitDll = Join-Path $root 'System.IO.Hashing.dll'
Copy-Item -LiteralPath (Join-Path $pkg 'netstandard2.0\System.IO.Hashing.dll') -Destination $kitDll
$job = Start-Job -ScriptBlock {
    param($p)
    Add-Type -Path $p
    [void][System.IO.Hashing.XxHash128]::new()
    Start-Sleep -Seconds 25
} -ArgumentList $kitDll
Start-Sleep -Seconds 8
try {
    # Same bytes, exactly what New-ReconstructScript does every run.
    Copy-Item -LiteralPath (Join-Path $pkg 'netstandard2.0\System.IO.Hashing.dll') -Destination $kitDll -Force
    "overwrite while loaded: SUCCEEDED"
} catch {
    "overwrite while loaded: FAILED - $($_.Exception.GetType().Name): $($_.Exception.Message)"
}
Stop-Job $job; Remove-Job $job -Force
Start-Sleep -Seconds 1
try { Remove-Item -LiteralPath $root -Recurse -Force } catch { "cleanup: $($_.Exception.Message)" }
