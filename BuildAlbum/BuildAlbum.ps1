Clear-Host; #Process level on next line: 0 = all, 1 = move to process path, 2 = convert from process path to output
$ProcLvl = 1
$InputFileRootPath ="S:"
$PrepFileRootPath ="D:\AlbumPrep"
$ConvFileRootPath ="D:\AlbumConv"
$OutputFilePrepend = "D:\Album"
#Define output definitions:
$OutputSizes = @(
    [pscustomobject]@{XDim=1440;YDim=1080;FPS=30;Conv2Vid=1})
#    [pscustomobject]@{XDim=1280;YDim=720;FPS=30})

#Adding dependent scripts:
powershell -command "& { . .\CopyMediaFromNetwork2Local.ps1; Copy-MediaFromNetwork}"
powershell -command "& { . .\PrepareMediaForDisplay.ps1; Prepare-MediaForDisplay}"

if (($ProcLvl -eq 0) -or ($ProcLvl -eq 1)){
    Copy-MediaFromNetwork $InputFileRootPath $PrepFileRootPath
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 2)){
    Copy-Prepare-MediaForDisplay $PrepFileRootPath $ConvFileRootPath $OutputFilePrepend $OutputSizes
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 3)){
    Copy-Prepare-MediaForDisplay $PrepFileRootPath $ConvFileRootPath $OutputFilePrepend $OutputSizes
}
#3 Steps:
#1. Prepare files by copying them to local path
#2. Prepare images by converting them to a conversion path (enhance / rotate)
#3. Resize images into their destination path
#4. Resize videos into their destination path


