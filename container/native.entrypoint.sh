#!/bin/sh
set -eu
for argument do
    case "$argument" in
        --config|--config=*) exec /opt/filebackup/filebackup "$@" ;;
    esac
done
exec /opt/filebackup/filebackup "$@" --config "${FILEBACKUP_CONFIG_PATH:-/config/FileBackup.json}"
