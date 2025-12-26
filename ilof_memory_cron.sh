#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------
# Globals
# ---------------------------------
SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
CRON_INTERVAL=10  # default interval in minutes
LOG_FILE="var/log/memory_usage.log"
HELPER_SCRIPT="/usr/local/bin/ilof_log_memory.sh"

# ---------------------------------
# Helpers
# ---------------------------------
usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [options]

Options:
  --dry-run                  Show what would be executed without making changes
  --interval <minutes>       Cron job frequency in minutes (default: 10)
  -h, --help                 Show this help message

Example:
  sudo ${SCRIPT_NAME} --interval 5 --dry-run
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
        echo "ERROR: Must run as root" >&2
        exit 1
    fi
}

# ---------------------------------
# Argument parsing
# ---------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --interval)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    CRON_INTERVAL="$2"
                    shift 2
                else
                    echo "ERROR: --interval requires a numeric argument"
                    exit 1
                fi
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ---------------------------------
# Ensure cron is installed and running
# ---------------------------------
ensure_cron_installed() {
    if ! command -v cron >/dev/null 2>&1; then
        echo "Installing cron..."
        run apt-get update -y
        run apt-get install -y cron
        run systemctl enable --now cron
    else
        echo "Cron is already installed."
        run systemctl enable --now cron
    fi
}


# ---------------------------------
# Create helper script for logging memory
# ---------------------------------
create_helper_script() {
    echo "Creating helper script at ${HELPER_SCRIPT}..."
    run bash -c "cat > ${HELPER_SCRIPT} <<'EOF'
#!/usr/bin/env bash
LOG_FILE=\"${LOG_FILE}\"

# Ensure log file exists and add header if missing
if [[ ! -f \"\$LOG_FILE\" ]]; then
    touch \"\$LOG_FILE\"
    chmod 644 \"\$LOG_FILE\"
    echo \"Datetime,Type,Total,Used,Free,Shared,Buff/Cache,Available\" >> \"\$LOG_FILE\"
fi

# Get current datetime
NOW=\"\$(date +'%Y-%m-%d %H:%M:%S')\"

# Append Mem and Swap info in CSV format
free -m | awk -v dt=\"\$NOW\" '
NR==2 {
    # Mem line
    type=\$1
    printf \"%s,%s,%s,%s,%s,%s,%s,%s\n\", dt, type, \$2, \$3, \$4, \$5, \$6, \$7
}
NR==3 {
    # Swap line (some fields missing, fill with 0)
    type=\$1
    total=\$2
    used=\$3
    free=\$4
    shared=\$5
    buffcache=\$6
    avail=\$7
    printf \"%s,%s,%s,%s,%s,%s,%s,%s\n\", dt, type, total, used, free, shared, buffcache, avail
}
' >> \"\$LOG_FILE\"
EOF"

    run chmod +x "$HELPER_SCRIPT"
}


# ---------------------------------
# Create idempotent cron job
# ---------------------------------
create_cron_job() {
    echo "Creating cron job to log memory usage every ${CRON_INTERVAL} minutes..."

    # Remove any existing cron job for this script
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Removing old cron job (if exists)"
        echo "[DRY-RUN] Setting new cron job: */${CRON_INTERVAL} * * * * ${HELPER_SCRIPT}"
        return
    fi

    # Fetch existing root crontab (ignore errors if none)
    tmpfile=$(mktemp)
    crontab -l -u root 2>/dev/null | grep -v "$HELPER_SCRIPT" > "$tmpfile" || true

    # Append new cron job
    echo "*/${CRON_INTERVAL} * * * * ${HELPER_SCRIPT}" >> "$tmpfile"

    # Install updated crontab
    crontab -u root "$tmpfile"
    rm -f "$tmpfile"

    echo "✔ Cron job installed successfully."
}

# ---------------------------------
# Main
# ---------------------------------
parse_args "$@"
require_root

echo "Starting memory logging setup..."
ensure_cron_installed
create_helper_script
create_cron_job

echo "✔ Memory logging setup completed."
exit 0
