#!/usr/bin/env bash
# configure-backup.sh - install a daily backup cron job for application data.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

BACKUP_SCRIPT="/usr/local/bin/backup-app.sh"
CRON_FILE="/etc/cron.d/backend-backup"

configure_backup() {
    log_info "Installing backup script..."
    if [[ ! -f "${REPO_ROOT}/backup/backup.sh" ]]; then
        die "backup/backup.sh not found in repo at ${REPO_ROOT}/backup/backup.sh"
    fi
    cp "${REPO_ROOT}/backup/backup.sh" "$BACKUP_SCRIPT"
    chmod 755 "$BACKUP_SCRIPT"

    mkdir -p /var/backups/backend-app

    log_info "Installing daily backup cron job (02:00)..."
    cat > "$CRON_FILE" <<'EOF'
0 2 * * * root /usr/local/bin/backup-app.sh
EOF
    chmod 644 "$CRON_FILE"
    log_info "Backup cron job installed at $CRON_FILE."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_backup
fi