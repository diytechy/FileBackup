Clear-Host #Process level on next line: 0 = all, 1 = move to process path, 2 = convert from process path to output
Write-Host "Powershell version: $($PSVersionTable.PSVersion)"
Write-Host $PSScriptRoot
Set-Location -Path $PSScriptRoot
$ProcLvl = 0 #Usually 0 (Process all) unless debugging.
$SetTmpPath = "T" #If utalizing RAM drive for conversion (1 gb), set this to the letter of the drive that should be created.  Else keep blank.
if ((HOSTNAME) -EQ "DESKTOP-OFFICE")
{
    $BuDrv = "Z"
    $SetTmpPath = "T:"
}
else
{
    $BuDrv = "D"
    $SetTmpPath = ""
}
#For testing, note the configuration file is also
$UseTestPath = 1;
if ($UseTestPath)
{

    $InputFileRootPath = ".\TestInput"
    $PrepFileRootPath  = ".\TestOut\Prep"
    $ConvFileRootPath  = ".\TestOut\Conv"
    $OutputFilePrepend = ".\AlbumOut"
    $OutputDefs = @(
    [pscustomobject]@{
        XDim = 1440;
        YDim = 900;
        FPS = 20;
        PicDispTime = 6;
        MaxSrtRot = 30;
        FadeTime = 0.7;
        BulkVidTimeMin = 20;
        NameMethod = "FldrLvl2";
        ImgVidFldr = "\ImgInVid";
        Quality = 30;
        ExpAud = 0;
        CleanBuild = 1;
    })

}
#************************************
#Define standard / non-test paths
#************************************
else
{
    $InputFileRootPath ="S:"
    $PrepFileRootPath  = $BuDrv+ ":\AlbumPrep"
    $ConvFileRootPath  = $BuDrv+ ":\AlbumConv"
    $OutputFilePrepend = $BuDrv+ ":\Album"
    $OutputDefs = @(
        [pscustomobject]@{
            XDim = 1440;
            YDim = 900;
            FPS = 30;
            PicDispTime = 6;
            MaxSrtRot = 30;
            FadeTime = 0.7;
            BulkVidTimeMin = 20;
            NameMethod = "FldrLvl2";
            ImgVidFldr = "\ImgInVid";
            Quality = 23;
            ExpAud = 0;
            CleanBuild = 0;
        }
        #[pscustomobject]@{
        #    XDim = 1920;
        #    YDim = 1080;
        #    FPS = 30;
        #    PicDispTime = 6;
        #    MaxSrtRot = 30;
        #    FadeTime = 0.7;
        #    BulkVidTimeMin = 30;
        #    NameMethod = "FldrLvl2";
        #    ImgVidFldr = "\ImgInVid";
        #    Quality = 22;
        #    ExpAud = 0;
        #    CleanBuild = 0;
        #}
    )
}
#Clean paths if applicable
$CopyMedia = 0
foreach ($def in $OutputDefs)
{
    if ($def.CleanBuild)
    {
        $ChkPath = $PrepFileRootPath
        #$ChkPath = $def.PrepFileRootPath
        if (Test-Path -LiteralPath $ChkPath)
        {
            remove-item -LiteralPath $ChkPath -Recurse -Force
        }
        $ChkPath = $ConvFileRootPath
        #$ChkPath = $def.ConvFileRootPath
        if (Test-Path -LiteralPath $ChkPath)
        {
            remove-item -LiteralPath $ChkPath -Recurse -Force
        }
        $CopyMedia = 1
    }
}
#Adding dependent scripts:
Import-Module ".\CopyMediaFromNetwork2Local.psm1"
Import-Module ".\PrepareMediaForDisplay.psm1"
Import-Module ".\PackMediaIntoVideo.psm1"

#Build derived definitions
$OutputDefs | Add-Member -MemberType NoteProperty -Name Outpath -Value $([string])
$OutputDefs | Add-Member -MemberType NoteProperty -Name OutGrp -Value $([string])
$OutputDefs | Add-Member -MemberType NoteProperty -Name VidPack -Value $([Int])
foreach($set in $OutputDefs)
{
    $AlbumRootParts = $OutputFilePrepend.split([System.IO.Path]::DirectorySeparatorChar)
    $RootFldr = (Resolve-Path $AlbumRootParts[0]).Path
    $Prepend  = $RootFldr+[System.IO.Path]::DirectorySeparatorChar+$AlbumRootParts[1..($AlbumRootParts.Count-1)]
    $Set.Outpath = ($Prepend+$set.XDim+"x"+$set.YDim+"q"+$set.Quality)
    $Set.OutGrp = ($Set.Outpath+"-Groups")
    if($Set.PicDispTime -and $Set.BulkVidTimeMin -and $Set.ImgVidFldr.Count)
    {
        $Set.VidPack = 1
    }
}
#Resolve paths
if (Test-Path $InputFileRootPath)
{
    $InputFileRootPath = (Resolve-Path $InputFileRootPath).Path
}
if (Test-Path $PrepFileRootPath) {}
else{New-Item -ItemType Directory $PrepFileRootPath}
$PrepFileRootPath  = (Resolve-Path $PrepFileRootPath).Path
if (Test-Path $ConvFileRootPath) {}
else{New-Item -ItemType Directory $ConvFileRootPath}
$ConvFileRootPath  = (Resolve-Path $ConvFileRootPath).Path
#Run operations.
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 1) -or $CopyMedia){
    Copy-MediaFromNetwork $InputFileRootPath $PrepFileRootPath
}
if (($ProcLvl -eq 0) -or ($ProcLvl -eq 2)){
    $PrepMediaDef = Update-ConvertedMediaImagesForDisplay $PrepFileRootPath $ConvFileRootPath $SetTmpPath
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


