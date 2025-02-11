function Join-VidPartsFromList
{
    param (
        $FileListProps,
        [string]$outputFile = "output.mp4",
        $vidqty = [Int] 20
    )
    try
    {
        $FileList = ($FileListProps | Select-Object -ExpandProperty FullName)
    }
    catch
    {
        throw "Input must be a list of strings."
    }
    $grpfldr = $outputFile
    $tranprepend = $outputFile+"\t"
    $finfile = $outputFile+".mp4"
    if (Test-Path -Path $grpfldr -PathType Container){}
    else {$null = New-Item -ItemType Directory -Path $grpfldr -Force}
    if($FileList.Count -lt 1)
    {
        throw "No files found, or format not supported"
    }
    else
    {
        Write-Host "Getting properties of all video files and building full command for $outputFile..."

        $FileList | Add-Member -MemberType NoteProperty -Name VidDef -Value $([System.ValueTuple[int, int, int, double,string, string]])
        $FileList | Add-Member -MemberType NoteProperty -Name Dur -Value $([decimal])
        $FileList | Add-Member -MemberType NoteProperty -Name FrameRate -Value $([decimal])
        $FileList | Add-Member -MemberType NoteProperty -Name Need2Conv -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name colorspace -Value $([string]"")
        $FileList | Add-Member -MemberType NoteProperty -Name pixfmt -Value $([string]"")
        $FileList | Add-Member -MemberType NoteProperty -Name vcodec -Value $([string]"")
        $FileList | Add-Member -MemberType NoteProperty -Name acodec -Value $([string]"")
        $FileList | Add-Member -MemberType NoteProperty -Name arate -Value $([decimal]0)
        $FileList | Add-Member -MemberType NoteProperty -Name width -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name height -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name SortInd -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name timebase -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name atimebase -Value $([int]0)
        $FileList | Add-Member -MemberType NoteProperty -Name nomexppath -Value $([string]"")
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $NfilesProc = 0;
        #*********************************************************************
        #*********************** Get file properties *************************
        #*********************************************************************
        foreach ($entry in $FileList)
        {
            #Get video definition.
            $ChkName = $entry+"srt"
            $VPramsCmd = "ffprobe -v error -show_streams -select_streams v`:0 -of ini `"$ChkName`""
            $APramsCmd = "ffprobe -v error -show_streams -select_streams a`:0 -of ini `"$ChkName`""
            $VPrams = Invoke-Expression $VPramsCmd
            $APrams = Invoke-Expression $APramsCmd
            $PreWidth = [Int]::0
            $PreHeight = [Int]::0
            $Rotation = [Int]::0
            $timebase = 0
            $colorspace = ""
            $pixfmt = ""
            $vcodec = ""
            $acodec = ""
            $arate = 0
            $framerate = 0
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
                    if ( $Pram.StartsWith("framerate="))
                    {
                        $framerate = [decimal]::Parse($Pram.split('framerate=')[1])
                    }
                    if ( $Pram.StartsWith("rotation="))
                    {
                        $Rotation = [Int]::Parse($Pram.split('rotation=')[1])
                    }
                    if ( $Pram.StartsWith("duration="))
                    {
                        $Dur = [decimal]::Parse($Pram.split('duration=')[1])
                    }
                    if ( $Pram.StartsWith("time_base="))
                    {
                        $timebase = [Int] (1/([decimal] (Invoke-Expression ($Pram.split('time_base=')[1]))))
                    }
                    if ( $Pram.StartsWith("color_space="))
                    {
                        $colorspace = $Pram.split('color_space=')[1]
                    }
                    if ( $Pram.StartsWith("pix_fmt="))
                    {
                        $pixfmt = $Pram.split('pix_fmt=')[1]
                    }
                    if ( $Pram.StartsWith("codec_name="))
                    {
                        $vcodec = $Pram.split('codec_name=')[1]
                    }
                }
                foreach ($Pram in $APrams)
                {
                    if ( $Pram.StartsWith("codec_name="))
                    {
                        $acodec = $Pram.split('codec_name=')[1]
                    }
                    if ( $Pram.StartsWith("sample_rate="))
                    {
                        $arate = $Pram.split('sample_rate=')[1]
                    }
                    if ( $Pram.StartsWith("time_base="))
                    {
                        $atimebase = [Int] (1/([decimal] (Invoke-Expression ($Pram.split('time_base=')[1]))))
                    }
                }

            }
            $Width = $PreWidth
            $Height = $PreHeight
            $vdefinition = $colorspace+$pixfmt+$vcodec
            $adefinition = $acodec
        # pixel format, colorspace, vcodec, acodec, Width, height, timebase, arate,
            $entry.VidDef = [System.ValueTuple[int, int, int, decimal, string, string]]::new(
                     $Width, $Height, $timebase, $arate, $vdefinition, $adefinition)

            $entry.framerate = $framerate; $entry.timebase = $timebase; $entry.Dur = $Dur
            $entry.width = $width; $entry.height = $height; $entry.vcodec = $vcodec
            $entry.acodec = $acodec; $entry.arate  = $arate; $entry.pixfmt = $pixfmt
            $entry.atimebase = $atimebase; $entry.colorspace = $colorspace
            $NfilesProc++
            $entry.SortInd = $NfilesProc
            if($stopwatch.ElapsedMilliseconds -gt 5000)
            {
                write-host "$outputFile`: Imported file $NfilesProc of $($FileList.Count)"
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            }
        }
        #*********************************************************************
        #*********************** End of property import *************************
        #*********************************************************************
        $NotInFirstGrp = 0
        $GrpSets = $FileList | Group-Object -Property VidDef
        #$FileList | Add-Member -MemberType NoteProperty -Name FrameRate -Value $([decimal])
        $GrpSets | Add-Member -MemberType NoteProperty -Name TotalDur -value $([decimal]0)
        foreach ($Grp in $GrpSets)
        {
            foreach ($file in ($Grp| Select-Object -Expand Group))
            {
                $Grp.TotalDur = $Grp.TotalDur + $file.Dur
            }
        }
        $GrpSets = $GrpSets| Sort-Object TotalDur -Descending
        foreach ($grp in $GrpSets){
            if($NotInFirstGrp)
            {
                #($file in ($_| Select-Object -Expand Group))
                foreach($file in ($grp| Select-Object -ExpandProperty Group))
                {
                    $file.Need2Conv = 1
                }


            }
            #$colorspace+$pixfmt+$vcodec
            #This is only entered for the first group, the group with the most items.
            else{
                $expgrp = ($grp| Select-Object -ExpandProperty Group)
                $selcolorspace = $expgrp[0].colorspace
                $selpixfmt = $expgrp[0].pixfmt
                $selvcodec = $expgrp[0].vcodec
                $selacodec = $expgrp[0].acodec
                $selarate = $expgrp[0].arate
                $vseltimebase = $expgrp[0].timebase
                $aseltimebase = $expgrp[0].atimebase
            }
            $NotInFirstGrp++
        }
        if ($NotInFirstGrp -gt 1)
        {
            Write-Host "$grpfldr`: Video sets for are not all the same properties, some files may be ignored, or converted."
        }

        #*********************************************************************
        #*********************** Perpare transitions  *************************
        #*********************************************************************
        #Only pick files with common format, since they must be concatable.
        $FileList = @($GrpSets |  Select-Object -ExpandProperty Group) | Where-Object -Property Need2Conv -eq 0
        $FileList = $FileList | Add-Member -MemberType NoteProperty -Name ExportSuccess -Value $([int]0)
        $NFilesExported = 0
        $LastExpIdx = -1
        $CurrExpIdx = 0
        $LastVid = 0
        $PrevVid2TransitionFrom = ""
        $PrevVidDuration = 0
        $VidPathStr = [String[]]::new($FileList.Count*2+1)
        foreach ($file in $FileList)
        {
            try
            {
                $postname = [System.IO.Path]::GetFileNameWithoutExtension($file)
                $tdur = $file.dur
                $VSrt = $file+"srt"
                $VEnd = $file+"end"
                if(PrevVid2TransitionFrom.Length)
                {
                    $prename  = [System.IO.Path]::GetFileNameWithoutExtension($PrevVid2TransitionFrom)
                }
                $CurrExpIdx = $LastExpIdx+1
                #If first video, fade in.
                if ($NFilesExported -eq 0)
                {
                    $CurrExpIdx = $CurrExpIdx+1
                    $tname = $tranprepend + "-fadein" + $postname + ".mp4"
                    tincmd = "ffmpeg -i `"$VSrt`" -vf `"fade=t=in:st=0:d=$tdur`" -af `"afade=t=in:st=0:d=$tdur`" `"$tname`""
                    (Invoke-Expression $tincmd) *> $null
                    $VidPathStr[$CurrExpIdx+1] = $tname
                }
                #Else transition from previous video
                else
                {
                    $CurrExpIdx = $CurrExpIdx+1
                    $tname = $tranprepend + $prename + "to" + $postname + ".mp4"
                    $V1 = $PrevVid2TransitionFrom+"end"
                    tcmd = "ffmpeg -i `"$V1`" -i `"$VSrt`" -filter_complex `"xfade=offset=0.0:duration=$tdur;acrossfade=duration=$tdur`" `"$tname`""
                    (Invoke-Expression $tcmd) *> $null
                    $VidPathStr[$CurrExpIdx+1] = $tname
                }
                #Standard, just add the file to the transition list.
                $CurrExpIdx = $CurrExpIdx+1
                $VidPathStr[$CurrExpIdx+1] = $file

                #If the file, fade to black.
                if ($CurrIdx -eq $FileList.Count)
                {
                    $CurrExpIdx = $CurrExpIdx+1
                    $tname = $tranprepend + "-fadeout" + $postname + ".mp4"
                    toutcmd = "ffmpeg -i `"$VEnd`" -vf `"fade=t=out:st=0:d=$tdur`" -af `"afade=t=out:st=0:d=$tdur`" `"$tname`""
                    (Invoke-Expression $toutcmd) *> $null
                    $VidPathStr[$CurrExpIdx+1] = $tname
                }
                #If we get this far, update the previous properties for the next video to transition from.
                $PrevVidDuration = $file.dur
                $PrevVid2TransitionFrom = $file
            }
            catch{
            }

        }

        #Build list of all raw files to concat.
        #Concat files.
        Write-Host "$finfile complete"
    }
}