#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$ReportPath = "A:\AllDatabaseFiles.csv"

$HashPaths = @(
"A:\SharedFilesHashTable.csv"
"A:\PrivateFilesHashTable.csv"
"A:\NonDocsFilesHashTable.csv"
#"D:\SharedFilesHashTable.csv"
#"D:\PrivateFilesHashTable.csv"
#"D:\NonDocsFilesHashTable.csv"
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
$Prog = 0;
$Total = $SrcFilesGroupedByLength.Count
$Perc = 0
$PrevPerc = 0
foreach ($filegrp in $SrcFilesGroupedByLength)
{
    if ($filegrp.Count -gt 1)
    {
        $LenInd = $LenInd + 1
        foreach ($selfile in ($filegrp| Select-Object -Expand Group))
        {
			$selfile.LenGrp = $LenInd
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
    $Prog++
    $Perc = $Prog*100/$Total
    if ($Perc -gt ($PrevPerc + 1))
    {
        Write-Host ("Inc "+ $Perc.ToString() +"% at length index " +$LenInd.ToString())
		$PrevPerc = $Perc
    }
}

Write-Host "Remaining hash definitions computed"
$SrcFilesPosDup = ($SrcFilesGroupedByLength | Select-Object -Expand Group) | Where-Object { $_.LenGrp -gt 0 }

$SrcFilesPosDup | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host "Full list produced and saved"