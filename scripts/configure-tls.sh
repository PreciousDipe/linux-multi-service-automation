#!/usr/bin/env bash
# configure-tls.sh - generate a self-signed certificate, then swap
# the plain-HTTP vhost for a redirect-to-HTTPS vhost + the HTTPS vhost.
# Only runs when provision.sh is called with --with-tls.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

CERT_DIR="/etc/nginx/ssl"
DOMAIN="${DOMAIN:-localhost}"

configure_tls() {
    apt_install_if_missing openssl
    log_info "Setting up self-signed TLS certificate for CN=$DOMAIN..."
    mkdir -p "$CERT_DIR"

    if [[ -f "${CERT_DIR}/server.crt" && -f "${CERT_DIR}/server.key" ]]; then
        log_info "Self-signed certificate already exists, skipping generation."
    else
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${CERT_DIR}/server.key" \
            -out "${CERT_DIR}/server.crt" \
            -subj "/CN=${DOMAIN}" >>"$LOG_FILE" 2>&1 \
            || die "Failed to generate self-signed certificate"
        chmod 600 "${CERT_DIR}/server.key"
        log_info "Self-signed certificate generated at $CERT_DIR."
    fi

    # backend.conf's port-80 server block would conflict with the redirect
    # vhost below (both trying to claim listen 80), so unlink it from
    # sites-enabled. The file itself stays in sites-available — its
    # `upstream backend_app` block is still needed by backend-tls.conf.
    if [[ -L /etc/nginx/sites-enabled/backend.conf ]]; then
        rm -f /etc/nginx/sites-enabled/backend.conf
        log_info "Unlinked plain-HTTP vhost from sites-enabled (upstream definition kept in sites-available)."
    fi

    # Deploy the redirect vhost (port 80 -> https) and the HTTPS vhost (port 443).
    cp "${REPO_ROOT}/nginx/backend-redirect.conf" /etc/nginx/sites-available/backend-redirect.conf
    ln -sf /etc/nginx/sites-available/backend-redirect.conf /etc/nginx/sites-enabled/backend-redirect.conf

    cp "${REPO_ROOT}/nginx/backend-tls.conf" /etc/nginx/sites-available/backend-tls.conf
    ln -sf /etc/nginx/sites-available/backend-tls.conf /etc/nginx/sites-enabled/backend-tls.conf

    nginx -t >>"$LOG_FILE" 2>&1 || die "nginx TLS configuration test failed"
    systemctl reload nginx
    log_info "TLS enabled: HTTP (80) now redirects to HTTPS (443)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    configure_tls
fi