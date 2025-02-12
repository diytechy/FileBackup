Clear-Host #Process level on next line: 0 = all, 1 = move to process path, 2 = convert from process path to output
Write-Host "Powershell version: $($PSVersionTable.PSVersion)"
$ProcLvl = 3 #Remember- this is completed
$InputFileRootPath ="S:"
$PrepFileRootPath ="D:\AlbumPrep"
$ConvFileRootPath ="D:\AlbumConv"
$OutputFilePrepend = "D:\Album"
#0 - Only generate content when new files are available, 1
#1 - Generate content if files appear updated.
$InputFileRootPath ="D:\T"
$PrepFileRootPath ="D:\TAlbumPrep"
$ConvFileRootPath ="D:\TAlbumConv"
$OutputFilePrepend = "D:\TAlbum"
#Define output definitions:
$OutputDefs = @(
    [pscustomobject]@{
        XDim=1440;
        YDim=900;
        FPS=30;
        PicDispTime=6;
        FadeTime = 0.7;
        BulkVidTimeMin=20;
        NameMethod = "FldrLvl2";
        ImgVidFldr="\ImgInVid";
        Quality=25})
#    [pscustomobject]@{XDim=1280;YDim=720;FPS=30})

#Adding dependent scripts:
Import-Module ".\BuildAlbum\CopyMediaFromNetwork2Local.psm1"
Import-Module ".\BuildAlbum\PrepareMediaForDisplay.psm1"
Import-Module ".\BuildAlbum\PackMediaIntoVideo.psm1"

#Build derived definitions
$OutputDefs | Add-Member -MemberType NoteProperty -Name Outpath -Value $([string])
$OutputDefs | Add-Member -MemberType NoteProperty -Name OutGrp -Value $([string])
$OutputDefs | Add-Member -MemberType NoteProperty -Name VidPack -Value $([Int])
foreach($set in $OutputDefs)
{
    $Set.Outpath = ($OutputFilePrepend+$set.XDim+"x"+$set.YDim)
    $Set.OutGrp = ($OutputFilePrepend+$set.XDim+"x"+$set.YDim+"Groups")
    if($Set.PicDispTime -and $Set.BulkVidTimeMin -and $Set.ImgVidFldr.Count)
    {
        $Set.VidPack = 1
    }
}
#Run operations.
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 1)){
    Copy-MediaFromNetwork $InputFileRootPath $PrepFileRootPath
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 2)){
    $PrepMediaDef = Update-ConvertedMediaImagesForDisplay $PrepFileRootPath $ConvFileRootPath
    Update-MediaForDisplaySets $PrepMediaDef $OutputDefs
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 3)){
    Write-Host "***************************************"
    Write-Host "**** Building final output videos *****"
    Write-Host "***************************************"
    Set-VideoFromMedia $OutputDefs
}
$stopwatch.Stop()
$elapsedTime = $stopwatch.Elapsed
write-host "Elapsed time: $elapsedTime"
#3 Steps:
#1. Prepare files by copying them to local path
#2. Prepare images by converting them to a conversion path (enhance / rotate)
#3. Resize images into their destination path
#4. Resize videos into their destination path


