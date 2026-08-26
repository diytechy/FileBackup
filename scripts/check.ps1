<#
.SYNOPSIS
    FileBackup check harness — the single gate command (local + CI).

.DESCRIPTION
    Runs, and fails nonzero on any failure:
        1. PSScriptAnalyzer (tests/PSScriptAnalyzerSettings.psd1; any diagnostic = fail)
        2. python scripts/trace.py --strict        (0 traceability orphans; at
           -Gate G3/all also --require-verified: every Verification=Test SR is
           Status=Verified — the machine half of the G3 exit criteria)
        3. python scripts/check_docs.py            (doc navigability: 0 broken
           intra-repo links; generated composites ignored)
        4. scripts/gen_arch_map.ps1 -Check         (generated module map, flow,
           and dependency diagram not stale in architecture.md / AGENTS.md)
        5. Pester unit suite                        (tests/Unit)
        6. python scripts/check_perf.py            (-Gate G3/all: performance
           budgets vs docs/test/perf-metrics.json; inert while the PB registry
           holds only the placeholder — process.md SS9)
        7. Integration sweep via tests/Run-All.ps1  (Full/Release tiers only)

    Tiers (cumulative): Smoke = steps 1-6 (fast, every push); Full = + Subst
    integration sweep (PRs); Release = + the same sweep flagged for the slow/
    hardware runbook (the harness still drives the Subst sweep here; hardware
    VHDX/RealUSB are run out-of-band per AGENTS.md sec.6).

.PARAMETER Tier
    Smoke (default) | Full | Release.

.PARAMETER Gate
    G1 | G2 | G3 | all. Default: the first line of docs/gate (the kit's
    machine-readable active gate; falls back to 'all' if the file is absent).
    G3/all add the --require-verified status criterion to the traceability
    step; run -Gate G2 while a change is mid-decomposition (Draft SRs are
    expected then and must not fail the harness).

.PARAMETER Modes
    Integration compression combos (forwarded to Run-All.ps1). Default: both.

.NOTES
    Mirrors the kit's scripts/check.py contract (gate + exit code), wired to the
    PowerShell/Pester/Python stack.
#>
[CmdletBinding()]
param(
    [ValidateSet('Smoke','Full','Release')][string]$Tier = 'Smoke',
    [ValidateSet('','G1','G2','G3','all')][string]$Gate = '',
    [string]$Modes = 'Plain,Compress'
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$failures = New-Object System.Collections.Generic.List[string]

# Default gate: read docs/gate (one line, e.g. "G3") so local runs and CI
# enforce the same bar the project is actually at (process.md SS7).
if (-not $Gate) {
    $gateFile = Join-Path $repo 'docs\gate'
    $Gate = if (Test-Path -LiteralPath $gateFile) {
        (Get-Content -LiteralPath $gateFile -TotalCount 1).Trim()
    } else { 'all' }
    if ($Gate -notin 'G1','G2','G3','all') {
        throw "docs/gate contains '$Gate' - expected G1|G2|G3|all"
    }
}

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
    # Authoritative maintained lint surface (AGENTS.md sec.5). The legacy root
    # scripts and standalone Auxilary/DatabaseDuplicateDeletion utilities this
    # list once excluded were deleted 2026-07-03 (AGENTS.md sec.7).
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
    # Phase scope (process.md §4 "Phased delivery"): untagged SRs are always in
    # scope; SRs tagged with a not-yet-delivered phase (e.g. bash-v1) are
    # exempted EXPLICITLY and reported as phase-deferred. When a phase ships,
    # append it here (e.g. 'core,bash-v1') so its SRs must be Verified.
    # container-v1 shipped 2026-08-23: the first green container CI job on
    # resync_v2 (run 32673687758) is the promotion evidence — SR-034/044/048/
    # 052 flipped Verified and TC-060/079/080/088/101/102 flipped Pass in the
    # SAME commit that armed this ratchet.
    # ca-v1 shipped 2026-08-25 (WP9, content-addressed storage): SR-058..064
    # flipped Verified and TC-117..135 flipped Pass in the SAME commit that armed
    # it here and in .github/workflows/tests.yml. bash-v2 (SR-033) remains the one
    # phase-deferred row.
    if ($Gate -in 'G3','all') { $traceArgs += @('--require-verified', '--phase', 'core,bash-v1,container-v1,kitbump-v6,ca-v1') }
    python (Join-Path $repo 'scripts\trace.py') @traceArgs
}

# 3. Doc navigability (broken intra-repo links; generated composites ignored)
Invoke-Step 'Doc navigability (check_docs.py)' {
    python (Join-Path $repo 'scripts\check_docs.py') --root $repo `
        --ignore 'docs/test/report.md' --ignore 'docs/releases/*'
}

# 4. Generated-docs freshness (module map + flow + dependency diagram) -----
Invoke-Step 'Architecture map freshness' {
    pwsh -NoProfile -File (Join-Path $repo 'scripts\gen_arch_map.ps1') -Check
}

# 5. Unit tests -----------------------------------------------------------
Invoke-Step 'Pester unit' {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = (Join-Path $repo 'tests\Unit')
    $cfg.Run.Exit = $false
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Normal'
    $r = Invoke-Pester -Configuration $cfg
    if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) unit test(s) failed" }
}

# 6. Performance budgets (G3+: comparator over docs/test/perf-metrics.json;
#    inert while performance-budgets.csv holds only the PB-000 placeholder) --
if ($Gate -in 'G3','all') {
    Invoke-Step 'Performance budgets (check_perf.py)' {
        # check_perf's default artifact paths are cwd-relative (no --docs flag),
        # so run it from the repo root.
        Push-Location $repo
        try { python (Join-Path $repo 'scripts\check_perf.py') --tier ($Tier.ToLower()) }
        finally { Pop-Location }
    }
}

# 7. Integration sweep (Full / Release) ----------------------------------
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
