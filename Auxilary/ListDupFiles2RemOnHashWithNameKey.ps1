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
$DupReport = "A:\AllDuplicatesToRemove.csv"

#Highest value in this array has priority
$DupRemKeys = @(
"Delete"
"Duplicate"
"DNP"
"FellasDocs"
"PetersDocs"
"Repo_Serv"
)

foreach ($path in $HashPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $HashProps += @(Import-Csv -LiteralPath $path)
    }
}
Write-Host "All hash definitions imported"

$HashProps | Add-Member -MemberType NoteProperty -Name LenGrp -Value $([int]0)
$HashProps | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
$HashProps | Add-Member -MemberType NoteProperty -Name DelGrp -Value $([int]0)


$SrcFilesGroupedByLength = $HashProps | Group-Object -Property Length

Write-Host "Files grouped by size"
$LenInd = 0
foreach ($filegrp in $SrcFilesGroupedByLength)
{
    if ($filegrp.Count -gt 1)
    {
        $LenInd = $LenInd + 1
        foreach ($selfile in ($filegrp| Select-Object -Expand Group))
        {
            if ($selfile.Hash.Length)
            {
                #Hash already exists, nothing to do.
            }
            else
            {
                $hashset = Get-FileHash -LiteralPath $selfile.FullName
                $selfile.Hash = $hashset.Hash
            }
        }
    }
}
Write-Host "Remaining hash definitions computed"
$SrcFilesPosDup = ($SrcFilesGroupedByHash | Select-Object -Expand Group) | Where-Object { $_.LenGrp -gt 0 }
SrcFilesGroupedByHash = $SrcFilesPosDup | Group-Object -Property Hash
$DupInd = 0
foreach ($hashgrp in $SrcFilesGroupedByHash) {

    if ($hashgrp.Count -gt 1)
    {
        $DupInd = $DupInd + 1
        foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
            $selfile.DupGrp = $DupInd[0]
        }
    }
}

$DupSetFull = ($SrcFilesGroupedByHash | Select-Object -Expand Group) | Where-Object { $_.DupGrp -gt 0 }
Write-Host "Full duplicate list produced"

$DupSets2Chk = $DupSetFull | Group-Object -Property DupGrp
foreach ($DupSet in $DupSets2Chk)
{
    $DupSetFileCnt = $DupSet.Count
    foreach ($file in $DupSet)
    {
        foreach ($namechk in $DupRemKeys)
        {
            if(($DupSetFileCnt -gt 1) -and ($file.FullName.Contains($namechk)))
            {
                $DupSetFileCnt = $DupSetFileCnt - 1
                $file.DelGrp = $file.DupGrp
                break
            }
        }
    }
}
$DelSetFull = ($SrcFilesGroupedByHash | Select-Object -Expand Group) | Where-Object { $_.DelGrp -gt 0 }
$DelSetFull | Export-Csv -Path $DupReport -NoTypeInformation
Write-Host "Full delete list produced and saved"