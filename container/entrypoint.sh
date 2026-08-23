#!/bin/sh
set -eu

config_path=${FILEBACKUP_CONFIG_PATH:-/config/FileBackup.json}
log_path=${FILEBACKUP_LOG_PATH:-/logs/Backup_Global.log}

exec pwsh -NoLogo -NoProfile -NonInteractive -File /opt/filebackup/FileBackup.ps1 \
    -ConfigPath "$config_path" \
    -GlobalLogPath "$log_path" \
    -NoMail \
    -NonInteractive \
    -ExitCode \
    "$@"
