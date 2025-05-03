
function New-VideoZoomedOutFromPic
{
    param (
        [string]$InputPicPath,
        [Int]$InputWidth,
        [Int]$InputHeight,
        [Int]$InputBorderDef,
        [decimal] $SrtZoom,
        [decimal] $ZoomRate,
        [decimal] $RotRate,
        [decimal] $XRatio,
        [decimal] $YRatio,
        [decimal] $NFramesTrn,
        [decimal] $NFramesStd,
        [Int]$OutWidth,
        [Int]$OutHeight,
        [string]$OutputPathSrt,
        [string]$OutputPathNom,
        [string]$OutputPathEnd,
        [string]$FFMPEGSettings
    )
    #Reference notes:
    # Clone ref:
    #   https://stackoverflow.com/questions/76961118/imagemagick-how-do-i-reuse-one-single-image-to-overlay-it-multiple-times
    #   https://stackoverflow.com/questions/29736137/imagemagick-multiple-operations-in-single-invocation
    #   https://stackoverflow.com/questions/73708237/can-imagemagick-generate-multiple-outputs-from-one-input

    # https://www.imagemagick.org/script/command-line-options.php#distort
    # https://im.snibgo.com/animsrt.htm
    #%IMG7%magick ^
    #-loop 0 -delay 20 ^
    #%SRC% ^
    #-duplicate 4 ^
    #-define distort:viewport=%OUT_WI%x%OUT_HT%+0+0 ^
    #-distort SRT ^
    #%%[fx:%IN_X%+%D_IN_X%*t],^
    #%%[fx:%IN_Y%+%D_IN_Y%*t],^
    #%%[fx:%SCALE%*pow(%D_SCALE%,t)],^
    #%%[fx:%ANGLE%+%D_ANGLE%*t],^
    #%%[fx:%OUT_X%-%D_OUT_X%*t],^
    #%%[fx:%OUT_Y%-%D_OUT_Y%*t] ^
    #as_g1.gif

#$IMFrameCmdEx: (MPR:orig -define distort:viewport=$OutWidthx$OutHeight -distort SRT p1,p2,p3,p... output.png
#ffmpeg import ex: -i Vid1 -i Vid2 -i...

  #  Ex:
  #  magick input.png \
  # \( -clone 0 -shave '1x0' \) \
  # \( -clone 0 -shave '2x0' \) \
  # \( -clone 0 -shave '3x0' \) \
  # \( -clone 0 -shave '4x0' \) \
  # \( -clone 0 -shave '5x0' \) \
  # \( -clone 0 -shave '0x1' \) \
  # \( -clone 0 -shave '0x2' \) \
  # \( -clone 0 -shave '0x3' \) \
  # \( -clone 0 -shave '0x4' \) \
  # \( -clone 0 -shave '0x5' \) \
  # -delete 0 output_%02d.png

 #  %IMG7%magick ^
 # %SRC% ^
 # -define distort:viewport=600x400+0+0 ^
 # -distort SRT 3134,4241,0.75,32.5,200,266.67 ^
 # as_ex1.png

    $IMCmdSrt = "magick `"$( $file.ConvPath )`" -bordercolor black -border $InputBorderDef -write MPR:orig -delete 0"
    $IMConvPrepend = "``(MPR:orig -define distort:viewport=$OutWidthx$OutHeight -distort SRT "
    $IMCmdEnd = ""
    $TmpDirName = [System.IO.Path]::GetFileNameWithoutExtension($InputPicPath)
    $BuildDir = $env:TEMP + "\" + $TmpDirName + (Get-Date -Format "FileDateTime")
    if (Get-Command magick -ErrorAction SilentlyContinue) {}
    else {throw  "Image Magick not detected, images will not be converted"}
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {}
    else {throw  "ffmpeg not detected, images will not be converted"}
    if( -not(Test-Path $BuildDir -PathType Container))
    {(New-Item -Path $BuildDir -ItemType "directory") *> $null}
    try
    {
        $NFrames = $NFramesTrn*2 + $NFramesStd
        $AtEndTransInd = $NFramesTrn+$NFramesStd
        $NFrameChars = [Math]::ceiling(([Math]::Log($NFrames)/[Math]::Log(10)))
        if ($NFrameChars -lt 1)
        {
            $NFrameChars = 1
        }
        $FDef    = [string[]]::new($NFrameChars);
        $IMCmd   = [string[]]::new($NFrames);
        $FFMPEGSrtVidInput   = [string[]]::new($NFramesTrn);
        $FFMPEGNomVidInput   = [string[]]::new($NFramesStd);
        $FFMPEGEndVidInput   = [string[]]::new($NFramesTrn);
        for ($i = 0; $i -lt $NFrameChars; $i++) {
            $FDef[$i] = "0"
        }
        $FFmtDef = Join-String -InputObject $FDef
        $TPath = $BuildDir + "\" + "cmd2run.txt"
        $MgkPath = $BuildDir + "\" + "script.mgk"
        for ($i = 0; $i -lt $NFrames; $i++) {
            $SetZoom   = $SrtZoom - ($ZoomRate*$i)
            $SetRotate = $0 + ($RotRate*$i)
            if ($SetZoom -lt 1.0)
            {
                $SetZoom = 1.0
            }
            $FPath = $BuildDir + "\" + $i.ToString($FFmtDef) + ".png"
            $XOffset = ($InputWidth*$XRatio*(1.0 - 1.0/$SetZoom))
            $YOffset = ($InputHeight*$YRatio*(1.0 - 1.0/$SetZoom))
            #Add image file path to array, and add image magic command to array:
            $IMCmd[$i] = $IMConvPrepend+" $XOffset,$YOffset,0,0,$SetZoom,$SetRotate "+ "$FPath" +"``)"
            #Add ffmpeg imporrt definition depending on where we're at
            $ImportStr = " -i $FPath"
            if ($i -ge ($AtEndTransInd)){
                $FFMPEGEndVidInput[$i - $AtEndTransInd] = $ImportStr
            }
            elseif ($i -ge ($NFramesTrn))
            {
                $FFMPEGNomVidInput[$i - $NFramesTrn] = $ImportStr
            }
            else
            {
                $FFMPEGSrtVidInput[$i] = $ImportStr
            }
        }
        $NLC = "```r`n"

        #Now create the full command and run image magic to create the pictures.
        $IMCmdMid = Join-String -InputObject $IMCmd -Separator $NLC
        $IMCmdArray = $IMCmdSrt, $IMCmdMid, $IMCmdEnd
        $IMCmdRun = Join-String -InputObject $IMCmdArray -Separator $NLC

        #Now create the commands for ffmpeg for each video, and create the videos
        $FFMPEGPre = "ffmpeg -y -f concat -safe 0"
        #Note, format defined by $FFMPEGSettings
        $FFMPEGSrtVidInputSet = Join-String -InputObject $FFMPEGSrtVidInput -Separator $NLC
        $FFMPEGSrtVidArray = $FFMPEGPre, $FFMPEGSrtVidInputSet, $FFMPEGSettings, $OutputPathSrt
        $FFSrtCmd = Join-String -InputObject $FFMPEGSrtVidArray -Separator $NLC

        $FFMPEGNomVidInputSet = Join-String -InputObject $FFMPEGNomVidInput -Separator $NLC
        $FFMPEGNomVidArray = $FFMPEGPre, $FFMPEGNomVidInputSet, $FFMPEGSettings, $OutputPathNom
        $FFNomCmd = Join-String -InputObject $FFMPEGNomVidArray -Separator $NLC

        $FFMPEGEndVidInputSet = Join-String -InputObject $FFMPEGEndVidInput -Separator $NLC
        $FFMPEGEndVidArray = $FFMPEGPre, $FFMPEGEndVidInputSet, $FFMPEGSettings, $OutputPathEnd
        $FFEndCmd = Join-String -InputObject $FFMPEGEndVidArray -Separator $NLC

        $AllCmdsSet  = $IMCmdRun,$FFSrtCmd,$FFNomCmd,$FFEndCmd
        $AllCmds = Join-String -InputObject $AllCmdsSet -Separator "`r`n`r`n"
        $IMCmdRun | Out-File $MgkPath
        $AllCmds | Out-File $TPath

        #Save all commands for debug if enabled

        #Perform all actions
        (Invoke-Expression "magick -script $MgkPath") *> $null
        (Invoke-Expression $FFSrtCmd) *> $null
        (Invoke-Expression $FFNomCmd) *> $null
        (Invoke-Expression $FFEndCmd) *> $null
        #Write-Host "Done"
    }
    catch{}
    #Cleanup
    finally{
        #(Remove-Item -LiteralPath $BuildDir -Recurse -Force -EA SilentlyContinue -Verbose)*>null
    }
}

function Update-ConvertedMediaImagesForDisplay
{
    param (
        [string]$PrepFileRootPath,
        [string]$ConvFileRootPath
    )
    if (Get-Command jpegr -ErrorAction SilentlyContinue) {$RotImg = 1}
    else {throw  "Jpeg lossless rotator not detected, images will not be converted"}
    if (Get-Command magick -ErrorAction SilentlyContinue) {}
    else {throw  "Image Magick not detected, images will not be converted"}

    $HashTblDateFormat = "O"
    $CurrInnerProgPercInt = [int32[]]::new(1);
    $PrevInnerProgPercInt = [int32[]]::new(1);
    $InnerLoopProg = @{
        ID = 1
        Activity = "Getting ready.  Please wait..."
        Status = "Getting ready.  Please wait..."
        PercentComplete = 0
        CurrentOperation = 0
    }

    $ImgTypes = @("jpg", "gif", "tif", "tiff", "jpeg", "png", "bmp")
    $VidTypes = @("wmv", "mov", "m4a", "mp4", "avi", "WEBM", "mkv")

    #************************************************************
    #******************Step 2, convert images.*******************
    #************************************************************
    $AllPrepFiles = @(Get-ChildItem -LiteralPath $PrepFileRootPath -Recurse -File)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name RelPath -Value $( [string] )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvPath -Value $( [string]"" )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ContExt -Value $( [string] )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name LastWriteTimeStr -Value $( [string] )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name SelLabelGrp -Value $( [string] )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name Need2ConvFlag -Value $( [int]0 )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvExpected -Value $( [int]0 )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsImg -Value $( [int]0 )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsVid -Value $( [int]0 )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name FileIdx -Value $( [int]0 )
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name TupleVal -Value [System.ValueTuple[string, long, datetime]]
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name Exported -Value $( [int]0 )
    #If there are prep files, process.
    if ($AllPrepFiles.Count)
    {
        #*****************************************************
        #* Getting high level expectations for prep files ****
        #*****************************************************
        $PrpL = $PrepFileRootPath.Length
        $ConvReportPath = ($ConvFileRootPath + "\Report.csv")
        $ConvReportTupleExists = @{ }
        $CurrentPrepFileTupleExists = @{ }
        if (Test-Path -LiteralPath $ConvReportPath)
        {
            $PrevConvProps = Import-Csv -LiteralPath $ConvReportPath
            $PrevConvProps | Add-Member -MemberType NoteProperty -Name LastWriteTimeDateTime -Value $( [DateTime] )
            $PrevConvProps | Add-Member -MemberType NoteProperty -Name RemoveFlag -Value $( [int]0 )
            $PrevConvProps | Add-Member -MemberType NoteProperty -Name TupleVal -Value [System.ValueTuple[string, long, datetime]]
            Write-Host ($PrevConvProps.Count.ToString() + " files to check for previous properties")
            foreach ($PrevProp in $PrevConvProps)
            {
                $PrevProp.LastWriteTimeDateTime = [datetime]::ParseExact($PrevProp.LastWriteTimeStr, $HashTblDateFormat, $null)
                $key = [System.ValueTuple[string, long, datetime]]::new(
                        $PrevProp.RelPath, $PrevProp.Length, $PrevProp.LastWriteTimeDateTime)
                #If the file actually exists, set the flag so that it's not converted again.
                if(Test-Path $PrevProp.ConvPath -PathType Leaf)
                {
                    $PrevProp.TupleVal = $key
                    $ConvReportTupleExists[$key] = 1
                }
            }
        }
        Write-Host ($AllPrepFiles.Count.ToString() + " files to get conversion attributes for...")
        $FileCntr = 0
        foreach ($file in $AllPrepFiles)
        {
            $FileCntr++
            $file.FileIdx = $FileCntr
            $ExtLen = $file.FullName.Length - $PrpL
            $RelPath = $file.FullName.Substring($PrpL, $ExtLen)
            $file.RelPath = $RelPath
            $file.LastWriteTimeStr = $file.LastWriteTime.ToString($HashTblDateFormat)
            $datekey = [System.ValueTuple[string, long, datetime]]::new(
                    $RelPath, $file.Length, $file.LastWriteTime)
            #Set tuple for current conversion map, for removal reference.
            $CurrentPrepFileTupleExists[$datekey] = 1
            $file.TupleVal = $datekey
            $IncChk = 0
            foreach ($type in $ImgTypes)
            {
                if ( $file.Name.EndsWith($type))
                {
                    $file.ConvExpected = 1
                    $file.IsImg = 1
                    $file.ContExt = ".jpg"
                    $IncChk = 1
                }
            }
            foreach ($type in $VidTypes)
            {
                if ( $file.Name.EndsWith($type))
                {
                    $file.IsVid = 1
                    $file.ContExt = ".mp4"
                }
            }
            #If it is an image, set the conversion source path accordingly.
            if ($IncChk)
            {
                $file.ConvPath = ($ConvFileRootPath + $RelPath)
            }
            if ($ConvReportTupleExists[$datekey])
            {
            }#do nothing, file exists and is up-to-date.
            elseif($IncChk)
            {
                $file.Need2ConvFlag = 1
            }
        }
        #Remove items that shouldn't be there.  Not really necessary but good to cleanup
        Write-Host ("Checking for old converted files to remove")
        foreach ($PrevProp in $PrevConvProps)
        {
            if ($CurrentPrepFileTupleExists[$PrevProp.TupleVal])
            {
            } #Do nothing if file should exist.
            #elseif(Test-Path -LiteralPath $PrevProp.ConvPath){} #Do nothing if there is no path information.
            elseif(Test-Path -Path $PrevProp.ConvPath -PathType Leaf)
            {
                $PrevProp.RemoveFlag = 1
            }
        }
        $OldPrepFiles2Rem = ($AllPrepFiles | Where-Object -Property RemoveFlag -eq 1)
        Write-Host ($OldPrepFiles2Rem.Count.ToString() + " old converted media files to remove!")
        foreach ($PrevProp in $OldPrepFiles2Rem)
        {
            remove-item -LiteralPath $PrevProp.ConvPath -Force
        }
        $Files2Conv = ($AllPrepFiles | Where-Object -Property Need2ConvFlag -eq 1)
        Write-Host ($Files2Conv.Count.ToString() + " media files to convert!")
        $PrevInnerProgPercInt[0] = 0
        $LoopProg = 0
        $AllFilesizeTtl = $Files2Conv | Measure-Object -Property Length -Sum; $AllFilesizeTtl = $AllFilesizeTtl.Sum
        if ($Files2Conv.Count)
        {
            $ConvDirs2Batch = (Split-Path $Files2Conv.ConvPath -Parent) | Get-Unique | Sort-Object { $_.Length }
        }
        foreach ($file in $Files2Conv)
        {
            if ( -not(Test-Path -LiteralPath $file.ConvPath -PathType Leaf))
            {
                #Create file template
                $null = New-Item -ItemType File -Path $file.ConvPath -Force
            }
            #Do the conversion stuff here
            copy-item $file.FullName $file.ConvPath
            #if($RotImg){$null = jpegr $file.ConvPath}
            #if($MagImg){$null = magick mogrify -autocolor -autotone -enrich -autogamma $file.ConvPath}
            $file.Exported = 1
            $LoopProg += $file.Length
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
            {
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                $InnerLoopProg.Status = "Converting files: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                Write-Progress @InnerLoopProg
            }
            Write-Progress @InnerLoopProg -Completed
        }
        if ($RotImg -and $ConvDirs2Batch.Count)
        {
            Write-Host ($ConvDirs2Batch.Count.ToString() + " media folders to batch rotate!")
            $PrevInnerProgPercInt[0] = 0
            $LoopProg = 0
            $AllFilesizeTtl = $ConvDirs2Batch.Count
            foreach ($fldr in $ConvDirs2Batch)
            {
                $jpegrcmd = "jpegr -auto -s `"$fldr`""
                (Invoke-Expression $jpegrcmd) *> $null
                $LoopProg ++
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
                {
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                    $InnerLoopProg.Status = "Rotating Images: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                    Write-Progress @InnerLoopProg
                }
            }
            Write-Progress @InnerLoopProg -Completed

        }
        $FilesConverted = @(($AllPrepFiles | Where-Object -Property ConvExpected -eq 1) | Where-Object -Property Need2ConvFlag -eq 0)
        if ($FilesConverted.Count){
            $FilesConverted = $FilesConverted + @($Files2Conv | Where-Object -Property Exported -eq 1)}
        else {$FilesConverted = @($Files2Conv | Where-Object -Property Exported -eq 1)}
        $FilesConverted | Select-Object -Property Name,RelPath,ConvPath,Length,LastWriteTimeStr|
                Export-Csv -LiteralPath $ConvReportPath -NoTypeInformation
    }
    Write-Output $AllPrepFiles
}


function Update-MediaForDisplaySets
{
    param (
        $AllPrepFiles,
        $OutputSizes
    )
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue)
    {
    }
    else
    {
        throw  "ffmpeg not detected, videos will not be converted"
    }
    if (Get-Command magick -ErrorAction SilentlyContinue)
    {
    }
    else
    {
        throw  "Image Magick not detected, videos will not be converted"
    }

    $CurrInnerProgPercInt = [int32[]]::new(1);
    $PrevInnerProgPercInt = [int32[]]::new(1);
    $HashTblDateFormat = "O"
    $arval = 48000 #audio rate
    $vrate = 60000 #timescale
    $tqual = 10 #Quality to convert to for transitions, higher quality because these must be reencoded with fade to reduce loss.
    $GDefs = @{
        MaxSrtZoom = 1.5
        MinSrtZoom = 1.2
        frameRate = 0 #Configured below per set.
        audiorate = $arval
        videorate = $vrate
        tq = $tqual
        vq = $tqual #Is updated per set definition.
        ffmpegvcdcstd = "" #Configured below per set.
        ffmpegvcdctra = "" #Configured below per set.
        ffmpegaudcmd = "-c:a aac -ar $arval "
    }
    $ExpFileTupleNonZeroIdx = @{ }
    $ExpFileRelPathExists = @{ }
    #Now, for each set, run the final export tooling depending on if the file is a video or image.
    #********************************************************************************************
    #********************************************************************************************
    #********************************************************************************************
    $ImageFiles = @($AllPrepFiles | Where-Object -Property IsImg -eq 1)
    $VideoFiles = @($AllPrepFiles | Where-Object -Property IsVid -eq 1)
    $AllFiles = $ImageFiles + $VideoFiles
    #$SrcFileTuple2EntryIdx = @{ }
    #Define file existance and up-to-date definitions.
    Write-Host ($AllFiles.Count.ToString() + " media files to prepare for content presentation!")
    $idx = 0
    foreach ($file in $AllFiles)
    {
        $idx++
        $ExpFileTupleNonZeroIdx[$file.TupleVal] = $idx
        $ExpFileRelPathExists[$file.relpath] = 1
    }
    $CurrDateTime = Get-Date
    foreach ($set in $OutputSizes)
    {
        #Get group names for files according to set definition.
        #Definitions for exporting, which will be used in actual data export.
        $GDefs.frameRate = $set.FPS
        $GDefs.ffmpegvcdcstd = "-video_track_timescale $vrate -framerate $($Set.fps ) -vcodec libx265 -crf $($Set.Quality ) -colorspace 1 -preset slow -pix_fmt yuvj420p -r $( $set.FPS ) -movflags faststart "
        $GDefs.ffmpegvcdctra = "-video_track_timescale $vrate -framerate $($Set.fps ) -vcodec libx265 -crf $($GDefs.tq ) -colorspace 1 -preset slow -pix_fmt yuvj420p -r $( $set.FPS ) -movflags faststart "
        #Clear-Variable -Name "Files2Chk"
        $Files2Chk = $AllFiles
        $Files2Chk | Add-Member -MemberType NoteProperty -Name RelContPath -Value $( [string]"" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ContCreationDate -Value $( [datetime] ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ContCreationDateStr -Value $( [string] "" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ContPath -Value $( [string]"" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ContTitle -Value $( [string]"" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ImgVidPFlg -Value $( [int]0 ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name RelImgVidPath -Value $( [string]"" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ImgVidPath -Value $( [string]"" ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name InstInd -Value $( [int]0 ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name Exp2ContPath -Value $( [int]0 ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name ExpDefComplete -Value $( [int]0 ) -Force
        $Files2Chk | Add-Member -MemberType NoteProperty -Name PreRepExpIndP1 -Value $( [int]0 ) -Force
        foreach ($file in $Files2Chk)
        {
            if ($file.IsImg -and $set.ImgVidFldr.Length -and $set.PicDispTime)
            {
                $file.ImgVidPFlg = 1
            }
            $TenativeLbl = ""
            if ( $set.NameMethod.StartsWith("FldrLvl"))
            {
                $LvlIdx = [Int]$set.NameMethod.split("FldrLvl")[1]
                $Parts = $file.relpath -split '\\'
                #If the level index desired is folder, use it, else keep the label designation blank.
                if ($Parts.Count -ge ($LvlIdx + 1))
                {
                    $TenativeLbl = $Parts[$LvlIdx]
                }
            }
            else
            {
            }
            if ($TenativeLbl.Length)
            {
                $CleanedLabel = $TenativeLbl -replace "[^a-zA-Z0-9 _-]"
                $file.SelLabelGrp = $CleanedLabel
            }
        }
        #Create common definitions for set.
        Write-Host ("Exporting media for set: " + $set.XDim + " by " + $set.YDim)
        $ContFileRootPath = $set.Outpath
        $VidPacksRootPath = $ContFileRootPath + $set.ImgVidFldr
        if (-not (Test-Path -LiteralPath $ContFileRootPath -PathType Container))
        {
            New-Item -Path $ContFileRootPath -ItemType "directory" | Out-Null
        }
        if ($set.ImgVidFldr.length -and $set.PicDispTime -and (-not (Test-Path -LiteralPath $VidPacksRootPath -PathType Container)))
        {
            New-Item -Path $VidPacksRootPath -ItemType "directory" | Out-Null
        }
        $ContReportPrePath = ($ContFileRootPath + "\PreReport.csv")
        #Define files groups that should exxist so they are not reomved.
        #$PrevContInd = @{ }
        $PrevFileSet = @{ }
        #$selfilename = Split-Path -Path $ContReportPrePath -Leaf
        $PrevFileSet[$ContReportPrePath] = 1
        #Remove old content items if they are not up to date anymore.
        Write-Host ("Checking report file to verify integrity and determine which files need to be updated...")
        if (Test-Path -Path $ContReportPrePath)
        {
            $PrevContProps = Import-Csv -LiteralPath $ContReportPrePath
            $PrevContProps| Add-Member -MemberType NoteProperty -Name ContCreationDate -Value $([DateTime])  -Force
            Write-Host ("Checking " + $PrevContProps.Count.ToString() + " old entries...")
            $RepIdxP1 = 0
            foreach ($SelProp in $PrevContProps)
            {
                $fileU2D = 0
                $RepIdxP1++
                #Check to see if all properties in the report are up-to-date.
                $DateTimeVal = [datetime]::ParseExact($SelProp.LastWriteTimeStr, $HashTblDateFormat, $null)
                $datekey = [System.ValueTuple[string, long, datetime]]::new(
                        $SelProp.RelPath, $SelProp.Length, $DateTimeVal)

                if($SelProp.RelContPath.Endswith("mp4")){

                #write-host($SelProp.RelContPath)
                }
                if ($SelProp.RelContPath.Length)
                {
                    #If the file exists, check the creation date
                    $FullContPath = $ContFileRootPath + "\" + $SelProp.RelContPath
                    if (Test-Path $FullContPath -PathType Leaf)
                    {
                        $SelCreationTime = [datetime]::ParseExact($SelProp.ContCreationDateStr, $HashTblDateFormat, $null)
                        $SelProp.ContCreationDate = $SelCreationTime
                        #If the creation date matches, check to see if the video image is up-to-date
                        if ($SelCreationTime -eq (Get-Item -LiteralPath "$FullContPath").CreationTime)
                        {
                            #See if a corresponding file index exists
                            if ($ExpFileTupleNonZeroIdx[$datekey])
                            {
                                #See if there should be a corresponding image path.
                                if ($Files2Chk[$ExpFileTupleNonZeroIdx[$datekey]-1].ImgVidPFlg)
                                {
                                    if ($SelProp.RelImgVidPath.Length)
                                    {
                                        $FullImgPath = $ContFileRootPath + $SelProp.RelImgVidPath
                                        if (Test-Path $FullImgPath -PathType Leaf)
                                        {
                                            #If the creation date matches, check to see if the video image is up-to-date
                                            if ($SelCreationTime = (Get-Item -LiteralPath "$FullImgPath").CreationTime)
                                            {
                                                #If the creation date matches, check to see if the video image is up-to-date
                                                if ($SelCreationTime = (Get-Item -LiteralPath "$FullImgPath").CreationTime)
                                                {
                                                    $fileU2D = 1
                                                    $PrevFileSet[$FullImgPath] = 1
                                                }
                                            }
                                        }
                                    }

                                }
                                #If the files exists, but there should not be an image video, claim this index.
                                else
                                {
                                    $fileU2D = 1
                                }
                            }
                        }
                    }
                }
                #Set the index and group index for reference.
                if ($fileU2D)
                {
                    $Files2Chk[$ExpFileTupleNonZeroIdx[$datekey]-1].PreRepExpIndP1 = $RepIdxP1
                    $Files2Chk[$ExpFileTupleNonZeroIdx[$datekey]-1].InstInd = [Int] $SelProp.InstInd
                    $PrevFileSet[$FullContPath] = 1
                }
            }
        }
        #Remove files from the folder which didn't belong to the database.
        $AllCurrContFiles = @(Get-ChildItem -LiteralPath $ContFileRootPath -Recurse -File)
        $AllCurrContFiles | Add-Member -MemberType NoteProperty -Name RemFlag -Value $( [int]0 )  -Force
        foreach ($ContFile in $AllCurrContFiles)
        {
            #If this is a transition file and the core file exists, assume all three can stay (don't tag for removal)
            $PathLen = $ContFile.FullName.Length
            if ($ContFile.Fullname.EndsWith("mp4srt") -or $ContFile.Fullname.EndsWith("mp4end"))
            {
                $CoreName = $ContFile.Fullname.Substring(0, ($PathLen - 3))
            }
            else
            {
                $CoreName = $ContFile.Fullname
            }
            if ($PrevFileSet[$CoreName])
            {
            }#If file should exist, do nothing.
            else
            {
                $ContFile.RemFlag = 1
            }
        }
        $CurrContFiles2Rem = @($AllCurrContFiles| Where-Object -Property RemFlag -eq 1)
        Write-Host ("Removing " + $CurrContFiles2Rem.Count.ToString() + " file(s) that were not expectedor out of date...")
        foreach ($ContFile in $CurrContFiles2Rem)
        {
            remove-item -LiteralPath $ContFile.FullName -Force
        }
        #Get index of current content items

        #Group files
        $FileGroups = @($Files2Chk | Group-Object -Property SelLabelGrp)
        Write-Host ("Checking " + $FileGroups.Count.ToString() + " group(s)...")
        foreach ($grp in $FileGroups)
        {
            $InstIdxSet = @{ }
            foreach ($file in ($grp| Select-Object -ExpandProperty Group))
            {
                #If a previous index already exists for this file, store it.
                if ($file.InstInd)
                {
                    $InstIdxSet[$file.InstInd] = 1
                }
            }
            #Populate any missing indexes for the group
            $GrpIdx = 1;
            foreach ($file in ($grp| Select-Object -Expand Group))
            {
                #Also set all the corresponding information for that index.
                if ($file.InstInd)
                {
                    #It's already been exported, so set the flag.
                    $file.ExpDefComplete = 1
                    $file.ContCreationDate = $PrevContProps[$file.PreRepExpIndP1-1].ContCreationDate
                    $file.RelContPath      = $PrevContProps[$file.PreRepExpIndP1-1].RelContPath
                    $file.RelImgVidPath    = $PrevContProps[$file.PreRepExpIndP1-1].RelImgVidPath
                }
                else
                {
                    #Incriment index till one is found that is not used.
                    if ($InstIdxSet.Count)
                    {
                        while ($InstIdxSet[$GrpIdx])
                        {
                            $GrpIdx++
                        }
                    }
                    #Once it's found, set it and set the map to indicate the index has been used.
                    $file.InstInd = $GrpIdx
                    $file.ContCreationDate = $CurrDateTime
                    $InstIdxSet[$GrpIdx] = 1
                    #Set the flag to export the content, since it's new.
                    $file.Exp2ContPath = 1
                }
                #Finally, convert datestr.
                $file.ContCreationDateStr = $file.ContCreationDate.ToString($HashTblDateFormat)

            }
        }
        #Ungroup all files back to the original variable.
        $Files2Chk = ($FileGroups| Select-Object -Expand Group)

        #Create the export path and perform the export.
        Write-Host ("Checking " + ($Files2Chk | Where-Object -Property Exp2ContPath -eq 1).Count.ToString() + " for content definitions...")
        foreach ($file in @($Files2Chk | Where-Object -Property Exp2ContPath -eq 1))
        {
            if ($file.SelLabelGrp.Length)
            {
                $Designator = $file.SelLabelGrp + "-" + $file.InstInd.ToString('00000')}
            else{ $Designator = $file.InstInd.ToString('00000') }
            $file.RelContPath = $Designator + $file.ContExt
            $file.ContPath = ($ContFileRootPath + "\" + $file.RelContPath)
            $file.ContTitle = $Designator
            #If the intent is also to convert the picture to a video, also define the path of the video to export to.
            try
            {
                if ($file.IsImg -and $set.ImgVidFldr.Length -and $set.PicDispTime)
                {
                    $file.RelImgVidPath = ($set.ImgVidFldr + "\" + $Designator + ".mp4")
                    $file.ImgVidPath = ($ContFileRootPath + $file.RelImgVidPath)
                }
                #It's already been exported, so set the flag.
                $file.ExpDefComplete = 1
            }
            catch
            {
            }
        }
        #Create report placeholder if it doesn't exist
        if (Test-Path -Path $ContReportPrePath)
        {
        }
        else
        {
            $null = New-Item -ItemType File -Path $ContReportPrePath -Force
        }
        ($Files2Chk | Where-Object -Property ExpDefComplete -eq 1) | Select-Object -Property RelPath,Length,LastWriteTimeStr,RelContPath,RelImgVidPath,ContCreationDateStr,InstInd|
                Export-Csv -LiteralPath $ContReportPrePath -NoTypeInformation
        #Save the prep file

        #Process the files

        $PrevInnerProgPercInt[0] = 0
        $LoopProg = 0
        $ShowProg = 0
        $RunSeries = 1
        $funcDef = ${function:New-VideoZoomedOutFromPic}.ToString()
        $AllFilesizeTtl = ($Files2Chk| Where-Object -Property Exp2ContPath -eq 1) | Measure-Object -Property Length -Sum; $AllFilesizeTtl = $AllFilesizeTtl.Sum
        Write-Host ("Exporting " + ($Files2Chk | Where-Object -Property Exp2ContPath -eq 1).Count.ToString() + " files...")
        #(($Files2Chk| Where-Object -Property Exp2ContPath -eq 1)) | ForEach-Object -Parallel{
        (($Files2Chk| Where-Object -Property Exp2ContPath -eq 1)) | ForEach-Object{
            if ($RunSeries) {
                $file = $_
                $XDim = $set.XDim
                $YDim = $set.YDim
                $FadeTime = $set.FadeTime
                $PicDispTime = $set.PicDispTime
                $VidPack = $set.VidPack
                $framerate =     $GDefs.framerate
                $MinSrtZoom =    $GDefs.MinSrtZoom
                $MaxSrtZoom =    $GDefs.MaxSrtZoom
                $ffmpegvcdcstd = $GDefs.ffmpegvcdcstd
                $ffmpegvcdctra = $GDefs.ffmpegvcdctra
                $ffmpegaudcmd =  $GDefs.ffmpegaudcmd
                $CurrDateTime =  $CurrDateTime}
            else{
                ${function:New-VideoZoomedOutFromPic} = $using:funcDef
                $file = $_
                $XDim = $using:set.XDim
                $YDim = $using:set.YDim
                $FadeTime = $using:set.FadeTime
                $PicDispTime = $using:set.PicDispTime
                $VidPack = $using:set.VidPack
                $framerate = $using:GDefs.framerate
                $MinSrtZoom = $using:GDefs.MinSrtZoom
                $MaxSrtZoom = $using:GDefs.MaxSrtZoom
                $ffmpegvcdcstd = $using:GDefs.ffmpegvcdcstd
                $ffmpegvcdctra = $using:GDefs.ffmpegvcdctra
                $ffmpegaudcmd = $using:GDefs.ffmpegaudcmd
                $CurrDateTime = $using:CurrDateTime}
            $whdispratio = $XDim/$YDim
            write-host "Building content for file index: $( $file.FileIdx ) - $( $file.Name )..."
            #write-host "Codec export definition: $ffmpegvcdcstd"
            #Create common definitions.
            $SelFadeFrames = [Int]($FadeTime*$framerate)
            $SelFadeTime = ($SelFadeFrames/$framerate)
            $SelNormFrames = [Int]($PicDispTime*$framerate)
            $SelNormTime = ($SelNormFrames/$framerate)
            try
            {
                if ($file.IsImg)
                {
                    $ScaleWIM = 1
                    $image = New-Object -ComObject Wia.ImageFile
                    $image.loadfile($file.ConvPath)
                    $whimgratio = $image.Width/$image.Height
                    #If we're converting the picture to an image, it must oversized substantially to
                    #allow smooth zooming.  Keeping a whole number in case it is rendered to the nominal dimensions.
                    if (($file.ImgVidPath.length) -and ($ScaleWIM -ne 1))
                    {
                        $contw = [math]::Ceiling($XDim*4*$MaxSrtZoom)
                        $conth = [math]::Ceiling($YDim*4*$MaxSrtZoom)
                    }
                    #If width is greater, limit this dimension for resize.
                    elseif ($whimgratio -gt $whdispratio)
                    {
                        $contw = $XDim
                        $conth = ($XDim/$whimgratio)
                        $border = [Math]::Ceiling(($image.Width/$whdispratio - $image.Height)/2)
                        $borderdef ="$($border.ToString())x0"
                    }
                    else
                    {
                        $conth = $YDim
                        $contw = ($YDim*$whimgratio)
                        $border = [Math]::Ceiling(($image.Height*$whdispratio - $image.Width)/2)
                        $borderdef = "0x$($border.ToString())"
                    }
                    $wint = $contw -as [Int]
                    $hint = $conth -as [Int]
                    $SizeStr = $wint.ToString() + "x" + $hint.ToString()
                    $SizeStr2 = $XDim.ToString() + ":" + $YDim.ToString()
                    $SizeOut = $XDim.ToString() + "x" + $YDim.ToString()
                    $quality = 95
                    if ($file.ImgVidPath.length)
                    {
                        $ExpCmd = "-compose Copy -gravity center -extent  $SizeStr -quality $quality "
                        $PstCmd = "-compose Copy -gravity center -extent  $SizeOut -quality $quality "
                    }
                    else
                    {
                        $ExpCmd = ""
                        $PstCmd = ""
                    }
                    #magick input.jpg -resize 800x600 -background black -compose Copy \
                    #-gravity center -extent 800x600 -quality 92 output.jpg#Optional / future explore:
                    #$null = magick $file.ConvPath -auto-gamma -auto-level -white-balance -resize ($contw.ToString()+"x"+$conth.ToString()+">") $file.ContPath
                    #
                    $IMCmd1 = "magick `"$( $file.ConvPath )`" -auto-orient -resize $SizeStr -quality $($quality.ToString() ) -background black "
                    $IMCmdOut = "`"$( $file.ContPath )`""
                    $IMCmd = $IMCmd1 + $ExpCmd + $IMCmdOut
                    (Invoke-Expression $IMCmd) *> $null
                    [System.IO.File]::SetCreationTime( "$( $file.ContPath )", $CurrDateTime)
                    if ($file.ImgVidPath.length)
                    {
                        #Write-Host("**************************L1****************************")
                        $FullImgDur = $FadeTime*2 + $PicDispTime
                        $NFramesTrn = ($FadeTime*$FrameRate) -as [Int]
                        $NFramesStd = ($PicDispTime*$FrameRate) -as [Int]
                        $NFramesExp = ($FullImgDur*$FrameRate) -as [Int]
                        #Zoompan configuration here.
                        $SetSrtZoom = Get-Random -Minimum $MinSrtZoom -Maximum $MaxSrtZoom
                        $XRatio = Get-Random -Minimum 0.0 -Maximum 1.0
                        $YRatio = Get-Random -Minimum 0.0 -Maximum 1.0
                        $ZoomRate = ($SetSrtZoom - 1)/$NFramesExp
                        $SetNomZoom = $SetSrtZoom - ($ZoomRate*$SelFadeFrames)
                        $SetEndZoom = $SetNomZoom - ($ZoomRate*$SelNormFrames)

                        #Write-Host("**************************L2****************************")
                        $ffmpegCmd1 = "ffmpeg -y "
                        $ffmpegCmdA = "-f lavfi -i anullsrc  -loop 1 -f image2 "
                        $ffmpegCmdV1 = "-framerate " + $frameRate + " -i `"$( $file.ContPath )`" "
                        $SrtffmpegCmdV2 = "-t $SelFadeTime "
                        $Srtfiltercfg1 = "-filter_complex `"[1:v]zoompan=z='if(gte(in,1),min(pzoom-$ZoomRate,1.5),$SetSrtZoom)'"
                        $ffmpegCmdV2 = "-t $SelNormTime "
                        $filtercfg1 = "-filter_complex `"[1:v]zoompan=z='if(gte(in,1),min(pzoom-$ZoomRate,1.5),$SetNomZoom)'"
                        $EndffmpegCmdV2 = "-t $SelFadeTime "
                        $Endfiltercfg1 = "-filter_complex `"[1:v]zoompan=z='if(gte(in,1),min(pzoom-$ZoomRate,1.5),$SetEndZoom)'"
                        $filtercfgX = ":x='($wint*$XRatio*(1.0-1/zoom))'"
                        $filtercfgY = ":y='$hint*$YRatio*(1.0-1/zoom)'"
                        $filtercfg2 = ":d=1:fps=$frameRate`:s=$SizeOut`" "

                        #Write-Host("**************************L3****************************")
                        $ffmpegOutSrt = "-map 0:a -map 1:v -s $SizeStr2 -f 'mp4' `"$($file.ImgVidPath)srt`""
                        $ffmpegOutNom = "-map 0:a -map 1:v -s $SizeStr2 -f 'mp4' `"$($file.ImgVidPath)`""
                        $ffmpegOutEnd = "-map 0:a -map 1:v -s $SizeStr2 -f 'mp4' `"$($file.ImgVidPath)end`""
                        #Write-Host("**************************L4****************************")
                        $ffmpegCmdSrt = $ffmpegCmd1 + $ffmpegCmdA + $ffmpegCmdV1 + $SrtffmpegCmdV2 `
                        + $Srtfiltercfg1 + $filtercfgX + $filtercfgY + $filtercfg2 `
                        + $ffmpegaudcmd + $ffmpegvcdctra + $ffmpegOutSrt

                        #Write-Host("**************************L5****************************")
                        $ffmpegCmdNom = $ffmpegCmd1 + $ffmpegCmdA + $ffmpegCmdV1 + $ffmpegCmdV2 `
                        + $filtercfg1 + $filtercfgX + $filtercfgY + $filtercfg2 `
                        + $ffmpegaudcmd + $ffmpegvcdcstd + $ffmpegOutNom
                        $ffmpegCmdEnd = $ffmpegCmd1 + $ffmpegCmdA + $ffmpegCmdV1 + $EndffmpegCmdV2 `
                        + $Endfiltercfg1 + $filtercfgX + $filtercfgY + $filtercfg2 `
                        + $ffmpegaudcmd + $ffmpegvcdctra + $ffmpegOutEnd

                        #Write-Host("**************************L8****************************")
                        #Execute the FFmpeg command
                        #write-host "ffmpeg command for image conversion:"
                        #write-host $ffmpegcmd
                        #$ffmpegCmdSrt | Out-File -FilePath "$($file.ImgVidPath)srtcmd"
                        if($ScaleWIM)
                        {
                            write-host "About to call function..."
                            New-VideoZoomedOutFromPic $file.ContPath $wint $hint $borderdef $SetSrtZoom $ZoomRate 0 $XRatio $YRatio $NFramesTrn  $NFramesStd $XDim  $YDim ($file.ImgVidPath + "srt") $file.ImgVidPath ($file.ImgVidPath + "end")
                        }else{
                            (Invoke-Expression $ffmpegCmdSrt) *> $null
                            (Invoke-Expression $ffmpegCmdEnd) *> $null
                            (Invoke-Expression $ffmpegCmdNom) *> $null
                        }
                        #If each file has content, set the creation time.

                        [System.IO.File]::SetCreationTime( "$($file.ImgVidPath)srt", $CurrDateTime)
                        [System.IO.File]::SetCreationTime( "$($file.ImgVidPath)end", $CurrDateTime)
                        [System.IO.File]::SetCreationTime( "$($file.ImgVidPath)", $CurrDateTime)
                        Write-Host("**************************L9****************************")
                        #Now rewrite the image again with a smaller size, to save on space.
                        $IMCmd1 = "magick `"$( $file.ConvPath )`" -auto-orient -resize $SizeOut -quality $($quality.ToString() ) -background black "
                        $IMCmdOut = "`"$( $file.ContPath )`""
                        $IMCmd = $IMCmd1 + $PstCmd + $IMCmdOut
                        (Invoke-Expression $IMCmd) *> $null
                        [System.IO.File]::SetCreationTime( "$( $file.ContPath )", $CurrDateTime)
                    }
                }
                elseif($file.IsVid)
                {
                    $VPrams = ffprobe -v error -show_streams -select_streams v:0 -of ini $file.FullName
                    $VWidth = [Int]::0
                    $VWidth = [Int]::0
                    $Rotation = [Int]::0
                    $Duration = 0.0
                    if ($VPrams.Count -gt 1)
                    {
                        foreach ($Pram in $VPrams)
                        {
                            if ( $Pram.StartsWith("width="))
                            {
                                $PreWidth = [Int]::Parse($Pram.split('width=')[1])
                            }
                            if ( $Pram.StartsWith("height="))
                            {
                                $PreHeight = [Int]::Parse($Pram.split('height=')[1])
                            }
                            if ( $Pram.StartsWith("rotation="))
                            {
                                $Rotation = [Int]::Parse($Pram.split('rotation=')[1])
                            }
                            if ( $Pram.StartsWith("duration="))
                            {
                                $Duration = [Decimal]::Parse($Pram.split('duration=')[1])
                            }
                        }
                        #If video is not oriented according to it's resolution, assume  a 90 deg turn.
                        if ($Rotation%180 -ne 0)
                        {
                            $VWidth = $PreHeight
                            $VHeight = $PreWidth
                        }
                        else
                        {
                            $VWidth = $PreWidth
                            $VHeight = $PreHeight
                        }
                        $whvidratio = $VWidth/$VHeight
                        #If width is greater, limit this dimension for resize.
                        if ($whvidratio -gt $whdispratio)
                        {
                            $contw = [int]$XDim
                            $conth = [int]($XDim/$whvidratio)
                        }
                        else
                        {
                            $conth = [int]$YDim
                            $contw = [int]($YDim*$whvidratio)
                        }
                        #If video packing, need to set the pad limits
                        if ($VidPack)
                        {
                            $Sides = $XDim - $contw;
                            $TopBot = $YDim - $conth;
                            $LBand = [math]::Floor($Sides/2)
                            $TBand = [math]::Floor($TopBot/2)
                            $RBand = $LBand
                            $BBand = $TBand

                            if ($Sides%2)
                            {
                                $RBand = $LBand + 1
                            }
                            if (($TopBot%2) -ge 1)
                            {
                                $BBand = $TBand + 1
                            }
                            $wint = $XDim -as [Int]
                            $hint = $YDim -as [Int]
                        }
                        else
                        {
                            $LBand = 0
                            $TBand = 0
                            $RBand = 0
                            $BBand = 0
                            if (($contw%2) -ge 1)
                            {
                                $contw = [math]::Ceiling($contw)
                            }
                            else
                            {
                                $contw = [math]::Floor($contw)
                            }
                            if (($conth%2) -ge 1)
                            {
                                $conth = [math]::Ceiling($conth)
                            }
                            else
                            {
                                $conth = [math]::Floor($conth)
                            }
                            $wint = $contw -as [Int]
                            $hint = $conth -as [Int]
                        }
                        $sizestr = $wint.ToString() + ":" + $hint.ToString()
                        #If bordering is required.
                        if ($LBand -or $RBand -or $TBand -or $BBand)
                        {
                            $PadOpt = ",pad=" + $sizestr + "`:$LBand`:$TBand,setsar=1"
                        }
                        else
                        {
                            $PadOpt = ""
                        }
                        $nomdur = $Duration - ($SelFadeTime*2)
                        $endsrt = $Duration - $SelFadeTime
                        if ($SelFadeTime -lt ($nomdur/2)){$AFd = $SelFadeTime }
                        else{$AFd = ($nomdur/2)}
                        $AOtOf = $nomdur - $AFd
                        $ffmpeginputsrt = "ffmpeg -y -t $SelFadeTime -i `"$( $file.FullName )`" "
                        $ffmpeginputnom = "ffmpeg -y -ss $SelFadeTime -t $nomdur -i `"$( $file.FullName )`" "
                        $ffmpeginputend = "ffmpeg -y -ss $endsrt -t $SelFadeTime -i `"$( $file.FullName )`" "
                        $ffmpegvidfilt = "scale=$wint`:$hint`:force_original_aspect_ratio=decrease$PadOpt"
                        $ffmpegvidcmd1 = "-vf "+ $ffmpegvidfilt
                        $ffmpegcmdsrt = $ffmpeginputsrt + $ffmpegvidcmd1 + " " + $ffmpegaudcmd + $ffmpegvcdctra + " -movflags faststart -f 'mp4' `"$( $file.ContPath)srt`""
                        $ffmpegcmdend = $ffmpeginputend + $ffmpegvidcmd1 + " " + $ffmpegaudcmd + $ffmpegvcdctra + " -movflags faststart -f 'mp4' `"$( $file.ContPath)end`""
                        $ffmpegcmdnom = $ffmpeginputnom + "-filter_complex `"[0:v]$ffmpegvidfilt`;[0:a]afade=t=in:st=0:d=$AFd,afade=t=out:st=$AOtOf`:d=$AFd`" " + $ffmpegaudcmd + $ffmpegvcdcstd + " -f 'mp4' `"$( $file.ContPath)`""

                        write-host "T0"
                        $ffmpegcmdnom | Out-File -FilePath "$($file.ContPath)nomcmd"
                        $ffmpegcmdsrt | Out-File -FilePath "$($file.ContPath)srtcmd"
                        $ffmpegcmdend | Out-File -FilePath "$($file.ContPath)endcmd"
                        (Invoke-Expression $ffmpegcmdsrt) *> $null
                        (Invoke-Expression $ffmpegcmdend) *> $null
                        (Invoke-Expression $ffmpegcmdnom) *> $null
                        write-host "T1"
                        [System.IO.File]::SetCreationTime( "$($file.ContPath)srt", $CurrDateTime)
                        [System.IO.File]::SetCreationTime( "$($file.ContPath)end", $CurrDateTime)
                        [System.IO.File]::SetCreationTime( "$($file.ContPath)", $CurrDateTime)
                        write-host "T2"

                        #write-host "ffmpeg command for video conversion:"
                        #write-host $ffmpegcmd
                        (Invoke-Expression $ffmpegcmd) *> $null
                        $file.ExpDefComplete = 1
                        $_.ExpDefComplete = 1

                    }
                }
            }
            catch
            {
            }
            if ($ShowProg)
            {
                $LoopProg += $file.Length
                $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
                if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
                {
                    $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                    $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                    $InnerLoopProg.Status = "Creating content files: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                    Write-Progress @InnerLoopProg
                }
            }
        }
        #} -ThrottleLimit 4
        #4 - 6.5 min
        #4 - 3.3 min on Desktop
        #1 - 5.5 min on desktop
        #2 - 3.6 min on desktop
        #8 - 3 min on desktop
    }
}