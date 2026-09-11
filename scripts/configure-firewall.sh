#!/usr/bin/env bash
# configure-firewall.sh - configure UFW with only necessary ports open.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

configure_firewall() {
    log_info "Configuring UFW firewall (default deny incoming)..."

    # Reset first so reruns always converge to the same rule set,
    # instead of accumulating duplicate/stale rules over time.
    ufw --force reset >>"$LOG_FILE" 2>&1
    ufw default deny incoming >>"$LOG_FILE" 2>&1
    ufw default allow outgoing >>"$LOG_FILE" 2>&1

    # Only open what's actually needed: SSH to manage the box, HTTP for the proxy.
    ufw allow 22/tcp comment 'SSH' >>"$LOG_FILE" 2>&1
    ufw allow 80/tcp comment 'HTTP' >>"$LOG_FILE" 2>&1

    # 443 only opens if TLS was requested via provision.sh --with-tls.
    if [[ "${ENABLE_TLS:-false}" == "true" ]]; then
        ufw allow 443/tcp comment 'HTTPS' >>"$LOG_FILE" 2>&1
        log_info "Port 443 opened (TLS enabled)."
    fi

    # Note: port 3000 (the backend) is intentionally never opened here —
    # it's only reachable via nginx on 127.0.0.1.
    ufw --force enable >>"$LOG_FILE" 2>&1
    log_info "UFW firewall enabled. Current status:"
    ufw status verbose | tee -a "$LOG_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_firewall
fi