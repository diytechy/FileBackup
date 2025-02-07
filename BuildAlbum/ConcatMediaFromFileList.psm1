function Join-VideosFromList
{
    param (
        $FileListPathOrCSV,
        [decimal]$crossfadedur = 0.5,
        [string]$outputFile = "output.mp4",
        [int]$vidqty = 50
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
    if (Test-Path -Path $outputFile){}
    else {$null = New-Item -ItemType File -Path $outputFile -Force}
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
                $VLastAppend = ""
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
            }
            #Temp override for testing:
            $VStreamStrInput = "["+$InstanceInd.ToString()+":v]"
            if (-not $LastFile)
            {
                $VFadeInputStr[$SelInd] = $PrevVFadeStr+$VStreamStrInput+"xfade=transition=fade:duration="+$crossfadedur.ToString()+":offset="+$NextVidOffset.ToString()+$VLastAppend+";"
            }
            $PrevVFadeStr = $CurrVFadeStr #For next iteration
            #Get audio fade definitoins.
            $AStreamStrInput = "["+$InstanceInd.ToString()+":a]"
            $AChanInputStr[$SelInd] = "["+ $SelInd.ToString()+":a]" + "asettb=AVTB" +$PrevAFadeStr +"`;"
            if (-not $LastFile)
            {
                $AFadeInputStr[$SelInd] = $PrevAFadeStr+$AStreamStrInput+"acrossfade=d="+$crossfadedur.ToString()+$ALastAppend
            }
            $PrevAFadeStr = $CurrAFadeStr #For next iteration

        }
        Write-Host "Building final command string"
        $CmdPartInput = $VidPathInputStr -join " \`n"
        $CmdPartVChan = $VChanInputStr -join "\`n"
        $CmdPartVFade = $VFadeInputStr -join "\`n"
        $CmdPartAChan = $AChanInputStr -join "\`n"
        $CmdPartAFade = $AFadeInputStr -join "\`n"
        $CmdPartEnded = " -vcodec libx265 -pix_fmt yuv420p -x265-params crf=$vidqty -acodec aac -movflags faststart " +$outputFile

        $FullCmdStart = "ffmpeg -y "+$CmdPartInput+" -filter_complex \`n`""
        #$PreCmd = $FullCmdStart + "\`n" + $CmdPartVChan + "\`n" + $CmdPartVFade + "\`n" + $CmdPartAChan + "\`n" + $CmdPartAFade + "`"\`n" + $CmdPartEnded
        $PreCmd = $FullCmdStart + "\`n" + $CmdPartVChan + "\`n" + $CmdPartVFade + "\`n" + $CmdPartAFade + "`"\`n" + $CmdPartEnded
        #$PreCmd = $FullCmdStart + "\`n" + $CmdPartVChan + "\`n" + $CmdPartVFade + "`"\`n" +  $CmdPartEnded
        $FullCmd = $PreCmd -replace '\\\r?\n',''

        Write-Host "Building video"
        Invoke-Expression $FullCmd
        Write-Host "Build complete"
    }
}