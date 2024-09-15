$folder = 'n:'
Get-ChildItem $folder -Recurse | ? {$_ -match '%|#|_'} | sort psiscontainer, {$_.fullname.length * -1} | % {ren $_.FullName $($_.name -replace '%|#' -replace '_', ' ')}