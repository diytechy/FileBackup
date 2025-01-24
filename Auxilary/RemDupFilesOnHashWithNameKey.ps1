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
$DupReport = "D:\AllPotentialDuplicates.csv"

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

$hTable=@{}
$ATable=@{
FullName = $HashProps.FullName | Out-String
Hash = $HashProps.Hash | Out-String
}

$HashProps.psobject.properties | foreach -begin {$h=@{}} -process {$h."$($_.Name)" = $_.Value} -end {$h}


foreach($r in $HashProps)
{
    $hTable[$r.FullName]=$r.FullName | Out-String
    $hTable[$r.Hash]=$r.Hash | Out-String
}

#Now build full hash table definition and determine what to remove.
$hTable | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
Write-Host "All hash codes converted"

$SrcFilesGroupedByHash = $hTable | Group-Object -Property Hash
Write-Host "All hash codes grouped"
foreach ($hashgrp in $SrcFilesGroupedByHash) {

    if ($hashgrp.Count -gt 1)
    {
        $DupInd[0] = $DupInd[0] + 1
        foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
            $selfile.DupGrp = $DupInd[0]
        }
    }
}
$DupSet = ($SrcFilesGroupedByHash | Select-Object -Expand Group) | Where-Object { $_.DupGrp -gt 0 }
if ($DupSet.Count){
    $DupSet | Select-Object -Property DupGrp,FullName |
    Export-Csv -LiteralPath $DupReport -NoTypeInformation
}