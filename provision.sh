#!/usr/bin/env bash
#
# provision.sh - Main orchestrator for the multi-service Linux environment.
# This is the single entry point: running this one script sets up every
# component (backend, nginx, firewall, fail2ban, logging, and bonus features)
# by calling each individual service script in the correct dependency order.
#
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/provision.log"
export LOG_FILE

source "${PROJECT_ROOT}/scripts/config.sh"

export APP_USER="appsvc"
export APP_HOME="/opt/backend-app"
export APP_PORT="3000"
export ENABLE_TLS="false"
export DOMAIN="localhost"

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --with-tls           Enable bonus self-signed TLS on port 443
  --domain <name>       Domain/CN to use for the TLS certificate (default: localhost)
  --skip-monitoring     Skip installing the bonus health-check cron job
  --skip-backup         Skip installing the bonus backup cron job
  -h, --help            Show this help message
EOF
}

SKIP_MONITORING="false"
SKIP_BACKUP="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-tls) export ENABLE_TLS="true"; shift ;;
        --domain) export DOMAIN="${2:?--domain requires a value}"; shift 2 ;;
        --skip-monitoring) SKIP_MONITORING="true"; shift ;;
        --skip-backup) SKIP_BACKUP="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help for usage)" ;;
    esac
done

trap 'log_error "provision.sh failed at line $LINENO. See ${LOG_FILE} for details."' ERR

main() {
    require_root
    touch "$LOG_FILE"
    log_info "===== Starting provisioning run (ENABLE_TLS=${ENABLE_TLS}) ====="

    # --- Step 1: base system + service user + backend app ---
    source "${PROJECT_ROOT}/scripts/system-setup.sh";        setup_system
    source "${PROJECT_ROOT}/scripts/create-user.sh";         create_service_user
    source "${PROJECT_ROOT}/scripts/install-backend.sh";   install_python_runtime; deploy_backend_app
    source "${PROJECT_ROOT}/scripts/configure-logrotate.sh"; configure_logrotate

    # --- Step 2: start the backend app as a systemd service ---
    log_info "Installing systemd unit for backend-app..."
    cp "${PROJECT_ROOT}/systemd/backend.service" /etc/systemd/system/backend-app.service
    systemctl daemon-reload
    systemctl enable backend-app >>"$LOG_FILE" 2>&1
    systemctl restart backend-app
    log_info "backend-app service started."

    # --- Step 3: reverse proxy (+ optional TLS) ---
    source "${PROJECT_ROOT}/scripts/configure-nginx.sh";     configure_nginx

    if [[ "$ENABLE_TLS" == "true" ]]; then
        source "${PROJECT_ROOT}/scripts/configure-tls.sh";   configure_tls
    fi

    # --- Step 4: firewall + intrusion prevention ---
    source "${PROJECT_ROOT}/scripts/configure-firewall.sh";  configure_firewall
    source "${PROJECT_ROOT}/scripts/configure-fail2ban.sh";  configure_fail2ban

    # --- Step 5: bonus monitoring/backup ---
    if [[ "$SKIP_MONITORING" != "true" ]]; then
        source "${PROJECT_ROOT}/scripts/configure-monitoring.sh"; configure_monitoring
    fi

    if [[ "$SKIP_BACKUP" != "true" ]]; then
        source "${PROJECT_ROOT}/scripts/configure-backup.sh";     configure_backup
    fi

    # --- Step 6: verify everything actually came up ---
    source "${PROJECT_ROOT}/scripts/verify.sh"; verify_deployment

    log_info "===== Provisioning completed successfully ====="
    log_info "Try: curl http://localhost/health"
}

main "$@"

