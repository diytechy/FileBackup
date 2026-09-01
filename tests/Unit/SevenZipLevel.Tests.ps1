<#
.SYNOPSIS  FILEBACKUP_7Z_LEVEL: the operator-configurable 7-Zip effort level
           (SR-004, SR-037, LLR-004, LLR-037).
.NOTES     TC-232.

           HOW THE 7-ZIP INVOCATION IS CAPTURED. Compress-FileWithSevenZip
           takes the executable as a PARAMETER, so no seam is needed: the test
           passes a fake 7z .cmd that writes its own argument line to a file and
           exits 0. Every level arm runs in a CHILD pwsh, because the level is
           resolved once at FileBackup.Common's IMPORT - setting the variable in
           this already-imported session would prove nothing.

           The invalid arms exist to pin the split that keeps a RESTORE safe:
           the import may never throw (the restore kit bundles Common), so the
           loud refusal belongs to the backup entry point instead.
           Run: Invoke-Pester -Path tests\Unit\SevenZipLevel.Tests.ps1
#>

BeforeAll {
    $script:repo  = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules\FileBackup.Common.psm1') -Force
    $script:entry = Join-Path $repo 'FileBackup.ps1'
    $script:pwsh  = (Get-Process -Id $PID).Path

    function New-Fake7z {
        <#
        .SYNOPSIS
            A stand-in 7z that records its argument line and reports success.
        .OUTPUTS
            [hashtable] Exe (the .cmd to pass as -SevenZipPath) and ArgsFile.
        #>
        param([Parameter(Mandatory)][string]$Folder)
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        $argsFile = Join-Path $Folder 'args.txt'
        $exe      = Join-Path $Folder 'fake7z.cmd'
        # The space before '>' keeps cmd.exe from reading a trailing digit as a
        # redirection handle, whatever the argument line ends with.
        $lines = @('@echo off', ('echo %*  > "{0}"' -f $argsFile))
        [IO.File]::WriteAllText($exe, ($lines -join "`r`n") + "`r`n")
        return @{ Exe = $exe; ArgsFile = $argsFile }
    }

    function Get-SevenZipArgumentLine {
        <#
        .SYNOPSIS
            Runs Compress-FileWithSevenZip in a CHILD pwsh with
            FILEBACKUP_7Z_LEVEL set as given (-Level $null leaves it unset) and
            returns the argument line the fake 7z saw.
        #>
        param([AllowNull()][string]$Level, [Parameter(Mandatory)][string]$Folder)
        $fake   = New-Fake7z -Folder $Folder
        $source = Join-Path $Folder 'payload.txt'
        [IO.File]::WriteAllText($source, ('compressible ' * 100))
        $driver = Join-Path $Folder 'drive.ps1'
        [IO.File]::WriteAllText($driver, @'
param([string]$Repo, [string]$Fake, [string]$Source, [string]$Dest)
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
Compress-FileWithSevenZip -SevenZipPath $Fake -SourceFile $Source -Destination7z $Dest
'@)
        $previous = $env:FILEBACKUP_7Z_LEVEL
        try {
            if ([string]::IsNullOrEmpty($Level)) { Remove-Item Env:\FILEBACKUP_7Z_LEVEL -ErrorAction SilentlyContinue }
            else { $env:FILEBACKUP_7Z_LEVEL = $Level }
            & $script:pwsh -NoProfile -File $driver -Repo $script:repo -Fake $fake.Exe `
                -Source $source -Dest (Join-Path $Folder 'out.7z') *>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because 'the fake 7z reports success'
        } finally {
            if ([string]::IsNullOrEmpty($previous)) { Remove-Item Env:\FILEBACKUP_7Z_LEVEL -ErrorAction SilentlyContinue }
            else { $env:FILEBACKUP_7Z_LEVEL = $previous }
        }
        Test-Path -LiteralPath $fake.ArgsFile -PathType Leaf |
            Should -BeTrue -Because 'the fake 7z must actually have been invoked'
        return (Get-Content -LiteralPath $fake.ArgsFile -Raw)
    }

    function Invoke-WithLevel {
        <#
        .SYNOPSIS
            Runs a scriptblock with FILEBACKUP_7Z_LEVEL set to $Level, always
            restoring this session's own value afterwards.
        #>
        param([AllowNull()][string]$Level, [Parameter(Mandatory)][scriptblock]$Body)
        $previous = $env:FILEBACKUP_7Z_LEVEL
        try {
            # Windows cannot hold an EMPTY environment variable: assigning ''
            # deletes it, so empty and absent are the same case by construction.
            if ([string]::IsNullOrEmpty($Level)) { Remove-Item Env:\FILEBACKUP_7Z_LEVEL -ErrorAction SilentlyContinue }
            else { $env:FILEBACKUP_7Z_LEVEL = $Level }
            & $Body
        } finally {
            if ([string]::IsNullOrEmpty($previous)) { Remove-Item Env:\FILEBACKUP_7Z_LEVEL -ErrorAction SilentlyContinue }
            else { $env:FILEBACKUP_7Z_LEVEL = $previous }
        }
    }

    function New-LevelConfig {
        # The CLIXML form, as the other unit suites use: the loader accepts it
        # and no JSON schema surface is involved in this case at all.
        param([string]$Path, [string]$Src, [string]$Bkp, [string]$Chg, [bool]$Compress)
        $set = [pscustomobject]@{
            Name = 'S'; SourcePath = $Src; BackupPath = $Bkp; ChangePath = $Chg
            HashRecalcFreq = 'A'; CompressEnabled = $Compress
        }
        @{ Secrets = $null; BackupSets = @($set) } | Export-Clixml -LiteralPath $Path
    }

    function Invoke-EntryPoint {
        <#
        .SYNOPSIS
            The real entry point in a child process (so `exit` is observable),
            returning its status code and merged output.
        #>
        param([string]$Cfg)
        $out = & $script:pwsh -NoProfile -File $script:entry -ConfigPath $Cfg `
                    -NoMail -NonInteractive -ExitCode *>&1 | Out-String
        return @{ Code = $LASTEXITCODE; Output = $out }
    }

    function New-BackupFixture {
        # A source tree, and the paths a run would create but has not yet.
        param([string]$Root, [bool]$Compress)
        $src = Join-Path $Root 'src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'a.txt'), ('hello ' * 200))
        $paths = @{
            Src = $src
            Bkp = Join-Path $Root 'bkp'
            Chg = Join-Path $Root 'chg'
            Cfg = Join-Path $Root 'config.xml'
            Log = Join-Path $Root 'Backup_Global.log'
        }
        New-LevelConfig -Path $paths.Cfg -Src $src -Bkp $paths.Bkp -Chg $paths.Chg -Compress $Compress
        return $paths
    }
}

Describe 'FILEBACKUP_7Z_LEVEL selects the -mx level (SR-004, LLR-004, TC-232)' {
    It 'sends -mx=9 when the variable is not set - the default IS today (TC-232)' {
        $line = Get-SevenZipArgumentLine -Level $null -Folder (Join-Path $TestDrive 'absent')
        $line | Should -Match '(^|\s)-mx=9(\s|$)'
    }

    It 'sends -mx=1 for FILEBACKUP_7Z_LEVEL=1 (TC-232)' {
        $line = Get-SevenZipArgumentLine -Level '1' -Folder (Join-Path $TestDrive 'one')
        $line | Should -Match '(^|\s)-mx=1(\s|$)'
        $line | Should -Not -Match '-mx=9'
    }

    It 'accepts the boundary values 0 and 9 (TC-232)' {
        (Get-SevenZipArgumentLine -Level '0' -Folder (Join-Path $TestDrive 'zero')) |
            Should -Match '(^|\s)-mx=0(\s|$)'
        (Get-SevenZipArgumentLine -Level '9' -Folder (Join-Path $TestDrive 'nine')) |
            Should -Match '(^|\s)-mx=9(\s|$)'
    }

    It 'still passes the rest of the argument list unchanged (TC-232)' {
        $line = Get-SevenZipArgumentLine -Level '3' -Folder (Join-Path $TestDrive 'three')
        $line | Should -Match '^\s*a\s+-mx=3\s+-bso0\s+-bsp0\s+"'
    }
}

Describe 'An invalid FILEBACKUP_7Z_LEVEL never breaks an IMPORT (SR-037, LLR-037, TC-232)' {
    It 'imports FileBackup.Common with <_> and resolves the level to 9 (TC-232)' -ForEach @('10', '-1', 'fast', '  ') {
        # The restore kit bundles this module. An import that threw over a
        # setting RESTORE never reads would turn a typo into an unrecoverable
        # backup, which is why the refusal lives in the backup entry point.
        $level  = $_
        $driver = Join-Path $TestDrive ('import-{0}.ps1' -f ([guid]::NewGuid()))
        [IO.File]::WriteAllText($driver, @'
param([string]$Repo)
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
$d = Get-FileBackupDefaults
"LEVEL=$($d.SevenZipCompressionLevel) INVALID=[$($d.SevenZipCompressionLevelInvalid)]"
'@)
        $out = Invoke-WithLevel -Level $level -Body {
            & $script:pwsh -NoProfile -File $driver -Repo $script:repo *>&1 | Out-String
        }
        $LASTEXITCODE | Should -Be 0 -Because 'the import must not throw'
        $out | Should -Match 'LEVEL=9'
        $out | Should -Match ([regex]::Escape("INVALID=[$level]"))
    }

    It 'resolves an ABSENT/EMPTY variable to 9 with nothing rejected (TC-232)' {
        $driver = Join-Path $TestDrive 'import-empty.ps1'
        [IO.File]::WriteAllText($driver, @'
param([string]$Repo)
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
$d = Get-FileBackupDefaults
"LEVEL=$($d.SevenZipCompressionLevel) INVALID=[$($d.SevenZipCompressionLevelInvalid)]"
'@)
        $out = Invoke-WithLevel -Level '' -Body {
            & $script:pwsh -NoProfile -File $driver -Repo $script:repo *>&1 | Out-String
        }
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match 'LEVEL=9'
        $out | Should -Match ([regex]::Escape('INVALID=[]'))
    }
}

Describe 'A compression-enabled backup REFUSES an invalid level (SR-037, LLR-037, TC-232)' {
    It 'exits 2 naming the variable and the range, creating nothing, for <_> (TC-232)' -ForEach @('10', '-1', 'fast', '  ') {
        $level = $_
        $p = New-BackupFixture -Root (Join-Path $TestDrive ('refuse-' + [guid]::NewGuid())) -Compress $true
        $r = Invoke-WithLevel -Level $level -Body { Invoke-EntryPoint -Cfg $p.Cfg }

        # 2 is the SR-042/SR-043 usage/precondition code the config refusals
        # already use - no new exit code was invented for this knob.
        $r.Code   | Should -Be 2
        $r.Output | Should -Match 'FILEBACKUP_7Z_LEVEL'
        $r.Output | Should -Match '0-9'
        Test-Path -LiteralPath $p.Bkp | Should -BeFalse -Because 'the refusal is BEFORE any mutation'
        Test-Path -LiteralPath $p.Chg | Should -BeFalse
        Test-Path -LiteralPath $p.Log | Should -BeFalse -Because 'a refused run creates no log'
    }

    It 'leaves a PLAIN run (CompressEnabled=false) completely unaffected (TC-232)' {
        $p = New-BackupFixture -Root (Join-Path $TestDrive 'plain') -Compress $false
        $r = Invoke-WithLevel -Level 'fast' -Body { Invoke-EntryPoint -Cfg $p.Cfg }

        $r.Code   | Should -Be 0
        $r.Output | Should -Not -Match 'FILEBACKUP_7Z_LEVEL'
        Test-Path -LiteralPath (Join-Path $p.Bkp 'MANIFEST.csv') -PathType Leaf |
            Should -BeTrue -Because 'the level has no bearing on a run that never compresses'
    }
}

Describe 'Restore never depends on the level (SR-037, TC-232)' {
    It 'neither restorer mentions FILEBACKUP_7Z_LEVEL (TC-232)' {
        foreach ($restorer in 'Reconstruct.ps1', 'bash\reconstruct.sh') {
            $text = Get-Content -LiteralPath (Join-Path $repo $restorer) -Raw
            $text | Should -Not -Match 'FILEBACKUP_7Z_LEVEL' -Because "$restorer must never read the knob"
        }
    }
}
