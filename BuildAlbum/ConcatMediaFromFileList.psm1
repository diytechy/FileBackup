function Join-VideosFromList
{
    param (
        $FileListPathOrCSV,
        [decimal]$crossfadedur = 0.5,
        [string]$outputFile = "output.mp4",
        $vidqty = [Int] 20
    )
    $FileChk = Test-Path $FileListPathOrCSV -PathType Leaf
    $FldrChk = Test-Path $FileListPathOrCSV -PathType Container
    if((($FileChk.Count -eq 1) -and $FileChk -and $FileListPathOrCSV.endsWith("csv")) )
    {
        $FileList = Import-Csv -LiteralPath $FileListPathOrCSV
    }
    elseif(($FldrChk.Count -eq 1) -and $FldrChk)
    {
        $AllInputFiles = @(Get-ChildItem -LiteralPath $FileListPathOrCSV -Filter "*.mp4" -Recurse)
        $FileList = ($AllInputFiles | Select-Object -ExpandProperty FullName)
    }
    elseif(($FileListPathOrCSV.Count -gt 1) -and ($FileListPathOrCSV[0] -is [string]))
    {
        $FileList = $FileListPathOrCSV
    }
    else
    {
        try
        {
            $FileList = ($FileListPathOrCSV | Select-Object -ExpandProperty FullName)
        }
        catch
        {
            throw "Input must be a list of strings, list of files, a directory, or path to a csv."
        }
    }
    $grpfldr = $outputFile
    $vscript = $outputFile+"\vstream.ps1"
    $ascript = $outputFile+"\astream.ps1"
    $vidfile = $outputFile+"\vstream.mp4"
    $audfile = $outputFile+"\astream.aac"
    $finfile = $outputFile+".mp4"
    if (Test-Path -Path $grpfldr -PathType Container){}
    else {$null = New-Item -ItemType Directory -Path $grpfldr -Force}
    if($FileList.Count -lt 1)
    {
        throw "No files found, or format not supported"
    }
    elseif($FileList.Count -eq 1)
    {
        Write-Host "Only one file found, copying video to output"
    }
    elseif($FileList.Count -gt 1)
    {
        Write-Host "Getting properties of all video files and building full command for $outputFile..."
        $InstanceInd = [Int] 0
        $SelInd      = [Int] 0
        $VidPathVInputStr = [String[]]::new($FileList.Count)
        $VidPathAInputStr = [String[]]::new($FileList.Count)
        $VChanInputStr   = [String[]]::new($FileList.Count)
        $AChanInputStr   = [String[]]::new($FileList.Count)
        $VFadeInputStr   = [String[]]::new($FileList.Count)
        $AFadeInputStr   = [String[]]::new($FileList.Count)
        $PrevVFadeStr = "[0]"
        $PrevAFadeStr = "[0:a]"
        $NextVidOffset = 0
        $LastFile = [Int]0
        #$TupleSet = [System.ValueTuple[int, int, long, string, string, string, string]]
        #::new($FileList.Count)
        #Tuple for format verification before concat attempt.
        # pixel format, colorspace, vcodec, acodec, Width, height, timebase, arate,
        #width, height, timebase, arate, vdefinition,adefinition
        #2 int, 1 long, 4 string
        #$FileList | Add-Member -MemberType NoteProperty -Name VidDef -Value $([System.ValueTuple[int, int, double]])
        #$colorspace+$pixfmt+$vcodec
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
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $NfilesProc = 0;
        foreach ($entry in $FileList)
        {
            #Get video definition.
            $VPramsCmd = "ffprobe -v error -show_streams -select_streams v`:0 -of ini `"$entry`""
            $VKeyFrCmd = "ffprobe -v error -select_streams v:0 -skip_frame nokey -show_entries frame=pkt_pts_time -of csv=p=0 `"$entry`""
            $VKeyFrCmd = "ffprobe -loglevel error -skip_frame nokey -select_streams v:0 -show_entries frame=pkt_pts_time -of ini `"$entry`""
            $VKeyFrCmd = "ffprobe -select_streams v -show_entries frame=pict_type,pts_time -of ini -skip_frame nokey -i `"$entry`""
            $APramsCmd = "ffprobe -v error -show_streams -select_streams a`:0 -of ini `"$entry`""
            $VPrams = Invoke-Expression $VPramsCmd
            $APrams = Invoke-Expression $APramsCmd
            $KeyFrames = Invoke-Expression $VKeyFrCmd
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

            $entry.framerate = $framerate
            $entry.timebase = $timebase
            $entry.Dur = $Dur
            $entry.width = $width
            $entry.height = $height
            $entry.vcodec = $vcodec
            $entry.acodec = $acodec
            $entry.arate  = $arate
            $entry.pixfmt = $pixfmt
            $entry.atimebase = $atimebase
            $entry.colorspace = $colorspace
            $NfilesProc++
            $entry.SortInd = $NfilesProc
            if($stopwatch.ElapsedMilliseconds -gt 5000)
            {
                write-host "$outputFile`: Imported file $NfilesProc of $($FileList.Count)"
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            }
        }
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
        $FileList = $GrpSets |  Select-Object -ExpandProperty Group
        $FileList = $FileList | Add-Member -MemberType NoteProperty -Name ExportSuccess -Value $([int]0)
        $vtimebasefilt = "settb=expr=1/$vseltimebase"
        $atimebasefilt = "settb=expr=1/$aseltimebase"

        $NFilesExported = 0
        $CurrIdx = 0
        $LastVid = 0
        $PrevVid2TransitionFrom = ""
        $PrevVidFilterChainDef = ""
        $PrevVidFilterChainDef = ""
        $PrevVidDuration = 0
        $PrevInput2CfgStr = ""
        foreach ($file in $FileList)
        {
            CurrIdx++
            if (CurrIdx -eq $FileList.Count)
            {
                LastVid = 1
            }
            if ($NFilesExported -eq 0)
            {
                FirstVid = 1
            }
            #If file needs to be converted, define the stream input definition.
            $TranInput2CfgStr = ""
            $StadOutputCfgStr = ""
            $StreamIdx = 0
            $VStreamLbl = "VS$StreamIdx"
            #First, add conversions for the timebase if necessary.
            $TranInputPrevCfgStr
            if ($file.timebase -ne $seltimebase)
            {

            }
            else
            {
                $ImportDur = $file.Dur - $crossfadedur*2
            }
            #Create a fade out if this is the last video
            if ($LastVid)
            {
                if ($vfilterdef)
                {
                    $vfilterdef = $vfilterdef + ","
                }
                $vfilterdef = $vfilterdef + ","
            }
            #Build transition from previous video if necesasry.
            if (NFilesExported -gt 0)
            {
                try
                {
                    #First build the transition definition for the next video fading out of this one.

                }
                catch
                {
                    continue
                }
            }
            #Transition has been generated, now prepare for the next transition
            # and finally kick out the part of the video that is unfaded.
            try
            {
                #First, try to import the video to ensure it can actually be imported next time for the transition.

                $InputStr = "ffmpeg -y"; FadeIn = 0; FadeOut = 0;
                vfd1 = "", vfd2 = "" ; afd1 = "", afd2 = ""
                if (FirstVid -and LastVid)
                {
                    $InputT = 0; $ImportDur = $file.Dur; FadeIn=1; FadeOut=1
                }
                elseif(FirstVid)
                {
                    $InputT = 0; $ImportDur = $file.Dur - $crossfadedur; FadeIn=1
                    $vfd1 = "fade=t=in:st=0:d=$crossfadedur"
                    $afd1 = "afade=t=in:st=0:d=$crossfadedur"
                }
                elseif(LastVid)
                {
                    $InputT = $crossfadedur; $ImportDur = $file.Dur - $crossfadedur; FadeOut=1
                    $vfd2 = "fade=t=in:st=$($file.Dur-$crossfadedur):d=$crossfadedur"
                    $afd2 = "afade=t=in:st=$($file.Dur-$crossfadedur):d=$crossfadedur"
                }
                $InputStr = $InputStr + " -ss $InputT -t $ImportDur"
                $InputStr = $InputStr + " -i $file"
                $OutputStr = ""
                #Video output definition
                if ($file.timebase -ne $seltimebase)
                {
                    $OutputStr = $OutputStr + " -video_track_timescale $seltimebase"
                }
                if ($file.colorspace -ne $selcolorspace)
                {
                    $OutputStr = $OutputStr + " -colorspace $selcolorspace"
                }
                if ($file.selpixfmt -ne $selselpixfmt)
                {
                    $OutputStr = $OutputStr + " -pixfmt $selselpixfmt"
                }
                if ($file.vcodec -ne $selvcodec)
                {
                    $OutputStr = $OutputStr + " -vcodec $selvcodec"
                }
                #Audio output definition
                if ($file.atimebase -ne $aseltimebase)
                {
                    $OutputStr = $OutputStr + " -audio_track_timescale $aseltimebase"
                }
                if ($file.vcodec -ne $selarate)
                {
                    $OutputStr = $OutputStr + " -ar $selarate"
                }
                if ($file.vcodec -ne $selacodec)
                {
                    $OutputStr = $OutputStr + " -acodec $selacodec"
                }
                $OutputStr = $OutputStr + " -o $grpfldr+`"`\$NFilesExported.mp4"
                $ffmpegcmd = $InputStr + " " + $OutputStr
                #Run command, and if successful, incriment the number of exported files.
                (Invoke-Expression $ffmpegcmd) *> $null

                if ($LastVid -eq 0)
                {
                    #Built the import definition for the following transition.
                    $PrevTranInputCfgStr = "ffmpeg -y"
                    $PrevTranInputCfgStr = $PrevTranInputCfgStr + " -ss $( $file.dur - $crossfadedur )"
                    $PrevTranInputCfgStr = $PrevTranInputCfgStr + " -t $crossfadedur"
                    if ($file.framerate -ne $selframerate)
                    {
                        $PrevTranInputCfgStr = $PrevTranInputCfgStr + " -framerate $selframerate"
                    }
                    $PrevTranInputCfgStr = $PrevTranInputCfgStr + " -i $PrevVid2TransitionFrom"

                    PVFG = ""
                    $FG0Inst = 0
                    $FGIn0 = "[0:v]";
                    $FGOut0 = "[VFG0_$FG0Inst]";
                    #Build the input processing video filtergraph for the next transition
                    if ($file.timebase -ne $vseltimebase)
                    {
                        PVFG = PVFG+$FGIn0+$vtimebasefilt+$FGOut0; FG0Inst++; $FGIn0 = $FGOut0; $FGOut0 = "[VFG0_$FG0Inst]"
                    }

                    PAFG = ""
                    $FG0Inst = 0
                    $FGIn0 = "[0:a]";
                    $FGOut0 = "[AFG0_$FG0Inst]";
                    #Build the input processing audio filtergraph for the next transition
                    if ($file.atimebase -ne $aseltimebase)
                    {
                        PAFG = PAFG+$FGIn0+$vtimebasefilt+$FGOut0; FG0Inst++; $FGIn0 = $FGOut0; $FGOut0 = "[AFG0_$FG0Inst]"
                    }
                }
                #Now, export the actual video export.
                $file.ExportSuccess = 1
                $NFilesExported++

            }
            catch
            {
                continue
            }

        }
        #Build list of all raw files to concat.

        #Concat files.
        Write-Host "$finfile complete"
    }
}