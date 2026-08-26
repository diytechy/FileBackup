<#
.SYNOPSIS  G5 - Edge & failure paths.
#>
function Invoke-G5 {
    param([pscustomobject]$Env, [string]$BackupScript, [string]$Mode, [bool]$Compress)
    $suite = $Mode
    $group = 'G5-EdgeCases'
    $cfg = Join-Path $Env.Root 'cfg-g5.xml'
    Write-TestConfig $cfg $Env.SrcPath $Env.BkpPath $Env.ChgPath $Compress

    # G5.1 pre-existing Temp staging folder must abort
    Reset-TestEnvironment $Env
    New-Item -ItemType Directory -Path (Join-Path $Env.ChgPath 'Temp') -Force | Out-Null
    Assert-True $suite $group 'G5.1' 'PreexistingTemp_throws' {
        try {
            Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
            $log = Join-Path $Env.ChgPath 'backup.log'
            if (Test-Path -LiteralPath $log) {
                return [bool](Select-String -LiteralPath $log -Pattern 'staging folder' -Quiet)
            }
            return $false
        } catch { return $true }
    }

    # G5.4 read-only file in source
    Reset-TestEnvironment $Env
    $ro = Join-Path $Env.SrcPath 'readonly.txt'
    New-TestFile $ro 'locked'
    (Get-Item -LiteralPath $ro).IsReadOnly = $true
    Assert-True $suite $group 'G5.4' 'ReadOnlyFile_backedUp' {
        Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
        $row = Get-ManifestRow (Join-Path $Env.BkpPath 'MANIFEST.csv') 'readonly.txt'
        $null -ne $row
    }

    # G5.8 hidden & dot entries are captured and restored (SR-057, TC-113, D-4).
    # Until kit revision 6 no PowerShell-side enumeration used -Force: these
    # files were silently never backed up. Attributes are NOT preserved on
    # restore (the 9-column schema has nowhere to carry them) — the contract is
    # bytes-exact content at the right path.
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath '.dotfile') 'DOT-CONTENT'
    $dotDir = Join-Path $Env.SrcPath '.config\nested'
    New-Item -ItemType Directory -Path $dotDir -Force | Out-Null
    New-TestFile (Join-Path $dotDir 'deep.txt') 'DEEP-CONTENT'
    $hFile = Join-Path $Env.SrcPath 'hidden.txt'
    New-TestFile $hFile 'HIDDEN-CONTENT'
    (Get-Item -LiteralPath $hFile -Force).Attributes = ((Get-Item -LiteralPath $hFile -Force).Attributes -bor [IO.FileAttributes]::Hidden)
    $hDir = Join-Path $Env.SrcPath 'hiddendir'
    New-Item -ItemType Directory -Path $hDir -Force | Out-Null
    New-TestFile (Join-Path $hDir 'inside.txt') 'INSIDE-CONTENT'
    (Get-Item -LiteralPath $hDir -Force).Attributes = ((Get-Item -LiteralPath $hDir -Force).Attributes -bor [IO.FileAttributes]::Hidden)
    $sFile = Join-Path $Env.SrcPath 'system.txt'
    New-TestFile $sFile 'SYSTEM-CONTENT'
    (Get-Item -LiteralPath $sFile -Force).Attributes = ((Get-Item -LiteralPath $sFile -Force).Attributes -bor [IO.FileAttributes]::System)
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    $manifest = Join-Path $Env.BkpPath 'MANIFEST.csv'
    Assert-ManifestRow $suite $group 'G5.8' 'Dot_file_row' $manifest '.dotfile' $true
    Assert-ManifestRow $suite $group 'G5.8' 'Nested_dotdir_row' $manifest '.config\nested\deep.txt' $true
    Assert-ManifestRow $suite $group 'G5.8' 'Hidden_file_row' $manifest 'hidden.txt' $true
    Assert-ManifestRow $suite $group 'G5.8' 'Hidden_dir_row' $manifest 'hiddendir\inside.txt' $true
    Assert-ManifestRow $suite $group 'G5.8' 'System_file_row' $manifest 'system.txt' $true
    $g58t = Join-Path $Env.ReconPath 'g58-restore'
    Invoke-Reconstruct -ReconstructScript (Join-Path $Env.BkpPath 'RECONSTRUCT.ps1') -TargetRoot $g58t | Out-Null
    Assert-True $suite $group 'G5.8' 'Restore_all_hidden_dot_bytes' {
        $ok = $true
        foreach ($rel in '.dotfile', '.config\nested\deep.txt', 'hidden.txt', 'hiddendir\inside.txt', 'system.txt') {
            $restored = Join-Path $g58t $rel
            $original = Join-Path $Env.SrcPath $rel
            if (-not (Test-Path -LiteralPath $restored)) { $ok = $false; continue }
            if ((Get-Content -LiteralPath $restored -Raw) -ne (Get-Content -LiteralPath $original -Raw -Force)) { $ok = $false }
        }
        $ok
    }

    # G5.7 idempotency: second run with no source changes
    Reset-TestEnvironment $Env
    New-TestFile (Join-Path $Env.SrcPath 'stable.txt') 'unchanging'
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Invoke-Backup -BackupScriptPath $BackupScript -ConfigPath $cfg | Out-Null
    Assert-True $suite $group 'G5.7' 'Idempotent_secondRun' {
        # A no-op second run creates no snapshot now; the manifest row count must be stable.
        $rows = @(Import-Csv -LiteralPath (Join-Path $Env.BkpPath 'MANIFEST.csv'))
        $rows.Count -eq 1
    }
}
