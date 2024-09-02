﻿#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0
#Warning - This is the first functional powershell script I have attempted to create.  Suggestions appreciated
# but may not be understood.
#Assumptions:
    #Backup is performed daily and started at the same time.
    #Files to backup are in a subfolder (you could try to set a blank check label, but I am not testing for it)


#Configuration Parameters
#BkpVolLbl - The label of the volume / drive to backup to.
#SrcVolLbl - The label of the volume / drive to backup from.
#RepFldrLbl - The name of the folder where reports will be generated (and old file versions archived to if enabled)
#ChkFldrLbl - The folder / path in the source drive to actually backup (this script is not designed to backup root, for various reasons)
#BackupPrevAndRemovedFilesToRepFldr - Allows old file versions to be backed up before they are overwritten.
#SrcHashIfEqualPathAndModDateFreq - How often to perform a hash on all files in the source folder, for verifying content has truly remained constant..
#BkpHashIfEqualPathAndModDateFreq - How often to perform a hash on all files in backup  folder when all other attributes match, for verifying content has truly remained constant.
#Freq codes for above vars: "E" - Every time, "W" - Every week (Occurs on sunday), "M" - Every month (Occurs on first day), "Y" - Every year (Occurs on Jan, 1)
#Path Configurations:
PriVolLbl = "Library"
BkpVolLbl = "PriBackup"
BkpVolLbl2 = "LPBackup"

$BkpSets = @( @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "C:\SharedFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl;
RepFldrLbl = "Report";
ChkFldrLbl = "Shared";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
}, @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "C:\PrivateFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl;
RepFldrLbl = "Report";
ChkFldrLbl = "Private";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
}, @{
SrcVolLbl = $PriVolLbl;
SrcHshPth = "C:\NonDocsFilesHashTable.csv";
BkpVolLbl = $BkpVolLbl;
RepVolLbl = $BkpVolLbl2;
RepFldrLbl = "Report";
ChkFldrLbl = "NonDocs";
BackupPrevAndRemovedFilesToRepFldr = 1;
SrcHashIfEqualPathAndModDateFreq = "W";
BkpHashIfEqualPathAndModDateFreq = "M";
})
#

$BkpVolumeLabel = "SecondaryBackup"
$SrcVolumeLabel = "PrimaryBackup"
$ModFolderLabel = "Modified"
$ChkFolderLabel = "Shared\"

#Email server info
$EmailInfoPath   = "~\autocred.xml"
$SmtpServer      = "smtp.gmail.com"
$SmtpPort        = "587"


#This will do the following:

#1. Files that are in {BkpVolumeLabel}\{ChkFolderLabel} but not in {SrcVolumeLabel}\{ChkFolderLabel} 
# will be tagged as removed from source and will all be archieved into a 7z archive inside 
# {BkpVolumeLabel}\{ModFolderLabel} with the name of {yyyy-MM-dd-HH-mm-ss.7z}.  Files that were archived
# will then be deleted from the backup folder.  This is performed using a hash check, so modified files will
# also be tagged.

#2. Files that exist in {SrcVolumeLabel}\{ChkFolderLabel} but not {BkpVolumeLabel}\{ChkFolderLabel} (or are
# modified) will be copied from the source location to the backup location.

#Key Words
$PotLengthLimit = 254

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

#Before checking for copies, ect: set the parameters to send the email, as -if this does not load- the email cannot be sent and thus any caught error can't be emailed anyways.
$Secrets = Import-Clixml -Path $EmailInfoPath
$SendMsgProps = @{
    To = $Secrets.ToEmail
    From = $Secrets.FromEmail
    SmtpServer = $SmtpServer
    Port=$SmtpPort
    Credential = $Secrets.Credential
}
Try {
    $NBackupSets = $BkpSets.Count
    $TodayCode = $((Get-Date).ToString('yyyy-MM-dd-hh-mm-ss'))
    #First, validate the input configurations and get the corresponding properties.
    for ($i = 0; $i -lt $NBackupSets; $i++) {
        #Get all file paths to work with, and create label of delete archive if it needs to be created.
        $BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpDrives[$i].BkpVolLbl*"}).DriveLetter
        $SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like "*$BkpDrives[$i].SrcVolLbl*"}).DriveLetter
        if (($SrcDrives.Count -eq 1) -and ($SrcDrives.Count -eq 1))
        {
            $SrcDrive = $SrcDrives[0] + ":\"
            $BkpSets[$i].SrcPath = $SrcDrive + $BkpDrives[$i].ChkFldrLbl
            $BkpSets[$i].BkpPath = $BkpDrives[0] + ":\" + $BkpDrives[$i].ChkFldrLbl
            switch($BkpSets[$i].SrcHashIfEqualPathAndModDateFreq){
                "E" {$BkpSets[$i].CalcSrcHash = 1}
                "W" {
                    if ((Get-Date).DayOfWeek.value__ -eq 0){
                        $BkpSets[$i].CalcSrcHash = 1
                    }
                    else {$BkpSets[$i].CalcSrcHash = 0}}
                "M" {
                    if ((Get-Date).Day -eq 1){
                        $BkpSets[$i].CalcSrcHash = 1
                    }
                    else {$BkpSets[$i].CalcSrcHash = 0}}
                "Y" {
                    if (((Get-Date).Day -eq 1) -and ((Get-Date).Month -eq 1)){
                        $BkpSets[$i].CalcSrcHash = 1
                    }
                    else {$BkpSets[$i].CalcSrcHash = 0}}
                Default {throw "Invalid or undefined source hash configuration!"}
            }
            switch($BkpSets[$i].BkpHashIfEqualPathAndModDateFreq){
                "E" {$BkpSets[$i].CalcBkpHash = 1}
                "W" {
                    if ((Get-Date).DayOfWeek.value__ -eq 0){
                        $BkpSets[$i].CalcBkpHash = 1
                    }
                    else {$BkpSets[$i].CalcBkpHash = 0}}
                "M" {
                    if ((Get-Date).Day -eq 1){
                        $BkpSets[$i].CalcBkpHash = 1
                    }
                    else {$BkpSets[$i].CalcBkpHash = 0}}
                "Y" {
                    if (((Get-Date).Day -eq 1) -and ((Get-Date).Month -eq 1)){
                        $BkpSets[$i].CalcBkpHash = 1
                    }
                    else {$BkpSets[$i].CalcBkpHash = 0}}
                Default {throw "Invalid or undefined backup hash configuration!"}
            }

            if ($BkpSets[$i].RepFldrLbl.length -gt 0){
                $BkpSets[$i].EnableRprtGen = 1
                $RepPathRoot = $BkpDrives[$i] + ":\" + $BkpSets[$i].$RepFldrLbl
                $RepPathPre =  $RepPathRoot + "\" + $TodayCode
                $BkpSets[$i].RepPathRoot = $RepPathRoot
                #Create report paths
                $BkpSets[$i].ModReport = $RepPathPre + "-ModifiedOrDeletedFiles.txt"
                $BkpSets[$i].DelReport = $RepPathPre + "-RemovedFromBackupDueToDetectedMove.txt"
                $BkpSets[$i].CopyReport = $RepPathPre + "-CopiedToBackup.txt"
                $BkpSets[$i].LenReport = $SrcDrive + "ERROR" + " - " + $TodayCode + " - Length.txt"
                $BkpSets[$i].DupReport = $SrcDrive + $TodayCode + "-PotentialDuplicates.csv"
                if ($BkpSets[$i].BackupPrevAndRemovedFilesToRepFldr) {
                    $BkpSets[$i].ArchiveChangesInRep = 1
                    $BkpSets[$i].RepPathFldr = $RepPathPre + "\"
                    $BkpSets[$i].RepPath7Zip = $RepPathPre + ".7z"
                }
                else {
                    $BkpSets[$i].ArchiveChangesInRep = 0
                }
            }
            else {
                $BkpSets[$i].ArchiveChangesInRep = 0
                $BkpSets[$i].EnableRprtGen = 1
            }
        }
        else{
            throw "Dependent drive not found!"
        }
    }

    #Check for 7-zip, required to build out archives if intention appears to be to modify.
    $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

    if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
        throw "7 zip executable '$7zipPath' not found"
    }
    else {
        Set-Alias Start-SevenZip $7zipPath
    }
    
    for ($i = 0; $i -lt $NBackupSets; $i++) {
        $SrcPath       = $BkpSets[$i].SrcPath
        $BkpPath       = $BkpSets[$i].BkpPath
        $CalcSrcHash   = $BkpSets[$i].CalcSrcHash
        $CalcBkpHash   = $BkpSets[$i].CalcBkpHash
        $EnableRprtGen = $BkpSets[$i].EnableRprtGen
        #Create report paths
        $RepPathRoot   = $BkpSets[$i].RepPathRoot
        $ModReport     = $BkpSets[$i].ModReport 
        $DelReport     = $BkpSets[$i].DelReport 
        $CopyReport    = $BkpSets[$i].CopyReport
        $LenReport     = $BkpSets[$i].LenReport 
        $DupReport     = $BkpSets[$i].DupReport
        #Archive paths
        $ArchiveChangesInRep = $BkpSets[$i].ArchiveChangesInRep = 1
        $RepPathFldr         = $BkpSets[$i].RepPathFldr
        $RepPath7Zip         = $BkpSets[$i].RepPath7Zip

        #Build out grouping definition, note there are probably much more efficient ways to do this.
        $CurrInd  = [int[]]::new(1);
        $ExtLen   = [int[]]::new(1);

        $SrcLen   = $SrcPath.Length;
        $BkpLen   = $BkpPath.Length;
        $ModLen   = $RepPathFldr.Length;

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
        #Group all files by their size (since those might be duplicate):
        # 1. If enabled, set a flag for items from each group that appear to be equal based on their path and modification date.
        # 2. Then seperate out files from groups that aren't flagged and only exist in the source or only exist in the backup path,
        #    as those will require action to be taken.
        if ($SkipHashIfEqualPathAndModDate) {
            $AllFiles | Add-Member -MemberType NoteProperty -Name BkpFnd -Value $([int]0)
            $FilesGroupedSizeWise = $AllFiles | Group-Object -Property Length 
            foreach ($group in $FilesGroupedSizeWise) {
                #$files = ($group| Select-Object -Expand Group)
                foreach ($file in ($group| Select-Object -Expand Group)){
                    if ($file.LocKey -eq $SrcKey){
                        $ExtLen[0] = $file.FullName.Length - $SrcLen
                        $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
                        #Get 0 indexed result of file, to then compare modification date.
                        $CurrInd[0] = ($group| Select-Object -Expand Group).FullName.IndexOf($file.BkpPath)
                        #If we found a matching index, it exists, let's see if the modification dates are the same.
                        if($CurrInd[0] -ge 0){
                            #Do the modification dates match?  If so tag both the modified and backup file so we don't spend anymore time on it.
                            #Note this does create risk where a deleted file from the backup region is no longer able to be verified as a duplicate,
                            #and thus will be archived when it could have been deleted outright.
                            if ($file.LastWriteTime -eq ($group| Select-Object -Expand Group)[$CurrInd[0]].LastWriteTime){
                                $file.BkpFnd = 1
                                ($group| Select-Object -Expand Group)[$CurrInd[0]].BkpFnd = 1
                            }
                        }
                    }
                }
            }
            #Now rebuild, only keeping files that didn't have their backup found.
            $FilesGroupedSizeWise = (($FilesGroupedSizeWise| Select-Object -Expand Group) | Where-Object { $_.BkpFnd -ne 1}) | Group-Object -Property Length 
        }
        else {
            $FilesGroupedSizeWise = $AllFiles | Group-Object -Property Length 
        }

        #If any files remain, we need to decide what to  do with them.
        if ($FilesGroupedSizeWise.Count) {
            $FilesGroupedSizeWise | Add-Member -MemberType  NoteProperty -Name LocKey -Value $([int]0)
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
            #Now act on each group:
            # 1. If enabled, remove items from the group that appear to be equal based on their path and name
            # 2. Allocate each group to a seperate lists of items to be deleted from backup, to be copied from source
            #    or to be compared using their hash.
            #$Files2CmprCont = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group


            $UnhashedFiles2Send2Del = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object -Expand Group
            foreach ($file in $UnhashedFiles2Send2Del) {
                $ExtLen[0] = $file.FullName.Length - $BkpLen
                $file.RemPath = $RepPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetRemove
            }
            $UnhashedFiles2Copy2Bkp = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object -Expand Group
            foreach ($file in $UnhashedFiles2Copy2Bkp) {
                $ExtLen[0] = $file.FullName.Length - $SrcLen
                $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetBackup
            }
            $Files2CmprCont = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group
            $Files2Hash = $Files2CmprCont
            #Calculate the hash of files.
            $Asset = New-Object -TypeName PSObject
            $GroupID = @{Length=0; BkpPath=""; Hash="****************************************************************"}
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
                $file.RemPath = $RepPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
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
                    $file.RemPath = $RepPathFldr + $file.FullName.Substring($BkpLen,$ExtLen[0])
                }
                $file.GroupID = $file.BkpPath+"-S-"+$file.Length.tostring()+"-H-"+$file.Hash

            }
            $FilesGroupedByGroupID = $HashedFiles2Chk2Copy | Group-Object -Property GroupID
            $FilesNotBackedUp = $FilesGroupedByGroupID| Where-Object { $_.Count -ne 2 } | Select-Object -Expand Group
            $RenamedFiles2Copy2Bkp = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object
            $RenamedBFiles2PermDel = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object
            if( -Not (Test-Path -Path $RepPathRoot ) ) {
                New-Item -Path $RepPathRoot -ItemType "directory" | Out-Null
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
                New-Item -Path $RepPathFldr -ItemType "directory" | Out-Null
                foreach ($dir2make in $DeleteDirs2Set) {
                    if( -Not (Test-Path -Path $dir2make ) ) {
                        New-Item -Path $dir2make -ItemType "directory" | Out-Null
                    }
                }
                foreach ($file2move in $Files2Send2DelAndZip) {
                    Move-Item -Path $file2move.FullName -Destination $file2move.RemPath
                }
                #Now zip up folder, and delete.
                Start-SevenZip a -mx=9 -bso0 -bsp0 $RepPath7Zip $RepPathFldr
                Remove-Item -LiteralPath $RepPathFldr -Force -Recurse| Out-Null
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