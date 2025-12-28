@{
    Secrets = @{
        ToEmail     = 'you@example.com'
        FromEmail   = 'backup@example.com'
        Credential  = (Get-Credential)  # saved via Export-Clixml beforehand
    }
    BackupSets = @(
        [pscustomobject]@{
            Name            = 'MainData'
            SourcePath      = 'D:\Data'
            BackupPath      = 'E:\Backups\DataStore'
            ChangePath      = 'E:\Backups\DataChanges'
            HashRecalcFreq  = 'W'   # D/W/M
            CompressEnabled = $true # or $false
        }
    )
} | Export-Clixml -Path "$HOME\BackupConfig.xml"