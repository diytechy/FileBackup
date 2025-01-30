#Process level, 0 = all, 1 = move to process path, 2 = convert from process path to output
$ProcLvl = 0
$InputFileRootPath ="S:"
$PrepFileRootPath ="D:\AlbumPrep"
$ConvFileRootPath ="D:\AlbumConv"
$OutputFilePrepend = "D:\Album"
$OutputSizes = @(
    [pscustomobject]@{XDim=1440;YDim=1080})
#    [pscustomobject]@{XDim=1280;YDim=720})

$ImgTypes = @(
"jpg"
"gif"
"tif"
"tiff"
"jpeg"
"png"
"bmp"
)

$VidTypes = @(
"wmv"
"mov"
"m4a"
"mp4"
"avi"
)
#3 Steps:
#1. Prepare files by copying them to local path
#2. Prepare images by converting them to a conversion path (enhance / rotate)
#3. Resize images into their destination path
#4. Resize videos into their destination path

#JPEG Lossless rotator path:

#Image Magick path:

#Image resizer path:

#Handbrake path:

$HashTblDateFormat = "O"
$AllTypes = $ImgTypes + $VidTypes
$CurrInnerProgPercInt = [int32[]]::new(1);
$PrevInnerProgPercInt = [int32[]]::new(1);
$CurrInnerProgDbl  = [double[]]::new(1);
$InnerLoopProg = @{
	ID       = 1
	Activity = "Getting ready.  Please wait..."
	Status   = "Getting ready.  Please wait..."
	PercentComplete  = 0
	CurrentOperation = 0
}
#Write-Host $AllTypes[0]
#Verify all process staging files are up-to-date.  Copy them over or delete them as needed.
if((($ProcLvl -eq 0) -or ($ProcLvl -eq 1)) -and (Test-Path -LiteralPath $InputFileRootPath)){
    #Make the prep directory if it doesn't already exist.
    if(Test-Path -LiteralPath $PrepFileRootPath) {}#do nothing
    else {New-Item -Path "$PrepFileRootPath" -ItemType Directory}

    $AllInputFiles = @(Get-ChildItem -LiteralPath $InputFileRootPath -Recurse -File)
    #For all files, see if it should be copied, and if so if it already is.
    #Then create a tuple for the filename, size, and datetime.
    if ($AllInputFiles.Count)
    {
        $FndFile = @{}
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name CopyPath -Value $([string]"****")
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name CopyFlag -Value $([int]0)
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name TupleVal -Value [System.ValueTuple[string, long, datetime]]
        $SrcL = $InputFileRootPath.Length
        Write-Host ($AllInputFiles.Count.ToString() + " files found!")

        foreach($file in $AllInputFiles)
        {
            $IncChk = -not($file.FullName.Contains("DNP"))
            if($IncChk){
                foreach($type in $AllTypes){
                    if($file.Name.EndsWith($type) -and $IncChk){$file.CopyFlag = 1}
                }
            }
            if($file.CopyFlag)
            {
                $ExtLen = $file.FullName.Length - $SrcL
                $RelPth = $file.FullName.Substring($SrcL, $ExtLen)
                $file.CopyPath = $PrepFileRootPath + $RelPth
                $datekey = [System.ValueTuple[string, long, datetime]]::new(
                        $RelPth, $file.Length, $file.LastWriteTime)
                $FndFile[$datekey] = 1
                $file.TupleVal = $datekey;
            }
        }
        $PreFiles2Copy = ($AllInputFiles | Where-Object -Property CopyFlag -eq 1)
        Write-Host ($PreFiles2Copy.Count.ToString() + " media files found!")
        #Now, for all prep files, see remove any that don't have a tuple match
        $PrpFndFile = @{}
        $PrpL = $PrepFileRootPath.Length
        $PrePrepFiles = @(Get-ChildItem -LiteralPath $PrepFileRootPath -Recurse -File)
        foreach ($file in $PrePrepFiles)
        {
            $ExtLen = $file.FullName.Length - $PrpL
            $RelPth = $file.FullName.Substring($PrpL, $ExtLen)
            $datekey = [System.ValueTuple[string, long, datetime]]::new(
                    $RelPth, $file.Length, $file.LastWriteTime)
            $PrpFndFile[$datekey] = 1
            #if the file exists/matches the source, ignore it.
            if($FndFile[$datekey]){}
            #else, the file isn't in the source anymore, and should be removed.
            else
            {
                Remove-Item -LiteralPath $file.FullName
            }
        }
        #Now copy all the files that need to be copied.
        $PreFiles2Copy | Add-Member -MemberType NoteProperty -Name SkipFlg -Value $([int]0)
        foreach ($file in $PreFiles2Copy)
        {
            #If the file already exists in the prep path, don't do anything
            if ($PrpFndFile[$file.TupleVal])
            {
                $file.SkipFlg = 1
            }
            #else copy it accordingly.
        }
        $Files2Copy = ($PreFiles2Copy | Where-Object -Property SkipFlg -eq 0)
        Write-Host ($Files2Copy.Count.ToString() + " media files to copy!")
        $PrevInnerProgPercInt[0] = 0
        $LoopProg = 0
        $AllFilesizeTtl = $Files2Copy | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum

        foreach ($file in $Files2Copy)
        {
            if(Test-Path -LiteralPath $file.CopyPath){}#Do nothing
            else{ #Create file
                $null = New-Item -ItemType File -Path $file.CopyPath -Force
            }
            Copy-Item $file.FullName $file.CopyPath -Force
            $LoopProg += $file.Length
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
            {
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                $InnerLoopProg.Status = "Copying files: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                Write-Progress @InnerLoopProg
            }
        }
    }
}
#If we aren't set to process the source directory, just grab file definitoins from prep space.
elseif(Test-Path -LiteralPath $PrepFileRootPath) {
    #Do nothing, proceed as is.
}
else{
    throw "The input processing path was empty."
}
#************************************************************
#******************Step 2, convert images.*******************
#************************************************************
$AllPrepFiles = @(Get-ChildItem -LiteralPath $PrepFileRootPath -Recurse -File)
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name RelPath -Value $([string]"****")
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvPath -Value $([string]"****")
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name LastWriteTimeStr -Value $([string]"****")
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name SelLabelGrp -Value $([string]"****")
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name Need2ConvFlag -Value $([int]0)
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvExpected -Value $([int]0)
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsImg -Value $([int]0)
$AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsVid -Value $([int]0)
if((($ProcLvl -eq 0) -or ($ProcLvl -gt 1)) -and ($AllPrepFiles.Count))
{
    $PrpL = $PrepFileRootPath.Length
    $ConvReportPath = ($ConvFileRootPath + "\Report.csv")
    $PrevConvMap = @{}
    $CurrConvMap = @{}
    if(Test-Path -LiteralPath $ConvReportPath)
    {
        $PrevConvProps = Import-Csv -LiteralPath $ConvReportPath
        $PrevConvProps | Add-Member -MemberType NoteProperty -Name LastWriteTimeDateTime -Value $( [DateTime] )
        $PrevConvProps | Add-Member -MemberType NoteProperty -Name TupleVal -Value [System.ValueTuple[string, long, datetime]]
        foreach ($PrevProp in $PrevConvProps)
        {
            $PrevProp.LastWriteTimeDateTime = [datetime]::ParseExact($PrevProp.LastWriteTimeStr, $HashTblDateFormat, $null)
            $key = [System.ValueTuple[string, long, datetime]]::new(
                    $PrevProp.RelPath, $PrevProp.Length, $PrevProp.LastWriteTimeDateTime)
            $PrevProp.TupleVal = $key
            $PrevConvMap[$key] = 1
        }
    }
    foreach ($file in $AllPrepFiles){
        $ExtLen = $file.FullName.Length - $PrpL
        $RelPath = $file.FullName.Substring($PrpL, $ExtLen)
        $ChkPath = $file.FullName.Substring(($PrpL+1), ($ExtLen-1))
        #$ChkPath = $file.FullName.Substring($PrpL+1, $ExtLen)
        $Parts = $ChkPath -split '\\', 3
        $file.RelPath = $RelPath
        $file.SelLabelGrp = $Parts[1] #Grap other folder
        $file.LastWriteTimeStr = $file.LastWriteTime.ToString($HashTblDateFormat)
        $datekey = [System.ValueTuple[string, long, datetime]]::new(
                $RelPath, $file.Length, $file.LastWriteTime)
        $IncChk = 0
        foreach($type in $ImgTypes){
            if($file.Name.EndsWith($type)){
                $file.ConvExpected = 1
                $file.IsImg = 1
                $IncChk = 1
                #Set tuple for current conversion map, for removal reference.
                $CurrConvMap[$datekey] = 1
            }
        }
        foreach($type in $VidTypes){
            if($file.Name.EndsWith($type)){
                $file.IsVid = 1
            }
        }
        #If it is an image, set the conversion source path accordingly.
        if($IncChk)
        {
            $file.ConvPath = ($ConvFileRootPath + $RelPath)
        }
        if(($PrevConvMap[$datekey]) -and (Test-Path -LiteralPath $file.ConvPath)){}#do nothing, file exists and is up-to-date.
        elseif($IncChk){
            $file.Need2ConvFlag = 1
        }
    }
    $ExpectedFiles = ($AllPrepFiles | Where-Object -Property ConvExpected -eq 1)
    $Files2Conv    = ($AllPrepFiles | Where-Object -Property Need2ConvFlag -eq 1)
    Write-Host ($Files2Conv.Count.ToString() + " media files to convert!")
    $PrevInnerProgPercInt[0] = 0
    $LoopProg = 0
    $AllFilesizeTtl = $Files2Conv | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum
    $Files2Conv | Add-Member -MemberType NoteProperty -Name Complete -Value $([int]0)
    foreach ($file in $Files2Conv)
    {
        if(Test-Path -LiteralPath $file.ConvPath){}#Do nothing
        else{ #Create file
            $null = New-Item -ItemType File -Path $file.ConvPath -Force
        }
        #Do the conversion stuff here
        copy-item $file.FullName $file.ConvPath

        $file.Complete = 1
        $LoopProg += $file.Length
        $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
        if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
        {
            $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
            $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
            $InnerLoopProg.Status = "Converting files: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
            Write-Progress @InnerLoopProg
            #$Files2Conv | Where-Object -Property Complete -eq 1 |
            #Select-Object -Property RelPath, Length, LastWriteTimeStr, ConvPath|
            #Export-Csv -Path $ConvReportPath -NoTypeInformation
        }
    }
    #Remove items that shouldn't be there.  Not really necessary but good to cleanup
    Write-Host "Removeing old converted files that are no longer present if applicable"
    foreach ($PrevProp in $PrevConvProps){
        if($CurrConvMap[$PrevProp.TupleVal]) {} #Do nothing if file should exist.
        #elseif(Test-Path -LiteralPath $PrevProp.ConvPath){} #Do nothing if there is no path information.
        elseif(Test-Path -Path $PrevProp.ConvPath){
            remove-item -LiteralPath $PrevProp.ConvPath -Force
        }
    }
    #Finally save off report of converted files.
    #$ConvReportPath
    $ExpectedFiles | Select-Object -Property Name,RelPath,ConvPath,Length,LastWriteTimeStr|
            Export-Csv -LiteralPath $ConvReportPath -NoTypeInformation
    #Now, for each set, run the final export tooling depending on if the file is a video or image.
    $ImageFiles = ($AllPrepFiles | Where-Object -Property IsImg -eq 1)
    $VideoFiles = ($AllPrepFiles | Where-Object -Property IsVid -eq 1)
    $AllFiles = $ImageFiles + $VideoFiles

    foreach ($set in $OutputSizes){
        #Convert all logs accordingly
        Write-Host ("Exporting media for set: " + $set.XDim + " by "  + $set.YDim)
        foreach($file in $AllFiles){
            #
        }

    }
}

