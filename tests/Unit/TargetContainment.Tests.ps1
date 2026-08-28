<#
.SYNOPSIS  SR-009: the restore target must be proven OUTSIDE the backup, and the
           proof must be physical rather than lexical (TC-181).
.NOTES     A junction is the case a lexical comparison gets wrong. GetFullPath
           normalises separators and '..' but never follows a reparse point, so
           a target named under an innocent-looking folder that RESOLVES into
           the backup compared as outside - and the restore then wrote into the
           backup it was protecting (2026-08-28 independent review, T1; recorded
           before that as D-7/F-3, the divergence from the bash twin, which has
           always resolved links through realpath).

           These tests create a REAL junction. New-Item -ItemType Junction needs
           no elevation; where it is unavailable the case skips loudly rather
           than passing vacuously.
           Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

    # Reconstruct.ps1 is a script, not a module: lift the two functions out of
    # its AST rather than dot-sourcing it, which would start a restore.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repo 'Reconstruct.ps1'), [ref]$null, [ref]$null)
    $all = $ast.FindAll({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($name in 'Resolve-PathPhysically', 'Test-PathIsInside') {
        $fn = $all | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $fn) { throw "Reconstruct.ps1 no longer defines $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

Describe 'Target containment is physical, not lexical (SR-009, TC-181)' {
    BeforeAll {
        $script:root    = Join-Path $TestDrive 'containment'
        $script:backup  = Join-Path $root 'backup'
        $script:outside = Join-Path $root 'outside'
        New-Item -ItemType Directory -Path $backup, $outside -Force | Out-Null
        $script:link = Join-Path $outside 'link'
        $script:haveJunction = $false
        try {
            New-Item -ItemType Junction -Path $link -Target $backup -ErrorAction Stop | Out-Null
            $script:haveJunction = $true
        } catch {
            $script:haveJunction = $false
        }
    }
    AfterAll {
        if ($script:haveJunction) {
            Remove-Item -LiteralPath $script:link -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    It 'REFUSES a target that reaches the backup root through a junction' {
        if (-not $haveJunction) { Set-ItResult -Skipped -Because 'junctions unavailable on this host'; return }
        # The attack: the path is NAMED outside the backup and LANDS inside it.
        Test-PathIsInside -Child (Join-Path $link 'restore') -Parent $backup |
            Should -BeTrue -Because 'the junction resolves into the backup, so restoring there would write into it'
    }

    It 'still allows a genuinely external target' {
        if (-not $haveJunction) { Set-ItResult -Skipped -Because 'junctions unavailable on this host'; return }
        Test-PathIsInside -Child (Join-Path $outside 'real') -Parent $backup | Should -BeFalse
    }

    It 'still treats a prefix-sharing sibling as outside' {
        # 'backup-restore' must not match 'backup' - the reason this compares
        # with a trailing separator instead of a plain StartsWith.
        Test-PathIsInside -Child ($backup + '-restore') -Parent $backup | Should -BeFalse
    }

    It 'still treats a nested target as inside' {
        Test-PathIsInside -Child (Join-Path $backup 'sub\deeper') -Parent $backup | Should -BeTrue
    }

    It 'still treats the root itself as inside' {
        Test-PathIsInside -Child $backup -Parent $backup | Should -BeTrue
    }

    It 'handles a target whose parent does not exist yet' {
        # The usual case: the guard runs BEFORE the target is created, so the
        # resolver has to work from the deepest EXISTING ancestor.
        Test-PathIsInside -Child (Join-Path $backup 'not\here\yet') -Parent $backup | Should -BeTrue
        Test-PathIsInside -Child (Join-Path $outside 'not\here\yet') -Parent $backup | Should -BeFalse
    }

    It 'resolves a junction that is itself the target' {
        if (-not $haveJunction) { Set-ItResult -Skipped -Because 'junctions unavailable on this host'; return }
        Test-PathIsInside -Child $link -Parent $backup |
            Should -BeTrue -Because 'the link IS the backup root once resolved'
    }

    It 'normalises separators and .. the way the lexical version did' {
        Test-PathIsInside -Child (Join-Path $backup 'a\..\b') -Parent $backup | Should -BeTrue
        Test-PathIsInside -Child (Join-Path $backup '..\elsewhere') -Parent $backup | Should -BeFalse
    }
}
