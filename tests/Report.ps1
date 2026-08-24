<#
.SYNOPSIS  Console summary of test results.
#>
function Write-SummaryReport {
    param([System.Collections.IEnumerable]$Results)

    $byStatus = $Results | Group-Object Status
    $pass = ($byStatus | Where-Object Name -eq 'PASS' | Select-Object -ExpandProperty Count) -as [int]
    $fail = ($byStatus | Where-Object Name -eq 'FAIL' | Select-Object -ExpandProperty Count) -as [int]
    $skip = ($byStatus | Where-Object Name -eq 'SKIP' | Select-Object -ExpandProperty Count) -as [int]

    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ("  PASS: {0}" -f $pass) -ForegroundColor Green
    Write-Host ("  FAIL: {0}" -f $fail) -ForegroundColor ($(if ($fail) {'Red'} else {'Green'}))
    Write-Host ("  SKIP: {0}" -f $skip) -ForegroundColor Yellow

    if ($fail -gt 0) {
        Write-Host ""
        Write-Host "Failed tests:" -ForegroundColor Red
        $Results | Where-Object Status -eq 'FAIL' |
            Select-Object Suite, Group, ScenarioId, TestName, Detail |
            Format-Table -AutoSize
    }
}
