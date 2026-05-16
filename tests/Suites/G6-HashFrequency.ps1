<#
.SYNOPSIS  G6 - HashRecalcFreq matrix.
.NOTES
    Exercises Should-RecalculateHashes by dot-sourcing FileBackup.ps1 into a child scope
    and varying LastHashRun. NO backup runs here - pure unit checks.
#>
function Invoke-G6 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G6-HashFrequency'

    # Import the function via a transient module so we don't run the script body.
    $code = Get-Content -LiteralPath $BackupScript -Raw
    # Extract just Should-RecalculateHashes (start through 'endregion' after it).
    if ($code -notmatch '(?s)function Should-RecalculateHashes\s*\{.+?\n\}') {
        Add-TestResult $suite $group 'G6.0' 'ExtractFunction' 'SKIP' 'Should-RecalculateHashes not found'
        return
    }
    $fnText = $Matches[0]
    $mod = New-Module -Name FbBackupFreqTest -ScriptBlock ([scriptblock]::Create($fnText))
    Import-Module $mod -Force

    $now = Get-Date '2026-06-15T12:00:00'
    $cases = @(
        @{ Id='G6.A.same' ; Freq='A'; Last=$now.AddMinutes(-1); Expected=$true  },
        @{ Id='G6.D.same' ; Freq='D'; Last=$now.AddHours(-1);   Expected=$false },
        @{ Id='G6.D.next' ; Freq='D'; Last=$now.AddDays(-1);    Expected=$true  },
        @{ Id='G6.W.same' ; Freq='W'; Last=$now.AddHours(-1);   Expected=$false },
        @{ Id='G6.M.same' ; Freq='M'; Last=$now.AddDays(-5);    Expected=$false },
        @{ Id='G6.M.next' ; Freq='M'; Last=$now.AddMonths(-1);  Expected=$true  },
        @{ Id='G6.Y.next' ; Freq='Y'; Last=$now.AddYears(-1);   Expected=$true  },
        @{ Id='G6.N.never'; Freq='N'; Last=$now.AddYears(-10);  Expected=$false }
    )

    # Override Get-Date inside the module's scope so the function reads our fixed "now".
    foreach ($c in $cases) {
        # Build a wrapper that temporarily redefines Get-Date
        $script = {
            param($freq, $last, $fixedNow)
            function Get-Date { $fixedNow }
            Should-RecalculateHashes -FreqCode $freq -LastHashRun $last
        }
        $result = & $script $c.Freq $c.Last $now
        Assert-True $suite $group $c.Id ("Freq_{0}_Last_{1}" -f $c.Freq, $c.Last.ToString('yyyyMMdd')) {
            $result -eq $c.Expected
        }
    }

    Remove-Module FbBackupFreqTest -Force -ErrorAction SilentlyContinue
}
