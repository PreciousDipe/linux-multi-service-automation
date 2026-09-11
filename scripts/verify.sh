#!/usr/bin/env bash
# verify.sh - post-provision verification checks (correctness gate).
# Runs last: confirms every service configured above is actually up and responding.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

verify_deployment() {
    log_info "Running post-provision verification..."

    systemctl is-active --quiet nginx && log_info "nginx: active" || die "nginx is not running"
    systemctl is-active --quiet backend-app && log_info "backend-app: active" || die "backend-app is not running"
    systemctl is-active --quiet fail2ban && log_info "fail2ban: active" || die "fail2ban is not running"
    ufw status | grep -q "Status: active" && log_info "ufw: active" || die "ufw is not active"

    local health
    health="$(curl -fsS --max-time 5 http://127.0.0.1/health)" || die "Health check via nginx failed"
    log_info "Health check response: $health"

    log_info "All verification checks passed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    verify_deployment
fi