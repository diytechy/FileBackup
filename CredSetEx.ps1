<#
.SYNOPSIS
    Example config builder for FileBackup.ps1. Run once to produce the CLIXML
    config it reads (default: $HOME\BackupConfig.xml).

.DESCRIPTION
    Edit the values below and run under pwsh:  pwsh -File .\CredSetEx.ps1
    Get-Credential prompts for the SMTP account; CLIXML encrypts it under the
    current Windows user so it can be restored later by FileBackup.ps1.

    See README.md ("Config format") for every field. Mail is optional: omit the
    Secrets/SmtpServer fields (or run FileBackup.ps1 -NoMail) to skip it.
#>
@{
    Secrets = @{
        ToEmail     = 'you@example.com'
        FromEmail   = 'backup@example.com'
        SmtpServer  = 'smtp.example.com'
        SmtpPort    = 587
        Credential  = (Get-Credential)        # SMTP login; encrypted into the CLIXML
    }
    BackupSets = @(
        [pscustomobject]@{
            Name               = 'MainData'
            SourcePath         = 'D:\Data'
            BackupPath         = 'E:\Backups\DataStore'
            ChangePath         = 'E:\Backups\DataChanges'
            HashRecalcFreq     = 'W'    # A/E/D/W/M/Y/N — when to re-hash unchanged files
            CompressEnabled    = $true  # store data files as .7z
        }
    )
} | Export-Clixml -Path "$HOME\BackupConfig.xml"