#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

#Configuration Parameters
#This will significantly increase compare time by assuming files between the primary and secondary check 
#folders that have the same relative path, modification date, and size, are the exact same file, such that
#calculating and comparing the hash would not be required.  Turning this off will ensure any file modification is
#indeed backed up, but will significantly increase execution time of the backup script and result in more
#wear to platter disks.
$SkipHashChkForEqualPathAndModDate = 1

#Path Configurations:
$BkpVolumeLabel = "SecondaryBackup"
$SrcVolumeLabel = "PrimaryBackup"
$DelFolderLabel = "Modified"
$ChkFolderLabel = "Shared\"

#Email server info
$EmailInfoPath   = "~\autocred.xml"
$SmtpServer      = "smtp.gmail.com"
$SmtpPort        = "587"


#This will do the following:

#1. Files that are in {BkpVolumeLabel}\{ChkFolderLabel} but not in {SrcVolumeLabel}\{ChkFolderLabel} 
# will be tagged as removed from source and will all be archieved into a 7z archive inside 
# {SrcVolumeLabel}\{ChkFolderLabel} with the name of {yyyy-MM-dd-HH-MM-ss.7z}.  Files that were archived
# will then be deleted from the backup folder.  This is performed using a hash check, so modified files will
# also be tagged.

#2. Files that exist in {SrcVolumeLabel}\{ChkFolderLabel} but not {BkpVolumeLabel}\{ChkFolderLabel} (or are
# modified) will be copied from the source location to the backup location.

#Key Words
$PotLengthLimit = 256

$SrcKey = 0
$BkpKey = 1
$BthKey = 2

$DoNothing = 0
$SetBackup = 1
$SetRemove = 2

if (-not (Test-Path -Path $EmailInfoPath -PathType Leaf)) {
    throw "Email definition file '$EmailInfoPath' not found, modify and execute the PrepCredentialFile.ps1 to securly create with user specific attributes"
}

#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = 'Continue'

#Before try, set the parameters to send the email, as -if this does not load- the email cannot be sent and thus any caught error can't be emailed anyways.
$Secrets = Import-Clixml -Path $EmailInfoPath
$SendMsgProps = @{
    To = $Secrets.ToEmail
    From = $Secrets.FromEmail
    SmtpServer = $SmtpServer
    Port=$SmtpPort
    Credential = $Secrets.Credential
}
Try {
    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
        throw "7 zip executable '$7zipPath' not found"
    }

    Set-Alias Start-SevenZip $7zipPath

    $BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpVolumeLabel*"}).DriveLetter
    $SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$SrcVolumeLabel*"}).DriveLetter
    $SrcDrive = $SrcDrives[0] + ":\"
    $SrcPath = $SrcDrive + $ChkFolderLabel
    $BkpPath = $BkpDrives[0] + ":\" + $ChkFolderLabel
    $TodayCode = $((Get-Date).ToString('yyyy-MM-dd-hh-mm-ss'))
    $DelPathRoot = $BkpDrives[0] + ":\" + $DelFolderLabel
    $DelPathPre =  $DelPathRoot + "\" + $TodayCode
    $DelPathFldr = $DelPathPre + "\"
    $DelPath7Zip = $DelPathPre + ".7z"
    $ModReport = $DelPathPre + "-ModifiedOrDeletedFiles.txt"
    $DelReport = $DelPathPre + "-RemovedFromBackupDueToDetectedMove.txt"
    $CopyReport = $DelPathPre + "-CopiedToBackup.txt"
    $LenReport = $SrcDrive + "ERROR" + " - " + $TodayCode + " - Length.txt"
    $DupReport = $SrcDrive + $TodayCode + "-PotentialDuplicates.csv"
    
    #Build out grouping definition, note there are probably much more efficient ways to do this.
    $CurrInd  = [int[]]::new(1);
    $ExtLen   = [int[]]::new(1);

    $SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$SrcVolumeLabel*"}).DriveLetter
    $SrcPath = $SrcDrives[0] + ":\" + $ChkFolderLabel

    $SrcLen   = $SrcPath.Length;
    $BkpLen   = $BkpPath.Length;
    $ModLen   = $DelPathFldr.Length;

    $AllSrcFiles = @(Get-ChildItem -Path $SrcPath -Recurse -File)
    $AllSrcFldrs = @(Get-ChildItem -Path $SrcPath -Recurse -Directory | Select-Object -Property FullName)
    $AllSrcFiles = @($AllSrcFiles | Add-Member -MemberType NoteProperty -Name From -Value $SrcKey -PassThru)

    if (-not (Test-Path -Path $BkpPath -PathType Container)) {
        New-Item -Path $BkpPath -ItemType "directory" | Out-Null
    }
    $AllBkpFiles = @(Get-ChildItem -Path $BkpPath -Recurse -File)
    $AllBkpFldrs = @(Get-ChildItem -Path $BkpPath -Recurse -Directory | Select-Object -Property FullName)
    $AllBkpFiles = @($AllBkpFiles | Add-Member -MemberType NoteProperty -Name From -Value $BkpKey -PassThru)
    $AllFiles = $AllSrcFiles + $AllBkpFiles
    $AllFiles | Add-Member -MemberType NoteProperty -Name BkpPath -Value $([string]"")
    $AllFiles | Add-Member -MemberType NoteProperty -Name RemPath -Value $([string]"")
    $AllFiles | Add-Member -MemberType NoteProperty -Name DeterminedAction -Value $([int]0)
    $AllFiles | Add-Member -MemberType NoteProperty -Name FullPotLength -Value $([int]0)
    $AllFiles | Add-Member -MemberType NoteProperty -Name LocKey -Value $([int]0)
    $AllFiles | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
    if ($AllSrcFldrs.count){
        $AllFldrs = $AllFldrs + $AllSrcFldrs
    }
    if ($AllBkpFldrs.count){
        $AllFldrs = $AllFldrs + $AllBkpFldrs
    }
    $AllFldrs | Add-Member  -MemberType NoteProperty -Name RelPath -Value $([string]"")
    $AllFldrs | Add-Member -MemberType NoteProperty -Name LocKey -Value $([int]0)
    $AllFldrs | Add-Member -MemberType NoteProperty -Name RelLen -Value $([int]0)

    #************************ Pre ***************************
    #Check for file path length.
    $CurrInd  = [int[]]::new(1);
    $CurrInd[0] = 0
    foreach ($file in $AllFiles) {
        if($file.FullName.StartsWith($SrcPath)){
            $file.FullPotLength = $file.FullName.Length - $SrcLen + $ModLen
            $file.LocKey = $SrcKey
        } else {
            $file.FullPotLength = $file.FullName.Length - $BkpLen + $ModLen
            $file.LocKey = $BkpKey
        }
    }

    foreach ($SelFldr in $AllFldrs) {
        #Write-Host $selfldr.FullName
        #$SelFldr = $AllFldrs[$i]
        if($SelFldr.FullName.StartsWith($SrcPath)) {
            $ExtLen[0] = $SelFldr.FullName.Length - $SrcLen
            $SelFldr.LocKey = $SrcKey
            $SelFldr.RelPath = $SelFldr.FullName.Substring($SrcLen,$ExtLen[0])
            $SelFldr.RelLen = $ExtLen[0]
        }
        else {
            $ExtLen[0] = $SelFldr.FullName.Length - $BkpLen
            $SelFldr.LocKey = $BkpKey
            $SelFldr.RelPath = $SelFldr.FullName.Substring($BkpLen,$ExtLen[0])
            $SelFldr.RelLen = $ExtLen[0]
        }
    }
    #Produce directories to create and remove
    $GrpRelDir = @($AllFldrs | Group-Object  -Property RelPath | ?{ $_.Count -eq 1 } | Select-Object -Expand Group)
    $BackupDirs2Del = @($GrpRelDir | ?{ $_.LocKey -eq $BkpKey } | Sort-Object -Property RelLen)
    #$BackupDirs2Set = @($GrpRelDir | ?{ $_.LocKey -eq $SrcKey } | Sort-Object -Property RelLen -Descending)

    $FilesMayExceedLim = $group.Group | Group-Object  -Property From | ?{ $_.FullPotLength -gt $PotLengthLimit }
    if ($FilesMayExceedLim.Count){
        $FilesMayExceedLim.FullName | Out-File -Append $LenReport
    }
    
    #************************ 1 ***************************
    $FilesGroupedSizeWise = $AllFiles | Group-Object -Property Length 
    $FilesGroupedSizeWise | Add-Member -MemberType  NoteProperty -Name LocKey -Value $([int]0)
    #Build out grouping definition, note there are probably much more efficient ways to do this.
    foreach ($group in $FilesGroupedSizeWise) {
        $SrcSubGrp = $group.Group | Group-Object  -Property From | ?{ $_.Name -eq $SrcKey }
        $BkpSubGrp = $group.Group | Group-Object  -Property From | ?{ $_.Name -eq $BkpKey }
        if ($group.Count -eq $SrcSubGrp.Count){
            $group.LocKey = $SrcKey
        }
        elseif ($group.Count -eq $BkpSubGrp.Count){
            $group.LocKey = $BkpKey
        }
        else {
            $group.LocKey = $BthKey
        }
    }

    #************************ 2 ***************************
    #Now allocate each group to a seperate lists, to be grouped later, and hash those that need to be checked.
    $UnhashedFiles2Send2Del = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object -Expand Group
    foreach ($file in $UnhashedFiles2Send2Del) {
        $ExtLen[0] = $file.FullName.Length - $BkpLen
        $file.RemPath = $DelPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
        $file.DeterminedAction = $SetRemove
    }
    $UnhashedFiles2Copy2Bkp = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object -Expand Group
    foreach ($file in $UnhashedFiles2Copy2Bkp) {
        $ExtLen[0] = $file.FullName.Length - $SrcLen
        $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
        $file.DeterminedAction = $SetBackup
    }
    
    $Asset = New-Object -TypeName PSObject
    $GroupID = @{Length=0; BkpPath=""; Hash="****************************************************************"}

    $Files2Hash = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group
    $Files2Hash | Add-Member -MemberType NoteProperty -Name Hash -Value $([string]"****************************************************************")
    $Files2Hash | Add-Member -MemberType NoteProperty -Name GroupID -Value $([string]"")

    foreach ($prehashfile in $Files2Hash) {
        $hashset = Get-FileHash -Path $prehashfile.FullName
        $prehashfile.Hash = $hashset.Hash
    }

    $FilesGroupedByHash = $Files2Hash | Group-Object -Property Hash
    $FilesGroupedByHash | Add-Member -MemberType NoteProperty -Name LocKey -Value $([int]0)
    $FilesGroupedByHash | Add-Member -MemberType NoteProperty -Name DupKey -Value $([int]0)
    #Build out grouping definition, note there are probably much more efficient ways to do this.
    $DupInd  = [int[]]::new(1);
    foreach ($hashgrp in $FilesGroupedByHash) {
        $SrcSubGrp = $hashgrp.Group | Group-Object  -Property From | ?{ $_.Name -eq $SrcKey }
        $BkpSubGrp = $hashgrp.Group | Group-Object  -Property From | ?{ $_.Name -eq $BkpKey }
        if ($hashgrp.Count -eq $SrcSubGrp.Count){
            $hashgrp.LocKey = $SrcKey
        }
        elseif ($hashgrp.Count -eq $BkpSubGrp.Count){
            $hashgrp.LocKey = $BkpKey
        }
        else {
            $hashgrp.LocKey = $BthKey
        }
        if ($SrcSubGrp.Count -gt 1)
        {
            $DupInd[0] = $DupInd[0] + 1
            $hashgrp.DupKey = 1;
            foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
                if ($selfile.LocKey -eq $SrcKey) {
                    $selfile.DupGrp = $DupInd[0]
                }
            }
        }
    }
    $DupSet = ($FilesGroupedByHash| Select-Object -Expand Group) | Where-Object { $_.DupGrp -gt 0 }
    #$DupList = @{
    #    Group = $DupSet.DupGrp
    #    File  = $DupSet.FullName
    #}
    if ($DupSet.Count){
        $DupSet | Select-Object -Property DupGrp,FullName |
        Export-Csv -LiteralPath $DupReport -NoTypeInformation
        #$DupList| ConvertTo-Csv | Out-File -Append -FilePath $DupReport
    }
    
    #************************ 3 ***************************
    #Now allocate each group to a seperate lists, to be grouped later, and hash those that need to be checked.
    $HashedFiles2Send2Del = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object -Expand Group
    foreach ($file in $HashedFiles2Send2Del) {
        $ExtLen[0] = $file.FullName.Length - $BkpLen
        $file.RemPath = $DelPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
        $file.DeterminedAction = $SetRemove
    }
    $HashedFiles2Copy2Bkp = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object -Expand Group
    foreach ($file in $HashedFiles2Copy2Bkp) {
        $ExtLen[0] = $file.FullName.Length - $SrcLen
        $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
        $file.DeterminedAction = $SetBackup
    }
    $HashedFiles2Chk2Copy = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group

    foreach ($file in $HashedFiles2Chk2Copy) {
        #If the fiile is in the source path, calculate the equivalent backup path for that file.
        #Else, just set it to the full path.
        if($file.FullName.StartsWith($SrcPath)){
            $ExtLen[0] = $file.FullName.Length - $SrcLen
            $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
        } else {
            $ExtLen[0] = $file.FullName.Length - $BkpLen
            $file.BkpPath = $file.FullName
            $file.RemPath = $DelPathFldr + $file.FullName.Substring($BkpLen,$ExtLen[0])
        }
        $file.GroupID = $file.BkpPath+"-S-"+$file.Length.tostring()+"-H-"+$file.Hash

    }
    $FilesGroupedByGroupID = $HashedFiles2Chk2Copy | Group-Object -Property GroupID
    $FilesNotBackedUp = $FilesGroupedByGroupID| Where-Object { $_.Count -ne 2 } | Select-Object -Expand Group
    $RenamedFiles2Copy2Bkp = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object
    $RenamedBFiles2PermDel = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object
    if( -Not (Test-Path -Path $DelPathRoot ) ) {
        New-Item -Path $DelPathRoot -ItemType "directory" | Out-Null
    }


    #************************ 4 ***************************
    #Delete files from backup since they have been renamed, moved, or otherwise exist in the source.
    $Files2DelFromBackupWOZip = $RenamedBFiles2PermDel
    if ($Files2DelFromBackupWOZip.Count) {
        Remove-Item -Path $Files2DelFromBackupWOZip.FullName -Force
        $Files2DelFromBackupWOZip.FullName | Out-File -Append $DelReport
    }
    

    #************************ 5 ***************************
    #Move files that have been removed from source but still exist in the backup folder to thier designated delete location and zip.  Save report.
    if ($HashedFiles2Send2Del.Count)     {$Files2Send2DelAndZip = $Files2Send2DelAndZip + $HashedFiles2Send2Del}
    if ($UnhashedFiles2Send2Del.Count)   {$Files2Send2DelAndZip = $Files2Send2DelAndZip + $UnhashedFiles2Send2Del}
    if ($Files2Send2DelAndZip.Count) {
        $DeleteDirs2Set = (Split-Path $Files2Send2DelAndZip.RemPath -Parent) | Get-Unique | Sort-Object { $_.Length }
        New-Item -Path $DelPathFldr -ItemType "directory" | Out-Null
        foreach ($dir2make in $DeleteDirs2Set) {
            if( -Not (Test-Path -Path $dir2make ) ) {
                New-Item -Path $dir2make -ItemType "directory" | Out-Null
            }
        }
        foreach ($file2move in $Files2Send2DelAndZip) {
            Move-Item -Path $file2move.FullName -Destination $file2move.RemPath
        }
        #Now zip up folder, and delete.
        Start-SevenZip a -mx=9 -bso0 -bsp0 $DelPath7zip $DelPathFldr
        Remove-Item -LiteralPath $DelPathFldr -Force -Recurse| Out-Null
        $Files2Send2DelAndZip.FullName | Out-File -Append $ModReport
    }


    #************************ 6 ***************************
    #Copy corresonding files from source to backup.
    if ($RenamedFiles2Copy2Bkp.Count)  {$Files2Backup = $Files2Backup + $RenamedFiles2Copy2Bkp}
    if ($HashedFiles2Copy2Bkp.Count)   {$Files2Backup = $Files2Backup + $HashedFiles2Copy2Bkp}
    if ($UnhashedFiles2Copy2Bkp.Count) {$Files2Backup = $Files2Backup + $UnhashedFiles2Copy2Bkp}
    if ($Files2Backup.Count) {
        $BackupDirs2Set = (Split-Path $Files2Backup.BkpPath -Parent) | Get-Unique | Sort-Object { $_.Length }
        foreach ($dir2make in $BackupDirs2Set) {
            if( -Not (Test-Path -Path $dir2make ) ) {
                New-Item -Path $dir2make -ItemType "directory" | Out-Null
            }
        }
        foreach ($file2copy in $Files2Backup) {
            Copy-Item -Path $file2copy.FullName -Destination $file2copy.BkpPath | Out-Null
        }
        $Files2Backup.FullName | Out-File -Append $CopyReport
    }
    
    #************************ 7 ***************************
    #Delete remaining directories in backup that don't exist in source.
    if ($BackupDirs2Del.count) {
        foreach ($dir2remove in $BackupDirs2Del.FullName) {
            if((Test-Path -Path $dir2remove) ) {
                Remove-Item -LiteralPath $dir2remove  -Force -Recurse | Out-Null
            }
        }
    }

    
    #************************ 8 ***************************
    #Wrapup, set alert definitions.
    $SendMsgProps['Body'] = "All files updated"
    $SendMsgProps['Subject'] = "Automatic Backup Successful"

} Catch {
    $SendMsgProps['Body'] = $($error[0])
    $SendMsgProps['Subject'] = "Automatic Backup Failed"
    $Error[0]
}
#Send-MailMessage @SendMsgProps -UseSsl