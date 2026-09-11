#!/usr/bin/env bash
# config.sh - shared logging, validation, and helper functions.
set -euo pipefail

LOG_FILE="${LOG_FILE:-/var/log/provision.log}"

# Core log writer: prefixes every line with a timestamp and level,
# then prints it to the terminal AND appends it to the log file.
log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $msg" | tee -a "$LOG_FILE"
}

# Convenience wrappers around log() for each severity level.
log_info()  { log "INFO"  "$*"; }
log_warn()  { log "WARN"  "$*"; }
log_error() { log "ERROR" "$*" >&2; }  # errors also go to stderr

# Log an error and immediately stop the script with a failure exit code.
die() {
    log_error "$*"
    exit 1
}

# Refuse to continue unless running as root (UID 0) — most steps here
# install packages or write to system directories.
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "This script must be run as root (use sudo)."
    fi
}

# True/false check for whether a given command is available on PATH.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Guard for "this variable must be set before continuing."
# ${!name} is indirect variable expansion — it looks up the value
# of the variable NAMED by $name, not $name itself.
require_var() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        die "Required variable '$name' is not set."
    fi
}

# Install an apt package only if it isn't already installed.
# This is what makes package installation idempotent across reruns.
apt_install_if_missing() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log_info "Package '$pkg' already installed, skipping."
    else
        log_info "Installing package '$pkg'..."
        apt-get install -y "$pkg" >>"$LOG_FILE" 2>&1 || die "Failed to install package '$pkg'"
    fi
}

# Make a one-time backup of a config file before we overwrite it,
# so the original is always recoverable.
backup_file_if_exists() {
    local f="$1"
    if [[ -f "$f" && ! -f "${f}.orig" ]]; then
        cp "$f" "${f}.orig"
        log_info "Backed up $f to ${f}.orig"
    fi
}

# Confirm DNS resolution works before any step that depends on reaching
# the internet (apt mirrors, NodeSource/PyPI, etc). Tries three tools
# in order since not all of them are guaranteed to be installed.
verify_dns() {
    local host="${1:-google.com}"
    log_info "Verifying DNS resolution for $host..."
    if command_exists getent && getent hosts "$host" >/dev/null 2>&1; then
        log_info "DNS resolution is OK for $host."
        return 0
    fi
    if command_exists host && host "$host" >/dev/null 2>&1; then
        log_info "DNS resolution is OK for $host."
        return 0
    fi
    if command_exists nslookup && nslookup "$host" >/dev/null 2>&1; then
        log_info "DNS resolution is OK for $host."
        return 0
    fi
    die "DNS resolution failed for $host. Check /etc/resolv.conf and network connectivity."
}