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
