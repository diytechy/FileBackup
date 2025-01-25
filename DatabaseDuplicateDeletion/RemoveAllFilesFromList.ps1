
$DelReport = "A:\AllDuplicatesToRemove.csv"

$Files2Rem = @(Import-Csv -LiteralPath $DelReport)
foreach($selfile in $Files2Rem)
{
	Remove-Item	-LiteralPath $selfile.FullName
}