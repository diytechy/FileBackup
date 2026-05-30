<#
.SYNOPSIS
    Auxiliary (standalone): create one .7z per immediate subfolder of a directory.

.DESCRIPTION
    NOT part of the FileBackup engine. Edit $Fldrs2Comp (parent whose subfolders
    are zipped) and $OutputFldr (where the .7z files land). Requires 7-Zip.
    Source: https://stackoverflow.com/questions/43728173
#>

$Fldrs2Comp = "D:\2Chk"
$OutputFldr = "D:\DupFldrComp"




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
