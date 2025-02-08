Import-Module ".\BuildAlbum\ConcatMediaFromFileList.psm1"
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
        $VidPacksFileDefPath = $set.OutGrp
        $AllInputFiles = @(Get-ChildItem -LiteralPath $ContFileRootPath -Filter "*.mp4")
        #Add in video packs for images if defined and intended.
        if((Test-Path -LiteralPath $VidPacksRootPath -PathType Container) -and $set.ImgVidFldr.Length -and $set.PicDispTime)
        {
            $AllInputFiles = $AllInputFiles + @(Get-ChildItem -LiteralPath $VidPacksRootPath -Filter "*.mp4")
        }
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name GroupN -Value $([int])
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name Dur -Value $([Decimal])
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
            $ToRun = "ffprobe -v error -select_streams v -show_entries stream=width,duration -of csv=p=0 `"" +$file.Fullname+ "`""
            ($VPrams = Invoke-Expression $ToRun) *> $null
            $splitString = $VPrams -split ","
            #$Width = [Int] $splitString[0]
            $file.Dur = [decimal] $splitString[1]
        }
        $TarBitrate = 5000;
        if ($set.MaxSizeInGB)
        {
            $DurTotal = $AllInputFiles | Measure-Object -Property Dur -Sum ; $DurTotal = [double] $DurTotal.Sum
            $BitTotal = 8*$set.MaxSizeInGB*1.25e+8
            $TarBitrate = $BitTotal/$DurTotal #Assume fading is negligable.
        }
        $Groups= $AllInputFiles | Select-Object -ExpandProperty GroupN | Sort-Object -Unique
        $Groups | Add-Member -MemberType NoteProperty -Name FileListPath -Value $([string])
        $Groups | Add-Member -MemberType NoteProperty -Name VidExpPath -Value $([string])
        #Map to store file list.
        $GrpDef = @{}
        #Now build a list for each group.  This will be used in ffmpeg to actually build out the video.
        foreach ($grp in $Groups){
            $FileSet = (($AllInputFiles | Where-Object {( $_.GroupN -eq $grp)} | Sort-Object -Property Name) | Select-Object -ExpandProperty FullName)
            $GrpDef[$grp] = $FileSet
            $grp.FileListPath = $VidPacksFileDefPath  + " Grp-" + $grp.ToString()
            $grp.VidExpPath   = $VidPacksFileDefPath  + "\Grp-" + $grp.ToString()+".mp4"
            #Create file to describe what videos to append.
            $FileSet | Export-Csv -Path $grp.FileListPath -NoTypeInformation
        }
        $Groups | ForEach-Object -Parallel{
            $FadeTime      = $using:set.FadeTime
            $Quality       = $using:set.Quality
            $GrpDef        = $using:GrpDef
            $SelGrpDef     = $GrpDef[$_]
            Import-Module ".\BuildAlbum\ConcatMediaFromFileList.psm1"
            Join-VideosFromList $SelGrpDef $FadeTime $_.VidExpPath $Quality
        } -ThrottleLimit 1
        $SelGrpN = 0
    }
}
