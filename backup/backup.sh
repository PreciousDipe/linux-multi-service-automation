#!/usr/bin/env bash
# backup.sh - creates a verified, timestamped backup of application data
# and prunes old backups beyond the retention window.
# Installed to /usr/local/bin and run daily via cron.
set -euo pipefail

APP_DIR="/opt/backend-app"
BACKUP_DIR="/var/backups/backend-app"
RETENTION_DAYS=7
TS="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE_NAME="backend-app-${TS}.tar.gz"
DEST="${BACKUP_DIR}/${ARCHIVE_NAME}"
LOG_FILE="/var/log/backend-backup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"

log "Starting backup of ${APP_DIR}..."
tar --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    -czf "$DEST" \
    -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")" \
    || { log "ERROR: tar failed, aborting backup"; exit 1; }

if tar -tzf "$DEST" >/dev/null 2>&1; then
    log "Backup created and verified: $DEST ($(du -h "$DEST" | cut -f1))"
else
    log "ERROR: backup archive failed integrity check, removing corrupt file"
    rm -f "$DEST"
    exit 1
fi

DELETED=$(find "$BACKUP_DIR" -name '*.tar.gz' -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
log "Pruned ${DELETED} backup(s) older than ${RETENTION_DAYS} days"

log "Backup run complete."