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
    It 'is 12 in BOTH restorers, and they agree (TC-173)' {
        # Nothing pinned these before, which is exactly how they drifted to 8
        # and 6 while the project documented 9 - so every WP12 store reports the
        # kit it carries as 8.
        # 10 -> 11: WP17 Part A edits the kit-bundled FileBackup.Common.psm1
        # (the already-compressed extension list and its comment), and AGENTS.md
        # section 3 bumps the revision whenever a kit-bundled file changes
        # behaviour - Owner ruling Q1, 2026-08-31.
        # 11 -> 12 (2026-09-01): FILEBACKUP_7Z_LEVEL makes the 7-Zip level
        # operator-configurable in that same kit-bundled Common.psm1. Restorer
        # logic is unchanged, but the file is bundled, so the marker moves.
        # WP16 (PROPOSED) therefore takes 13 and merges TC-216 into this case.
        $ps1 = Select-String -Path (Join-Path $repo 'Reconstruct.ps1') -Pattern '^# KitRevision: (\d+)' |
               Select-Object -First 1
        $sh  = Select-String -Path (Join-Path $repo 'bash\reconstruct.sh') -Pattern '^# KitRevision: (\d+)' |
               Select-Object -First 1
        $ps1 | Should -Not -BeNullOrEmpty
        $sh  | Should -Not -BeNullOrEmpty
        $ps1.Matches[0].Groups[1].Value | Should -Be '12'
        $sh.Matches[0].Groups[1].Value  | Should -Be '12'
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
        # The list is SEVEN. An earlier version of this test named six and
        # silently omitted System.IO.Hashing.dll while claiming to prove the
        # whole kit - so removing the DLL deposition would not have failed it
        # (2026-08-28 independent review, T4).
        $expected = @('RECONSTRUCT.ps1', 'RECONSTRUCT.cmd', 'RECONSTRUCT.command',
                      'reconstruct.sh', 'FileBackup.Common.psm1',
                      'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')
        $expected.Count | Should -Be 7 -Because 'SR-007 names seven artifacts'
        foreach ($artifact in $expected) {
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
    It 'restores WRITABLE files from a READ-ONLY pool, through the real restorer' {
        # The previous version of this test performed the attribute clear ITSELF
        # and asserted the result - a demonstration of Copy-Item's behaviour, not
        # a test of Restore-OneRow. Deleting the production code would not have
        # failed it (2026-08-28 independent review, T4). This runs a real backup,
        # marks every pool object read-only - which is what WP14 will do - and
        # restores through the DEPLOYED kit.
        $root = Join-Path $TestDrive 'ro-real'
        $src  = Join-Path $root 'src'
        $bkp2 = Join-Path $root 'bkp'
        $chg2 = Join-Path $root 'chg'
        New-Item -ItemType Directory -Path $src, $bkp2, $chg2 -Force | Out-Null
        # A .jpg is on NonCompressibleExtensions, so it is stored RAW even with
        # compression on - and RAW is the Copy-Item path, the only one that
        # propagates the read-only attribute. Without a raw row this test passes
        # with the production clear deleted, because 7-Zip sets the extracted
        # file's own attributes and never inherits the pool object's.
        Set-Content -LiteralPath (Join-Path $src 'photo.jpg') -Value 'RAW-STORED-CONTENT' -NoNewline
        # Large and repetitive so Compress mode stores it as a .7z: the EXPAND
        # path has to clear the attribute too, and it does not go through
        # Copy-Item at all.
        Set-Content -LiteralPath (Join-Path $src 'big.txt') -Value ('COMPRESSIBLE-' * 3000) -NoNewline

        $cfg = Join-Path $root 'cfg.xml'
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $src; BackupPath = $bkp2; ChangePath = $chg2
            HashRecalcFreq = 'A'; CompressEnabled = $true
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $cfg
        & (Join-Path $repo 'FileBackup.ps1') -ConfigPath $cfg -NoMail -NonInteractive *>&1 | Out-Null

        $manifest = Join-Path $bkp2 'MANIFEST.csv'
        Test-Path -LiteralPath $manifest | Should -BeTrue -Because 'the backup must have run'
        $rows = @(Import-Csv -LiteralPath $manifest)
        @($rows | Where-Object Compressed -eq 'Yes').Count |
            Should -BeGreaterThan 0 -Because 'the archive path must be exercised'
        @($rows | Where-Object Compressed -eq 'No').Count |
            Should -BeGreaterThan 0 -Because 'the RAW copy path is the one that propagates read-only'

        # Write-protect every stored object - the WP14 end state.
        foreach ($row in $rows) {
            if ($row.DataPath) {
                $obj = Join-Path $bkp2 $row.DataPath
                if (Test-Path -LiteralPath $obj) { Set-ItemProperty -LiteralPath $obj -Name IsReadOnly -Value $true }
            }
        }
        @(Get-ChildItem -LiteralPath $bkp2 -File | Where-Object IsReadOnly).Count |
            Should -BeGreaterThan 0 -Because 'the pool really is protected now'

        $target = Join-Path $root 'restored'
        try {
            $out = & (Join-Path $bkp2 'RECONSTRUCT.ps1') -TargetRoot $target -ExitCode 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "a protected pool must still restore. Output: $out"

            foreach ($name in 'photo.jpg', 'big.txt') {
                $restored = Get-Item -LiteralPath (Join-Path $target $name) -Force
                $restored.IsReadOnly |
                    Should -BeFalse -Because "'$name' must come back as an ordinary writable file"
            }
            (Get-Content -LiteralPath (Join-Path $target 'photo.jpg') -Raw) | Should -Be 'RAW-STORED-CONTENT'
            (Get-Content -LiteralPath (Join-Path $target 'big.txt') -Raw)   | Should -Be ('COMPRESSIBLE-' * 3000)
        } finally {
            # Leave nothing read-only behind or TestDrive cleanup fails.
            Get-ChildItem -LiteralPath $bkp2 -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object IsReadOnly | ForEach-Object { $_.IsReadOnly = $false }
        }
    }
}

Describe 'The container image carries every kit template (SR-007, SR-072)' {
    It 'copies each template New-ReconstructScript REQUIRES, or the image fails every backup' {
        # New-ReconstructScript THROWS when a kit template is missing, so a file
        # left out of the image does not ship a smaller kit - it fails every
        # backup the container runs, which is the surface HomeHub consumes.
        # Adding bash/reconstruct.command did exactly that until the Dockerfile
        # was updated with it.
        $dockerfile = Get-Content -LiteralPath (Join-Path $repo 'Dockerfile') -Raw
        $engine     = Get-Content -LiteralPath (Join-Path $repo 'Modules\FileBackup.Engine.psm1') -Raw

        # Every 'bash/<name>' template the generator reaches for.
        $needed = [regex]::Matches($engine, "Join-Path 'bash' (?:'([^']+)'|\`$script:Def\.(\w+))") |
                  ForEach-Object {
                      if ($_.Groups[1].Success) { $_.Groups[1].Value }
                      else { (Get-FileBackupDefaults)."$($_.Groups[2].Value)" }
                  }
        $needed | Should -Not -BeNullOrEmpty -Because 'the generator copies at least reconstruct.sh'
        foreach ($template in $needed) {
            $dockerfile | Should -Match ([regex]::Escape("COPY bash/$template")) -Because "the image must carry '$template'"
        }
    }
}

Describe 'STA marshalling for the folder picker (SR-073, TC-183)' {
    It 'runs a scriptblock on an STA thread FROM AN MTA HOST, without killing the process' {
        # PowerShell 7.3+ is STA by default, so this path is unreachable in-
        # process here - it has to be driven from a genuinely MTA child. That is
        # why the broken version survived: every existing picker test injects a
        # -Picker and never reaches the marshalling at all.
        #
        # The original implementation used a raw System.Threading.Thread. A
        # PowerShell scriptblock there has no Runspace and throws an UNHANDLED
        # PSInvalidOperationException on a background thread, which TERMINATES
        # THE PROCESS - so this test asserts the exit code as well as the value.
        $probe = @'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$null, [ref]$null)
$fn  = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
       Where-Object { $_.Name -eq 'Invoke-OnStaThread' } | Select-Object -First 1
. ([scriptblock]::Create($fn.Extent.Text))
$host_state = [System.Threading.Thread]::CurrentThread.GetApartmentState().ToString()
$r = Invoke-OnStaThread -Script { param($t) [System.Threading.Thread]::CurrentThread.GetApartmentState().ToString() + '/' + $t } -Arguments @('ok')
Write-Output "$host_state|$r"
'@
        $probeFile = Join-Path $TestDrive 'sta-probe.ps1'
        Set-Content -LiteralPath $probeFile -Value $probe -Encoding UTF8

        $pwsh = (Get-Process -Id $PID).Path
        $out  = & $pwsh -MTA -NoProfile -NonInteractive -File $probeFile (Join-Path $repo 'Reconstruct.ps1') 2>&1
        $code = $LASTEXITCODE

        $code | Should -Be 0 -Because "a raw thread would take the process down. Output: $out"
        $line = @($out | Where-Object { "$_" -match '\|' }) | Select-Object -Last 1
        $line | Should -Not -BeNullOrEmpty -Because "the probe must have produced a result. Output: $out"
        $parts = "$line".Split('|')
        $parts[0] | Should -Be 'MTA' -Because 'the host really must be MTA or this proves nothing'
        $parts[1] | Should -Be 'STA/ok' -Because 'the scriptblock must run on STA and its value must cross back'
    }
}
