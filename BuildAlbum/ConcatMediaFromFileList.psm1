function Join-VideosFromList
{
    param (
        $FileListPathOrCSV,
        [decimal]$crossfadedur = 0.5,
        [string]$outputFile = "output.mp4"
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
        Write-Host "Getting properties of all video files and building full command"
        $InstanceInd = [Int] 0
        $SelInd      = [Int] 0
        $VidPathInputStr = [String[]]::new($FileList.Count)
        $VChanInputStr   = [String[]]::new($FileList.Count)
        $AChanInputStr   = [String[]]::new($FileList.Count)
        $VFadeInputStr   = [String[]]::new($FileList.Count)
        $AFadeInputStr   = [String[]]::new($FileList.Count)
        $PrevVFadeStr = "[0]"
        $PrevAFadeStr = "[0:a]"
        $NextVidOffset = 0
        $LastFile = [Int]0
        foreach ($entry in $FileList)
        {
            #Get video definition.
            $ToRun = "ffprobe -v error -select_streams v -show_entries stream=width,height,duration -of csv=p=0 `"" +$entry+ "`""
            $VPrams = Invoke-Expression $ToRun
            $splitString = $VPrams -split ","
            $Width = [Int] $splitString[0]
            $Height = [Int] $splitString[1]
            $Dur = [decimal] $splitString[2]
            $NextVidOffset = $NextVidOffset + $Dur - $crossfadedur

            ##Incriment index for use in other string definitions
            $InstanceInd ++
            $SelInd = $InstanceInd-1
            #Get video path input definition.
            $VidPathInputStr[$SelInd] = "-i `""+$entry.ToString() +"`""
            #Get video fade definitions.
            $CurrVFadeStr = "[vfade"+$InstanceInd.ToString()+"]"
            $CurrAFadeStr = "[afade"+$InstanceInd.ToString()+"]"
            if ($InstanceInd -eq ($FileList.Count-1))
            {
                $VLastAppend = ",format=yuv420p"
                $ALastAppend = ""
            }
            elseif ($InstanceInd -ge $FileList.Count)
            {
                $LastFile = 1
            }
            else
            {
                $VLastAppend = $CurrVFadeStr
                $ALastAppend = $CurrAFadeStr+";"
                #Temp override for testing:
                $ALastAppend = ";"
            }
            #Temp override for testing:
            $VLastAppend = ""
            $VFadeStreamStr = "["+$InstanceInd.ToString()+"]"
            #$VChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":v]" + "settb=AVTB" +$PrevVFadeStr +"`;"
            #=expr=1/25
            #$VChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":v]" + "settb=expr=1/6000" +$PrevVFadeStr +"`;"
            #if($SelInd)
            #{
            #    $VChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":v]" + "settb=expr=1/6000"+ "[MAIN]" +"`;"
            #}
            #else{
            #    $VChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":v]" + "settb=expr=1/6000" +$PrevVFadeStr +"`;"
            #}
            #$VChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":v]" + "settb=expr=1/6000" +$PrevVFadeStr +"`;"
            if (-not $LastFile)
            {
                $VFadeInputStr[$SelInd] = $PrevVFadeStr+$VFadeStreamStr+"xfade=transition=fade:duration="+$crossfadedur.ToString()+":offset="+$NextVidOffset.ToString()+$VLastAppend+";"
            }
            $PrevVFadeStr = $VFadeStreamStr #For next iteration
            #Get audio fade definitoins.
            $AFadeStreamStr = "["+$InstanceInd.ToString()+":a]"
            $AChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":a]" + "asettb=AVTB" +$PrevAFadeStr +"`;"
            if (-not $LastFile)
            {
                $AFadeInputStr[$SelInd] = $PrevAFadeStr+$AFadeStreamStr+"acrossfade=d="+$crossfadedur.ToString()+$ALastAppend
            }
            $PrevAFadeStr = $AFadeStreamStr #For next iteration

        }
        Write-Host "Building final command string"
        #$CmdPartStart = Join-String
        $CmdPartInput = $VidPathInputStr -join " \`n"
        $CmdPartVChan = $VChanInputStr -join "\`n"
        $CmdPartVFade = $VFadeInputStr -join "\`n"
        $CmdPartAChan = $AChanInputStr -join "\`n"
        $CmdPartAFade = $AFadeInputStr -join "\`n"
        $CmdPartEnded = " -vcodec libx265 -pix_fmt yuv420p -x265-params crf=5 -acodec aac -movflags faststart " +$outputFile

        $FullCmdStart = "ffmpeg -y "+$CmdPartInput+" -filter_complex \`n`""
        $PreCmd = $FullCmdStart + "\`n" + $CmdPartVChan + "\`n" + $CmdPartVFade + "\`n" + $CmdPartAChan + "\`n" + $CmdPartAFade + "`"\`n" + $CmdPartEnded
        $PreCmd = $FullCmdStart + "\`n" + $CmdPartVChan + "\`n" + $CmdPartVFade + "\`n" + $CmdPartAFade + "`"\`n" + $CmdPartEnded
        $FullCmd = $PreCmd -replace '\\\r?\n',''
        #$FullCmd = "dir `"$FileListPathOrCSV`""

        Write-Host "Building video"
        Invoke-Expression $FullCmd
        Write-Host "Build complete"
    }
}