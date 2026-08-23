<#
.SYNOPSIS
    Master test driver. Sweeps storage modes & compression across each suite (G1-G8).

.PARAMETER Backend
    Subst | VHDX | RealUSB

.PARAMETER ResultRoot
    Where to write CSV/JUnit/HTML results.

.PARAMETER Groups
    Comma list of group IDs to run, e.g. "G1,G3". Default: all.

.PARAMETER Modes
    Comma list of "<Mode>+<Compress>" combos. Default: all four:
        Mirror, Mirror+Compress, HashAddressed, HashAddressed+Compress

.PARAMETER EmitJUnit
    Also write results.xml in JUnit format (for CI).

.PARAMETER NonInteractive
    No prompts; missing deps -> hard fail.
#>
[CmdletBinding()]
param(
    [ValidateSet('Subst','VHDX','RealUSB')][string]$Backend = 'Subst',
    [string]$ResultRoot = (Join-Path $env:TEMP "FileBackupTests"),
    [string]$Groups = 'G1,G2,G3,G4,G5,G6,G7,G8,G9',
    [string]$Modes  = 'Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress',
    [switch]$EmitJUnit,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$here = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$repo = [System.IO.Path]::GetDirectoryName($here)
$BackupScript = Join-Path $repo 'FileBackup.ps1'

if (-not (Test-Path -LiteralPath $BackupScript)) {
    throw "FileBackup.ps1 not found at $BackupScript"
}

# ---------- dot-source harness + backend + suites ----------
# Common is imported so suites that deliberately tamper with a MANIFEST.csv can
# re-stamp its witness (Write-ManifestWitness, SR-038) and keep exercising the
# failure they mean to, rather than tripping witness verification.
Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
. (Join-Path $here 'Common\Harness.ps1')
. (Join-Path $here 'Common\VolumeBackend.ps1')
foreach ($id in @('G1','G2','G3','G4','G5','G6','G7','G8','G9')) {
    $suiteFile = Get-ChildItem -LiteralPath (Join-Path $here 'Suites') -Filter "$id-*.ps1" |
                 Select-Object -First 1
    if ($suiteFile) { . $suiteFile.FullName }
}

# ---------- result root ----------
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$runRoot = Join-Path $ResultRoot "run_$stamp"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

# ---------- spin up backend ----------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "FileBackup test run - backend: $Backend"   -ForegroundColor Cyan
Write-Host "Result root: $runRoot"
Write-Host "=========================================" -ForegroundColor Cyan

$envRoot = Join-Path $runRoot 'env'
$Env = New-TestEnvironment -Backend $Backend -Root $envRoot

# ---------- decode modes ----------
$modeCombos = $Modes -split ',' | ForEach-Object {
    $parts = $_.Trim() -split '\+'
    [pscustomobject]@{
        Mode     = $parts[0]
        Compress = ($parts.Count -gt 1 -and $parts[1] -eq 'Compress')
    }
}

$wantedGroups = $Groups -split ',' | ForEach-Object { $_.Trim() }

try {
    foreach ($combo in $modeCombos) {
        Write-Host ""
        Write-Host "------ MODE: $($combo.Mode), Compress=$($combo.Compress) ------" -ForegroundColor Magenta
        foreach ($gid in $wantedGroups) {
            $fn = Get-Command -Name "Invoke-$gid" -ErrorAction SilentlyContinue
            if (-not $fn) {
                Write-Warning "Group function Invoke-$gid not found; skipping."
                continue
            }
            try {
                & $fn -Env $Env -BackupScript $BackupScript -Mode $combo.Mode -Compress $combo.Compress
            } catch {
                Add-TestResult $combo.Mode $gid '*' 'GroupCrashed' 'FAIL' $_.Exception.Message
            }
        }
    }
} finally {
    Remove-TestEnvironment -Env $Env
}

# ---------- write results ----------
$csvPath = Join-Path $runRoot 'results.csv'
$script:TestResults | Export-Csv -LiteralPath $csvPath -NoTypeInformation
Write-Host ""
Write-Host "CSV results: $csvPath" -ForegroundColor Cyan

if ($EmitJUnit) {
    $junitPath = Join-Path $runRoot 'results.xml'
    . (Join-Path $here 'Report-JUnit.ps1')
    Export-JUnitReport -Results $script:TestResults -Path $junitPath
    Write-Host "JUnit:        $junitPath" -ForegroundColor Cyan
}

# Always run summary
. (Join-Path $here 'Report.ps1')
Write-SummaryReport -Results $script:TestResults

$failed = @($script:TestResults | Where-Object Status -eq 'FAIL').Count
exit ($(if ($failed -gt 0) { 1 } else { 0 }))
