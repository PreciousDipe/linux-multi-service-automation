#!/usr/bin/env bash
# system-setup.sh - update apt, install base packages, verify DNS.
# This is the first step, nothing else should run until
# the system's packages are installed  and the network is confirmed working.
set -euo pipefail

# Resolve this script's own directory so config.sh can be found
# regardless of where provision.sh is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

setup_system() {
    log_info "Updating apt package index..."
    apt-get update -y >>"$LOG_FILE" 2>&1 || die "apt-get update failed"

    # Packages every later step depends on, installed here up front
    # so subsequent scripts can assume they already exist.
    local base_pkgs=(curl wget gnupg2 ca-certificates software-properties-common ufw fail2ban logrotate cron dnsutils openssl)
    for pkg in "${base_pkgs[@]}"; do
        apt_install_if_missing "$pkg"
    done

    # Fail here if DNS is broken, rather than later
    # errors from apt/pip/npm trying to reach the internet.
    verify_dns "github.com"
    log_info "System setup complete."
}

# Lets this script run standalone (sudo ./system-setup.sh) for testing,
# while still being sourced (not auto-run) by provision.sh.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root
    setup_system
fi