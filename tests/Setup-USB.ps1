<#
.SYNOPSIS
    Wipe a USB device, create four GPT partitions, format NTFS, and label them
    FBTEST-SRC / FBTEST-BKP / FBTEST-CHG / FBTEST-RCN for use by the RealUSB backend.

.PARAMETER DiskNumber
    Target disk number from Get-Disk. -1 (default) prompts interactively.

.PARAMETER Confirm
    Skip the typed 'WIPE' confirmation. DO NOT use casually.

.NOTES
    Requires Admin. Refuses to operate on a disk whose BusType != USB.
#>
[CmdletBinding()]
param(
    [int]$DiskNumber = -1,
    [int]$SrcSizeGB  = 2,
    [int]$BkpSizeGB  = 4,
    [int]$ChgSizeGB  = 4,
    [switch]$Confirm
)

$ErrorActionPreference = 'Stop'

# Require admin
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p  = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Setup-USB.ps1 must run as Administrator (Storage cmdlets require it)."
}

# Pick disk
if ($DiskNumber -lt 0) {
    Write-Host "USB disks detected:" -ForegroundColor Cyan
    Get-Disk | Where-Object BusType -eq 'USB' |
        Format-Table Number, FriendlyName, @{N='SizeGB';E={[math]::Round($_.Size/1GB,1)}}, OperationalStatus
    $DiskNumber = [int](Read-Host "USB disk number to wipe")
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
if ($disk.BusType -ne 'USB') {
    throw ("Disk {0} BusType={1} (expected USB). Refusing to wipe." -f $DiskNumber, $disk.BusType)
}

$totalRequiredGB = $SrcSizeGB + $BkpSizeGB + $ChgSizeGB + 1   # +1 for Recon minimum
if (($disk.Size/1GB) -lt $totalRequiredGB) {
    throw ("Disk too small. Has {0:N1} GB, need at least {1} GB." -f ($disk.Size/1GB), $totalRequiredGB)
}

if (-not $Confirm) {
    Write-Host ""
    Write-Host "About to WIPE disk $DiskNumber ($($disk.FriendlyName), $([math]::Round($disk.Size/1GB,1)) GB)" -ForegroundColor Red
    Write-Host "Partition plan:" -ForegroundColor Yellow
    Write-Host "  FBTEST-SRC : $SrcSizeGB GB"
    Write-Host "  FBTEST-BKP : $BkpSizeGB GB"
    Write-Host "  FBTEST-CHG : $ChgSizeGB GB"
    Write-Host "  FBTEST-RCN : remaining"
    Write-Host ""
    if ((Read-Host "Type 'WIPE' to proceed (anything else aborts)") -ne 'WIPE') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# Clean + GPT
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
Initialize-Disk -Number $DiskNumber -PartitionStyle GPT

$specs = @(
    @{ Label='FBTEST-SRC'; Size=$SrcSizeGB },
    @{ Label='FBTEST-BKP'; Size=$BkpSizeGB },
    @{ Label='FBTEST-CHG'; Size=$ChgSizeGB },
    @{ Label='FBTEST-RCN'; Size=0 }   # 0 => UseMaximumSize
)
foreach ($s in $specs) {
    $part = if ($s.Size -eq 0) {
        New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
    } else {
        New-Partition -DiskNumber $DiskNumber -Size ($s.Size * 1GB) -AssignDriveLetter
    }
    Format-Volume -DriveLetter $part.DriveLetter -FileSystem NTFS `
                  -NewFileSystemLabel $s.Label -Confirm:$false -Force | Out-Null
    Write-Host ("  {0}: -> {1} (NTFS, {2} GB)" -f $part.DriveLetter, $s.Label, $s.Size) -ForegroundColor Green
}

# Drop config file alongside
$cfg = Join-Path $PSScriptRoot 'Config\real-volumes.json'
if (-not (Test-Path -LiteralPath $cfg)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Config\real-volumes.json.example') -Destination $cfg
    Write-Host "Created $cfg (defaults match labels just written)." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "USB ready. Run RunAllTests.bat RealUSB to drive tests against it." -ForegroundColor Green
