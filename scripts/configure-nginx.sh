#!/usr/bin/env bash
# configure-nginx.sh - install and configure nginx as a reverse proxy to the backend.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

configure_nginx() {
    apt_install_if_missing nginx

    log_info "Deploying nginx reverse proxy config..."
    cp "${PROJECT_ROOT}/nginx/upstream.conf" /etc/nginx/sites-available/upstream.conf
    ln -sf /etc/nginx/sites-available/upstream.conf /etc/nginx/sites-enabled/upstream.conf

    cp "${PROJECT_ROOT}/nginx/backend.conf" /etc/nginx/sites-available/backend.conf
    ln -sf /etc/nginx/sites-available/backend.conf /etc/nginx/sites-enabled/backend.conf

    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
        log_info "Removed default nginx site to avoid port 80 conflicts."
    fi

    log_info "Testing nginx configuration..."
    nginx -t >>"$LOG_FILE" 2>&1 || die "nginx configuration test failed, check $LOG_FILE"

    systemctl enable nginx >>"$LOG_FILE" 2>&1
    systemctl restart nginx
    log_info "Nginx reverse proxy configured and running on port 80."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_nginx
fi