#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$HashPaths = @(
#"A:\SharedFilesHashTable.csv"
#"A:\PrivateFilesHashTable.csv"
#"A:\NonDocsFilesHashTable.csv"
"D:\SharedFilesHashTable.csv"
"D:\PrivateFilesHashTable.csv"
"D:\NonDocsFilesHashTable.csv"
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
#$HashProps.Hash
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
$PrevInnerProgPercInt[0] = 0;

#Shorten length for simplicity
$SrcL = $CmprPath.Length
foreach ($file in $AllFiles) {
    #Get hash
    $hashset = Get-FileHash -LiteralPath $file.FullName
    $file.Hash = $hashset.Hash
    
    #Get substring def.
    $ExtLen = $file.FullName.Length - $SrcL

    $LoopProg += $file.Length
    if($HashProps.Hash -eq $file.Hash) {
        $file.MoveLoc = $DupHashMovePath + $file.FullName.Substring($SrcL,$ExtLen)
        $file.MoveFileFlag = 1
        $file.MoveLbl = "HASH"
    }
    elseif($HashProps.Name -eq $file.Name){
        $file.MoveLoc = $DupNameMovePath + $file.FullName.Substring($SrcL,$ExtLen)
        $file.MoveFileFlag = 1
        $file.MoveLbl = "NAME"
    }
    elseif($DupJSONMovePath -and $file.Name.Contains(".json")){
        $file.MoveLoc = $DupJSONMovePath + $file.FullName.Substring($SrcL,$ExtLen)
        $file.MoveFileFlag = 1
        $file.MoveLbl = "JSON"
    }

    #$FullMovePathLength = $file.FullName.Length - $SrcLen + $ModLen
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
$Files2Move = @($AllFiles | Where-Object{( $_.MoveFileFlag -eq 1)})

$hashfolders = $Files2Move | Where-Object{( $_.MoveLbl.contains("HASH"))} | Select-Object -Property MoveLoc | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique
$namefolders = $Files2Move | Where-Object{( $_.MoveLbl.contains("NAME"))} | Select-Object -Property MoveLoc| ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique
$jsonfolders = $Files2Move | Where-Object{( $_.MoveLbl.contains("JSON"))} | Select-Object -Property MoveLoc| ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique

$jsonfolders = $Files2Move | Where-Object{( $_.MoveLbl.contains("JSON"))} | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique
#Getting all folders
<#

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
#>