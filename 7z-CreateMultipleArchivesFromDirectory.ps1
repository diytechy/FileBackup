
#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

#What directory contents should be archived
$BkpFldrPath = "E:\02\0\"
#Where should the archives / reports be saved
$7zOutputDir = "E:\BackupSnapshotArchives\"
#What size should we average for precompression size, note there is not intelligent grouping here, 
# but that complexity could be added, it merely acts as a way to break apart all files before archiving.
$IdealPreCompSize = 1000000000
#What temp path should be used to create the archives.
$ArchivePrepPath = "E:\TempPath\"

#7-s path, in general shouldn't need to change
$7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"

if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip executable '$7zipPath' not found"
}

Set-Alias Start-SevenZip $7zipPath

#Runtime variables
$GrpSrtVal = 1;
$ExtLen   = [int[]]::new(1);
$SizeRoll = [int64[]]::new(1);
$SelGrpID = [int64[]]::new(1);$SelGrpID[0] =$GrpSrtVal;
$RelPath = ""

#***************************************start here
#Create path templates for report and zip.
$TodayCode = $((Get-Date).ToString('yyyy-MM-dd-hh-mm-ss'))
$7ZPathPrepend = $7zOutputDir + $TodayCode + "_Snapshot_Archive_Grp_"
$7ZRprtPrepend = $7zOutputDir + $TodayCode + "_Snapshot_Report_Grp_"

$SrcLen   = $BkpFldrPath.Length;
$AllSrcFiles = @(Get-ChildItem -Path $BkpFldrPath -Recurse -File)
$AllSrcFiles | Add-Member  -MemberType NoteProperty -Name TmpPath -Value $([string]"")
$AllSrcFiles | Add-Member  -MemberType NoteProperty -Name GrpID -Value $([int64]0)
foreach ($SelFile in $AllSrcFiles) {
    $ExtLen[0] = $SelFile.FullName.Length - $SrcLen
    $RelPath = $SelFile.FullName.Substring($SrcLen,$ExtLen[0])
    $SelFile.TmpPath = $ArchivePrepPath+$RelPath
    $SizeRoll[0] = $SizeRoll[0]+$SelFile.Length
    $SelFile.GrpID = $SelGrpID[0]
    #If the accumulated file size has accumulated over the pre-compression size, switch the group number for the next file.
    if ($SizeRoll[0] -ge $IdealPreCompSize){
        $SelGrpID[0] = $SelGrpID[0]+1
        while ($SizeRoll[0] -ge $IdealPreCompSize) {
            $SizeRoll[0] = $SizeRoll[0] - $IdealPreCompSize
        }
    }
}
$FileGrps = @($AllSrcFiles | Group-Object  -Property GrpID)

$SelGrpID[0] =$GrpSrtVal-1;
foreach ($SelFileGrp in $FileGrps) {
    $SelGrpID[0] =$SelGrpID[0]+1;
    $SelFileList = @($SelFileGrp| Select-Object -Expand Group)
    $BackupDirs2Set = (Split-Path $SelFileList.TmpPath -Parent) | Get-Unique | Sort-Object { $_.Length }
    #Prepare temp directory
    Remove-Item -LiteralPath $ArchivePrepPath  -Force -Recurse | Out-Null
    New-Item -Path $ArchivePrepPath -ItemType "directory" | Out-Null
    #Create subdirectories
    foreach ($dir2make in $BackupDirs2Set) {
        if( -Not (Test-Path -Path $dir2make ) ) {
            New-Item -Path $dir2make -ItemType "directory" | Out-Null
        }
    }
    #Copy files to temp directory
    foreach ($file2cpy in $SelFileList) {
        Copy-Item -Path $file2cpy.FullName -Destination $file2cpy.TmpPath | Out-Null
    }
    #Create output names
    $IDStr = '{0:d4}' -f [Int]$SelGrpID[0].ToString()
    $RprtPath = $7ZRprtPrepend + $IDStr + ".txt"
    $ArchPath = $7ZPathPrepend + $IDStr + ".7z"
    Start-SevenZip a -mx=9 -bso0 -bsp0 $ArchPath $ArchivePrepPath
    $SelFileList.TmpPath | Out-File -Append $RprtPath
    $Msg = "Group " + $SelGrpID[0].ToString() + " of " + $FileGrps.Count.ToString() + " archived"
    Write-Output $Msg
    #pause ("Press key to continue.")
}

#Below function from https://stackoverflow.com/questions/20886243/press-any-key-to-continue
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