# NOTE: Below function copied from stack-overflow:
#https://stackoverflow.com/questions/43728173/looping-through-all-subfolders-zipping-each-folder-in-powershell

$Fldrs2Comp = "E:\02\ToSift\ToSort\Isolate\Server Backups\Pre_MINI-SERV"
$OutputFldr = "E:\02\ToSift\ToSort\Isolate\Server Backups\Pre_MINI-SERV_Comp"




$7zipPath = "$env:ProgramFiles\7-Zip\7z.exe"
if (-not (Test-Path -Path $7zipPath -PathType Leaf)) {
    throw "7 zip executable '$7zipPath' not found"
}
else {
    Set-Alias Start-SevenZip $7zipPath
}

$subfolders = Get-ChildItem $Fldrs2Comp | Where-Object { $_.PSIsContainer }

ForEach ($s in $subfolders) 
{
    $path = $s
    $fullpath = $path.FullName
    $fldrname = $path.BaseName
    $OutName  = Join-Path $OutputFldr $fldrname
    $z7name   = $OutName + ".7z"
    Start-SevenZip a -mx=9 $z7name $fullpath
}
