#!/usr/bin/env bash
set -uo pipefail

# Orchestration script to run other provisioning scripts sequentially and show a summary table
# Usage: sudo ./ilof_run_all.sh [--dry-run] [--stop-on-failure] [--scripts script1,script2,...]

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
STOP_ON_FAILURE=false
LOG_DIR="./log/ilof_run"
SCRIPTS=()

usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [options]

Options:
  --dry-run                 Show what would be executed without making changes
  --stop-on-failure         Stop the run if any step fails (default: continue)
  --scripts <csv-list>      Comma-separated list of scripts to run (default: all known scripts in the same dir)
  -h, --help                Show this help message

Example:
  sudo ${SCRIPT_NAME} --dry-run --scripts ilof_security_hardening.sh,ilof_createuser.sh
EOF
}

require_root() {
    # simple root check (skip during dry-run)
    [[ "$DRY_RUN" == "true" ]] && return
    [[ $EUID -ne 0 ]] && { echo "ERROR: Must run as root." >&2; exit 1; }
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            --stop-on-failure) STOP_ON_FAILURE=true; shift ;;
            --scripts)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: --scripts requires an argument"; exit 1
                fi
                IFS=',' read -r -a SCRIPTS <<< "$2"; shift 2
                ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

# Default scripts (in preferred order) if none provided
default_scripts() {
    local dir
    dir="$(cd "$(dirname "$0")" && pwd)"
    echo "${dir}/ilof_createuser.sh"
    echo "${dir}/ilof_security_hardening.sh"
    echo "${dir}/ilof_nginx_docker.sh"
    echo "${dir}/ilof_memory_cron.sh"
}

# Format seconds to H:MM:SS
fmt_time() {
    local T=$1
    printf '%02d:%02d:%02d' $((T/3600)) $(((T%3600)/60)) $((T%60))
}

main() {
    parse_args "$@"
    require_root

    if [[ "${#SCRIPTS[@]}" -eq 0 ]]; then
        # populate defaults (full paths)
        mapfile -t SCRIPTS < <(default_scripts)
    else
        # expand provided names into paths relative to this dir if needed
        local d
        d="$(cd "$(dirname "$0")" && pwd)"
        for i in "${!SCRIPTS[@]}"; do
            local name="${SCRIPTS[$i]}"
            # if path not absolute and file exists in script dir, expand
            if [[ "$name" != /* && -f "${d}/$name" ]]; then
                SCRIPTS[$i]="${d}/${name}"
            fi
        done
    fi

    # Prepare log dir
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would create log dir: ${LOG_DIR}"
    else
        mkdir -p "$LOG_DIR"
        chmod 0755 "$LOG_DIR"
    fi

    # Data holders
    declare -a names=()
    declare -a status=()
    declare -a exitcodes=()
    declare -a durations=()
    declare -a logfiles=()

    local idx=0
    local any_failed=false

    for script in "${SCRIPTS[@]}"; do
        idx=$((idx+1))
        local sname="$(basename "$script")"
        names+=("$sname")
        local logfile="${LOG_DIR}/${sname}.log"
        logfiles+=("$logfile")

        # Check existence
        if [[ ! -f "$script" ]]; then
            status+=("MISSING")
            exitcodes+=("-")
            durations+=("-")
            echo "[WARN] $sname not found; skipping"
            any_failed=true
            if [[ "$STOP_ON_FAILURE" == true ]]; then
                break
            else
                continue
            fi
        fi

        echo "Running step ${idx}: ${sname}"

        local start ts_end elapsed
        start=$(date +%s)

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] bash ${script} --dry-run"
            rc=0
        else
            rc=0
            bash "$script" >> "$logfile" 2>&1 || rc=$?
        fi

        ts_end=$(date +%s)
        elapsed=$((ts_end - start))
        durations+=("$(fmt_time "$elapsed")")

        if [[ "$DRY_RUN" == "true" ]]; then
            status+=("DRY-RUN")
            exitcodes+=("0")
        else
            if [[ $rc -eq 0 ]]; then
                status+=("OK")
                exitcodes+=("$rc")
            else
                status+=("FAIL")
                exitcodes+=("$rc")
                any_failed=true
            fi
        fi

        # Stop on failure if requested
        if [[ "$STOP_ON_FAILURE" == true && "$DRY_RUN" != "true" && ${status[-1]} == "FAIL" ]]; then
            echo "Stopping on failure (stop-on-failure enabled)."
            break
        fi
    done

    # Print summary table
    printf "\n\nSummary:\n"
    printf '%-4s %-35s %-8s %-9s %-8s %s\n' "#" "Script" "Status" "ExitCode" "Elapsed" "Log"
    printf '%s\n' "----------------------------------------------------------------------------------------------------"
    for i in "${!names[@]}"; do
        printf '%-4d %-35s %-8s %-9s %-8s %s\n' $((i+1)) "${names[$i]}" "${status[$i]}" "${exitcodes[$i]}" "${durations[$i]}" "${logfiles[$i]}"
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        printf "\nNote: This was a dry-run; no changes were made.\n"
    fi

    if [[ "$any_failed" == true ]]; then
        printf "\nSome steps failed. Check individual log files under %s\n" "$LOG_DIR"
        # exit non-zero to indicate failure
        exit 1
    else
        printf "\nAll steps completed successfully.\n"
        exit 0
    fi
}

main "$@"
