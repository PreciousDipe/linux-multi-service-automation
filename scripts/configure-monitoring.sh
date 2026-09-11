#!/usr/bin/env bash
# configure-monitoring.sh - install a cron job that checks service health every 5 minutes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

MONITOR_SCRIPT="/usr/local/bin/health-check.sh"
CRON_FILE="/etc/cron.d/backend-health-check"

configure_monitoring() {
    log_info "Installing health-check monitoring script..."
    cp "${REPO_ROOT}/monitoring/health-check.sh" "$MONITOR_SCRIPT"
    chmod 755 "$MONITOR_SCRIPT"

    log_info "Installing cron job (every 5 minutes)..."
    cat > "$CRON_FILE" <<'EOF'
*/5 * * * * root /usr/local/bin/health-check.sh >> /var/log/backend-health.log 2>&1
EOF
    chmod 644 "$CRON_FILE"

    log_info "Monitoring cron job installed at $CRON_FILE."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_monitoring
fi