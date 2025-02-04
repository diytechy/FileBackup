Clear-Host; #Process level on next line: 0 = all, 1 = move to process path, 2 = convert from process path to output
$ProcLvl = 2
$InputFileRootPath ="S:"
$PrepFileRootPath ="D:\AlbumPrep"
$ConvFileRootPath ="D:\AlbumConv"
$OutputFilePrepend = "D:\Album"
#Define output definitions:
$OutputDefs = @(
    [pscustomobject]@{XDim=1440;YDim=1080;FPS=30;PicDispTime=5;FadeTime = 0.7;BulkVidTimeMin=20})
#    [pscustomobject]@{XDim=1280;YDim=720;FPS=30})

#Adding dependent scripts:
Import-Module ".\BuildAlbum\CopyMediaFromNetwork2Local.psm1"
Import-Module ".\BuildAlbum\PrepareMediaForDisplay.psm1"

#Build derived definitions
foreach($set in $OutputDefs)
{
    $ContFileRootPath = ($OutputFilePrepend+$set.XDim+"x"+$set.YDim)
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 1)){
    Copy-MediaFromNetwork $InputFileRootPath $PrepFileRootPath
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 2)){
    New-MediaForDisplay $PrepFileRootPath $ConvFileRootPath $OutputFilePrepend $OutputDefs
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 3)){
    Set-VideoFromMedia $OutputFilePrepend $OutputDefs
}
#3 Steps:
#1. Prepare files by copying them to local path
#2. Prepare images by converting them to a conversion path (enhance / rotate)
#3. Resize images into their destination path
#4. Resize videos into their destination path


