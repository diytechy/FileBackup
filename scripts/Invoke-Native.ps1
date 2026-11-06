<#
.SYNOPSIS
Builds and checks the native engine with explicit disk-conscious cache locations.
#>
[CmdletBinding()]
param(
    [ValidateSet('Test','Build','Lint','Format')][string]$Action = 'Test',
    [string]$BuildRoot = $env:FILEBACKUP_BUILD_ROOT,
    [switch]$Release
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $BuildRoot) {
    $BuildRoot = if ($IsWindows -and (Test-Path -LiteralPath 'D:\')) { 'D:\FileBackupBuild' }
                 else { Join-Path $repo '.artifacts/native-build' }
}
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
foreach ($part in 'cargo-home', 'target', 'tmp') {
    New-Item -ItemType Directory -Force -Path (Join-Path $BuildRoot $part) | Out-Null
}
$saved = @{}
foreach ($key in 'CARGO_HOME', 'CARGO_TARGET_DIR', 'TEMP', 'TMP', 'TMPDIR') {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
try {
    $env:CARGO_HOME = Join-Path $BuildRoot 'cargo-home'
    $env:CARGO_TARGET_DIR = Join-Path $BuildRoot 'target'
    $env:TEMP = Join-Path $BuildRoot 'tmp'
    $env:TMP = $env:TEMP
    $env:TMPDIR = $env:TEMP
    $manifest = Join-Path $repo 'rust/Cargo.toml'
    $cargoArgs = switch ($Action) {
        'Test' { @('test','--locked','--manifest-path',$manifest,'--features','test-hooks') }
        'Build' { @('build','--locked','--manifest-path',$manifest) }
        'Lint' { @('clippy','--locked','--manifest-path',$manifest,'--all-targets','--features','test-hooks') }
        'Format' { @('fmt','--manifest-path',$manifest,'--','--check') }
    }
    if ($Release -and $Action -ne 'Format') { $cargoArgs += '--release' }
    if ($Action -eq 'Lint') { $cargoArgs += @('--','-D','warnings') }
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo $Action failed with exit $LASTEXITCODE" }
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
