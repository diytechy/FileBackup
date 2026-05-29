<#
.SYNOPSIS  G6 - HashRecalcFreq matrix.
.NOTES
    Pure unit checks against Test-HashRecalcDue (exported by FileBackup.Engine.psm1).
    A fixed -Now is injected so the result is deterministic. NO backup runs here.
#>
function Invoke-G6 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode + ($(if ($Compress) {'+Compress'} else {''}))
    $group = 'G6-HashFrequency'

    $engine = Join-Path (Split-Path $BackupScript -Parent) 'Modules\FileBackup.Engine.psm1'
    if (-not (Test-Path -LiteralPath $engine)) {
        Add-TestResult $suite $group 'G6.0' 'EngineModule' 'SKIP' "Engine module not found at $engine"
        return
    }
    Import-Module $engine -Force

    if (-not (Get-Command Test-HashRecalcDue -ErrorAction SilentlyContinue)) {
        Add-TestResult $suite $group 'G6.0' 'FunctionPresent' 'SKIP' 'Test-HashRecalcDue not exported'
        return
    }

    $now = Get-Date '2026-06-15T12:00:00'
    $cases = @(
        @{ Id='G6.A.same'  ; Freq='A'; Last=$now.AddMinutes(-1); Expected=$true  },
        @{ Id='G6.E.same'  ; Freq='E'; Last=$now.AddMinutes(-1); Expected=$true  },
        @{ Id='G6.D.same'  ; Freq='D'; Last=$now.AddHours(-1);   Expected=$false },
        @{ Id='G6.D.next'  ; Freq='D'; Last=$now.AddDays(-1);    Expected=$true  },
        @{ Id='G6.W.same'  ; Freq='W'; Last=$now.AddHours(-1);   Expected=$false },
        @{ Id='G6.W.next'  ; Freq='W'; Last=$now.AddDays(-8);    Expected=$true  },
        @{ Id='G6.M.same'  ; Freq='M'; Last=$now.AddDays(-5);    Expected=$false },
        @{ Id='G6.M.next'  ; Freq='M'; Last=$now.AddMonths(-1);  Expected=$true  },
        @{ Id='G6.Y.next'  ; Freq='Y'; Last=$now.AddYears(-1);   Expected=$true  },
        @{ Id='G6.N.never' ; Freq='N'; Last=$now.AddYears(-10);  Expected=$false },
        @{ Id='G6.null'    ; Freq='W'; Last=$null;               Expected=$true  }
    )

    foreach ($c in $cases) {
        $result = if ($null -eq $c.Last) {
            Test-HashRecalcDue -FreqCode $c.Freq -Now $now
        } else {
            Test-HashRecalcDue -FreqCode $c.Freq -LastHashRun $c.Last -Now $now
        }
        $name = "Freq_{0}" -f $c.Freq
        if ([bool]$result -eq [bool]$c.Expected) {
            Add-TestResult $suite $group $c.Id $name 'PASS' ''
        } else {
            Add-TestResult $suite $group $c.Id $name 'FAIL' ("expected {0}, got {1}" -f $c.Expected, $result)
        }
    }
}
