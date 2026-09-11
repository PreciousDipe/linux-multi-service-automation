#!/usr/bin/env bash
# install-backend.sh - install Python runtime, create a venv, and deploy the backend app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is one level up from scripts/ — needed to find app/app.py
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/config.sh"

APP_USER="${APP_USER:-appsvc}"
APP_HOME="${APP_HOME:-/opt/backend-app}"
VENV_DIR="${APP_HOME}/venv"

install_python_runtime() {
    # python3-venv is required to create virtual environments;
    # python3-pip is required to install packages inside them.
    apt_install_if_missing python3
    apt_install_if_missing python3-venv
    apt_install_if_missing python3-pip
}

deploy_backend_app() {
    log_info "Deploying backend application to $APP_HOME..."
    # install -d creates the directory with the given owner in one step.
    install -d -o "$APP_USER" -g "$APP_USER" "$APP_HOME"
    cp "${REPO_ROOT}/app/app.py" "${APP_HOME}/app.py"
    cp "${REPO_ROOT}/app/requirements.txt" "${APP_HOME}/requirements.txt"
    chown -R "${APP_USER}:${APP_USER}" "$APP_HOME"

    # Only create the virtualenv if it doesn't already exist —
    # re-creating it on every run would be slow and pointless.
    if [[ -d "$VENV_DIR" ]]; then
        log_info "Virtualenv already exists at $VENV_DIR, skipping creation."
    else
        log_info "Creating virtualenv at $VENV_DIR..."
        # Run as appsvc (not root) so the venv's files are owned correctly.
        sudo -u "$APP_USER" python3 -m venv "$VENV_DIR" \
            || die "Failed to create virtualenv"
    fi

    log_info "Installing Python dependencies into venv..."
    sudo -u "$APP_USER" "${VENV_DIR}/bin/pip" install --quiet --upgrade pip >>"$LOG_FILE" 2>&1
    sudo -u "$APP_USER" "${VENV_DIR}/bin/pip" install --quiet -r "${APP_HOME}/requirements.txt" >>"$LOG_FILE" 2>&1 \
        || die "Failed to install Python dependencies"

    log_info "Backend application deployed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    install_python_runtime
    deploy_backend_app
fi