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

#Highest value in this array has priority
$DupRemKeys = @(
"Delete"
"Duplicate"
"DNP"
"FellasDocs"
"PetersDocs"
"Repo_Serv"
)

$HashTable=@{}
foreach ($path in $HashPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $HashProps += @(Import-Csv -LiteralPath $path)
    }
}
Write-Host "All hash definitions imported"

foreach($r in $HashProps)
{
    $HashTable[$r.FullName]=$r.FullName | Out-String
    $HashTable[$r.Hash]=$r.Hash | Out-String
}

#Now build full hash table definition and determine what to remove.
$HashProps | Add-Member -MemberType NoteProperty -Name DupGrp -Value $([int]0)
$HashProps | Add-Member -MemberType NoteProperty -Name HashCode -Value $([string]"****************************************************************")
foreach ($FileEntry in $HashProps) {
    $FileEntry.HashCode = $FileEntry.Hash | Out-String
}
Write-Host "All hash codes converted"

$SrcFilesGroupedByHash = $HashProps | Group-Object -Property HashCode
foreach ($hashgrp in $SrcFilesGroupedByHash) {

    if ($hashgrp.Count -gt 1)
    {
        $DupInd[0] = $DupInd[0] + 1
        foreach ($selfile in ($hashgrp| Select-Object -Expand Group)){
            $selfile.DupGrp = $DupInd[0]
        }
    }
}