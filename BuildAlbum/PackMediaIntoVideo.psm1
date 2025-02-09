Import-Module ".\BuildAlbum\ConcatMediaFromFileList.psm1"
function Set-VideoFromMedia
{
    param (
        [string]$OutputFilePrepend,
        $OutputSizes
    )

    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    #Write-Host "ffmpeg is already installed."
    }
    else{Throw "ffmpeg not detected, videos will not be converted" }

    #Now - for each set - break all the files into designated groups and their corresponding destinations.
    foreach ($set in $OutputSizes){
        $ContFileRootPath = $set.Outpath
        $VidPacksRootPath = $ContFileRootPath + $set.ImgVidFldr
        $VidPacksFileDefPath = $set.OutGrp
        $AllInputFiles = @(Get-ChildItem -LiteralPath $ContFileRootPath -Filter "*.mp4")
        #Add in video packs for images if defined and intended.
        if((Test-Path -LiteralPath $VidPacksRootPath -PathType Container) -and $set.ImgVidFldr.Length -and $set.PicDispTime)
        {
            $AllInputFiles = $AllInputFiles + @(Get-ChildItem -LiteralPath $VidPacksRootPath -Filter "*.mp4")
        }
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name GroupN -Value $([int])
        $AllInputFiles | Add-Member -MemberType NoteProperty -Name Dur -Value $([Decimal])
        #Figure out the nominal number of files per group, assuming most are pictures lasting for the still duration.
        $NFilesPerGrp = (($Set.BulkVidTimeMin*60)/$Set.PicDispTime)
        $NGroups = [Math]::Floor($AllInputFiles.Count/$NFilesPerGrp) -as [Int]
        $SelGrpN = 1 -as [Int]
        foreach ($file in $AllInputFiles)
        #For each file
        {
            $file.GroupN = $SelGrpN
            $SelGrpN++
            if($SelGrpN -gt $NGroups){
                $SelGrpN = 1
            }
            #Leaving in case duration is needed in the future for grouping
            #$ToRun = "ffprobe -v error -select_streams v -show_entries stream=width,duration -of csv=p=0 `"" +$file.Fullname+ "`""
            #($VPrams = Invoke-Expression $ToRun) *> $null
            #$splitString = $VPrams -split ","
            ##$Width = [Int] $splitString[0]
            #$file.Dur = [decimal] $splitString[1]
        }
        #if ($set.MaxSizeInGB)
        #{
        #    $DurTotal = $AllInputFiles | Measure-Object -Property Dur -Sum ; $DurTotal = [double] $DurTotal.Sum
        #    #$BitTotal = 8*$set.MaxSizeInGB*1.25e+8
        #    #$TarBitrate = $BitTotal/$DurTotal #Assume fading is negligable.
        #}
        $Groups= $AllInputFiles | Select-Object -ExpandProperty GroupN | Sort-Object -Unique
        $Groups | Add-Member -MemberType NoteProperty -Name FileListPath -Value $([string])
        $Groups | Add-Member -MemberType NoteProperty -Name VidExpPath -Value $([string])
        #Map to store file list.
        $GrpDef = @{}
        #Now build a list for each group.  This will be used in ffmpeg to actually build out the video.
        foreach ($grp in $Groups){
            $FileSet = (($AllInputFiles | Where-Object {( $_.GroupN -eq $grp)} | Sort-Object -Property Name) | Select-Object -ExpandProperty FullName)
            $GrpDef[$grp] = $FileSet
            $grp.FileListPath = $VidPacksFileDefPath  + " Grp-" + $grp.ToString()
            $grp.VidExpPath   = $VidPacksFileDefPath  + "\Grp-" + $grp.ToString()+".mp4"
            #Create file to describe what videos to append.
            $FileSet | Export-Csv -Path $grp.FileListPath -NoTypeInformation
        }
        $Groups | ForEach-Object -Parallel{
            $FadeTime      = $using:set.FadeTime
            $Quality       = $using:set.Quality
            $GrpDef        = $using:GrpDef
            $SelGrpDef     = $GrpDef[$_]
            Import-Module ".\BuildAlbum\ConcatMediaFromFileList.psm1"
            Join-VideosFromList $SelGrpDef $FadeTime $_.VidExpPath $Quality
        } -ThrottleLimit 1
        $SelGrpN = 0
    }
}
