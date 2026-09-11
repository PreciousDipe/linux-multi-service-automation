#!/usr/bin/env bash
# configure-logrotate.sh - create app log directory and deploy logrotation policy.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

APP_USER="${APP_USER:-appsvc}"
# Matches the path hardcoded in app/app.py's logging.basicConfig(filename=...)
LOG_DIR="/var/log/myapp"

configure_logrotate() {
    log_info "Creating application log directory at $LOG_DIR..."
    # This must exist BEFORE the Flask app starts, since it opens
    # app.log for writing immediately on import.
    install -d -o "$APP_USER" -g "$APP_USER" -m 750 "$LOG_DIR"
    touch "${LOG_DIR}/app.log"
    chown "${APP_USER}:${APP_USER}" "${LOG_DIR}/app.log"

    log_info "Deploying logrotate policy for applications."
    cp "${REPO_ROOT}/logrotate/backend-app" /etc/logrotate.d/backend-app

    # -d = dry run: validates the policy syntax without actually rotating anything.
    logrotate -d /etc/logrotate.d/backend-app >>"$LOG_FILE" 2>&1 \
        || log_warn "logrotate dry-run reported warnings, review $LOG_FILE"

    log_info "Log rotation configured."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_logrotate
fi