<#
.SYNOPSIS
    Backend abstraction: every backend returns a [pscustomobject] with the same shape:
        @{ SrcPath; BkpPath; ChgPath; ReconPath; Dispose=<scriptblock> }
    so the suites are backend-agnostic.

    Backends:
        Subst      - subst-mapped letters over %TEMP%; default; no admin.
        VHDX       - dynamic VHDX files mounted as letters; admin + Hyper-V module.
        RealUSB    - reads tests\Config\real-volumes.json; resolves by FileSystemLabel.
#>

function New-TestEnvironment {
    param(
        [ValidateSet('Subst','VHDX','RealUSB')][string]$Backend = 'Subst',
        [string]$Root = (Join-Path $env:TEMP "FileBackupTests_$((Get-Date).ToString('yyyyMMdd_HHmmss'))")
    )
    switch ($Backend) {
        'Subst'   { return New-SubstEnv   -Root $Root }
        'VHDX'    { return New-VhdxEnv    -Root $Root }
        'RealUSB' { return New-RealUsbEnv }
    }
}

# ---------- Subst backend ----------

function New-SubstEnv {
    param([string]$Root)

    # Pick four free drive letters (high letters first) instead of hardcoding
    # X/Y/Z/W, which can collide with real drives on a dev machine.
    $candidates = 'X','Y','W','V','U','T','S','R','Q','P','N','M','K','J','H','G','F','E'
    $free = @()
    foreach ($c in $candidates) {
        if (-not (Test-Path "${c}:\")) { $free += $c }
        if ($free.Count -eq 4) { break }
    }
    if ($free.Count -lt 4) {
        throw "Need 4 free drive letters for the Subst backend; found only $($free.Count) ($($free -join ',')). Free up some drive letters and retry."
    }
    $letters = @{ Src=$free[0]; Bkp=$free[1]; Chg=$free[2]; Recon=$free[3] }

    $phys = @{
        Src   = Join-Path $Root 'Source'
        Bkp   = Join-Path $Root 'Backup'
        Chg   = Join-Path $Root 'Changes'
        Recon = Join-Path $Root 'Recon'
    }
    foreach ($p in $phys.Values) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }

    cmd /c "subst $($letters.Src):   `"$($phys.Src)`""   | Out-Null
    cmd /c "subst $($letters.Bkp):   `"$($phys.Bkp)`""   | Out-Null
    cmd /c "subst $($letters.Chg):   `"$($phys.Chg)`""   | Out-Null
    cmd /c "subst $($letters.Recon): `"$($phys.Recon)`"" | Out-Null

    [pscustomobject]@{
        Backend   = 'Subst'
        Root      = $Root
        SrcPath   = "$($letters.Src):\"
        BkpPath   = "$($letters.Bkp):\"
        ChgPath   = "$($letters.Chg):\"
        ReconPath = "$($letters.Recon):\"
        PhysSrc   = $phys.Src
        PhysBkp   = $phys.Bkp
        PhysChg   = $phys.Chg
        PhysRecon = $phys.Recon
        UsedLetters = @($letters.Src, $letters.Bkp, $letters.Chg, $letters.Recon)
        Dispose   = {
            foreach ($l in @($letters.Src, $letters.Bkp, $letters.Chg, $letters.Recon)) {
                cmd /c "subst ${l}: /d" 2>&1 | Out-Null
            }
        }.GetNewClosure()
    }
}

# ---------- VHDX backend ----------

function New-VhdxEnv {
    param([string]$Root)
    if (-not (Get-Command New-VHD -ErrorAction SilentlyContinue)) {
        throw "Hyper-V PowerShell module not available; VHDX backend requires Win10/11 Pro+ with Hyper-V feature."
    }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    $vols = @(
        @{ Name='FBTEST-SRC'; SizeGB=2 },
        @{ Name='FBTEST-BKP'; SizeGB=4 },
        @{ Name='FBTEST-CHG'; SizeGB=4 },
        @{ Name='FBTEST-RCN'; SizeGB=4 }
    )
    $mounted = @()
    foreach ($v in $vols) {
        $path = Join-Path $Root "$($v.Name).vhdx"
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        New-VHD -Path $path -SizeBytes ($v.SizeGB * 1GB) -Dynamic | Out-Null
        $disk = Mount-VHD -Path $path -Passthru | Get-Disk
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT
        $p = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        Format-Volume -DriveLetter $p.DriveLetter -FileSystem NTFS `
                      -NewFileSystemLabel $v.Name -Confirm:$false -Force | Out-Null
        $mounted += [pscustomobject]@{ Path = $path; Letter = $p.DriveLetter; Label = $v.Name }
    }

    $byLabel = @{}
    foreach ($m in $mounted) { $byLabel[$m.Label] = $m }

    [pscustomobject]@{
        Backend   = 'VHDX'
        Root      = $Root
        SrcPath   = "$($byLabel['FBTEST-SRC'].Letter):\"
        BkpPath   = "$($byLabel['FBTEST-BKP'].Letter):\"
        ChgPath   = "$($byLabel['FBTEST-CHG'].Letter):\"
        ReconPath = "$($byLabel['FBTEST-RCN'].Letter):\"
        Mounted   = $mounted
        Dispose   = {
            param($self)
            foreach ($m in $self.Mounted) {
                try { Dismount-VHD -Path $m.Path -ErrorAction Stop } catch { Write-Verbose "Dismount-VHD failed for $($m.Path): $($_.Exception.Message)" }
            }
        }
    }
}

# ---------- Real USB backend ----------

function New-RealUsbEnv {
    $cfgPath = Join-Path $PSScriptRoot '..\Config\real-volumes.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        throw "RealUSB backend requires tests\Config\real-volumes.json. See tests\Config\real-volumes.json.example."
    }
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json

    function Resolve-Label([string]$label, [int]$minGB) {
        $vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq $label } | Select-Object -First 1
        if (-not $vol) { throw "Volume with label '$label' not found." }
        if ($vol.Size / 1GB -lt $minGB) { throw "Volume '$label' is below MinSizeGB=$minGB." }
        if ($label -notlike 'FBTEST-*')  { throw "Label '$label' does not match FBTEST-* convention; refusing to use for safety." }
        return "$($vol.DriveLetter):\"
    }

    $src = Resolve-Label $cfg.Source.Label  $cfg.Source.MinSizeGB
    $bkp = Resolve-Label $cfg.Backup.Label  $cfg.Backup.MinSizeGB
    $chg = Resolve-Label $cfg.Changes.Label $cfg.Changes.MinSizeGB
    $rcn = Resolve-Label $cfg.Recon.Label   $cfg.Recon.MinSizeGB

    # Wipe contents (but never reformat)
    foreach ($p in @($src,$bkp,$chg,$rcn)) {
        Get-ChildItem -LiteralPath $p -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    [pscustomobject]@{
        Backend   = 'RealUSB'
        SrcPath   = $src
        BkpPath   = $bkp
        ChgPath   = $chg
        ReconPath = $rcn
        Dispose   = { }
    }
}

function Remove-TestEnvironment {
    param([pscustomobject]$Env)
    if ($Env -and $Env.Dispose) {
        try { & $Env.Dispose $Env } catch { Write-Warning "Dispose failed: $_" }
    }
}

function Reset-TestEnvironment {
    <#
        Clears the four volumes between scenarios without re-mounting.
    #>
    param([pscustomobject]$Env)
    foreach ($p in @($Env.SrcPath, $Env.BkpPath, $Env.ChgPath, $Env.ReconPath)) {
        Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
