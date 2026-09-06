<#
.SYNOPSIS
    Re-probes real files at several window counts and scores each geometry
    against the realised 7-Zip outcome, for the experiment
    docs/defect-review-2026-09-02-probe-sample-representativeness.md section 7
    names as "cheap and decisive".

.DESCRIPTION
    MEASUREMENT ONLY. It imports the Engine module and calls the SHIPPED
    Measure-SampleCompressibility through InModuleScope with -Samples varied;
    it changes no constant, writes no object, and touches no backup store.
    -Samples already generalizes in the shipped function (the offsets are
    computed from $Samples), so this needs no code change to run.

    The review's open question is whether interior windows read like the
    observed middle window. Only real files can answer it, and the realised
    in/out sizes in section 1d are the ground truth to score against.

.PARAMETER InputCsv
    CSV with columns: Path (the source file) and RealisedRatio (stored bytes /
    source bytes, from the review's section 1d table). Rows whose Path does not
    exist are reported and skipped.

.PARAMETER Samples
    The window counts to try. Defaults to the review's 3, 8, 13, 24.

.PARAMETER Threshold
    The shipped aggregate gate: compress when ratio <= 1 - Threshold. Default
    0.10, matching $script:CompressProbeThreshold.

.OUTPUTS
    One CSV row per (file x window count) to -OutputCsv, and a scored summary
    to the host.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputCsv,
    [int[]]$Samples   = @(3, 8, 13, 24),
    [double]$Threshold = 0.10,
    [string]$OutputCsv = 'probe-window-experiment.csv'
)

$ErrorActionPreference = 'Stop'

$engine = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules/FileBackup.Engine.psm1'
if (-not (Test-Path -LiteralPath $engine)) { throw "Engine module not found at '$engine'." }
Import-Module $engine -Force

$rows = @(Import-Csv -LiteralPath $InputCsv)
if ($rows.Count -eq 0) { throw "No rows in '$InputCsv'." }

$results = [System.Collections.Generic.List[object]]::new()

foreach ($row in $rows) {
    $path = [string]$row.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Warning "Skipping missing file '$path'."
        continue
    }
    $len = (Get-Item -LiteralPath $path).Length
    # The realised ratio is the ground truth: 1.0 means 7-Zip saved nothing, so
    # the honest verdict for that file is RAW however good the sample looked.
    $realised   = if ([string]::IsNullOrWhiteSpace([string]$row.RealisedRatio)) { $null }
                  else { [double]$row.RealisedRatio }
    $shouldHave = if ($null -eq $realised) { $null }
                  else { $realised -le (1.0 - $Threshold) }

    foreach ($n in $Samples) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $probe = InModuleScope -ModuleName FileBackup.Engine -ArgumentList $path, $n {
            param($p, $n)
            Measure-SampleCompressibility -Path $p -Samples $n
        }
        $sw.Stop()

        if ($null -eq $probe) {
            Write-Warning "Probe returned null for '$path' at $n windows (locked, or it moved under the sample)."
            continue
        }
        $decision = $probe.Ratio -le (1.0 - $Threshold)
        $results.Add([pscustomobject]@{
            Path         = $path
            Length       = $len
            Windows      = $n
            Ratio        = [math]::Round($probe.Ratio, 4)
            WouldCompress = $decision
            RealisedRatio = $realised
            ShouldCompress = $shouldHave
            Correct      = if ($null -eq $shouldHave) { $null } else { $decision -eq $shouldHave }
            ProbeMs      = [int]$sw.ElapsedMilliseconds
            WindowVector = ($probe.Windows | ForEach-Object { [math]::Round($_, 3) }) -join ','
        })
    }
}

$results | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation
Write-Host "Wrote $($results.Count) rows to '$OutputCsv'." -ForegroundColor Green

Write-Host ''
Write-Host 'Scored by window count (files with a RealisedRatio only):'
$results | Where-Object { $null -ne $_.Correct } | Group-Object Windows | ForEach-Object {
    $correct = @($_.Group | Where-Object { $_.Correct }).Count
    $avgMs   = [int](($_.Group | Measure-Object ProbeMs -Average).Average)
    [pscustomobject]@{
        Windows   = [int]$_.Name
        Files     = $_.Count
        Correct   = $correct
        Wrong     = $_.Count - $correct
        AvgProbeMs = $avgMs
    }
} | Sort-Object Windows | Format-Table -AutoSize
