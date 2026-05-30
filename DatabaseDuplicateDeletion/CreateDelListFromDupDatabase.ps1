<#
.SYNOPSIS
    Auxiliary (standalone) — STEP 2 of 3 of the database-driven dedup pipeline:
    from the size/hash candidates, pick which copy of each duplicate to delete.

.DESCRIPTION
    NOT part of the FileBackup engine. Reads $ReportPath (STEP 1 output), limits
    to media extensions, groups by SHA256 Hash, and within each duplicate group
    marks copies for deletion when their path contains a key from $DupRemKeys
    (lowest-priority/last-kept location wins), always leaving at least one copy.
    Writes a review list ($DupReport) and a delete list ($DelReport) consumed by
    STEP 3 (RemoveAllFilesFromList.ps1). REVIEW $DelReport before running STEP 3.
#>

$ReportPath = "A:\AllDatabaseFiles.csv"

$DelReport = "A:\AllDuplicatesToRemove.csv"
$DupReport = "A:\AllDuplicatesToReview.csv"

#Highest value in this array has priority
$DupRemKeys = @(
"Delete"
"Duplicate"
"DNP"
"Unkown"
"Unknown"
"FellasDocs"
"PetersDocs"
"Repo_Serv"
)

$SrcFilesPosDup = @(Import-Csv -LiteralPath $ReportPath)
$SrcFilesPosDup | Add-Member -MemberType NoteProperty -Name DelChk -Value $([int]0)
foreach($file in $SrcFilesPosDup)
{
   if($file.Length -gt 0)
   {
      $str = $file.FullName
      if ($str -like "*.jpg" -or $str -like "*.gif" -or $str -like "*.wma" -or $str -like "*.mp3" -or $str -like "*.mov" -or $str -like "*.mp4" -or $str -like "*.bmp" -or $str -like "*.m4a" -or $str -like "*.avi" -or $str -like "*.mp4")
      {
         $file.DelChk = 1
      }
   }
}
$SrcFilesPosDup2Chk = $SrcFilesPosDup | Where-Object { $_.DelChk -gt 0 }
$SrcFilesGroupedByHash = $SrcFilesPosDup2Chk | Where-Object { $_.Length -gt 0 } | Group-Object -Property Hash
$SubGrp = $SrcFilesPosDup
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
	Write-Host "Number of files in dup group: " + $DupSetFileCnt.ToString()
    foreach ($file in ($DupSet| Select-Object -Expand Group))
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
$DupSetFull | Export-Csv -Path $DupReport -NoTypeInformation
$DelSetFull | Export-Csv -Path $DelReport -NoTypeInformation
Write-Host "Full delete list produced and saved"