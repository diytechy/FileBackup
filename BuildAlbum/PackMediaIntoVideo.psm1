function Set-VideoFromMedia
{
    param (
        [string]$OutputFilePrepend,
        $OutputSizes
    )
    $HashTblDateFormat = "O"
    $CurrInnerProgPercInt = [int32[]]::new(1);
    $PrevInnerProgPercInt = [int32[]]::new(1);
    $InnerLoopProg = @{
	ID       = 1
	Activity = "Getting ready.  Please wait..."
	Status   = "Getting ready.  Please wait..."
	PercentComplete  = 0
	CurrentOperation = 0
    }
    #ffmpeg video & Handbrake path:
    $ConvVid = 1
    if (Get-Command npm -ErrorAction SilentlyContinue) {
    #Write-Host "ffmpeg is already installed."
    }
    else{Throw  "Error: npm not detected, dependencies cannot be installed to pack video."
    $ConvVid = 0}
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    #Write-Host "ffmpeg is already installed."
    }
    else{Write-Host  "ffmpeg not detected, videos will not be converted"
    $ConvVid = 0}
    if (Get-Command HandBrakeCLI -ErrorAction SilentlyContinue) {
    #Write-Host "HandBrakeCLI  is already installed."
    }
    else{Write-Host  "HandBrakeCLI not detected, videos will not be converted"
    $ConvVid = 0}

    #Check to see if ffmpeg-concat is installed, and if not, install it.
    $packages = npm list
    if( -not ($packages.Contains("Test")))
    {
        npm install -g ffmpeg-concat
        npm install ffmpeg-concat
    }
    #JPEG Lossless rotator path:
    $RotImg = 1
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
            #Write-Host "jpeg lossless rotator is already installed."
            }
        else{Write-Host  "jpeg lossless rotator not detected, images will not be rotated"
        $RotImg = 0}

    #Image Magick path:
    $MagImg = 1
    if (Get-Command magick -ErrorAction SilentlyContinue) {
            #Write-Host "Image Magick is already installed."
            }
        else{Write-Host  "Image Magick not detected, images will not be enhanced"
        $MagImg = 0}

    #Now - for each set - break all the files into designated groups and their corresponding destinations.
    foreach ($set in $OutputSizes){
        $ContFileRootPath = $set.Outpath
        $VidPacksRootPath = $ContFileRootPath + $set.ImgVidFldr
        $VidPacksFileDefPath = $set.Outpath + "\VidPackDef"
        $AllInputFiles = @(Get-ChildItem -LiteralPath $ContFileRootPath -Filter "*.mp4")
        #Add in video packs for images if defined and intended.
        if((Test-Path -LiteralPath $VidPacksRootPath -PathType Container) -and $set.ImgVidFldr.Length -and $set.PicDispTime)
        {
            $AllInputFiles = $AllInputFiles + @(Get-ChildItem -LiteralPath $VidPacksRootPath -Filter "*.mp4")
        }
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name GroupN -Value $([int])
        #Figure out the nominal number of files per group, assuming most are pictures lasting for the still duration.
        $NFilesPerGrp = (($Set.BulkVidTimeMin*60)/$Set.PicDispTime)
        $NGroups = [Math]::Floor($AllInputFiles.Count/$NFilesPerGrp) -as [Int]
        $SelGrpN = 1 -as [Int]
        foreach ($file in $AllInputFiles)
        #For each file
        {
            $file.GroupN = $SelGrpN
            $SelGrpN++
            if($SelGrpN -gt $NGroups){
                $SelGrpN = 1
            }
        }
        $Groups= $AllInputFiles | Select-Object -ExpandProperty GroupN | Sort-Object -Unique
        $Groups | Add-Member -MemberType NoteProperty -Name FileListPath -Value $([string])
        $Groups | Add-Member -MemberType NoteProperty -Name OutputPath -Value $([string])
        #Map to store file list.
        $GrpDef = @{}
        #Now build a list for each group.  This will be used in ffmpeg to actually build out the video.
        foreach ($grp in $Groups){
            $FileSet = (($AllInputFiles | Where-Object {( $_.GroupN -eq $grp)} | Sort-Object -Property Name) | Select-Object -ExpandProperty FullName)
            $GrpDef[$grp] = $FileSet
            $grp.FileListPath = $VidPacksFileDefPath  + " Grp-" + $grp.ToString()
            $grp.VidExpPath   = $VidPacksRootPath  + "\Grp-" + $grp.ToString()
            #Create file to describe what videos to append.
            $FileSet | Export-Csv -Path $grp.FileListPath -NoTypeInformation
        }
        $SelGrpN = 0
    }
}
