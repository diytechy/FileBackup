<#
.SYNOPSIS  WP13 / kit revision 10: the target-prompt decision core, the folder
           picker's fallbacks, the generated launchers, and the kit artifact
           list (SR-007, SR-016, SR-072, SR-073, SR-049).
.NOTES     TC-162, TC-163, TC-168, TC-171, TC-172, TC-173, TC-174.
           The picker's DIALOG is never shown here - and could not be. That is
           the point of the split: Test-ShouldPromptGraphically is pure, so its
           whole matrix is testable, and Select-FolderInteractively takes an
           injectable -Picker so every fallback is provable without a dialog.
           Run: Invoke-Pester -Path tests\Unit
#>

BeforeAll {
    $script:repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    Import-Module (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Force
    $script:reconstruct = Join-Path $repo 'Reconstruct.ps1'

    # Reconstruct.ps1 is a SCRIPT, not a module: dot-sourcing it would start a
    # restore. Lift the functions under test out of its AST instead.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($reconstruct, [ref]$null, [ref]$null)
    $allFunctions = $ast.FindAll({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    foreach ($name in 'Test-ShouldPromptGraphically', 'Select-FolderInteractively') {
        $fn = $allFunctions | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $fn) { throw "Reconstruct.ps1 no longer defines $name" }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

Describe 'Target-prompt decision core (SR-073, SR-016, TC-162)' {
    # The rule the whole feature rests on: a picker may only be offered where a
    # prompt was ALREADY reachable, so it can add no new way to block.
    It 'refuses to ask at all under -NonInteractive (SR-016)' {
        Test-ShouldPromptGraphically -NonInteractive $true -InputRedirected $false `
            -UserInteractive $true -NoGui $false -IsWindowsHost $true | Should -Be 'None'
    }
    It 'refuses to ask when stdin is redirected (SR-016)' {
        Test-ShouldPromptGraphically -NonInteractive $false -InputRedirected $true `
            -UserInteractive $true -NoGui $false -IsWindowsHost $true | Should -Be 'None'
    }
    It 'refuses to ask when there is NO console and NO desktop (SR-073)' {
        # The hole this closes had been shipping: a scheduled task set to run
        # whether or not a user is logged on passes neither -NonInteractive nor
        # a redirected stdin, so it reached Read-Host and waited forever. There
        # is nobody there to answer, so usage + exit 2 is the honest outcome.
        Test-ShouldPromptGraphically -NonInteractive $false -InputRedirected $false `
            -UserInteractive $false -NoGui $false -IsWindowsHost $true | Should -Be 'None'
    }
    It 'uses the typed prompt when -NoGui is asked for (SR-073)' {
        Test-ShouldPromptGraphically -NonInteractive $false -InputRedirected $false `
            -UserInteractive $true -NoGui $true -IsWindowsHost $true | Should -Be 'Text'
    }
    It 'offers the picker on a desktop session (SR-073)' {
        Test-ShouldPromptGraphically -NonInteractive $false -InputRedirected $false `
            -UserInteractive $true -NoGui $false -IsWindowsHost $true | Should -Be 'Gui'
    }
    It 'lets automation outrank a present desktop (SR-016)' {
        Test-ShouldPromptGraphically -NonInteractive $true -InputRedirected $false `
            -UserInteractive $true -NoGui $false -IsWindowsHost $true | Should -Be 'None'
    }
}

Describe 'Folder picker fallbacks (SR-073, TC-163)' {
    It 'returns the chosen folder' {
        Select-FolderInteractively -Picker { param($m) 'C:\chosen\dir' } | Should -Be 'C:\chosen\dir'
    }
    It 'trims a trailing separator, as osascript returns one' {
        Select-FolderInteractively -Picker { param($m) '/tmp/x/' } | Should -Be '/tmp/x'
    }
    It 'treats a cancel as no answer, never as a default target' {
        Select-FolderInteractively -Picker { param($m) $null } | Should -BeNullOrEmpty
    }
    It 'treats a blank answer as no answer' {
        Select-FolderInteractively -Picker { param($m) '   ' } | Should -BeNullOrEmpty
    }
    It 'never throws out of a broken toolkit - a missing dialog is not a failed restore' {
        { Select-FolderInteractively -Picker { param($m) throw 'no display' } } | Should -Not -Throw
        Select-FolderInteractively -Picker { param($m) throw 'no display' } | Should -BeNullOrEmpty
    }
}

Describe 'Kit revision marker (SR-049, TC-173)' {
    It 'is 10 in BOTH restorers, and they agree' {
        # Nothing pinned these before, which is exactly how they drifted to 8
        # and 6 while the project documented 9 - so every WP12 store reports the
        # kit it carries as 8.
        $ps1 = Select-String -Path (Join-Path $repo 'Reconstruct.ps1') -Pattern '^# KitRevision: (\d+)' |
               Select-Object -First 1
        $sh  = Select-String -Path (Join-Path $repo 'bash\reconstruct.sh') -Pattern '^# KitRevision: (\d+)' |
               Select-Object -First 1
        $ps1 | Should -Not -BeNullOrEmpty
        $sh  | Should -Not -BeNullOrEmpty
        $ps1.Matches[0].Groups[1].Value | Should -Be '10'
        $sh.Matches[0].Groups[1].Value  | Should -Be '10'
    }
}

Describe 'Generated launchers and the kit artifact list (SR-007, SR-072)' {
    BeforeAll {
        $script:root = Join-Path $TestDrive 'kit'
        $script:bkp  = Join-Path $root 'bkp'
        $script:chg  = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $bkp, $chg -Force | Out-Null
        New-ReconstructScript -BackupRoot $bkp -ChangeRoot $chg
    }

    It 'deposits all seven kit artifacts (SR-007, TC-171)' {
        foreach ($artifact in 'RECONSTRUCT.ps1', 'RECONSTRUCT.cmd', 'RECONSTRUCT.command',
                              'reconstruct.sh', 'FileBackup.Common.psm1', 'RECONSTRUCT.paths.json') {
            Test-Path -LiteralPath (Join-Path $bkp $artifact) -PathType Leaf |
                Should -BeTrue -Because "'$artifact' is part of the restore kit"
        }
    }

    It 'no longer writes RECONSTRUCT.bat' {
        Test-Path -LiteralPath (Join-Path $bkp 'RECONSTRUCT.bat') -PathType Leaf | Should -BeFalse
    }

    It 'generates a .cmd that is a PURE passthrough - no pause (SR-072, TC-168)' {
        # A pause in the launcher would also fire for a console-attached
        # automated caller passing no arguments, hanging it without ever
        # returning its exit code. The window-holding belongs in the restorer,
        # on the branch that has already proved a human is watching.
        $cmd = Get-Content -LiteralPath (Join-Path $bkp 'RECONSTRUCT.cmd') -Raw
        $cmd | Should -Match 'pwsh -NoProfile -ExecutionPolicy Bypass -File'
        $cmd | Should -Match '-ExitCode %\*'
        $cmd | Should -Not -Match '(?im)^\s*pause\s*$'
    }

    It 'writes the .cmd with CRLF, as cmd.exe expects' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $bkp 'RECONSTRUCT.cmd'))
        ([System.Text.Encoding]::ASCII.GetString($bytes)) | Should -Match "`r`n"
    }

    It 'copies a .command that delegates rather than duplicating the restore logic (SR-072)' {
        $c = Get-Content -LiteralPath (Join-Path $bkp 'RECONSTRUCT.command') -Raw
        # Finder starts a .command in $HOME, so it must find its own folder.
        $c | Should -Match 'dirname "\$\{BASH_SOURCE'
        $c | Should -Match 'cd "\$here"'
        $c | Should -Match 'reconstruct\.sh'
        # A double-click passes no arguments, and reconstruct.sh requires a target.
        $c | Should -Match '--pick-target'
    }

    It 'still treats a legacy RECONSTRUCT.bat as infrastructure (SR-022, TC-172)' {
        # A snapshot keeps the kit it was written with forever, so every
        # pre-revision-10 store still holds one. If the name stopped being
        # recognised, every run would report it as an orphan/not-in-DB row.
        $legacy = Join-Path $bkp 'RECONSTRUCT.bat'
        Set-Content -LiteralPath $legacy -Value '@echo off' -Encoding ASCII
        Test-IsInfrastructureFile -Root $bkp -FullPath $legacy | Should -BeTrue
    }

    It 'treats a NESTED file of the same name as user data (B6)' {
        $nested = Join-Path $bkp 'sub'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        $f = Join-Path $nested 'RECONSTRUCT.cmd'
        Set-Content -LiteralPath $f -Value 'x' -Encoding ASCII
        Test-IsInfrastructureFile -Root $bkp -FullPath $f | Should -BeFalse
    }
}

Describe 'A restored tree is ordinary writable files (SR-007, TC-174)' {
    It 'clears read-only on what it writes, so a protected store cannot pass its protection on' {
        # Copy-Item propagates the ReadOnly attribute, so without the clear a
        # write-protected pool object hands its read-only-ness to the restored
        # file. A snapshot keeps its kit forever, so this half has to ship
        # BEFORE any store is marked - a deployed kit cannot be fixed later.
        $src = Join-Path $TestDrive 'ro-src.bin'
        $dst = Join-Path $TestDrive 'ro-dst.bin'
        Set-Content -LiteralPath $src -Value 'protected content' -Encoding ASCII
        Set-ItemProperty -LiteralPath $src -Name IsReadOnly -Value $true

        Copy-Item -LiteralPath $src -Destination $dst -Force
        (Get-Item -LiteralPath $dst).IsReadOnly |
            Should -BeTrue -Because 'this is the propagation the restorer has to undo'

        # What Restore-OneRow now does at its single write choke point.
        $written = Get-Item -LiteralPath $dst -Force
        if ($written.IsReadOnly) { $written.IsReadOnly = $false }
        (Get-Item -LiteralPath $dst).IsReadOnly | Should -BeFalse

        Set-ItemProperty -LiteralPath $src -Name IsReadOnly -Value $false
    }
}
