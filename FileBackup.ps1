#First clean out variables (for clean run)
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
#Note if the backup files are scheduled to hash, the source files will also be hashed ton ensure syncrony.
#Path Configurations:

#

#Email server info
$PropsInfoPath   = "~\FileBackupProps.xml"
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

$ProgressUpdateRate_ms = 2000


$CurrInnerProgDbl  = [double[]]::new(1);
$CurrBkpSetProgDbl = [double[]]::new(1);
$CurrOuterProgDbl  = [double[]]::new(1);
$CurrBkpSetOverDbl = [double[]]::new(1);
$PrevInnerProgPercInt = [int32[]]::new(1);
$CurrInnerProgPercInt = [int32[]]::new(1);
$CurrInd  = [double[]]::new(1);
$RemEnbl = 1
$ArchiveChangesFlag = 1
$DbgInd = 0
#Key Words
$PotLengthLimit = 254

$SrcKey = 0
$BkpKey = 1
$BthKey = 2

$DoNothing = 0
$SetBackup = 1
$SetRemove = 2

if (-not (Test-Path -LiteralPath $PropsInfoPath -PathType Leaf)) {
    throw "Email definition file '$EmailInfoPath' not found, modify and execute the PrepCredentialFile.ps1 to securly create with user specific attributes"
}



#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = 'Continue'

#Before checking for copies, ect: set the parameters to send the email, as -if this does not load- the email cannot be sent and thus any caught error can't be emailed anyways.
$ImportProps = Import-Clixml -LiteralPath $PropsInfoPath
$Secrets     = $ImportProps.Secrets
$BkpSets     = $ImportProps.BkpSets
$SendMsgProps = @{
    To = $Secrets.ToEmail
    From = $Secrets.FromEmail
    SmtpServer = $SmtpServer
    Port=$SmtpPort
    Credential = $Secrets.Credential
}
#Initialize progress bar properties
$OuterLoopProg = @{
	ID       = 0
	Activity = "Getting ready.  Please wait..."
	Status   = "Getting ready.  Please wait..."
	PercentComplete  = 0
	CurrentOperation = 0
}
$InnerLoopProg = @{
	ID       = 1
	Activity = "Getting ready.  Please wait..."
	Status   = "Getting ready.  Please wait..."
	PercentComplete  = 0
	CurrentOperation = 0
	ParentID = 0
}

Try {
    $NBackupSets = $BkpSets.Count
	Write-Host "Number of sets to extract:" $NBackupSets.ToString()
    $TodayCode = $((Get-Date).ToString('yyyy-MM-dd-hh-mm-ss'))
    #$ArchiveChangesFlag = 0 #Checked later, if this gets set further in the loop, we need to verify 7z is installed.
    #First, validate the input configurations and get the corresponding properties.
    for ($i = 0; $i -lt $NBackupSets; $i++) {
        #Get all file paths to work with, and create label of delete archive if it needs to be created.
        $BkpDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like ("*"+$BkpSets[$i].BkpVolLbl+"*")}).DriveLetter
        $SrcDrives = (Get-Volume | Where-Object {$_.FileSystemLabel -like ("*"+$BkpSets[$i].SrcVolLbl+"*")}).DriveLetter
        if (($SrcDrives.Count -eq 1) -and ($SrcDrives.Count -eq 1)) {
            $SrcDrive = $SrcDrives[0] + ":\"
            $BkpSets[$i].SrcPath = $SrcDrive + $BkpSets[$i].ChkFldrLbl
            $BkpSets[$i].BkpPath = $BkpDrives[0] + ":\" + $BkpSets[$i].ChkFldrLbl
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
            if ($BkpSets[$i].CalcBkpHash){
                $BkpSets[$i].CalcSrcHash = 1
            }

            if ($BkpSets[$i].RepFldrLbl.length -gt 0){
                $BkpSets[$i].EnableRprtGen = 1
                $RepPathRoot = $BkpDrives[0] + ":\" + $BkpSets[$i].RepFldrLbl + "\" + $BkpSets[$i].ChkFldrLbl
                $RepPathPre =  $RepPathRoot + "\" + $TodayCode
                $BkpSets[$i].RepPathRoot = $RepPathRoot
                #Create report paths
                $BkpSets[$i].ModReport = $RepPathPre + "-ModifiedOrDeletedFiles.txt"
                $BkpSets[$i].DelReport = $RepPathPre + "-RemovedFromBackupDueToDetectedMove.txt"
                $BkpSets[$i].CopyReport = $RepPathPre + "-CopiedToBackup.txt"
                $BkpSets[$i].LenReport = $RepPathPre + "ERROR" + " - " + $TodayCode + " - Length.txt"
                $BkpSets[$i].DupReport = $RepPathPre + "-PotentialDuplicates.csv"
                if ($BkpSets[$i].BackupPrevAndRemovedFilesToRepFldr) {
                    $ArchiveChanges = 1
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
    if($ArchiveChangesFlag) {
        $7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

        if (-not (Test-Path -LiteralPath $7zipPath -PathType Leaf)) {
            throw "7 zip executable '$7zipPath' not found"
        }
        else {
            Set-Alias Start-SevenZip $7zipPath
        }
    }
	
	if($DbgInd){
		$SrtGrp = $DbgInd - 1
		$EndGrp = $DbgInd
	}else{
		$SrtGrp = 0
		$EndGrp = $NBackupSets
	}
    
    for ($i = $SrtGrp; $i -lt $EndGrp; $i++) {
        $SrcPath       = $BkpSets[$i].SrcPath
        $BkpPath       = $BkpSets[$i].BkpPath
        $CalcSrcHash   = $BkpSets[$i].CalcSrcHash
        $CalcBkpHash   = $BkpSets[$i].CalcBkpHash
        $EnableRprtGen = $BkpSets[$i].EnableRprtGen
        $HashTblPath   = $BkpSets[$i].SrcHshPth
        $RebuildSrcHashTblFlag   = $BkpSets[$i].CalcSrcHash
        $RebuildBkpHashTblFlag   = $BkpSets[$i].CalcSrcHash
        #Create report paths
        $RepPathRoot   = $BkpSets[$i].RepPathRoot
        $ModReport     = $BkpSets[$i].ModReport 
        $DelReport     = $BkpSets[$i].DelReport 
        $CopyReport    = $BkpSets[$i].CopyReport
        $LenReport     = $BkpSets[$i].LenReport 
        $DupReport     = $BkpSets[$i].DupReport
        #Archive paths
        $ArchiveChangesInRep = $BkpSets[$i].ArchiveChangesInRep
        $RepPathFldr         = $BkpSets[$i].RepPathFldr
        $RepPath7Zip         = $BkpSets[$i].RepPath7Zip
        #Load up the source hash table if it exists and the flag to rehash the entire source isn't set.


        #Build out grouping definition, note there are probably much more efficient ways to do this.
        $CurrInd  = [int[]]::new(1);
        $ExtLen   = [int[]]::new(1);

        $SrcLen   = $SrcPath.Length;
        $BkpLen   = $BkpPath.Length;
        $ModLen   = $RepPathFldr.Length;
		#Attribute updates for outer loop and resetting inner loop definitions.
		$CurrInnerProgDbl[0]  = 0;
		$CurrBkpSetOverDbl = $i;
        $TmpNum = $i+1;
#.ToString()
		$OuterLoopProg.Activity = "Set " + $TmpNum.ToString() + " of " + $NBackupSets.ToString() + " :Backing up " + $SrcPath + " to " + $BkpPath
		$OuterLoopProg.Status   = "Force source hashing: " + $RebuildSrcHashTblFlag.ToString() +", Force backup hashing: " +$RebuildBkpHashTblFlag.ToString()
		#General update fields.
		$CurrBkpSetProgDbl[0] = 0;
		$OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		$OuterLoopProg.PercentComplete  = $OuterProgPerc;
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @OuterLoopProg;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		Write-Progress @InnerLoopProg

		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Activity = "Getting folder / file properties"
		$InnerLoopProg.Status = "Getting source files..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		#$InnerLoopProg.CurrentOperation = "Current Step: " $InnerLoopProg.PercentComplete.ToString() "% Complete"
		Write-Progress @InnerLoopProg
		#*************************************************
        $AllSrcFiles = @(Get-ChildItem -LiteralPath $SrcPath -Recurse -File)
        $SrcFilesizeTtl = $AllSrcFiles | Measure-Object -Property Length -Sum; $SrcFilesizeTtl =$SrcFilesizeTtl.Sum
		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = $SrcFilesizeTtl.Count.ToString() + " source files found.  Getting source folders..."
		$CurrInnerProgDbl[0] = 0.25;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		#$InnerLoopProg.CurrentOperation = "Current Step: " $InnerLoopProg.PercentComplete.ToString() "% Complete"
		Write-Progress @InnerLoopProg
		#*************************************************
        $AllSrcFldrs = @(Get-ChildItem -LiteralPath $SrcPath -Recurse -Directory | Select-Object -Property FullName)
        $AllSrcFiles = @($AllSrcFiles | Add-Member -MemberType NoteProperty -Name From -Value $SrcKey -PassThru)

        if ((Test-Path -LiteralPath $HashTblPath -PathType Leaf) -and ($RebuildSrcHashTblFlag -eq 0)) {
			#**************UPDATING INNER LOOP****************
			$InnerLoopProg.Status = "Loading previously saved hash definition for source files..."
			Write-Progress @InnerLoopProg
			#*************************************************
            $AllOldSrcProps = Import-Csv -LiteralPath $HashTblPath
        }
        elseif ($AllOldSrcProps) {
            Remove-Variable AllOldSrcProps
        }

		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = $AllSrcFldrs.Count.ToString() + "Source folders found.  Getting backup files..."
		$CurrInnerProgDbl[0] = 0.5;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		Write-Progress @InnerLoopProg
		#*************************************************
        if( -Not (Test-Path -LiteralPath $BkpPath ) ) {
            New-Item -Path $BkpPath -ItemType "directory" | Out-Null
            $BkpFilesizeTtl = 0;
        }
        else {
            $BkpFilesizeTtl = $AllBkpFiles | Measure-Object -Property Length -Sum ; $BkpFilesizeTtl =$BkpFilesizeTtl.Sum
        }
        $AllBkpFiles = @(Get-ChildItem -LiteralPath $BkpPath -Recurse -File)
		#Write-Host $AllBkpFiles.length.ToString() " backup files to check"
		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = $AllBkpFiles.Count.ToString() + "Backup files found.  Getting backup folders..."
		$CurrInnerProgDbl[0] = 0.75;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		Write-Progress @InnerLoopProg
		#*************************************************
        $AllBkpFldrs = @(Get-ChildItem -LiteralPath $BkpPath -Recurse -Directory | Select-Object -Property FullName)
        $AllBkpFiles = @($AllBkpFiles | Add-Member -MemberType NoteProperty -Name From -Value $BkpKey -PassThru)

		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = $AllBkpFldrs.Count.ToString() + "Bbckup folders found.  Allocating properties to determine..."
		$CurrInnerProgDbl[0] = 0.99;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		Write-Progress @InnerLoopProg
		#*************************************************
        if ($AllFiles){Remove-Variable AllFiles}
        $AllFiles = $AllSrcFiles + $AllBkpFiles
        $AllFiles | Add-Member -MemberType NoteProperty -Name BkpPath -Value $([string]"")
        $AllFiles | Add-Member -MemberType NoteProperty -Name RemPath -Value $([string]"")
        $AllFiles | Add-Member -MemberType NoteProperty -Name DeterminedAction -Value $([int]0)
        $AllFiles | Add-Member -MemberType NoteProperty -Name FullPotLength -Value $([int]0)
        $AllFiles | Add-Member -MemberType NoteProperty -Name LocKey -Value $([int]0)
        $AllFiles | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
        $AllFiles | Add-Member -MemberType NoteProperty -Name Hash -Value $([string]"****************************************************************")
        
        if ($AllFldrs){Remove-Variable AllFldrs}
        if ($AllSrcFldrs.count){
            $AllFldrs = $AllFldrs + $AllSrcFldrs
        }
        if ($AllBkpFldrs.count){
            $AllFldrs = $AllFldrs + $AllBkpFldrs
        }
        $AllFldrs | Add-Member  -MemberType NoteProperty -Name RelPath -Value $([string]"")
        $AllFldrs | Add-Member -MemberType NoteProperty -Name LocKey -Value $([int]0)
        $AllFldrs | Add-Member -MemberType NoteProperty -Name RelLen -Value $([int]0)

        #************************ Pre - A ***************************
        #Check for file path length, and get the hash of the source files (either by matching properties to a previously hashed file or by rehashing)
        $CurrInd  = [int[]]::new(1); $CurrInd[0] = 0
        $MatchedHash  = [int[]]::new(1); $MatchedHash[0] = 0
		#**************UPDATING BOTH LOOPS****************
		$CurrBkpSetProgDbl[0] = 0.05;
		$OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		$OuterLoopProg.PercentComplete  = $OuterProgPerc;
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @OuterLoopProg;
		$InnerLoopProg.Activity = "Verifying which files need to be backed up..."
		$InnerLoopProg.Status = "Getting hash information for source files and backup properties..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
		#*************************************************
		#Prep to measure progress

        $AllFilesizeTtl = $AllFiles | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum
        $LoopProg = 0;
        $PrevInnerProgPercInt[0] = 0;
        foreach ($file in $AllFiles) {
            if($file.FullName.StartsWith($SrcPath)){
                $file.FullPotLength = $file.FullName.Length - $SrcLen + $ModLen
                $file.LocKey = $SrcKey
                #If we're not rebuilding the hash, recalculate
                if(-not($RebuildSrcHashTblFlag) -and $AllOldSrcProps){
                    $MatchingFile = @($AllOldSrcProps | ?{( $_.FullName -eq $file.FullName) -and ( $_.Length -eq $file.Length) -and ($_.LastWriteTime -eq $file.LastWriteTime.ToString())})
                    if($MatchingFile.Count -eq 1){
                        $file.Hash = $MatchingFile.Hash
                        $MatchedHash[0] = $MatchedHash[0] +1
                    }
                    else {
                        $hashset = Get-FileHash -LiteralPath $file.FullName
                        $file.Hash = $hashset.Hash
                    }
                }
                #Else if the hash must be rebuilt, do it now.
                else {
                    $hashset = Get-FileHash -LiteralPath $file.FullName
                    $file.Hash = $hashset.Hash
                }
            } else {
                $file.FullPotLength = $file.FullName.Length - $BkpLen + $ModLen
                $file.LocKey = $BkpKey
            }
            $LoopProg += $file.Length
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
				$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
            }
        }
		#**************UPDATING BOTH LOOPS****************
		$CurrBkpSetProgDbl[0] = 0.1;
		$OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		$OuterLoopProg.PercentComplete  = $OuterProgPerc;
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @OuterLoopProg;
		$InnerLoopProg.Status = "Saving source hash information for future runs..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
		#*************************************************

        #Export all source files for future import / compoarison.
        $SrcFilesWithHash = $AllFiles | Where-Object {( $_.LocKey -eq $SrcKey)} 
        $SrcFilesWithHash | Select-Object -Property Fullname, Length, LastWriteTime, Hash|
        Export-Csv -Path $HashTblPath -NoTypeInformation

        

        #************************ Pre - B ***************************
        #Prepare folder related attributes.
		#**************UPDATING BOTH LOOPS****************
		$CurrBkpSetProgDbl[0] = 0.15;
		$OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		$OuterLoopProg.PercentComplete  = $OuterProgPerc;
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @OuterLoopProg;
		$InnerLoopProg.Status = "Determining folders to create..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
		#*************************************************
        $LoopProg = 0
        $PrevInnerProgPercInt[0]  = 0;
        foreach ($SelFldr in $AllFldrs) {
            #Write-Host $selfldr.FullName0
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
            $LoopProg += 1
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/($AllFldrs.Count)
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
				$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
            }
        }
        #Return;
        #************************ Pre - C ***************************
		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = "Checking file names..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
        #***********************************************
        #Produce directories to create and remove
        $GrpRelDir = @($AllFldrs | Group-Object  -Property RelPath | ?{ $_.Count -eq 1 } | Select-Object -Expand Group)
        $BackupDirs2Del = @($GrpRelDir | ?{ $_.LocKey -eq $BkpKey } | Sort-Object -Property RelLen)

        $FilesMayExceedLim = $group.Group | Group-Object  -Property From | ?{ $_.FullPotLength -gt $PotLengthLimit }
        if ($FilesMayExceedLim.Count){
            $FilesMayExceedLim.FullName | Out-File -Append $LenReport
        }
        if( -Not (Test-Path -LiteralPath $RepPathRoot ) ) {
            New-Item -Path $RepPathRoot -ItemType "directory" | Out-Null
        }

        
        #************************ Pre - D ***************************
		#**************UPDATING INNER LOOP****************
		$InnerLoopProg.Status = "Determining duplicate files by content (hash)..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
        #***********************************************
        #Get duplicate group index to report duplicates
        $DupInd  = [int[]]::new(1); $DupInd[0] = 0
        $SrcFilesGroupedByHash = $SrcFilesWithHash | Group-Object -Property Hash
        $SrcFilesGroupedByHash | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
        foreach ($hashgrp in $SrcFilesGroupedByHash) {

            if ($hashgrp.Count -gt 1)
            {
                $DupInd[0] = $DupInd[0] + 1
                foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
                    $selfile.DupGrp = $DupInd[0]
                }
            }
        }
            

        #************************ Pre - E ***************************
        #Identify duplicates and produce report if enabled.
        $DupSet = ($SrcFilesGroupedByHash | Select-Object -Expand Group) | Where-Object { $_.DupGrp -gt 0 }
        if ($DupSet.Count -and $EnableRprtGen){
            $DupSet | Select-Object -Property DupGrp,FullName |
            Export-Csv -LiteralPath $DupReport -NoTypeInformation
        }

    
        #************************ 1 ***************************
        #Group all files by their size (since those might be duplicate):
        # 1. If enabled, set a flag for items from each group that appear to be equal based on their path and modification date.
        # 2. Then seperate out files from groups that aren't flagged and only exist in the source or only exist in the backup path,
        #    as those will require action to be taken.
		#**************UPDATING BOTH LOOPS****************
		$CurrBkpSetProgDbl[0] = 0.20;
		$OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		$OuterLoopProg.PercentComplete  = $OuterProgPerc;
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @OuterLoopProg;
		$InnerLoopProg.Status = "Determining which files require backup..."
		$CurrInnerProgDbl[0] = 0;
		$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		$OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		Write-Progress @InnerLoopProg
		#*************************************************
        $SkipHashIfEqualPathAndModDate = -not($RebuildBkpHashTblFlag)
        if ($SkipHashIfEqualPathAndModDate) {
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #**************UPDATING BOTH LOOPS****************
		    $InnerLoopProg.Status = "Determining if backup files exist according to path and modification date..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @InnerLoopProg
		    #*************************************************
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
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($FilesGroupedSizeWise.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
            #Now rebuild, only keeping files that didn't have their backup found.
            $FilesGroupedSizeWise = @((($FilesGroupedSizeWise| Select-Object -Expand Group) | Where-Object { $_.BkpFnd -ne 1}) | Group-Object -Property Length )
        }
        else {
            $FilesGroupedSizeWise = @($AllFiles | Group-Object -Property Length) 
        }
        
        #************************ 2 ***************************
        #If any files remain, we need to decide what to  do with them.
        if ($FilesGroupedSizeWise.Count) {
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.25;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Finding similarly sizes files to compare content..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************

		    #*************************************************
            $FilesGroupedSizeWise | Add-Member -MemberType  NoteProperty -Name LocKey -Value $([int]0)
            #************************ 2A ***************************
            #If any files have the same size in both the source and backup, they need to be tagged as existing in both, since we need more information about them before deciding what to do.
            #Files that are only in source can be directly copied.
            #Files that are only in backup can just be removed.
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
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($FilesGroupedSizeWise.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }

            #************************ 2B ***************************
            #Now act on each group:
            # 1. If enabled, remove items from the group that appear to be equal based on their path and name, because they should be the same (nothing needs to be done with them)
            # 2. Allocate each group to a seperate lists of items to be deleted from backup, to be copied from source
            #    or to be compared using their hash.
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.30;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Activity = "Mirroring content."
		    $InnerLoopProg.Status = "Removing items from group that are already backed up..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
            $UnhashedFiles2Send2Del = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object -Expand Group
            foreach ($file in $UnhashedFiles2Send2Del) {
                $ExtLen[0] = $file.FullName.Length - $BkpLen
                $file.RemPath = $RepPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetRemove
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($UnhashedFiles2Send2Del.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
            
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.33;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Tagging unique source files for backup..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
            $UnhashedFiles2Copy2Bkp = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object -Expand Group
            foreach ($file in $UnhashedFiles2Copy2Bkp) {
                $ExtLen[0] = $file.FullName.Length - $SrcLen
                $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetBackup
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($UnhashedFiles2Copy2Bkp.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
            
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.35;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Checking content of potential backup matches..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************

            #************************ 2C ***************************
            #As noted, if they were in both, need to get more info.
            $Files2CmprCont = $FilesGroupedSizeWise| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group
            $Files2Hash = $Files2CmprCont

            #Calculate the hash of files or grab it from the value that was already pulled.
            $Asset = New-Object -TypeName PSObject
            $GroupID = @{Length=0; BkpPath=""; Hash="****************************************************************"}
            $Files2Hash | Add-Member -MemberType NoteProperty -Name GroupID -Value $([string]"")
            foreach ($prehashfile in $Files2Hash) {
                if ($prehashfile.LocKey -eq $SrcKey) {
                    #Do nothing, the hash should already exist.
                }
                else {
                    $hashset = Get-FileHash -LiteralPath $prehashfile.FullName
                    $prehashfile.Hash = $hashset.Hash
                }
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($UnhashedFiles2Send2Del.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }

            
            
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.5;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Finalizing list of files to backup part 1 of 2..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************

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
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($FilesGroupedByHash.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
    
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.525;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Finalizing list of files to remove from backup..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
            #************************ 3 ***************************
            #Now allocate each group to a seperate lists, to be grouped later, and hash those that need to be checked.
            $HashedFiles2Send2Del = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object -Expand Group
            foreach ($file in $HashedFiles2Send2Del) {
                $ExtLen[0] = $file.FullName.Length - $BkpLen
                $file.RemPath = $RepPathFldr + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetRemove
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($HashedFiles2Send2Del.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.55;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Finalizing list of files to backup part 2 of 2..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
            $HashedFiles2Copy2Bkp = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object -Expand Group
            foreach ($file in $HashedFiles2Copy2Bkp) {
                $ExtLen[0] = $file.FullName.Length - $SrcLen
                $file.BkpPath = $BkpPath + $file.FullName.Substring($SrcLen,$ExtLen[0])
                $file.DeterminedAction = $SetBackup
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($HashedFiles2Copy2Bkp.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }
            }
            $HashedFiles2Chk2Copy = $FilesGroupedByHash| Where-Object { $_.LocKey -eq $BthKey } | Select-Object -Expand Group
            
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.575;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Finalizing list of files to backup part 2 of 2..."
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
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
                $LoopProg += 1
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/($HashedFiles2Copy2Bkp.Count)
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
					$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		            Write-Progress @InnerLoopProg
                }

            }
            $FilesGroupedByGroupID = $HashedFiles2Chk2Copy | Group-Object -Property GroupID
            $FilesNotBackedUp = $FilesGroupedByGroupID| Where-Object { $_.Count -ne 2 } | Select-Object -Expand Group
            $RenamedFiles2Copy2Bkp = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $SrcKey } | Select-Object
            $RenamedBFiles2PermDel = $FilesNotBackedUp| Where-Object { $_.LocKey -eq $BkpKey } | Select-Object

            
		    #**************UPDATING BOTH LOOPS****************
		    $CurrBkpSetProgDbl[0] = 0.6;
		    $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		    $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		    $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		    Write-Progress @OuterLoopProg;
		    $InnerLoopProg.Status = "Removing files from backup that already exist (have been renamed / removed as they were duplicate)"
		    $CurrInnerProgDbl[0] = 0;
		    $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		    $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
            $LoopProg = 0
			$PrevInnerProgPercInt[0] = 0
		    #*************************************************
            #************************ 4 ***************************
            #Delete files from backup since they have been renamed, moved, or otherwise exist in the source.
            $Files2DelFromBackupWOZip = $RenamedBFiles2PermDel
            if ($Files2DelFromBackupWOZip.Count -and $RemEnbl) {
                Remove-Item -LiteralPath $Files2DelFromBackupWOZip.FullName -Force
                $Files2DelFromBackupWOZip.FullName | Out-File -Append $DelReport
            }
    

            #************************ 5 ***************************
            
            #Move files that have been removed from source but still exist in the backup folder to thier designated delete location and zip.  Save report.
            if ($HashedFiles2Send2Del.Count)     {$Files2Send2DelAndZip = $Files2Send2DelAndZip + $HashedFiles2Send2Del}
            if ($UnhashedFiles2Send2Del.Count)   {$Files2Send2DelAndZip = $Files2Send2DelAndZip + $UnhashedFiles2Send2Del}
            if ($Files2Send2DelAndZip.Count -and $RemEnbl -and $ArchiveChangesFlag) {
		        #**************UPDATING BOTH LOOPS****************
		        $InnerLoopProg.Status = "Creating folders to prepare for archive..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                $DeleteDirs2Set = (Split-Path $Files2Send2DelAndZip.RemPath -Parent) | Get-Unique | Sort-Object { $_.Length }
                New-Item -Path $RepPathFldr -ItemType "directory" | Out-Null
                foreach ($dir2make in $DeleteDirs2Set) {
                    if( -Not (Test-Path -LiteralPath $dir2make ) ) {
                        New-Item -Path $dir2make -ItemType "directory" | Out-Null
                    }
                    $LoopProg += 1
                    $CurrInnerProgPercInt[0] = ($LoopProg*100)/($DeleteDirs2Set.Count)
                    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
						$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		                Write-Progress @InnerLoopProg
                    }
                }
		        #**************UPDATING BOTH LOOPS****************
		        $InnerLoopProg.Status = "Moving files to prepare for archive..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                foreach ($file2move in $Files2Send2DelAndZip) {
                    Move-Item -LiteralPath $file2move.FullName -Destination $file2move.RemPath
                    $LoopProg += 1
                    $CurrInnerProgPercInt[0] = ($LoopProg*100)/($Files2Send2DelAndZip.Count)
                    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
						$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		                Write-Progress @InnerLoopProg
                    }
                }
		        #**************UPDATING BOTH LOOPS****************
		        $InnerLoopProg.Status = "Compressing files for archive..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                #Now zip up folder, and delete.
                Start-SevenZip a -mx=9 -bso0 -bsp0 $RepPath7Zip $RepPathFldr
                Remove-Item -LiteralPath $RepPathFldr -Force -Recurse| Out-Null
                $Files2Send2DelAndZip.FullName | Out-File -Append $ModReport
            }


            #************************ 6 ***************************
            #Copy corresonding files from source to backup.
            if ($Files2Backup) {
                Remove-Variable Files2Backup
            }
            if ($RenamedFiles2Copy2Bkp.Count)  {$Files2Backup = $Files2Backup + $RenamedFiles2Copy2Bkp}
            if ($HashedFiles2Copy2Bkp.Count)   {$Files2Backup = $Files2Backup + $HashedFiles2Copy2Bkp}
            if ($UnhashedFiles2Copy2Bkp.Count) {$Files2Backup = $Files2Backup + $UnhashedFiles2Copy2Bkp}
            if ($Files2Backup.Count) {
		        #**************UPDATING BOTH LOOPS****************
		        $CurrBkpSetProgDbl[0] = 0.7;
		        $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		        $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		        $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		        Write-Progress @OuterLoopProg;
		        $InnerLoopProg.Status = "Creating directories for backup..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                $BackupDirs2Set = (Split-Path $Files2Backup.BkpPath -Parent) | Get-Unique | Sort-Object { $_.Length }
                foreach ($dir2make in $BackupDirs2Set) {
                    if( -Not (Test-Path -LiteralPath $dir2make ) ) {
                        New-Item -Path $dir2make -ItemType "directory" | Out-Null
                    }
                    $LoopProg += 1
                    $CurrInnerProgPercInt[0] = ($LoopProg*100)/($BackupDirs2Set.Count)
                    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
						$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		                Write-Progress @InnerLoopProg
                    }
                }
		        #**************UPDATING BOTH LOOPS****************
		        $InnerLoopProg.Status = "Backing up applicable files..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                foreach ($file2copy in $Files2Backup) {
                    Copy-Item -LiteralPath $file2copy.FullName -Destination $file2copy.BkpPath | Out-Null
                    $LoopProg += 1
                    $CurrInnerProgPercInt[0] = ($LoopProg*100)/($Files2Backup.Count)
                    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
						$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		                Write-Progress @InnerLoopProg
                    }
                }
                $Files2Backup.FullName | Out-File -Append $CopyReport
            }
    
            #************************ 7 ***************************
            #Delete remaining directories in backup that don't exist in source.
            if ($BackupDirs2Del.count -and $RemEnbl) {
		        #**************UPDATING BOTH LOOPS****************
		        $CurrBkpSetProgDbl[0] = 099;
		        $OuterProgPerc = [math]::floor((($CurrBkpSetOverDbl[0] + $CurrBkpSetProgDbl[0])*100)/$NBackupSets);
		        $OuterLoopProg.PercentComplete  = $OuterProgPerc;
		        $OuterLoopProg.CurrentOperation = "Overall Percent Complete: " + $OuterLoopProg.PercentComplete.ToString()
		        Write-Progress @OuterLoopProg;
		        $InnerLoopProg.Status = "Cleaing up directories from backup that no longer exist..."
		        $CurrInnerProgDbl[0] = 0;
		        $InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
		        $InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		        Write-Progress @InnerLoopProg
                $LoopProg = 0
				$PrevInnerProgPercInt[0] = 0
		        #*************************************************
                foreach ($dir2remove in $BackupDirs2Del.FullName) {
                    if((Test-Path -LiteralPath $dir2remove) ) {
                        Remove-Item -LiteralPath $dir2remove  -Force -Recurse | Out-Null
                    }
                    $LoopProg += 1
                    $CurrInnerProgPercInt[0] = ($LoopProg*100)/($BackupDirs2Del.Count)
                    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
                        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
						$InnerLoopProg.CurrentOperation = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		                Write-Progress @InnerLoopProg
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
    Write-Error ($_.Exception | Format-List -Force | Out-String) -ErrorAction Continue
    Write-Error ($_.InvocationInfo | Format-List -Force | Out-String) -ErrorAction Continue
    $SendMsgProps['Body'] = ($_.Exception | Format-List -Force | Out-String)
    $SendMsgProps['Subject'] = "Automatic Backup Failed"
}
Send-MailMessage @SendMsgProps -UseSsl

Function pause ($message)
{
    # Check if running Powershell ISE
    if ($psISE)
    {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("$message")
    }
    else
    {
        Write-Host "$message" -ForegroundColor Yellow
        $x = $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}