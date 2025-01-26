#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$runvar = 0
$MoveRepPath = "D:\Files2Move.csv"
$HashPaths = @(
"A:\SharedFilesHashTable.csv"
"A:\PrivateFilesHashTable.csv"
"A:\NonDocsFilesHashTable.csv"
#"D:\SharedFilesHashTable.csv"
#"D:\PrivateFilesHashTable.csv"
#"D:\NonDocsFilesHashTable.csv"
)
$CmprPath = "D:\2Chk\"
$DupDateMovePath = "D:\DupDateFldr\"
$DupHashMovePath = "D:\DupHashFldr\"
$DupNameMovePath = "D:\DupNameFldr\"
#$DupJSONMovePath = "D:\DupJSONFldr\"
$DupJSONMovePath = ""

$HashTblDateFormat = "O"

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
$HashProps | Add-Member -MemberType NoteProperty -Name Name  -Value $([string])
$HashProps | Add-Member -MemberType NoteProperty -Name LastWriteTimeDateTime -Value $([DateTime])
$AllFiles = @(Get-ChildItem -LiteralPath $CmprPath -Recurse -File)
$AllFiles | Add-Member -MemberType NoteProperty -Name Hash -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveFileFlag  -Value $([int16]0)
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLoc  -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLbl  -Value $([string]"****")
$AllFilesizeTtl = $AllFiles | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum

$datemap = @{}
$namemap = @{}
foreach ($srcprop in $HashProps){
    $srcprop.Name = ($srcprop.FullName | Split-Path -Leaf)
    $srcprop.LastWriteTimeDateTime = [datetime]::ParseExact($srcprop.LastWriteTimeStr, $HashTblDateFormat, $null)
    $datekey = [System.ValueTuple[string, long, datetime]]::new(
    $srcprop.Name, $srcprop.Length, $srcprop.LastWriteTimeDateTime)
    $namekey = [System.ValueTuple[string]]::new($srcprop.Name)

    $datemap[$datekey] = $srcprop
    $namemap[$namekey] = $srcprop
}
Write-Host "Data prepared."

$InnerLoopProg.Activity = "Getting hash of check files..."
$InnerLoopProg.Status = "Please wait..."
$CurrInnerProgDbl[0] = 0;
$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
$LoopProg = 0;
$PrevInnerProgPercInt[0] = -1;

#Shorten length for simplicity
$SrcL = $CmprPath.Length
if((Test-Path -LiteralPath $CmprPath) -and ($AllFiles.Count) -and ($runvar -ne 2))
{
    foreach ($file in $AllFiles)
    {
        if($file.Length)
        {
            #First, see if the file size has any matches in the databases, if not, it's definitely not a duplicate.
            $PotMatches = @($HashProps | Where-Object { $_.Length -eq $file.Length })
            if ($PotMatches.Count)
            {
                #Get substring def.
                $ExtLen = $file.FullName.Length - $SrcL
                $key = [System.ValueTuple[string, long, datetime]]::new(
                        $file.Name, $file.Length, $file.LastWriteTime)
                $MatchingFile = @($datemap[$key])
                if ($MatchingFile.Count -eq 1)
                {
                    $file.MoveLoc = $DupDateMovePath + $file.FullName.Substring($SrcL, $ExtLen)
                    $file.MoveFileFlag = 1
                    $file.MoveLbl = "DATE"
                }
                else
                {
                    try
                    {
                        $PotHits = 0
                        foreach ($potfile in ($HashProps | Where-Object { $_.Length -eq $file.Length }))
                        {
                            if ($potfile.Hash.Length -eq 0)
                            {
                                $hashset = Get-FileHash -LiteralPath $potfile.FullName
                                $potfile.Hash = $hashset.Hash
                            }
                                $PotHits++

                        }
                        Write-Host ("Potential Hits: " +$PotHits.ToString())
                        $PotMatches = @($HashProps | Where-Object { $_.Length -eq $file.Length })
                        $hashset = Get-FileHash -LiteralPath $file.FullName
                        $file.Hash = $hashset.Hash
                        if ($file.Hash.Length -and ($PotMatches.Hash -eq $file.Hash))
                        {
                            $file.MoveLoc = $DupHashMovePath + $file.FullName.Substring($SrcL, $ExtLen)
                            $file.MoveFileFlag = 1
                            $file.MoveLbl = "HASH"
                        }
                    }
                    catch
                    {
                        Write-Host "Hash check failed to run against file " + $file.FullName
                    }
                }
            }
            $namekey = [System.ValueTuple[string]]::new($file.Name)
            if ($file.MoveFileFlag)
            {
                #Already set, do nothing.
            }
            elseif($namemap[$namekey].Count)
            {
                $file.MoveLoc = $DupNameMovePath + $file.FullName.Substring($SrcL, $ExtLen)
                $file.MoveFileFlag = 1
                $file.MoveLbl = "NAME"
            }
            elseif($DupJSONMovePath -and $file.Name.Contains(".json"))
            {
                $file.MoveLoc = $DupJSONMovePath + $file.FullName.Substring($SrcL, $ExtLen)
                $file.MoveFileFlag = 1
                $file.MoveLbl = "JSON"
            }
            $LoopProg += $file.Length

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
    }
    $Files2Move = @($AllFiles | Where-Object{ ( $_.MoveFileFlag -eq 1) })
    $Files2Move | Export-Csv -LiteralPath $MoveRepPath -NoTypeInformation
    Write-Host "List of files to move exported"
}
if($runvar -ne 1)
{
    $ImpFiles2Move = Import-CSV -LiteralPath $MoveRepPath
    $allfoldersneeded = $ImpFiles2Move | ForEach-Object { Split-Path $_.MoveLoc -Parent } | Select-Object -Unique | Sort-Object { $_.Length }
    #Creating all folders if needed
    foreach ($fldr in  $allfoldersneeded)
    {
        if (-Not (Test-Path -LiteralPath $fldr))
        {
            New-Item -Path $fldr -ItemType "directory" | Out-Null
        }
    }

    #Now move respective files
    foreach ($file2move in $ImpFiles2Move)
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