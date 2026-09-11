#!/usr/bin/env bash
# configure-fail2ban.sh - configure fail2ban jails for SSH and nginx.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

configure_fail2ban() {
    apt_install_if_missing fail2ban

    log_info "Deploying fail2ban jail.local..."
    # jail.local overrides fail2ban's defaults (jail.conf) without editing
    # the package-managed file directly — the standard fail2ban convention.
    cp "${REPO_ROOT}/fail2ban/jail.local" /etc/fail2ban/jail.local

    systemctl enable fail2ban >>"$LOG_FILE" 2>&1
    systemctl restart fail2ban
    log_info "fail2ban configured. Active jails:"
    # || log_warn here (not die) because fail2ban-client can be briefly
    # unresponsive right after a restart — not worth failing the whole run over.
    fail2ban-client status | tee -a "$LOG_FILE" || log_warn "Could not query fail2ban-client status yet."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_fail2ban
fi