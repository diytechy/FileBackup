function New-MediaForDisplay
{
    param (
        [string]$PrepFileRootPath,
        [string]$ConvFileRootPath,
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
    $MaxSrtZoom = 1.3
    $MinSrtZoom = 1.1
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
    #************************************************************
    #******************Step 2, convert images.*******************
    #************************************************************
    $AllPrepFiles = @(Get-ChildItem -LiteralPath $PrepFileRootPath -Recurse -File)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name RelPath -Value $([string])
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvPath -Value $([string])
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ContExt -Value $([string])
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name LastWriteTimeStr -Value $([string])
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name SelLabelGrp -Value $([string])
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name Need2ConvFlag -Value $([int]0)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name ConvExpected -Value $([int]0)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsImg -Value $([int]0)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name IsVid -Value $([int]0)
    $AllPrepFiles | Add-Member -MemberType NoteProperty -Name TupleVal -Value [System.ValueTuple[string, long, datetime]]
    if($AllPrepFiles.Count)
    {
        $PrpL = $PrepFileRootPath.Length
        $ConvReportPath = ($ConvFileRootPath + "\Report.csv")
        $PrevConvMap = @{}
        $CurrConvMap = @{}
        if(Test-Path -LiteralPath $ConvReportPath)
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
                $PrevProp.TupleVal = $key
                $PrevConvMap[$key] = 1
            }
        }
        Write-Host ($AllPrepFiles.Count.ToString() + " files to get conversion attributes for...")
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
            $file.TupleVal = $datekey
            $IncChk = 0
            foreach($type in $ImgTypes){
                if($file.Name.EndsWith($type)){
                    $file.ConvExpected = 1
                    $file.IsImg = 1
                    $file.ContExt = ".jpg"
                    $IncChk = 1
                    #Set tuple for current conversion map, for removal reference.
                    $CurrConvMap[$datekey] = 1
                }
            }
            foreach($type in $VidTypes){
                if($file.Name.EndsWith($type)){
                    $file.IsVid = 1
                    $file.ContExt = ".mp4"
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
        #Remove items that shouldn't be there.  Not really necessary but good to cleanup
        Write-Host ("Checking for old files to remove")
        foreach ($PrevProp in $PrevConvProps){
            if($CurrConvMap[$PrevProp.TupleVal]) {} #Do nothing if file should exist.
            #elseif(Test-Path -LiteralPath $PrevProp.ConvPath){} #Do nothing if there is no path information.
            elseif(Test-Path -Path $PrevProp.ConvPath){
                $PrevProp.RemoveFlag = 1
            }
        }
        $OldPrepFiles2Rem  = ($AllPrepFiles | Where-Object -Property RemoveFlag -eq 1)
        Write-Host ($OldPrepFiles2Rem.Count.ToString() + " old media files to remove!")
        foreach($PrevProp in $OldPrepFiles2Rem)
        {
            remove-item -LiteralPath $PrevProp.ConvPath -Force
        }
        Write-Host ($Files2Conv.Count.ToString() + " media files to convert!")
        $PrevInnerProgPercInt[0] = 0
        $LoopProg = 0
        $AllFilesizeTtl = $Files2Conv | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum
        $Files2Conv | Add-Member -MemberType NoteProperty -Name Complete -Value $([int]0)
        if($Files2Conv.Count){
            $ConvDirs2Batch = (Split-Path $Files2Conv.ConvPath -Parent) | Get-Unique | Sort-Object { $_.Length }
        }
        foreach ($file in $Files2Conv)
        {
            if(Test-Path -LiteralPath $file.ConvPath){}#Do nothing
            else{ #Create file
                $null = New-Item -ItemType File -Path $file.ConvPath -Force
            }
            #Do the conversion stuff here
            copy-item $file.FullName $file.ConvPath
            #if($RotImg){$null = jpegr $file.ConvPath}
            #if($MagImg){$null = magick mogrify -autocolor -autotone -enrich -autogamma $file.ConvPath}
            $file.Complete = 1
            $LoopProg += $file.Length
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
            {
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                $InnerLoopProg.Status = "Converting files: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                Write-Progress @InnerLoopProg
            }
        }
        if($RotImg -and $ConvDirs2Batch.Count ){
            Write-Host ($ConvDirs2Batch.Count.ToString() + " media folders to batch rotate!")
            $PrevInnerProgPercInt[0] = 0
            $LoopProg = 0
            $AllFilesizeTtl = $ConvDirs2Batch.Count
            foreach ($fldr in $ConvDirs2Batch)
            {
                $null = jpegr -auto -s $fldr
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

        }
        #Finally save off report of converted files.
        #$ConvReportPath
        $ExpectedFiles | Select-Object -Property Name,RelPath,ConvPath,Length,LastWriteTimeStr|
                Export-Csv -LiteralPath $ConvReportPath -NoTypeInformation
        #Now, for each set, run the final export tooling depending on if the file is a video or image.
        $ImageFiles = @($AllPrepFiles | Where-Object -Property IsImg -eq 1)
        $VideoFiles = @($AllPrepFiles | Where-Object -Property IsVid -eq 1)
        $AllFiles = $ImageFiles + $VideoFiles
        Write-Host ($AllFiles.Count.ToString() + " media files to prepare for content presentation!")
        foreach ($set in $OutputSizes){
            $Files2Chk = $AllFiles
            $Files2Chk | Add-Member -MemberType NoteProperty -Name ContPath -Value $( [string] )
            $Files2Chk | Add-Member -MemberType NoteProperty -Name ContTitle -Value $( [string] )
            $Files2Chk | Add-Member -MemberType NoteProperty -Name ImgVidPath -Value $( [string] )
            $Files2Chk | Add-Member -MemberType NoteProperty -Name InstInd -Value $( [int] 0)
            $Files2Chk | Add-Member -MemberType NoteProperty -Name Exp2ContPath -Value $( [int] 0)
            $Files2Chk | Add-Member -MemberType NoteProperty -Name ExpContSuccess -Value $( [int] 0)
            $FileGroups = $Files2Chk | Group-Object -Property SelLabelGrp
            $whdispratio = $set.XDim/$set.YDim
            Write-Host ("Width to height ratio: "+$whdispratio.ToString())
            #Convert all logs accordingly
            Write-Host ("Exporting media for set: " + $set.XDim + " by "  + $set.YDim)
            $ContFileRootPath = $set.Outpath
            $VidPacksRootPath = $ContFileRootPath + $set.ImgVidFldr
            if (-not(Test-Path -LiteralPath $ContFileRootPath -PathType Container))
            {New-Item -Path $ContFileRootPath -ItemType "directory"}
            if ($set.ImgVidFldr.length -and $set.PicDispTime -and (-not(Test-Path -LiteralPath $VidPacksRootPath -PathType Container)))
            {New-Item -Path $VidPacksRootPath -ItemType "directory"}
            $ContReportPath = ($ContFileRootPath + "\Report.csv")
            $ContReportPrePath = ($ContFileRootPath + "\PreReport.csv")
            $PrevContInd = @{}
            $PrevFileSet = @{}
            #Remove old content items if they are not up to date anymore.
            Write-Host ("Removing old files if needed")
            if(Test-Path -Path $ContReportPath){
                $PrevContProps = Import-Csv -LiteralPath $ContReportPath
                $PrevContProps | Add-Member -MemberType NoteProperty -Name RemoveFlg -Value $( [int] 0)
                Write-Host ("Checking "+$PrevContProps.Count.ToString()+" old entries...")
                #Remove files from the database which don't have matching attributes to the current definitions
                foreach($SelProp in $PrevContProps){
                    $DateTimeVal = [datetime]::ParseExact($SelProp.LastWriteTimeStr, $HashTblDateFormat, $null)
                    $datekey = [System.ValueTuple[string, long, datetime]]::new(
                            $SelProp.RelPath, $SelProp.Length, $DateTimeVal)
                    $PrevContInd[$datekey] = $SelProp.GrpInstance
                    $selfilename = Split-Path -Path $SelProp.ContPath -Leaf
                    $PrevFileSet[$selfilename] = 1
                    if($CurrConvMap[$datekey]){}#If exists, do nothing
                    #Else remove it.
                    elseif(Test-Path -Path $SelProp.ContPath)
                    {
                       $SelProp.RemoveFlg = 1
                    }
                }
                $PrevContProps2Rem = ($PrevContProps | Where-Object -Property RemoveFlg -eq 1)
                Write-Host ($PrevContProps2Rem.Count.ToString()+" old entries set to remove...")
                foreach($SelProp in $PrevContProps2Rem){
                    if ($SelProp.ContPath.Length -and (Test-Path -LiteralPath $SelProp.ContPath -PathType Leaf))
                    {
                        Remove-Item -LiteralPath $SelProp.ContPath -Force
                    }
                    if ($SelProp.ImgVidPath.Length -and (Test-Path -LiteralPath $SelProp.ImgVidPath -PathType Leaf))
                    {
                        Remove-Item -LiteralPath $SelProp.ImgVidPath -Force
                    }
                }
            }
            #Remove files from the folder which didn't belong to the database.
            $AllCurrContFiles = @(Get-ChildItem -LiteralPath $ContFileRootPath -Recurse -File)
            foreach($ContFile in $AllCurrContFiles){
                if($PrevFileSet[$ContFile.Name]){}#If file should exist, do nothing.
                else{remove-item -LiteralPath $ContFile.FullName -Force}
            }
            #Get index of current content items
            Write-Host ("Checking "+$FileGroups.Count.ToString()+" groups...")
            foreach($grp in $FileGroups)
            {
                $InstIdxSet = @{}
                foreach ($file in ($grp| Select-Object -Expand Group))
                {
                    #
                    $datekey = [System.ValueTuple[string, long, datetime]]::new(
                            $file.RelPath, $file.Length, $file.LastWriteTime)
                    #If a previous index already exists for this file, store it.
                    if ($PrevContInd.Count -and $PrevContInd[$datekey])
                    {
                        $file.InstInd = $PrevContInd[$datekey]
                        $InstIdxSet[$file.InstInd] = 1
                    }
                }
                #Populate any missing indexes for the group
                $GrpIdx = 1;
                foreach ($file in ($grp| Select-Object -Expand Group) )
                {
                    if ($file.InstInd )
                    {
                        #It's already been exported, so set the flag.
                        $file.ExpContSuccess = 1
                    }
                    else
                    {
                        #Incriment index till one is found that is not used.
                        if($InstIdxSet.Count){
                            while($InstIdxSet[$GrpIdx]){$GrpIdx++}
                        }
                        #Once it's found, set it and set the map to indicate the index has been used.
                        $file.InstInd = $GrpIdx
                        $InstIdxSet[$GrpIdx] = 1
                        #Set the flag to export the content, since it's new.
                        $file.Exp2ContPath = 1
                    }

                }
            }
            #Ungroup all files
            $Files2GetCont = ($FileGroups| Select-Object -Expand Group)
            #Create the export path and perform the export.
            Write-Host ("Checking "+$Files2GetCont.Count.ToString()+" for content definitions...")
            foreach ($file in ($Files2GetCont| Where-Object -Property Exp2ContPath -eq 1))
            {
                $file.ContPath  = ($ContFileRootPath+"\"+$file.SelLabelGrp+"-"+$file.InstInd.ToString('0000')+$file.ContExt)
                $file.ContTitle = ($ContFileRootPath+"\"+$file.SelLabelGrp+"-"+$file.InstInd.ToString())
                #If the intent is also to convert the picture to a video, also define the path of the video to export to.
                try
                {
                    if ($file.IsImg -and $set.ImgVidFldr.Length -and $set.PicDispTime)
                    {
                        $file.ImgVidPath = ($ContFileRootPath + $set.ImgVidFldr + "\" + $file.SelLabelGrp + "-" + $file.InstInd.ToString('0000')+".mp4")
                    }
                }
                catch{}
            }
            #Create report placeholder if it doesn't exist
            if (Test-Path -Path $ContReportPrePath){}
            else {$null = New-Item -ItemType File -Path $ContReportPrePath -Force}
            $Files2GetCont | Select-Object -Property Name,RelPath,FullName,ConvPath,Length,LastWriteTimeStr,ContPath,ImgVidPath|
                Export-Csv -LiteralPath $ContReportPrePath -NoTypeInformation
            #Save the prep file

            #Process the files

            $PrevInnerProgPercInt[0] = 0
            $LoopProg = 0
            $AllFilesizeTtl = ($Files2GetCont| Where-Object -Property Exp2ContPath -eq 1) | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum
            Write-Host ("Exporting "+$Files2GetCont.Count.ToString()+" files...")
            foreach ($file in ($Files2GetCont| Where-Object -Property Exp2ContPath -eq 1))
            {
                try
                {
                    if ($file.IsImg)
                    {
                        $image = New-Object -ComObject Wia.ImageFile
                        $image.loadfile($file.ConvPath)
                        $whimgratio = $image.Width/$image.Height
                        #If width is greater, limit this dimension for resize.
                        if($file.ImgVidPath.length)
                        {
                            $contw = $set.XDim*2
                            $conth = $set.YDim*2
                        }
                        elseif ($whimgratio -gt $whdispratio)
                        {
                            $contw = $set.XDim
                            $conth = ($set.XDim/$whimgratio)
                        }
                        else
                        {
                            $conth = $set.YDim
                            $contw = ($set.YDim*$whimgratio)
                        }
                        $wint = $contw -as [Int]
                        $hint = $conth -as [Int]
                        $SizeStr = $wint.ToString() + "x" + $hint.ToString()
                        $SizeStr2 = $set.XDim.ToString() + ":" + $set.YDim.ToString()
                        $SizeOut = $set.XDim.ToString() + "x" + $set.YDim.ToString()
                        $quality = 95
                        if($file.ImgVidPath.length)
                        {
                            $ExpCmd = "-compose Copy -gravity center -extent  $SizeStr -quality $quality "
                        }
                        else{
                            $ExpCmd = ""
                        }
                        #magick input.jpg -resize 800x600 -background black -compose Copy \
                        #-gravity center -extent 800x600 -quality 92 output.jpg
                        $IMCmd1 = "magick `"$($file.ConvPath)`" -resize $SizeStr -quality $($quality.ToString()) -background black "
                        $IMCmdOut = "`"$($file.ContPath)`""
                        $IMCmd = $IMCmd1+$ExpCmd+$IMCmdOut
                        (Invoke-Expression $IMCmd) *> $null
                        if($file.ImgVidPath.length)
                        {
                            $FullImgDur = $Set.FadeTime*2 +$Set.PicDispTime
                            $frameRate = 30
                            $NFramesExp = [Int] ($FullImgDur*$frameRate)
                            #Zoompan configuration here.
                            $SetSrtZoom = Get-Random -Minimum $MinSrtZoom -Maximum $MaxSrtZoom
                            $SetSrtZoom = 1.5
                            $SetSrtX = Get-Random -Minimum 0.0 -Maximum ($wint*(1-1/$SetSrtZoom))
                            $SetSrtY = Get-Random -Minimum 0.0 -Maximum ($hint*(1-1/$SetSrtZoom))
                            $SetSrtX = ($wint*(1-1/$SetSrtZoom))
                            $SetSrtY = ($hint*(1-1/$SetSrtZoom))
                            #$SetSrtX = 0
                            #$SetSrtY = 0
                            $ZoomRate = ($SetSrtZoom-1)/$NFramesExp
                            $XRate = ($SetSrtX)/$NFramesExp
                            $YRate = ($SetSrtY)/$NFramesExp

                            $quality = 5 #Lower is better
                            $ffmpegCmd1 = "ffmpeg -y "
                            $ffmpegCmdA = "-f lavfi -i anullsrc  -loop 1 -f image2 "
                            $ffmpegCmdV1= "-framerate " + $frameRate + " -i `"$($file.ContPath)`" "
                            $ffmpegCmdV2 = "-r $frameRate -t $FullImgDur "
                            $filtercfg1 = "-filter_complex `"[1:v]zoompan=z='if(gte(in,1),min(pzoom-$ZoomRate,1.5),$SetSrtZoom)'"
                            $filtercfgX = ":x='if(gte(in,1),px-$XRate,$SetSrtX)'"
                            $filtercfgY = ":y='if(gte(in,1),py-$YRate,$SetSrtY)'"
                            $filtercfg2 = ":d=1:fps=$frameRate`" "
                            $filtercfg = $filtercfg1 + $filtercfgX + $filtercfgY + $filtercfg2

                            $ffmpegDef = "-vcodec libx264 -crf $quality -pix_fmt yuvj420p "
                            $ffmpegOut = "-map 0:a -map 1:v -s $SizeStr2 `"$($file.ImgVidPath)`""
                            $ffmpegCmd = $ffmpegCmd1+$ffmpegCmdA+$ffmpegCmdV1+$ffmpegCmdV2+$filtercfg+$ffmpegDef+$ffmpegOut

                            #Execute the FFmpeg command
                            (Invoke-Expression $ffmpegCmd) *> $null
                        }
                        $file.ExpContSuccess = 1
                        #Optional / future explore:
                        #$null = magick $file.ConvPath -auto-gamma -auto-level -white-balance -resize ($contw.ToString()+"x"+$conth.ToString()+">") $file.ContPath
                        #


                        }
                    elseif($file.IsVid -and $ConvVid)
                    {
                        ($VPrams = ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 $file.FullName) *> $null
                        $Parts = $VPrams -split ','
                        if ($Parts.Count -gt 1){
                            $VWidth = [Int]::Parse($Parts[0] -split ',', 1)
                            $VHeight = [Int]::Parse($Parts[($Parts.Count-1)] -split ',', 1)
                            $whvidratio = $VWidth/$VHeight
                            #If width is greater, limit this dimension for resize.
                            if ($whvidratio -gt $whdispratio)
                            {
                                $contw = [int]$set.XDim
                                $conth = [int]($set.XDim/$whvidratio)
                            }
                            else
                            {
                                $conth = [int]$set.YDim
                                $contw = [int]($set.YDim*$whvidratio)
                            }
                            #If video packing, need to set the pad limits
                            if($Set.VidPack)
                            {
                                $Sides = $set.XDim - $contw;
                                $TopBot = $set.YDim - $conth;
                                $LBand = [math]::Floor($Sides/2)
                                $TBand = [math]::Floor($TopBot/2)
                                $RBand = $LBand
                                $BBand = $TBand

                                if ($Sides%2)
                                {
                                    $RBand = $LBand+1
                                }
                                if (($TopBot%2) -ge 1)
                                {
                                    $BBand = $TBand+1
                                }
                                $wint = $set.XDim -as [Int]
                                $hint = $set.YDim -as [Int]
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
                                $VidPad = $null
                                $wint = $contw -as [Int]
                                $hint = $conth -as [Int]
                            }
                            #If bordering is required.
                            if($LBand -or $RBand -or $TBand -or $BBand)
                            {
                                $PadOpt = "--pad top=$($TBand.ToString()):bottom=$($BBand.ToString()):left=$($LBand.ToString()):right=$($RBand.ToString())"
                                $PadOpt = "--pad top=0:bottom=0"
                                $PadOpt = "--pad top=0"
                            }
                            else
                            {
                                $PadOpt = ""
                            }
                            $PadOpt = ""
                            $handbrakecmd = "handbrakecli -i `"$($file.FullName)`" $PadOpt -o `"$($file.ContPath)`" -w $($wint.ToString()) -l $($hint.ToString())"
                            (Invoke-Expression $handbrakecmd) *> $null
                            $file.ExpContSuccess = 1

                        }
                    }
                }
                catch{}
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

            #Save the report
            #$ContReportPath
            if (Test-Path -Path $ContReportPath){}
            else {$null = New-Item -ItemType File -Path $ContReportPath -Force}
            $FilesExportedWithCont = ($Files2GetCont | Where-Object -Property ExpContSuccess -eq 1)
            $FilesExportedWithCont | Select-Object -Property Name,RelPath,FullName,ConvPath,Length,LastWriteTimeStr,ContPath,ImgVidPath|
                Export-Csv -LiteralPath $ContReportPath -NoTypeInformation

        }
    }

}