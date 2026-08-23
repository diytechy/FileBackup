#!/bin/sh
set -eu

config_path=${FILEBACKUP_CONFIG_PATH:-/config/FileBackup.json}
log_path=${FILEBACKUP_LOG_PATH:-/logs/Backup_Global.log}

# Action dispatch (SR-048). FILEBACKUP_ACTION selects backup (the default),
# prune or snapshots; a leading positional WORD overrides it. Anything starting
# with '-' is a FileBackup.ps1 flag and is left in "$@" untouched, so every
# existing flags-only invocation behaves exactly as it did before.
action=${FILEBACKUP_ACTION:-backup}
case "${1:-}" in
    backup|prune|snapshots)
        action=$1
        shift
        ;;
esac

case "$action" in
    backup)
        ;;
    prune)
        # Retention POLICY belongs to the caller (IF-001): only explicit names.
        if [ -n "${FILEBACKUP_SNAPSHOT:-}" ]; then
            set -- -Action Prune -Snapshot "$FILEBACKUP_SNAPSHOT" "$@"
        else
            set -- -Action Prune "$@"
        fi
        case "${FILEBACKUP_DRY_RUN:-}" in
            1|true|TRUE|True|yes|YES|Yes)
                set -- -WhatIf "$@"
                ;;
        esac
        ;;
    snapshots)
        set -- -Action Snapshots "$@"
        ;;
    *)
        echo "entrypoint: unknown action '$action' (expected backup, prune or snapshots)" >&2
        exit 2
        ;;
esac

exec pwsh -NoLogo -NoProfile -NonInteractive -File /opt/filebackup/FileBackup.ps1 \
    -ConfigPath "$config_path" \
    -GlobalLogPath "$log_path" \
    -NoMail \
    -NonInteractive \
    -ExitCode \
    "$@"
