$BkpVolumeLabel = "SecondaryBackup"
$SrcVolumeLabel = "PrimaryBackup"
$TestSrcContentArchive = "C:\TestSrcContent\"

$BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpVolumeLabel*"}).DriveLetter
$BkpLetter = $BkpDrives[0] + ":\"
Remove-Item ($BkpLetter+"*") -Recurse
#Get-ChildItem -Path $BkpLetter -Include * | remove-Item -recurse -force

$SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$SrcVolumeLabel*"}).DriveLetter
$SrcLetter = $SrcDrives[0] + ":\"
Remove-Item ($SrcLetter+"*") -Recurse

#Get-ChildItem -Path $SrcLetter -Include * | remove-Item -recurse -force

robocopy   $TestSrcContentArchive $SrcLetter /MIR /R:0 /W:0 /NFL /NDL
