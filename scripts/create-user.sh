#!/usr/bin/env bash
# create-user.sh - create the dedicated, non-root service user for the backend app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# These can be overridden by exporting them before running this script;
# provision.sh exports both, so this fallback only matters for standalone runs.
APP_USER="${APP_USER:-appsvc}"
APP_HOME="${APP_HOME:-/opt/backend-app}"

create_service_user() {
    # id checks whether the user already exists — skip creation if so,
    # which is what makes re-running provisioning safe.
    if id "$APP_USER" >/dev/null 2>&1; then
        log_info "User '$APP_USER' already exists, skipping creation."
    else
        log_info "Creating system user '$APP_USER' (no login shell)..."
        # --system: no password, treated as a service account
        # --shell /usr/sbin/nologin: this account can never get an interactive shell
        useradd --system --create-home --home-dir "$APP_HOME" --shell /usr/sbin/nologin "$APP_USER" \
            || die "Failed to create user $APP_USER"
    fi

    # Ensure the home/app directory exists and is owned correctly,
    # whether the user was just created or already existed.
    mkdir -p "$APP_HOME"
    chown -R "${APP_USER}:${APP_USER}" "$APP_HOME"
    log_info "Service user '$APP_USER' ready with home '$APP_HOME'."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    create_service_user
fi