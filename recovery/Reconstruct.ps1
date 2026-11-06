<#
.SYNOPSIS
Independent recovery for native metadata v1. No native engine or network required.
.DESCRIPTION
Run in a trusted, exclusively controlled target tree. Requires PowerShell 7 and
the carried Common module and hashing DLL; 7-Zip only for compressed content.
#>
# KitRevision: 17
#requires -Version 7.0
# Implements: LLR-172, LLR-173, LLR-174, LLR-175, LLR-176, LLR-179
[CmdletBinding()]
param(
    [string]$TargetRoot,
    [string]$StoreRootOverride,
    [string]$RecordRoot = $PSScriptRoot,
    [string]$SevenZipPath,
    [switch]$Previous,
    [switch]$NonInteractive,
    [switch]$Interactive,
    [switch]$ExitCode
)
$ErrorActionPreference = 'Stop'
$script:Result = 0
$script:PreflightCode = 2
$script:RestoredFiles = 0
$script:FailedFiles = 0
$script:MetadataFailures = 0
function Write-Finding([int]$Code, [string]$Message) {
    if ($Code -eq 4 -or ($Code -eq 1 -and $script:Result -eq 0)) { $script:Result = $Code }
    Write-Warning $Message
}
function Write-MetadataFinding([string]$Message) {
    $script:MetadataFailures++
    Write-Finding 1 $Message
}
function Test-RecordedPath([string]$Path) {
    if (-not $Path -or $Path.StartsWith('/') -or $Path -match '[\x00-\x1f\\:*?"<>|]') { return $false }
    foreach ($part in $Path.Split('/')) {
        if (-not $part -or $part -in '.', '..' -or $part -match '[ .]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { return $false }
    }
    return $true
}
function Assert-OrdinaryAncestors([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        try {
            if ([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) { throw "Unsafe redirected path: $cursor" }
        } catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] {
            Write-Verbose 'Target ancestry component not yet created.'
        }
        # Other access/I/O failures remain errors: ordinary ancestry is unconfirmed.
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
function Test-Within([string]$Child, [string]$Parent) {
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return $Child.Equals($Parent, $comparison) -or $Child.StartsWith($Parent.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, $comparison)
}
function Get-RowKey($Row) { return "$($Row.xxH2Hash)|$($Row.Length)" }
function Get-PathKey([string]$Text) {
    # ASCII has no decomposition/combining marks; its full fold is A-Z -> a-z.
    # Keep the generated Unicode mapping for every non-ASCII path.
    if ($Text -cmatch '^[\x00-\x7f]*$') { return $Text.ToLowerInvariant() }
    $mapped = [Text.StringBuilder]::new()
    for ($i=0; $i -lt $Text.Length; $i++) {
        $count = if ([char]::IsHighSurrogate($Text[$i])) { 2 } else { 1 }
        $c = $Text.Substring($i,$count); $i += $count - 1
        [void]$mapped.Append($(if ($script:Fold.ContainsKey($c)) { $script:Fold[$c] } else { $c }))
    }
    $text = $mapped.ToString()
    $letters = [Collections.Generic.List[string]]::new()
    $classes = [Collections.Generic.List[int]]::new()
    for ($i=0; $i -lt $Text.Length; $i++) {
        $count = if ([char]::IsHighSurrogate($Text[$i])) { 2 } else { 1 }
        $c = $Text.Substring($i,$count); $i += $count - 1
        $class = if ($script:Combining.ContainsKey($c)) { $script:Combining[$c] } else { 0 }
        $j = $letters.Count
        while ($class -ne 0 -and $j -gt 0 -and $classes[$j-1] -gt $class) { $j-- }
        $letters.Insert($j,$c); $classes.Insert($j,$class)
    }
    return [string]::Concat($letters)
}
function Read-NativeRows([string]$Path, [string[]]$Columns) {
    $reader = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Path, [Text.Encoding]::UTF8, $true)
    try {
        $reader.SetDelimiters(','); $reader.TrimWhiteSpace = $false
        $header = $reader.ReadFields()
        if ($header.Count -ne $Columns.Count -or ($header -join ',') -cne ($Columns -join ',')) { throw 'Unsupported record header.' }
        while (-not $reader.EndOfData) {
            $fields = $reader.ReadFields()
            if ($fields.Count -ne $Columns.Count) { throw 'Malformed record shape.' }
            $row = [ordered]@{}
            for ($i = 0; $i -lt $Columns.Count; $i++) { $row[$Columns[$i]] = $fields[$i] }
            [pscustomobject]$row
        }
    } finally { $reader.Dispose() }
}
function Expand-BoundedObject([string]$Archive, [string]$Destination, [long]$Length) {
    $info = [Diagnostics.ProcessStartInfo]::new($SevenZipPath)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    foreach ($arg in @('e','-so','-mmt=2','-y','--',$Archive)) { $info.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::Start($info)
    $process.StandardInput.Close()
    [void]$process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
    $output = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $deadline = 300.0 + $Length / 1MB
    $buffer = [byte[]]::new(262144); [long]$written = 0
    try {
        $output = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write)
        while ($true) {
            if ($watch.Elapsed.TotalSeconds -gt $deadline) { throw [TimeoutException]::new('Extractor deadline exceeded.') }
            $read = $process.StandardOutput.BaseStream.ReadAsync($buffer, 0, $buffer.Length)
            while (-not $read.Wait(1000)) {
                if ($watch.Elapsed.TotalSeconds -gt $deadline) { throw [TimeoutException]::new('Extractor deadline exceeded.') }
            }
            $count = $read.GetAwaiter().GetResult()
            if ($count -eq 0) { break }
            if ($count -gt $Length - $written) { throw [IO.InvalidDataException]::new('Archive expands beyond recorded length.') }
            $output.Write($buffer, 0, $count); $written += $count
        }
        while (-not $process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -gt $deadline) { throw [TimeoutException]::new('Extractor deadline exceeded.') }
        }
        if ($process.ExitCode -ne 0 -or $written -ne $Length) { throw [IO.InvalidDataException]::new('Archive content is incomplete.') }
        $output.Flush($true)
    } finally {
        if (-not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(5000) }
        # Do not wait for EOF from inherited descendant pipes after the direct
        # process exits. Closing our ends also releases any pending async read.
        $process.StandardOutput.Close(); $process.StandardError.Close()
        if ($output) { $output.Dispose() }
        $process.Dispose()
    }
}
function Test-Content([string]$Path, $Row) {
    return (Get-Item -LiteralPath $Path).Length -eq [long]$Row.Length -and (Get-FileXxHash -FilePath $Path) -eq $Row.xxH2Hash
}
function Confirm-RecoveryKit {
    $found = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadLines((Join-Path $PSScriptRoot 'KIT.sha256'))) {
        if ($line -cnotmatch '^([0-9a-f]{64})  ([A-Za-z0-9._-]+)$' -or -not $found.Add($Matches[2])) { throw 'Invalid recovery kit inventory.' }
        $path = Join-Path $PSScriptRoot $Matches[2]
        $expected = $Matches[1]
        Assert-OrdinaryAncestors $path
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected) { throw 'Recovery kit is incomplete or mixed; use the preserved RECOVERY.previous route with explicit record/store roots.' }
    }
    foreach ($name in 'RECONSTRUCT.ps1','reconstruct.sh','reconstruct-core.sh','path-keys.awk','path-keys.tsv','FileBackup.Common.psm1','System.IO.Hashing.dll') {
        if (-not $found.Contains($name)) { throw 'Required kit inventory member is missing.' }
    }
}
try {
    if ($TargetRoot) { $Interactive = $false }
    elseif ($NonInteractive -or -not $Interactive -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'An explicit TargetRoot is required for unattended recovery.' }
    else {
        if ($IsWindows) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
                $dialog.Description = 'Choose the recovery target outside the backup store'
                try { if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $TargetRoot = $dialog.SelectedPath } }
                finally { $dialog.Dispose() }
            } catch { $TargetRoot = Read-Host 'Recovery target (absolute path; blank cancels)' }
        } else { $TargetRoot = Read-Host 'Recovery target (absolute path; blank cancels)' }
        if (-not $TargetRoot) { if ($ExitCode) { exit 0 }; return }
    }
    foreach ($root in @($TargetRoot, $RecordRoot, $StoreRootOverride)) {
        if ($root -and -not [IO.Path]::IsPathFullyQualified($root)) { throw 'Use absolute target, record and store paths.' }
    }
    Confirm-RecoveryKit
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'System.IO.Hashing.dll'))) { throw 'Missing carried System.IO.Hashing.dll; restore the complete recovery kit.' }
    Import-Module (Join-Path $PSScriptRoot 'FileBackup.Common.psm1') -Force
    Initialize-XxHashLibrary | Out-Null
    $script:Fold = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $script:Combining = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadLines((Join-Path $PSScriptRoot 'path-keys.tsv'))) {
        if ($line.StartsWith('#')) { continue }
        $parts = $line.Split("`t")
        $script:Fold[$parts[0]]=$parts[1]; $script:Combining[$parts[0]]=[int]$parts[2]
    }
    if (-not $script:Fold.ContainsKey('A')) { throw 'Required path comparison data is invalid.' }
    $RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
    if ($StoreRootOverride) { $store = [IO.Path]::GetFullPath($StoreRootOverride) }
    elseif ([IO.Path]::GetFileName($RecordRoot) -ceq 'CurrentBackup') { $store = [IO.Path]::GetDirectoryName($RecordRoot) }
    elseif ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($RecordRoot)) -ceq 'BackupHistory' -and [IO.Path]::GetFileName($RecordRoot) -match '^\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}(?:_\d+)?$') { $store = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($RecordRoot)) }
    else { throw 'Specify StoreRootOverride for a kit outside CurrentBackup or dated BackupHistory.' }
    $TargetRoot = [IO.Path]::GetFullPath($TargetRoot)
    Assert-OrdinaryAncestors $TargetRoot
    Assert-OrdinaryAncestors $store
    Assert-OrdinaryAncestors $RecordRoot
    if ((Test-Within $TargetRoot $store) -or (Test-Within $store $TargetRoot) -or
        (Test-Within $TargetRoot $RecordRoot) -or (Test-Within $RecordRoot $TargetRoot) -or
        (Test-Within $TargetRoot $PSScriptRoot) -or (Test-Within $PSScriptRoot $TargetRoot)) { throw 'Restore target overlaps protected store/record/kit paths.' }
    $suffix = if ($Previous) { '.prev' } else { '' }
    $manifest = Join-Path $RecordRoot "MANIFEST.csv$suffix"
    $directories = Join-Path $RecordRoot "DIRECTORIES.csv$suffix"
    $expected = 'DataPath,RelativePath,Length,LastWriteTimeStr,xxH2Hash,Compressed,StoredAsHashSize,Duplicate,MediaMBPerSec'
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $fileAncestors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [long]$bytes = 0
    [long]$largest = 0
    Read-NativeRows $manifest $expected.Split(',') | ForEach-Object {
        if (-not (Test-RecordedPath $_.RelativePath) -or $_.xxH2Hash -cnotmatch '^[0-9A-F]{32}$' -or $_.Length -notmatch '^\d+$' -or $_.StoredAsHashSize -cne 'Hash' -or $_.Compressed -cnotin 'Yes','No') { throw 'Malformed file record.' }
        if (-not $files.Add((Get-PathKey $_.RelativePath))) { throw 'File paths collide on the portable target profile.' }
        $length = [long]$_.Length
        if ($length -gt [long]::MaxValue - $bytes) { throw 'Output allocation overflows the supported range.' }
        $bytes += $length
        $largest = [Math]::Max($largest, $length)
    }
    foreach ($path in $files) {
        $parent = $path
        while ($parent.Contains('/')) {
            $parent = $parent.Substring(0, $parent.LastIndexOf('/'))
            [void]$fileAncestors.Add($parent)
            if ($files.Contains($parent)) { throw 'A file path is the ancestor of another file.' }
        }
    }
    $knownFree = Get-FreeSpaceBytes -Path $TargetRoot
    if ($null -eq $knownFree) { Write-Warning 'Target capacity is unavailable; recovery will stop on write failure.' }
    elseif ([double]$knownFree -lt ([double]$bytes + $largest + 4096.0 * $files.Count)) { $script:PreflightCode = 4; throw 'Insufficient space for expanded output, temporary replacement and filesystem overhead.' }
    if (-not $SevenZipPath) {
        $tool = Get-Command 7z,7zz,7za -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($tool) { $SevenZipPath = $tool.Source }
        elseif ($IsWindows -and (Test-Path -LiteralPath "$env:ProgramFiles/7-Zip/7z.exe")) { $SevenZipPath = "$env:ProgramFiles/7-Zip/7z.exe" }
    }
    $pool = [Collections.Generic.Dictionary[string,Collections.Generic.List[string]]]::new([StringComparer]::Ordinal)
    $states = @((Join-Path $store 'CurrentBackup'))
    if (Test-Path -LiteralPath (Join-Path $store 'BackupHistory')) {
        $states += @(Get-ChildItem -LiteralPath (Join-Path $store 'BackupHistory') -Directory -Force | Where-Object Name -Match '^\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}(?:_\d+)?$' | ForEach-Object FullName)
    }
    foreach ($state in $states) {
        try {
            Assert-OrdinaryAncestors $state
            $objects = if ($state -eq (Join-Path $store 'CurrentBackup')) {
                Get-ChildItem -LiteralPath $state -Directory -Force | Where-Object Name -Match '^[2-9a-z]{2}$' | ForEach-Object {
                    Assert-OrdinaryAncestors $_.FullName
                    Get-ChildItem -LiteralPath $_.FullName -File -Force
                }
            } else { Get-ChildItem -LiteralPath $state -File -Force }
            foreach ($object in $objects) {
                if ($object.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $identity = ConvertFrom-HashSizeFileName -Name $object.Name
                if (-not $identity) { continue }
                if ($state -eq (Join-Path $store 'CurrentBackup') -and $object.Directory.Name -cne $object.Name.Substring(0,2).ToLowerInvariant()) { continue }
                $key = "$($identity.HashHex)|$($identity.Length)"
                if (-not $pool.ContainsKey($key)) { $pool[$key] = [Collections.Generic.List[string]]::new() }
                $pool[$key].Add($object.FullName)
            }
        } catch { Write-Finding 4 "Pool cannot be inspected: $state" }
    }
    # Inspect actual forms before any target mutation, even when a row's flag is stale.
    $needsExtractor = $false
    $inspected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    Read-NativeRows $manifest $expected.Split(',') | ForEach-Object {
        $row = $_
        $key = Get-RowKey $row
        if ($inspected.Add($key) -and $pool.ContainsKey($key)) {
            $hasArchive = $false
            $rawCandidates = [Collections.Generic.List[string]]::new()
            foreach ($candidate in $pool[$key]) {
                try {
                    $form = Get-StoredObjectForm -Path $candidate -ExpectedHash $row.xxH2Hash -ExpectedLength ([long]$row.Length)
                    if ($form -eq 'Archive') { $hasArchive = $true }
                    elseif ($form -eq 'Raw') { $rawCandidates.Add($candidate) }
                } catch { Write-Verbose "Candidate cannot be inspected: $candidate" }
            }
            if ($hasArchive) {
                $rawSupply = $null
                foreach ($candidate in $rawCandidates) {
                    try { if (Test-Content $candidate $row) { $rawSupply = $candidate; break } }
                    catch { Write-Verbose "Candidate cannot be verified: $candidate" }
                }
                if ($rawSupply) {
                    [void]$pool[$key].Remove($rawSupply)
                    $pool[$key].Insert(0, $rawSupply)
                } else { $needsExtractor = $true }
            }
        }
    }
    if ($needsExtractor) {
        $script:PreflightCode = 4
        if (-not $SevenZipPath) { throw 'Compressed content requires local 7-Zip; install it or supply SevenZipPath.' }
        $info = [Diagnostics.ProcessStartInfo]::new($SevenZipPath)
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $info.ArgumentList.Add('i')
        $probe = [Diagnostics.Process]::Start($info)
        try {
            $probe.StandardInput.Close()
            [void]$probe.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
            [void]$probe.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
            if (-not $probe.WaitForExit(10000)) { $probe.Kill($true); [void]$probe.WaitForExit(5000); throw '7-Zip prerequisite check timed out.' }
            if ($probe.ExitCode -ne 0) { throw '7-Zip prerequisite check failed.' }
        } finally { $probe.StandardOutput.Close(); $probe.StandardError.Close(); $probe.Dispose() }
        $script:PreflightCode = 2
    }
    [IO.Directory]::CreateDirectory($TargetRoot) | Out-Null
    Read-NativeRows $manifest $expected.Split(',') | ForEach-Object {
        $row = $_
        $target = Join-Path $TargetRoot $row.RelativePath
        $temporary = $null
        try {
            Assert-OrdinaryAncestors $target
            $parent = [IO.Path]::GetDirectoryName($target)
            [IO.Directory]::CreateDirectory($parent) | Out-Null
            $temporary = Join-Path $parent ('.filebackup-' + [guid]::NewGuid().ToString('N'))
            $key = Get-RowKey $row
            $restored = $false
            if ($pool.ContainsKey($key)) {
                foreach ($candidate in $pool[$key]) {
                    try {
                        $form = Get-StoredObjectForm -Path $candidate -ExpectedHash $row.xxH2Hash -ExpectedLength ([long]$row.Length)
                        if ($form -eq 'Archive') {
                            if (-not $SevenZipPath) { Write-Finding 4 'Compressed content requires a local 7-Zip executable.'; continue }
                            Expand-BoundedObject $candidate $temporary ([long]$row.Length)
                        } else {
                            if ((Get-Item -LiteralPath $candidate).Length -ne [long]$row.Length) { continue }
                            [IO.File]::Copy($candidate, $temporary, $true)
                        }
                        if (Test-Content $temporary $row) { $restored = $true; break }
                    } catch [TimeoutException] { Write-Finding 4 "Extractor deadline exceeded: $($row.RelativePath)" }
                    catch { Write-Verbose "Candidate failed: $candidate" }
                }
            }
            if (-not $restored) {
                $script:FailedFiles++
                $cause = if ($pool.ContainsKey($key)) { 'No candidate passed content checks' } else { 'Content identity missing from pool' }
                Write-Finding 1 "${cause}: $($row.RelativePath)"; return
            }
            Assert-OrdinaryAncestors $target
            [IO.File]::SetAttributes($temporary, [IO.FileAttributes]::Normal)
            Sync-FileToDisk -LiteralPath $temporary
            [IO.File]::Move($temporary, $target, $true)
            $script:RestoredFiles++
            try { [IO.File]::SetLastWriteTimeUtc($target, [datetime]::Parse($row.LastWriteTimeStr).ToUniversalTime()) }
            catch { Write-Warning "Timestamp unavailable: $($row.RelativePath)" }
        } catch { $script:FailedFiles++; Write-Finding 4 "Target write failed: $($row.RelativePath): $($_.Exception.Message)" }
        finally { if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force } }
    }
    $metadata = @()
    try {
        $metadata = @(Read-NativeRows $directories @('RelativePath','Attributes','EntryKind','LinkTarget'))
    } catch { Write-MetadataFinding 'Required directory/link metadata is unavailable; independent files were recovered.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $acceptedDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $links = [Collections.Generic.List[object]]::new()
    foreach ($row in ($metadata | Sort-Object { $_.RelativePath.Length })) {
        try {
            $rel = $row.RelativePath
            $key = Get-PathKey $rel
            if (-not (Test-RecordedPath $rel) -or -not $seen.Add($key) -or $files.Contains($key) -or $row.EntryKind -cnotin 'Directory','FolderLink') { throw 'Invalid/conflicting directory record.' }
            $ancestor = $key
            while ($ancestor.Contains('/')) {
                $ancestor = $ancestor.Substring(0, $ancestor.LastIndexOf('/'))
                if ($files.Contains($ancestor)) { throw 'Metadata conflicts with independent file content.' }
            }
            if ($row.EntryKind -ceq 'FolderLink' -and $fileAncestors.Contains($key)) { throw 'Link metadata conflicts with file content.' }
            $full = Join-Path $TargetRoot $rel
            Assert-OrdinaryAncestors $full
            if ($row.EntryKind -ceq 'FolderLink') { $links.Add($row); continue }
            if ($row.LinkTarget) { throw 'Ordinary directory carries a target.' }
            [IO.Directory]::CreateDirectory($full) | Out-Null
            [void]$acceptedDirectories.Add($key)
        } catch { Write-MetadataFinding "Directory metadata rejected: $($row.RelativePath)" }
    }
    foreach ($row in $links) {
        try {
            if ($row.LinkTarget -ne '.' -and -not (Test-RecordedPath $row.LinkTarget)) { throw 'Invalid link mapping.' }
            $targetKey = Get-PathKey $row.LinkTarget
            if ($row.LinkTarget -ne '.' -and -not $acceptedDirectories.Contains($targetKey) -and -not $fileAncestors.Contains($targetKey)) { throw 'Link destination is not captured.' }
            $target = if ($row.LinkTarget -eq '.') { $TargetRoot } else { Join-Path $TargetRoot $row.LinkTarget }
            Assert-OrdinaryAncestors $target
            if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw 'Link destination is unavailable.' }
            $link = Join-Path $TargetRoot $row.RelativePath
            Assert-OrdinaryAncestors $link
            if (Test-Path -LiteralPath $link) { throw 'Link path already occupied.' }
            $parent = [IO.Path]::GetDirectoryName($link)
            [IO.Directory]::CreateDirectory($parent) | Out-Null
            $relative = [IO.Path]::GetRelativePath($parent,$target)
            try { [IO.Directory]::CreateSymbolicLink($link,$relative) | Out-Null }
            catch { Write-MetadataFinding "Host cannot recreate relative folder link: $($row.RelativePath)" }
        } catch { Write-MetadataFinding "Link metadata rejected: $($row.RelativePath)" }
    }
    foreach ($row in ($metadata | Sort-Object { $_.RelativePath.Length } -Descending)) {
        if ($row.EntryKind -ceq 'Directory' -and $row.Attributes -and $acceptedDirectories.Contains((Get-PathKey $row.RelativePath))) {
            try {
                $full = Join-Path $TargetRoot $row.RelativePath
                Assert-OrdinaryAncestors $full
                if ($IsWindows) { [IO.File]::SetAttributes($full, (ConvertTo-DirectoryAttributeFlag -Token $row.Attributes)) }
                else { Write-Warning "Windows directory attributes not applied: $($row.RelativePath)" }
            } catch { Write-Warning "Directory attributes unavailable: $($row.RelativePath)" }
        }
    }
} catch {
    if ($Interactive -and -not $NonInteractive -and -not [Console]::IsInputRedirected) { Write-Warning $_.Exception.Message; [void](Read-Host 'Press Enter to close') }
    if ($ExitCode) { Write-Error $_ -ErrorAction Continue; exit $script:PreflightCode }
    throw
}
Write-Output ("Recovery totals: restored={0}, failed={1}, required-metadata-findings={2}, exit={3}" -f $script:RestoredFiles,$script:FailedFiles,$script:MetadataFailures,$script:Result)
if ($Interactive -and -not $NonInteractive -and -not [Console]::IsInputRedirected) { Write-Host "Recovery finished with exit $script:Result"; [void](Read-Host 'Press Enter to close') }
if ($ExitCode) { exit $script:Result }
if ($script:Result -ne 0) { throw "Recovery incomplete (exit $script:Result)." }
