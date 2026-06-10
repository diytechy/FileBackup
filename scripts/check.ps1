<#
.SYNOPSIS
    FileBackup check harness — the single gate command (local + CI).

.DESCRIPTION
    Runs, and fails nonzero on any failure:
        1. PSScriptAnalyzer (tests/PSScriptAnalyzerSettings.psd1; any diagnostic = fail)
        2. python scripts/trace.py --strict        (0 traceability orphans; at
           -Gate G3/all also --require-verified: every Verification=Test SR is
           Status=Verified — the machine half of the G3 exit criteria)
        3. scripts/gen_arch_map.ps1 -Check         (generated module map, flow,
           and dependency diagram not stale in architecture.md / AGENTS.md)
        4. Pester unit suite                        (tests/Unit)
        5. Integration sweep via tests/Run-All.ps1  (Full/Release tiers only)

    Tiers (cumulative): Smoke = steps 1-4 (fast, every push); Full = + Subst
    integration sweep (PRs); Release = + the same sweep flagged for the slow/
    hardware runbook (the harness still drives the Subst sweep here; hardware
    VHDX/RealUSB are run out-of-band per AGENTS.md sec.6).

.PARAMETER Tier
    Smoke (default) | Full | Release.

.PARAMETER Gate
    G2 | G3 | all (default). G3/all add the --require-verified status criterion
    to the traceability step; run -Gate G2 while a change is mid-decomposition
    (Draft SRs are expected then and must not fail the harness).

.PARAMETER Modes
    Integration storage-mode combos (forwarded to Run-All.ps1). Default: all four.

.NOTES
    Mirrors the kit's scripts/check.py contract (gate + exit code), wired to the
    PowerShell/Pester/Python stack.
#>
[CmdletBinding()]
param(
    [ValidateSet('Smoke','Full','Release')][string]$Tier = 'Smoke',
    [ValidateSet('G2','G3','all')][string]$Gate = 'all',
    [string]$Modes = 'Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress'
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    Write-Host ""
    Write-Host "==== $Name ====" -ForegroundColor Cyan
    try {
        & $Body
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] $Name -> $($_.Exception.Message)" -ForegroundColor Red
        $failures.Add($Name)
    }
}

# 1. Lint -----------------------------------------------------------------
Invoke-Step 'PSScriptAnalyzer' {
    $settings = Join-Path $repo 'tests\PSScriptAnalyzerSettings.psd1'
    # Authoritative maintained lint surface (AGENTS.md sec.5). Legacy root scripts
    # (Test-Backup.ps1, PrepPropertiesFile.ps1) and the standalone Auxilary/
    # DatabaseDuplicateDeletion utilities are intentionally excluded.
    $roots = @('FileBackup.ps1','Reconstruct.ps1','Modules','tests','scripts') |
        ForEach-Object { Join-Path $repo $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $targets = Get-ChildItem -Path $roots -Recurse -Include *.ps1,*.psm1
    $diags = $targets | ForEach-Object {
        Invoke-ScriptAnalyzer -Path $_.FullName -Settings $settings
    }
    if ($diags) {
        $diags | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
        throw "$($diags.Count) diagnostic(s)"
    }
}

# 2. Traceability ---------------------------------------------------------
Invoke-Step 'Traceability (trace.py --strict)' {
    $traceArgs = @('--strict', '--docs', (Join-Path $repo 'docs'))
    if ($Gate -in 'G3','all') { $traceArgs += '--require-verified' }
    python (Join-Path $repo 'scripts\trace.py') @traceArgs
}

# 3. Generated-docs freshness (module map + flow + dependency diagram) -----
Invoke-Step 'Architecture map freshness' {
    pwsh -NoProfile -File (Join-Path $repo 'scripts\gen_arch_map.ps1') -Check
}

# 4. Unit tests -----------------------------------------------------------
Invoke-Step 'Pester unit' {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = (Join-Path $repo 'tests\Unit')
    $cfg.Run.Exit = $false
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Normal'
    $r = Invoke-Pester -Configuration $cfg
    if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) unit test(s) failed" }
}

# 5. Integration sweep (Full / Release) ----------------------------------
if ($Tier -in 'Full','Release') {
    Invoke-Step "Integration sweep ($Tier)" {
        pwsh -NoProfile -File (Join-Path $repo 'tests\Run-All.ps1') `
            -Backend Subst -Modes $Modes -EmitJUnit -NonInteractive
    }
}

# Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "================ check.ps1 (tier $Tier, gate $Gate) ================" -ForegroundColor Cyan
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host "All steps passed." -ForegroundColor Green
exit 0
