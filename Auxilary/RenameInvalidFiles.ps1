<#
.SYNOPSIS
    Auxiliary (standalone): strip '%' and '#' and turn '_' into spaces in every
    file/folder name under a drive/path. Deepest paths first so renames don't
    invalidate parent paths mid-run.
.NOTES
    NOT part of the FileBackup engine. Edit $folder before running. This renames
    in place with no preview — back up or test on a copy first.
#>
$folder = 'n:'
Get-ChildItem $folder -Recurse | ? {$_ -match '%|#|_'} | sort psiscontainer, {$_.fullname.length * -1} | % {ren $_.FullName $($_.name -replace '%|#' -replace '_', ' ')}