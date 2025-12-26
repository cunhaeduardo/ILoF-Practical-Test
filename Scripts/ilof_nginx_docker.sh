#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------
# Globals
# ---------------------------------
SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
WEB_USER="nginx_web"
NGINX_CONTAINER="ilof_nginx"
HOST_PORT=80
HOST_HTTPS_PORT=443
CUSTOM_INDEX_CONTENT="Server Provisioned by Eduardo on $(date +'%Y-%m-%d')"
NGINX_HTML_DIR="/srv/ilof_nginx_html"
DOCKER_IMAGE="nginx:latest"
USE_HTTPS=false

# ---------------------------------
# Helpers
# ---------------------------------
usage() {
    cat <<EOF
Usage: sudo ${SCRIPT_NAME} [options]

Options:
  --dry-run                Show what would be executed without making changes
  --https                  Enable HTTPS with self-signed certificate
  -h, --help               Show this help message

Example:
  sudo ${SCRIPT_NAME} --dry-run --https
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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --https)
                USE_HTTPS=true
                shift
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
# Install Docker if missing
# ---------------------------------
ensure_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        echo "Docker already installed."
        return
    fi

    echo "Installing Docker..."
    run apt-get update -y
    run apt-get install -y docker.io
    run systemctl enable --now docker
}

# ---------------------------------
# Prepare web content directory
# ---------------------------------
prepare_web_content() {
    echo "Preparing web content directory..."
    run mkdir -p "$NGINX_HTML_DIR"
    run bash -c "echo '$CUSTOM_INDEX_CONTENT' > ${NGINX_HTML_DIR}/index.html"
}

# ---------------------------------
# Generate self-signed cert (HTTPS)
# ---------------------------------
generate_self_signed_cert() {
    local cert_dir="${NGINX_HTML_DIR}/certs"
    run mkdir -p "$cert_dir"
    run openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${cert_dir}/nginx.key" \
        -out "${cert_dir}/nginx.crt" \
        -subj "/C=PT/ST=Porto/L=Porto/O=ILoF/CN=webserver_ilof"
}

# ---------------------------------
# Run Nginx container
# ---------------------------------
run_nginx_container() {
    echo "Running Nginx container..."
    
    # Remove old container if exists
    run docker rm -f "$NGINX_CONTAINER" 2>/dev/null || true

    # Base ports and volume
    local ports="-p ${HOST_PORT}:80"
    local volume="-v ${NGINX_HTML_DIR}:/usr/share/nginx/html:ro"

    if [[ "$USE_HTTPS" == true ]]; then
        echo "Configuring HTTPS..."
        generate_self_signed_cert

        # Create custom nginx.conf for HTTPS
        NGINX_CONF_DIR="/srv/ilof_nginx_conf"
        run mkdir -p "$NGINX_CONF_DIR"

        if [[ ! -f "${NGINX_CONF_DIR}/default.conf" ]]; then
            run bash -c "cat > ${NGINX_CONF_DIR}/default.conf <<EOF
server {
    listen 80;
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/certs/nginx.crt;
    ssl_certificate_key /etc/nginx/certs/nginx.key;

    root /usr/share/nginx/html;
    index index.html;
}
EOF"
        fi

        ports="-p ${HOST_PORT}:80 -p ${HOST_HTTPS_PORT}:443"
        volume="${volume} -v ${NGINX_HTML_DIR}/certs:/etc/nginx/certs:ro \
                           -v ${NGINX_CONF_DIR}/default.conf:/etc/nginx/conf.d/default.conf:ro"
    fi

    # Run the container
    run docker run -d \
        --name "$NGINX_CONTAINER" \
        $ports \
        $volume \
        --restart unless-stopped \
        $DOCKER_IMAGE
}



# ---------------------------------
# Main
# ---------------------------------
parse_args "$@"
require_root
echo "Starting Nginx Docker provisioning..."

ensure_docker_installed
prepare_web_content
run_nginx_container

echo "✔ Nginx Docker provisioning completed."
exit 0
