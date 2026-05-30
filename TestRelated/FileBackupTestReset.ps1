<#
.SYNOPSIS
    LEGACY helper: reset a real-hardware test environment by wiping the labelled
    Library/Backup volumes and re-seeding the source from a content archive.

.DESCRIPTION
    Superseded by the tests/ harness (Reset-TestEnvironment + the Subst/VHDX/
    RealUSB backends), which isolate test volumes safely. Kept for reference only.
    Resolves drives by FileSystemLabel ($PriVolLbl/$BkpVolLbl/$BkpVolLbl2), DELETES
    their contents, then robocopy /MIR mirrors $TestSrcContentArchive onto the
    source. Edit the labels/path before use. Destructive — do not run blindly.
#>

#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0
#Modify this path with your path that contains anything you want to copy over as a start test environment.
$TestSrcContentArchive = "C:\TestSrcContent\"
#Modify drive labels below:
$PriVolLbl = "Library"
$BkpVolLbl = "PriBackup"
$BkpVolLbl2 = "LPBackup"

$BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpVolLbl*"}).DriveLetter
$BkpLetter = $BkpDrives[0] + ":\"
Remove-Item ($BkpLetter+"*") -Recurse

$BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpVolLbl2*"}).DriveLetter
$BkpLetter = $BkpDrives[0] + ":\"
Remove-Item ($BkpLetter+"*") -Recurse

$SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$PriVolLbl*"}).DriveLetter
$SrcLetter = $SrcDrives[0] + ":\"
Remove-Item ($SrcLetter+"*") -Recurse

robocopy   $TestSrcContentArchive $SrcLetter /MIR /R:0 /W:0 /NFL /NDL
