#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------
# Variables
# ---------------------------------
USER_NAME=""
SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false


# ---------------------------------
# Functions
# ---------------------------------
usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} -u <username> [--dry-run]

Options:
  -u            Username to create and grant passwordless sudo
  --dry-run     Show what would be executed without making changes
  -h            Show this help message

Example:
  sudo ${SCRIPT_NAME} -u deploy_admin --dry-run
EOF
}


run() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}


require_root() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Skipping root check"
        return
    fi

    if [[ "$EUID" -ne 0 ]]; then
        echo "ERROR: This script must be run as root." >&2
        exit 1
    fi
}


parse_args() {
    local args=()

    # First pass: handle long options
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done

    # Reset positional parameters for getopts
    set -- "${args[@]}"

    # Parse short options
    while getopts ":u:h" opt; do
        case "$opt" in
            u)
                USER_NAME="${OPTARG}"
                ;;
            h)
                usage
                exit 0
                ;;
            \?)
                echo "Invalid option: -${OPTARG}" >&2
                usage
                exit 1
                ;;
            :)
                echo "Option -${OPTARG} requires an argument." >&2
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${USER_NAME}" ]]; then
        echo "ERROR: Username is required."
        usage
        exit 1
    fi
}



update_system() {
    echo "Updating system packages..."
    run apt-get update -y
    run apt-get upgrade -y
}


create_user_if_missing() {
    if id "${USER_NAME}" &>/dev/null; then
        echo "User '${USER_NAME}' already exists. Skipping creation."
    else
        echo "Creating user '${USER_NAME}'..."
        run useradd -m -s /bin/bash "${USER_NAME}"
    fi
}


configure_passwordless_sudo() {
    local sudoers_file="/etc/sudoers.d/${USER_NAME}"

    if [[ -f "${sudoers_file}" ]]; then
        echo "Sudo configuration already exists for ${USER_NAME}."
        return
    fi

    echo "Configuring passwordless sudo for ${USER_NAME}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] Would create ${sudoers_file}"
        echo "[DRY-RUN] Content:"
        echo "  ${USER_NAME} ALL=(ALL) NOPASSWD:ALL"
        return
    fi

    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
    chmod 0440 "${sudoers_file}"
    visudo -cf "${sudoers_file}"
}


# ---------------------------------
# Main
# ---------------------------------
require_root
parse_args "$@"

echo "Starting setup for user: ${USER_NAME}"

update_system
create_user_if_missing
configure_passwordless_sudo

echo "✔ User setup completed successfully."
exit 0 
