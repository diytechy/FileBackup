<#
.SYNOPSIS
    Auxiliary (standalone): quarantine likely-duplicate files out of a folder by
    matching them against pre-built "*HashTable.csv" databases.

.DESCRIPTION
    NOT part of the FileBackup engine and unrelated to its MANIFEST.csv schema.
    Reads one or more legacy hash-table CSVs (FullName/Length/LastWriteTimeStr/
    Hash columns) listed in $HashPaths, then scans $CmprPath and flags each file
    that matches a database entry by, in order: (name+size+date), SHA256 hash
    (only when $AllowHash), or base name. Flagged files are moved under the
    corresponding Dup* folder, preserving relative paths; empty source folders
    are pruned. Hashing uses Get-FileHash (SHA256), NOT xxHash128.

    Controls: $runvar (0=plan+move, 1=plan only, 2=move from existing CSV only),
    $AllowHash (enable the expensive hash pass). Edit all hardcoded paths first.
#>

#First clean out variables (for clean run)
Get-Variable -Exclude PWD,*Preference | Remove-Variable -EA 0

$runvar = 0
$AllowHash = 0
$MoveRepPath = "D:\Files2Move.csv"
$InvFilenameRepPath = "D:\InvalidFilenames.csv"
$HashPaths = @(
#"A:\SharedFilesHashTable.csv"
#"A:\PrivateFilesHashTable.csv"
#"A:\NonDocsFilesHashTable.csv"
"D:\SharedFilesHashTable.csv"
"D:\PrivateFilesHashTable.csv"
"D:\NonDocsFilesHashTable.csv"
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
$AllFiles | Add-Member -MemberType NoteProperty -Name ValidFilename -Value $([int16]0)
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLoc  -Value $([string]"****************************************************************")
$AllFiles | Add-Member -MemberType NoteProperty -Name MoveLbl  -Value $([string]"****")
$AllFilesizeTtl = $AllFiles | Measure-Object -Property Length -Sum ; $AllFilesizeTtl =$AllFilesizeTtl.Sum

$datemap = @{}
$namemap = @{}
$hashmap = @{}
$sizemap = @{}
$index = 0
foreach ($srcprop in $HashProps){
    $srcprop.Name = ($srcprop.FullName | Split-Path -Leaf)
    $srcprop.LastWriteTimeDateTime = [datetime]::ParseExact($srcprop.LastWriteTimeStr, $HashTblDateFormat, $null)
    $datekey = [System.ValueTuple[string, long, datetime]]::new(
    $srcprop.Name, $srcprop.Length, $srcprop.LastWriteTimeDateTime)
    $namekey = [System.ValueTuple[string]]::new([System.IO.Path]::GetFileNameWithoutExtension($srcprop.Fullname))
    $sizekey = [System.ValueTuple[long]]::new($srcprop.Length)

    $datemap[$datekey] = 1
    $namemap[$namekey] = 1
    $sizemap[$sizekey] = 1

        if ($srcprop.Name -eq "Bionic Commando.nes")
        {
            #Write-Host "Chk"
        }
    $index++
}
Write-Host "Data prepared."

$InnerLoopProg.Activity = "Getting properties of check files to compare..."
$InnerLoopProg.Status = "Please wait..."
$CurrInnerProgDbl[0] = 0;
$InnerLoopProg.PercentComplete = ($CurrInnerProgDbl[0] * 100)
$LoopProg = 0;
$PrevInnerProgPercInt[0] = -1;

#Shorten length for simplicity
$SrcL = $CmprPath.Length
$EnblFlg = 1
$FilesChecked = 0
if((Test-Path -LiteralPath $CmprPath) -and ($AllFiles.Count) -and ($runvar -ne 2) -and $EnblFlg)
{

    foreach ($file in $AllFiles)
    {
        if(Test-Path -LiteralPath $file.FullName)
        {
            $file.ValidFilename = 1
            $FilesChecked++
        }
    }
    #$AllFiles = ($AllFiles | Where-Object -Property ValidFilename -eq 1)
    Write-Host ("Total files validated: "+$FilesChecked.ToString())
    #Write-Host ("Total files validated: "+$AllFiles.Count.ToString())
    $index = 0
    foreach ($file in ($AllFiles | Where-Object -Property ValidFilename -eq 1))
    {
        if ($file.Name -eq "Bionic Commando.nes")
        {
            #Write-Host "Chk"
        }
        $index++
    }
    $index = 0
    foreach ($file in ($AllFiles | Where-Object -Property ValidFilename -eq 1))
    {
        if($file.Length) # -and ($index -ge 2876)
        {
            $sizekey = [System.ValueTuple[long]]::new($file.Length)
            $ExtLen = $file.FullName.Length - $SrcL
            #First, see if the file size has any matches in the databases, if not, it's definitely not a duplicate.
            #$PotMatches = @($HashProps | Where-Object { $_.Length -eq $file.Length })
            #$PotMatches = $HashProps.Where  $_.Length -eq $file.Length
            if ($sizemap[$sizekey])
            #if ($PotMatches.Count -and $EnblFlg)
            {
                #Get substring def.
                $key = [System.ValueTuple[string, long, datetime]]::new(
                        $file.Name, $file.Length, $file.LastWriteTime)
                if ($datemap[$key])
                {
                    $file.MoveLoc = $DupDateMovePath + $file.FullName.Substring($SrcL, $ExtLen)
                    $file.MoveFileFlag = 1
                    $file.MoveLbl = "DATE"
                }
                elseif($AllowHash)
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
                            $hashkey = [System.ValueTuple[string, long]]::new($potfile.Hash, $potfile.Length)
                            $hashmap[$hashkey] = 1
                            $PotHits++

                        }
                        Write-Host ("Potential Hits: " +$PotHits.ToString())
                        #$PotMatches = @($HashProps | Where-Object { $_.Length -eq $file.Length })
                        $hashset = Get-FileHash -LiteralPath $file.FullName
                        $file.Hash = $hashset.Hash
                        $hashkey = [System.ValueTuple[string, long]]::new($file.Hash, $file.Length)
                        if ($hashmap[$hashkey] )
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
            $namekey = [System.ValueTuple[string]]::new([System.IO.Path]::GetFileNameWithoutExtension($file.Fullname))
            if ($file.MoveFileFlag)
            {
                #Already set, do nothing.
            }
            elseif($namemap[$namekey])
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
        $index++
    }
    $Files2Move = @($AllFiles | Where-Object{ ( $_.MoveFileFlag -eq 1) })
    $Files2Move | Select-Object -Property MoveLbl,FullName,MoveLoc | Export-Csv -LiteralPath $MoveRepPath -NoTypeInformation
    #$AllFiles = ($AllFiles | Where-Object -Property ValidFilename -eq 1)
    $InvalidFileList = @($AllFiles | Where-Object -Property ValidFilename -ne 1)
    $InvalidFileList | Select-Object -Property FullName | Export-Csv -LiteralPath $InvFilenameRepPath -NoTypeInformation
    Write-Host "List of invalid files and files to move exported"
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
    Write-Host "All Complete!"