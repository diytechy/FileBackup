function Join-VideosFromList
{
    param (
        $FileListPathOrCSV,
        [decimal]$crossfadedur = 0.5,
        [string]$outputFile = "output.mp4"
    )
    if( -not (Test-Path $FileListPathOrCSV -PathType Leaf -ErrorAction SilentlyContinue))
    {
        $FileList = = Import-Csv -LiteralPath $FileListPathOrCSV
    }
    elseif( -not (Test-Path $FileListPathOrCSV -PathType Container))
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
        <#
        ffmpeg -i v0.mp4 -i v1.mp4 -i v2.mp4 -i v3.mp4 -i v4.mp4 -filter_complex \
        "[0][1:v]xfade=transition=fade:duration=1:offset=3[vfade1]; \
         [vfade1][2:v]xfade=transition=fade:duration=1:offset=10[vfade2]; \
         [vfade2][3:v]xfade=transition=fade:duration=1:offset=21[vfade3]; \
         [vfade3][4:v]xfade=transition=fade:duration=1:offset=25,format=yuv420p; \
         [0:a][1:a]acrossfade=d=1[afade1]; \
         [afade1][2:a]acrossfade=d=1[afade2]; \
         [afade2][3:a]acrossfade=d=1[afade3]; \
         [afade3][4:a]acrossfade=d=1" \
        -movflags +faststart out.mp4
        #>
        Write-Host "Getting properties of all video files and building full command"
        $InstanceInd = [Int] 0
        $VidPathInputStr = [string]
        $VFadeInputStr = [string]
        $AFadeInputStr = [string]
        $PrevVFadeStr = "0"
        $PrevAFadeStr = "0"

        foreach ($entry in $FileList)
        {
            #Get video definition.
            #($VPrams = ffprobe -v error -select_streams v -show_entries stream=width,height, -of flat $entry) *> $null
            #($VPrams = ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 $file.FullName) *> $null
            $VPrams = ffprobe -v error -select_streams v -show_entries stream=width,height,duration -of csv=p=0 `"$entry`"
            $splitString = $VPrams -split ","
            $Width = [Int] $splitString[0]
            $Height = [Int] $splitString[1]
            $Dur = [decimal] $splitString[2]

            #Get video path input definition.
            $VidPathInputStr[$InstanceInd] = "-i "+$entry
            ##Incriment index for use in other string definitions
            $InstanceInd ++
            #Get video fade definitions.
            $CurrVFadeStr = "[vfade"+$InstanceInd+"]"
            $CurrAFadeStr = "[afade"+$InstanceInd+"]"
            $VFadeInputStr[$InstanceInd] = "-i "+$entry
        }
        Write-Host "Getting properties of all video files..."
        foreach ($entry in $FileList)
        {

        }
    }
}