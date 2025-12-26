#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------
# Globals
# ---------------------------------
SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false

SSH_PORT=22
#SSH_PORT=2022
SSHD_CONFIG="/etc/ssh/sshd_config"

# ---------------------------------
# Helpers
# ---------------------------------
usage() {
    cat <<EOF
usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [options]

Options:
  --dry-run                 Show what would be executed without making changes
  --ssh-port <port>         SSH port to use (default: 2022)
  --sshd-config <path>      Path to sshd_config (default: /etc/ssh/sshd_config)
  -h, --help                Show this help message

Example:
  sudo ${SCRIPT_NAME} --ssh-port 2222 --dry-run
EOF
}

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

require_root() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Skipping root check"
        return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        echo "ERROR: This script must be run as root." >&2
        exit 1
    fi
}

# ---------------------------------
# Argument parsing
# ---------------------------------
parse_args() {
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --ssh-port)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    SSH_PORT="$2"
                    shift 2
                else
                    echo "ERROR: --ssh-port requires a numeric argument"
                    exit 1
                fi
                ;;
            --sshd-config)
                if [[ -n "${2:-}" ]]; then
                    SSHD_CONFIG="$2"
                    shift 2
                else
                    echo "ERROR: --sshd-config requires a file path argument"
                    exit 1
                fi
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Reset positional parameters in case you want to use $@ later
    set -- "${args[@]}"
}


# ---------------------------------
# Checks ssh installation
# ---------------------------------
ensure_openssh_installed() {
    echo "Checking OpenSSH server availability..."

    if command -v sshd >/dev/null 2>&1; then
        echo "OpenSSH server already installed."
        return
    fi

    echo "OpenSSH server not found. Installing..."

    run apt-get update -y
    run apt-get install -y openssh-server

    # Enable service if systemd exists
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl enable --now ssh
    fi
}



# ---------------------------------
# SSH hardening
# ---------------------------------
configure_ssh() {
    echo "Configuring SSH daemon..."

    if [[ ! -f "${SSHD_CONFIG}" ]]; then
        echo "ERROR: ${SSHD_CONFIG} not found"
        exit 1
    fi

    # Backup once
    if [[ ! -f "${SSHD_CONFIG}.bak" ]]; then
        run cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.bak"
    fi

    # Set SSH port
    if grep -qE '^\s*#?\s*Port ' "${SSHD_CONFIG}"; then
        run sed -i "s/^\s*#\?\s*Port .*/Port ${SSH_PORT}/" "${SSHD_CONFIG}"
    else
        echo "Port ${SSH_PORT}" | run tee -a "${SSHD_CONFIG}" >/dev/null
    fi

    # Disable root login
    if grep -qE '^\s*#?\s*PermitRootLogin ' "${SSHD_CONFIG}"; then
        run sed -i "s/^\s*#\?\s*PermitRootLogin .*/PermitRootLogin no/" "${SSHD_CONFIG}"
    else
        echo "PermitRootLogin no" | run tee -a "${SSHD_CONFIG}" >/dev/null
    fi

    # Validate SSH config
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] sshd -t"
    else
        sshd -t
    fi

    # Restart SSH
    run systemctl restart ssh

    echo "SSH hardened: port=${SSH_PORT}, root login disabled"
}

# ---------------------------------
# Firewall configuration
# ---------------------------------
configure_firewall() {
    echo "Configuring firewall (UFW)..."

    run apt-get update -y
    run apt-get install -y ufw

    run ufw default deny incoming
    run ufw default allow outgoing

    # Allow required ports
    run ufw allow ${SSH_PORT}/tcp
    run ufw allow 80/tcp
    run ufw allow 443/tcp

    # Enable firewall safely
    run ufw --force enable

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] ufw status verbose"
    else
        ufw status verbose
    fi
}

# ---------------------------------
# Main
# ---------------------------------
parse_args "$@"
require_root

echo "Starting security hardening..."

ensure_openssh_installed
configure_ssh
configure_firewall

echo "✔ Security hardening completed successfully."
exit 0
