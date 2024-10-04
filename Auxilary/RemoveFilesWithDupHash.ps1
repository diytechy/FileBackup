#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$HashPaths = @(
"A:\SharedFilesHashTable.csv"
"A:\PrivateFilesHashTable.csv"
"A:\NonDocsFilesHashTable.csv"
)
$CmprPath = "E:\2Chk\"

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
#$HashProps.Hash
$AllFiles = @(Get-ChildItem -LiteralPath $CmprPath -Recurse -File)
$AllFiles | Add-Member -MemberType NoteProperty -Name Hash -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name Loc  -Value $([int16]1)
$AllFilesizeTtl = $AllFiles | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum


$InnerLoopProg.Activity = "Getting hash of check files..."
$InnerLoopProg.Status = "Please wait..."
$CurrInnerProgDbl[0] = 0;
$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
$LoopProg = 0;
$PrevInnerProgPercInt[0] = 0;
foreach ($file in $AllFiles) {
    $hashset = Get-FileHash -LiteralPath $file.FullName
    $file.Hash = $hashset.Hash
    $LoopProg += $file.Length
    if ($AllFilesizeTtl) {
        $CurrInnerProgPercInt[0] = ($LoopProg*100)/$AllFilesizeTtl
        if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
            $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
            $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
			$InnerLoopProg.Status = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		    Write-Progress @InnerLoopProg
        }
    }
}

$OutObj = Compare-Object -ReferenceObject $AllFiles -DifferenceObject $HashProps -Property Hash -PassThru -IncludeEqual

#$OutObj.SideIndicator
#$FiltObj = Where-Object -InputObject $OutObj -Property "SideIndicator" -Value "<=" -EQ
#Worked? ==>   $FiltObj = $OutObj | Where-Object SideIndicator -Match "<="
$FiltObj = ($OutObj | Where-Object SideIndicator -Match "==") | Where-Object Loc -Match "1"


$InnerLoopProg.Activity = "Removing files that already exist in backup hashes..."
$LoopProg = 0;
$PrevInnerProgPercInt[0] = -1;
foreach ($file in $FiltObj) {
    Remove-Item -LiteralPath $file.FullName -Force
    $CurrInnerProgPercInt[0] = ($LoopProg*100)/$FiltObj.Count
    if ($CurrInnerProgPercInt[0] -gt $PrevInnerProgPercInt[0]){
        $InnerLoopProg.PercentComplete = $CurrInnerProgPercInt[0]
        $PrevInnerProgPercInt[0] = $CurrInnerProgPercInt[0]
		$InnerLoopProg.Status = "Current Step: " + $InnerLoopProg.PercentComplete.ToString() + "% Complete"
		Write-Progress @InnerLoopProg
    }
}