function Join-VideosFromList
{
    param (
        $FileListorCSVPath,
        [decimal]$crossfadedur = 0,
        [string]$outputFile = "output.mp4"
    )
    if( -not (Test-Path $FileListCSVPath -PathType Leaf))
    {
        $FileList = = Import-Csv -LiteralPath $FileListCSVPath
    }
    elseif( -not (Test-Path $FileListCSVPath -PathType Container))
    {
        $AllInputFiles = @(Get-ChildItem -LiteralPath $FileListCSVPath -Filter "*.mp4" -Recurse)
        $FileList = ($AllInputFiles | Select-Object -ExpandProperty FullName)
    }
    elseif($a.GetType() -eq "string")
    {
        $FileList = $FileListCSVPath
    }
    else
    {
        try
        {
            $FileList = ($FileListCSVPath | Select-Object -ExpandProperty FullName)
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
        Write-Host "Only one file found, copying video to output"
    }
}