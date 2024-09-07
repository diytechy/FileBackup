# NOTE: Below function copied from stack-overflow:
#https://stackoverflow.com/questions/43728173/looping-through-all-subfolders-zipping-each-folder-in-powershell

Fldrs2Comp = "E:\02\ToSift\ToSort\Isolate\Server Backups\Pre_MINI-SERV"
OutputFldr = "E:\02\ToSift\ToSort\Isolate\Server Backups\Pre_MINI-SERV_Comp"


if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip executable '$7zipPath' not found"
}
else {
    Set-Alias Start-SevenZip $7zipPath
}



function Compress-Subfolders
{
    param
    (
        [Parameter(Mandatory = $true)][string] $InputFolder,
        [Parameter(Mandatory = $true)][string] $OutputFolder
    )

    $subfolders = Get-ChildItem $InputFolder | Where-Object { $_.PSIsContainer }

    ForEach ($s in $subfolders) 
    {
        $path = $s
        $path
        Set-Location $path.FullName
        $fullpath = $path.FullName
        $pathName = $path.BaseName

        #Get all items 
        $items = Get-ChildItem

        $zipname = $path.name + ".zip"
        $zippath = Join-Path $outputfolder $zipname
        Compress-Archive -Path $items -DestinationPath $zippath
        
        Start-SevenZip a -mx=9 -bso0 -bsp0 $RepPath7Zip $RepPathFldr
    }
}