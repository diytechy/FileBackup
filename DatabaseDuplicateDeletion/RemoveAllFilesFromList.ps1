<#
.SYNOPSIS
    Auxiliary (standalone) — STEP 3 of 3 of the database-driven dedup pipeline:
    permanently delete every file listed in the delete CSV.

.DESCRIPTION
    NOT part of the FileBackup engine. Reads $DelReport (STEP 2 output) and
    Remove-Items each FullName.

    !!! DESTRUCTIVE AND IRREVERSIBLE !!! There is no prompt, no -WhatIf, and no
    Recycle Bin. Review $DelReport by hand first. To dry-run, add -WhatIf to the
    Remove-Item call below.
#>

$DelReport = "A:\AllDuplicatesToRemove.csv"

$Files2Rem = @(Import-Csv -LiteralPath $DelReport)
foreach($selfile in $Files2Rem)
{
	Remove-Item	-LiteralPath $selfile.FullName
}