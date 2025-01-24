#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$HashPaths = @(
"A:\SharedFilesHashTable.csv"
"A:\PrivateFilesHashTable.csv"
"A:\NonDocsFilesHashTable.csv"
#"D:\SharedFilesHashTable.csv"
#"D:\PrivateFilesHashTable.csv"
#"D:\NonDocsFilesHashTable.csv"
)
$CmprPath = "D:\2Chk\"
$DupHashMovePath = "D:\DupHashFldr\"
$DupNameMovePath = "D:\DupNameFldr\"
$DupJSONMovePath = "D:\DupJSONFldr\"


#Variable initialization.
$CurrInnerProgPercInt = [int32[]]::new(1);
$PrevInnerProgPercInt = [int32[]]::new(1);
$CurrInnerProgDbl  = [double[]]::new(1);
$InnerLoopProg = @{
	ID       = 1
	Activity = "Getting ready.  Please wait..."
	Status   = "Getting ready.  Please wait..."
	PercentComplete  = 0
	CurrentOperation = 0
}

foreach ($path in $HashPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $HashProps += @(Import-Csv -LiteralPath $path)
    }
}
Write-Host "All hash definitions imported"
$HashProps | Add-Member -MemberType NoteProperty -Name Loc  -Value $([int16]0)
$AllFiles = @(Get-ChildItem -LiteralPath $CmprPath -Recurse -File)
$AllFiles | Add-Member -MemberType NoteProperty -Name Hash -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveFileFlag  -Value $([int16]0)
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLoc  -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLbl  -Value $([string]"****")
$AllFilesizeTtl = $AllFiles | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum


$InnerLoopProg.Activity = "Getting hash of check files..."
$InnerLoopProg.Status = "Please wait..."
$CurrInnerProgDbl[0] = 0;
$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
$LoopProg = 0;
$PrevInnerProgPercInt[0] = -1;

#Shorten length for simplicity
$SrcL = $CmprPath.Length
if((Test-Path -LiteralPath $CmprPath) -and ($AllFiles.Count))
{
    foreach ($file in $AllFiles)
    {
        #Get hash
        try
        {
            $hashset = Get-FileHash -LiteralPath $file.FullName
            $file.Hash = $hashset.Hash
        }
        catch
        {
        }

        #Get substring def.
        $ExtLen = $file.FullName.Length - $SrcL

        $LoopProg += $file.Length
        if ($HashProps.Hash -eq $file.Hash)
        {
            $file.MoveLoc = $DupHashMovePath + $file.FullName.Substring($SrcL, $ExtLen)
            $file.MoveFileFlag = 1
            $file.MoveLbl = "HASH"
        }
        elseif($HashProps.Name -eq $file.Name)
        {
            $file.MoveLoc = $DupNameMovePath + $file.FullName.Substring($SrcL, $ExtLen)
            $file.MoveFileFlag = 1
            $file.MoveLbl = "NAME"
        }
        #elseif($DupJSONMovePath -and $file.Name.Contains(".json")){
        #    $file.MoveLoc = $DupJSONMovePath + $file.FullName.Substring($SrcL,$ExtLen)
        #    $file.MoveFileFlag = 1
        #    $file.MoveLbl = "JSON"
        #}

        if ($AllFilesizeTtl)
        {
            $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
            if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0])
            {
                $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
                $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
                $InnerLoopProg.Status = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
                Write-Progress @InnerLoopProg
            }
        }
    }
    $Files2Move = @($AllFiles | Where-Object{ ( $_.MoveFileFlag -eq 1) })

    #Getting all folders
    $hashfolders = $Files2Move | Where-Object{ ( $_.MoveLbl.contains("HASH")) } | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique
    $namefolders = $Files2Move | Where-Object{ ( $_.MoveLbl.contains("NAME")) } | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique
    $jsonfolders = $Files2Move | Where-Object{ ( $_.MoveLbl.contains("JSON")) } | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique

    $allfoldersneeded = $Files2Move | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique | Sort-Object { $_.Length }
    #Creating all folders if needed
    foreach ($fldr in  $allfoldersneeded)
    {
        if (-Not (Test-Path -LiteralPath $fldr))
        {
            New-Item -Path $fldr -ItemType "directory" | Out-Null
        }
    }

    #Now move respective files
    foreach ($file2move in $Files2Move)
    {
        Move-Item -LiteralPath $file2move.FullName -Destination $file2move.MoveLoc
    }

    #Now remove empty folders from the source.

    $EmptyFldrs = Get-ChildItem -Path $CmprPath  -Recurse -Directory | Where-Object { $_.GetFiles().Count -eq 0 -and $_.GetDirectories().Count -eq 0 }
    while ($EmptyFldrs)
    {
        foreach ($fldr2rem in $EmptyFldrs)
        {
            Remove-Item -LiteralPath $fldr2rem.FullName -Force -Recurse| Out-Null
        }
        $EmptyFldrs = Get-ChildItem -Path $CmprPath  -Recurse -Directory | Where-Object { $_.GetFiles().Count -eq 0 -and $_.GetDirectories().Count -eq 0 }
    }

}

#Now build full hash table definition and determine what to remove.
$SrcFilesGroupedByHash | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
foreach ($hashgrp in $SrcFilesGroupedByHash) {

    if ($hashgrp.Count -gt 1)
    {
        $DupInd[0] = $DupInd[0] + 1
        foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
            $selfile.DupGrp = $DupInd[0]
        }
    }
}