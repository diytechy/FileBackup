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
           loud refusal belongs to the backup entry point instead. They include
           CULTURE LOOKALIKES ('9' + U+200B, the Arabic-Indic U+0669): the first
           gate used -contains, which compares strings CULTURE-SENSITIVELY, so
           those passed it and the [int] cast then threw AT IMPORT - inside
           every restore kit, over a backup-only setting (2026-09-01 dual
           review, R-1).

           PROCESS SCOPE. The level is resolved once at Common's import, so it
           may only ever change across PROCESSES. Re-importing Common with
           -Force into a session that already holds FileBackup.Engine
           re-resolves it for that instance alone: Engine's nested Common keeps
           the OLD level while Get-FileBackupDefaults reports the new one.
           FileBackup.ps1's own import order is safe (Common once, before
           Engine, never re-imported mid-run) - and that scoping is why every
           level arm here runs in a CHILD pwsh.

           WINDOWS-ONLY. The fake 7z is a .cmd, so the Describe that needs it is
           skipped off Windows; Linux/container behavioural coverage of the knob
           is a recorded gap (TC-232).
           Run: Invoke-Pester -Path tests/Unit/SevenZipLevel.Tests.ps1
#>

BeforeAll {
    $script:repo  = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repo 'Modules' 'FileBackup.Common.psm1') -Force
    $script:entry    = Join-Path $repo 'FileBackup.ps1'
    $script:pwsh     = (Get-Process -Id $PID).Path
    $script:sevenZip = (Get-FileBackupDefaults).SevenZipDefaultPath

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

# The fake 7z is a cmd script, so this Describe needs cmd.exe (Windows).
Describe 'FILEBACKUP_7Z_LEVEL selects the -mx level (SR-004, LLR-004, TC-232)' -Skip:(-not $IsWindows) {
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
    It 'imports FileBackup.Common with <Label> and resolves the level to 9 (TC-232)' -ForEach @(
        @{ Label = "'10'"                           ; Value = '10' }
        @{ Label = "'-1'"                           ; Value = '-1' }
        @{ Label = "'fast'"                         ; Value = 'fast' }
        @{ Label = 'a whitespace-only string'       ; Value = '  ' }
        @{ Label = "'9' + U+200B (zero-width space)"; Value = ('9' + [char]0x200B) }
        @{ Label = 'U+0669 (Arabic-Indic nine)'     ; Value = ([string][char]0x0669) }
    ) {
        # The restore kit bundles this module. An import that threw over a
        # setting RESTORE never reads would turn a typo into an unrecoverable
        # backup, which is why the refusal lives in the backup entry point. The
        # last two arms are the culture lookalikes that PASSED the original
        # -contains gate and made the [int] cast throw right here (R-1).
        $level  = $Value
        $driver = Join-Path $TestDrive ('import-{0}.ps1' -f ([guid]::NewGuid()))
        # The child reports the rejected value BOTH raw and as code points: a
        # child process's stdout encoding would flatten U+200B or U+0669 to '?'
        # on the way back, and the code points are what the assertion can trust.
        [IO.File]::WriteAllText($driver, @'
param([string]$Repo)
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
$d   = Get-FileBackupDefaults
$inv = $d.SevenZipCompressionLevelInvalid
$cp  = if ($null -eq $inv) { '' } else { (([char[]]$inv | ForEach-Object { '{0:X4}' -f [int]$_ }) -join '-') }
"LEVEL=$($d.SevenZipCompressionLevel) INVALID=[$inv] CP=[$cp]"
'@)
        $out = Invoke-WithLevel -Level $level -Body {
            & $script:pwsh -NoProfile -File $driver -Repo $script:repo *>&1 | Out-String
        }
        $LASTEXITCODE | Should -Be 0 -Because 'the import must not throw'
        $out | Should -Match 'LEVEL=9'
        $points = (([char[]]$level | ForEach-Object { '{0:X4}' -f [int]$_ }) -join '-')
        $out | Should -Match ([regex]::Escape("CP=[$points]")) -Because 'the raw value must be recorded verbatim'
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

    It 'a RESTORE KIT layout still loads Common under <Label> (TC-232)' -ForEach @(
        @{ Label = "'9' + U+200B" ; Value = ('9' + [char]0x200B) }
        @{ Label = "'9' + U+FEFF" ; Value = ('9' + [char]0xFEFF) }
        @{ Label = "'9' + U+00AD" ; Value = ('9' + [char]0x00AD) }
        @{ Label = 'U+0669'       ; Value = ([string][char]0x0669) }
    ) {
        # Reconstruct.ps1 loads Common from its OWN folder
        # (Import-Module (Join-Path $here 'FileBackup.Common.psm1') -Force).
        # Before the fix these values died exactly there, so RECONSTRUCT.ps1
        # could not start at all over a variable only the BACKUP host reads.
        # This arm reproduces that load path from a kit-shaped folder.
        $kit = Join-Path $TestDrive ('kit-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $kit -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repo 'Modules' 'FileBackup.Common.psm1') -Destination $kit
        Copy-Item -LiteralPath (Join-Path $script:repo 'Reconstruct.ps1') -Destination $kit
        $driver = Join-Path $kit 'load.ps1'
        [IO.File]::WriteAllText($driver, @'
$commonModule = Join-Path $PSScriptRoot 'FileBackup.Common.psm1'
Import-Module $commonModule -Force
"LEVEL=$((Get-FileBackupDefaults).SevenZipCompressionLevel)"
'@)
        $out = Invoke-WithLevel -Level $Value -Body {
            & $script:pwsh -NoProfile -File $driver *>&1 | Out-String
        }
        $LASTEXITCODE | Should -Be 0 -Because 'a restore kit must load whatever the backup host had set'
        $out | Should -Match 'LEVEL=9'
    }
}

Describe 'A compression-enabled backup REFUSES an invalid level (SR-037, LLR-037, TC-232)' {
    It 'exits 2 naming the variable and the range, creating nothing, for <Label> (TC-232)' -ForEach @(
        @{ Label = "'10'"                           ; Value = '10' }
        @{ Label = "'-1'"                           ; Value = '-1' }
        @{ Label = "'fast'"                         ; Value = 'fast' }
        @{ Label = 'a whitespace-only string'       ; Value = '  ' }
        @{ Label = "'9' + U+200B (zero-width space)"; Value = ('9' + [char]0x200B) }
    ) {
        $level = $Value
        $p = New-BackupFixture -Root (Join-Path $TestDrive ('refuse-' + [guid]::NewGuid())) -Compress $true
        $r = Invoke-WithLevel -Level $level -Body { Invoke-EntryPoint -Cfg $p.Cfg }

        # 2 is the SR-042/SR-043 usage/precondition code the config refusals
        # already use - no new exit code was invented for this knob.
        $r.Code   | Should -Be 2
        $r.Output | Should -Match 'FILEBACKUP_7Z_LEVEL'
        $r.Output | Should -Match '0-9'
        # The rejected value is rendered DEFENSIVELY: printed raw, '9' + U+200B
        # reads as "'9' is not valid" and sends the operator hunting a phantom
        # (R-5). Everything outside printable ASCII becomes \uXXXX, and the
        # length is stated outright.
        $r.Output | Should -Match ([regex]::Escape("($($level.Length) characters)"))
        if ($level -cnotmatch '^[ -~]*$') {
            $r.Output | Should -Match '\\u200B' -Because 'an invisible character must be shown as an escape'
        }
        Test-Path -LiteralPath $p.Bkp | Should -BeFalse -Because 'the refusal is BEFORE any mutation'
        Test-Path -LiteralPath $p.Chg | Should -BeFalse
        Test-Path -LiteralPath $p.Log | Should -BeFalse -Because 'a refused run creates no log'
    }

    It 'leaves a PLAIN run (CompressEnabled=false) completely unaffected (TC-232)' {
        # The single Plain control arm: one invalid value is enough to show the
        # knob has no bearing on a run that never compresses.
        $p = New-BackupFixture -Root (Join-Path $TestDrive 'plain') -Compress $false
        $r = Invoke-WithLevel -Level 'fast' -Body { Invoke-EntryPoint -Cfg $p.Cfg }

        $r.Code   | Should -Be 0
        $r.Output | Should -Not -Match 'FILEBACKUP_7Z_LEVEL'
        Test-Path -LiteralPath (Join-Path $p.Bkp 'MANIFEST.csv') -PathType Leaf |
            Should -BeTrue -Because 'the level has no bearing on a run that never compresses'
    }
}

Describe 'Restore never depends on the level (SR-037, TC-232)' {
    It 'neither restorer makes a DIRECT reference to FILEBACKUP_7Z_LEVEL (TC-232)' {
        # A static claim, and deliberately no more: Reconstruct.ps1's host
        # self-test calls Compress-FileWithSevenZip, so its throwaway probe
        # archive DOES inherit whatever level Common resolved. What the scan
        # pins is that neither restorer reads POLICY from the variable;
        # correctness is level-independent, which the real-7-Zip round trip
        # below is what actually pins.
        foreach ($restorer in @((Join-Path $repo 'Reconstruct.ps1'),
                                (Join-Path $repo 'bash' 'reconstruct.sh'))) {
            $text = Get-Content -LiteralPath $restorer -Raw
            $text | Should -Not -Match 'FILEBACKUP_7Z_LEVEL' -Because "$restorer must never read the knob"
        }
    }
}

Describe 'Every level round-trips through the REAL 7-Zip (SR-004, LLR-004, TC-232)' {
    It 'compresses and expands byte-identically at level <_> (TC-232)' -ForEach @('0', '1') {
        # This arm is what earns the claim "any level's archive restores with
        # the same kit": every other arm only inspects an argument line.
        if (-not $script:sevenZip -or -not (Test-Path -LiteralPath $script:sevenZip -PathType Leaf)) {
            Set-ItResult -Skipped -Because '7-Zip is not available on this host'
        }
        $level = $_
        $work  = Join-Path $TestDrive ('real7z-' + $level)
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $source = Join-Path $work 'payload.txt'
        [IO.File]::WriteAllText($source, ('the quick brown fox jumps over the lazy dog ' * 460))  # ~20 KB
        $driver = Join-Path $work 'drive.ps1'
        [IO.File]::WriteAllText($driver, @'
param([string]$Repo, [string]$SevenZip, [string]$Source, [string]$Archive, [string]$Restored)
Import-Module (Join-Path $Repo 'Modules/FileBackup.Common.psm1') -Force
Compress-FileWithSevenZip -SevenZipPath $SevenZip -SourceFile $Source -Destination7z $Archive
Expand-FileWithSevenZip -SevenZipPath $SevenZip -Archive $Archive -DestinationFile $Restored
$len  = (Get-Item -LiteralPath $Source).Length
$hash = Get-FileXxHash -FilePath $Source
"LEVEL=$((Get-FileBackupDefaults).SevenZipCompressionLevel)"
"SRC=$((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash)"
"OUT=$((Get-FileHash -LiteralPath $Restored -Algorithm SHA256).Hash)"
"FORM=$(Get-StoredObjectForm -Path $Archive -ExpectedHash $hash -ExpectedLength $len)"
'@)
        $archive  = Join-Path $work 'out.7z'
        $restored = Join-Path $work 'back.txt'
        $out = Invoke-WithLevel -Level $level -Body {
            & $script:pwsh -NoProfile -File $driver -Repo $script:repo -SevenZip $script:sevenZip `
                -Source $source -Archive $archive -Restored $restored *>&1 | Out-String
        }
        $LASTEXITCODE | Should -Be 0 -Because "real 7-Zip must compress and expand at -mx=$level"
        $out | Should -Match "LEVEL=$level"

        $srcHash = ([regex]::Match($out, 'SRC=([0-9A-F]+)')).Groups[1].Value
        $outHash = ([regex]::Match($out, 'OUT=([0-9A-F]+)')).Groups[1].Value
        $srcHash | Should -Not -BeNullOrEmpty
        $outHash | Should -Be $srcHash -Because 'the restored bytes must be identical at any level'
        $out     | Should -Match 'FORM=Archive' -Because 'the kit must see a real archive, not raw bytes'

        # The 7-Zip signature, straight off the front of the stored object.
        $head = [byte[]]::new(6)
        $fs = [IO.File]::OpenRead($archive)
        try { $null = $fs.Read($head, 0, 6) } finally { $fs.Dispose() }
        (($head | ForEach-Object { $_.ToString('X2') }) -join '') |
            Should -Be '377ABCAF271C' -Because 'even -mx=0 (store mode) writes a real .7z container'
    }
}
