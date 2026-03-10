#!/usr/bin/env bash
#
# Production deployment script for OpenClaw
# Deploya solo OpenClaw - Tailscale è un modulo separato opzionale
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"

# Load default configuration from .env if exists
DEFAULT_ENV="${SCRIPT_DIR}/.env"
if [[ -f "$DEFAULT_ENV" ]]; then
    set -a
    source "$DEFAULT_ENV"
    set +a
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $*"; }

print_banner() {
    cat <<'EOF'
 _____  ____   ____  _     _____ _____ ____  _____ 
|  _  ||  _ \ / ___|| |   | ____| ____|  _ \| ____|
| | | || |_) | |    | |   |  _| |  _| | |_) |  _|  
| |_| ||  __/| |___ | |___| |___| |___|  _ <| |___ 
|_____||_|    \____||_____|_____|_____|_| \_\_____|
                                                    
           OPENCLAW DEPLOYMENT
EOF
    echo
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local errors=0
    
    # Docker
    if command -v docker >/dev/null 2>&1; then
        log_success "Docker: $(docker --version)"
    else
        log_error "Docker not found - please install Docker first"
        ((errors++))
    fi
    
    # Docker Compose
    if docker compose version >/dev/null 2>&1; then
        log_success "Docker Compose: $(docker compose version)"
    elif command -v docker-compose >/dev/null 2>&1; then
        log_warn "docker-compose (standalone) - consider upgrading to plugin"
    else
        log_error "Docker Compose not found"
        ((errors++))
    fi
    
    # Python 3
    if command -v python3 >/dev/null 2>&1; then
        log_success "Python 3: $(python3 --version)"
    else
        log_error "Python 3 not found"
        ((errors++))
    fi
    
    # curl
    if command -v curl >/dev/null 2>&1; then
        log_success "curl: $(curl --version | head -1)"
    else
        log_error "curl not found"
        ((errors++))
    fi
    
    # Disk space
    local available_space
    available_space="$(df -P "${HOME}" | tail -1 | awk '{print $4}')"
    if [[ "$available_space" -lt 1048576 ]]; then  # 1GB in KB
        log_warn "Low disk space: $((available_space / 1024))MB available"
    else
        log_success "Disk space: $((available_space / 1024))MB available"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "${errors} prerequisite(s) failed"
        return 1
    fi
    
    log_success "All prerequisites met"
    echo
}

prompt_configuration() {
    log_step "Configuration"
    echo
    log_info "Using default configuration from ${DEFAULT_ENV}"
    log_info "OpenClaw will be accessible locally on http://127.0.0.1:${OPENCLAW_PORT}"
    echo
    log_info "To enable remote access with Tailscale Funnel:"
    log_info "  1. Configure tailscale-funnel-compose/ module"
    log_info "  2. Run: ./tailscale-add-service.sh add"
    echo
}

create_data_directory() {
    log_step "Creating data directory..."
    
    mkdir -p "${DATA_DIR}/data"
    mkdir -p "${DATA_DIR}/backups"
    chmod 700 "${DATA_DIR}"
    
    # Fix permissions for Docker container (UID 1000)
    local uid
    uid="$(id -u)"
    if [[ "$uid" != "1000" ]]; then
        log_warn "Your UID is ${uid}, container expects UID 1000"
        log_info "Setting permissions on ${DATA_DIR}/data"
        sudo chown -R 1000:1000 "${DATA_DIR}/data" 2>/dev/null || true
    fi
    
    log_success "Data directory created: ${DATA_DIR}"
    echo
}

create_configuration() {
    log_step "Creating runtime configuration..."

    # Create OpenClaw .env file in runtime directory
    local env_file="${DATA_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" <<EOF
# OpenClaw Runtime Configuration
# Generated on $(date -Iseconds)
# DO NOT EDIT - changes will be overwritten
# Edit ${SCRIPT_DIR}/.env instead

OPENCLAW_CONTAINER_NAME=${OPENCLAW_CONTAINER_NAME}
OPENCLAW_IMAGE_NAME=${OPENCLAW_IMAGE_NAME}
OPENCLAW_DATA_DIR=${DATA_DIR}
OPENCLAW_PORT=${OPENCLAW_PORT}
OPENCLAW_BIND_ADDRESS=${OPENCLAW_BIND_ADDRESS}
LOG_LEVEL=${LOG_LEVEL:-info}
ENABLE_HEALTH_CHECK=${ENABLE_HEALTH_CHECK:-true}
EOF
        chmod 600 "$env_file"
        log_success "Created runtime .env: ${env_file}"
    else
        log_warn "Runtime .env already exists, skipping"
    fi

    # Copy docker-compose template
    local compose_file="${DATA_DIR}/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        cp "${SCRIPT_DIR}/docker-compose.openclaw.example.yml" "$compose_file"
        log_success "Created docker-compose.yml"
    else
        log_warn "docker-compose.yml already exists, skipping"
    fi

    echo
}

setup_systemd() {
    if [[ "$ENABLE_SYSTEMD" != "true" ]]; then
        return
    fi
    
    log_step "Setting up systemd service..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_warn "Systemd setup requires root privileges"
        log_info "To enable auto-start, run: sudo ${SCRIPT_DIR}/openclaw-manager.sh systemd-install"
        return
    fi
    
    # Copy service file
    cp "${SCRIPT_DIR}/openclaw.service" /etc/systemd/system/
    
    # Update paths in service file
    sed -i "s|/opt/openclaw-manager-system|${SCRIPT_DIR}|g" /etc/systemd/system/openclaw.service
    
    # Reload and enable
    systemctl daemon-reload
    systemctl enable openclaw.service
    
    log_success "Systemd service installed and enabled"
    log_info "Start with: systemctl start openclaw"
    log_info "Check status: systemctl status openclaw"
    echo
}

pull_docker_image() {
    log_step "Pulling Docker image..."

    local image_name="ghcr.io/openclaw/openclaw:latest"

    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image_name}$"; then
        log_info "Image already exists, checking for updates..."
        docker pull "$image_name" || log_warn "Failed to pull latest image"
    else
        docker pull "$image_name"
    fi

    log_success "Docker image ready"
    echo
}

print_next_steps() {
    echo
    echo "============================================"
    echo "         DEPLOYMENT COMPLETE!              "
    echo "============================================"
    echo
    echo -e "${GREEN}OpenClaw is ready to deploy!${NC}"
    echo
    echo "Next steps:"
    echo
    echo "  1. Start OpenClaw:"
    echo -e "     ${CYAN}cd ${SCRIPT_DIR}${NC}"
    echo -e "     ${CYAN}./openclaw-manager.sh start${NC}"
    echo
    echo "  2. Check status:"
    echo -e "     ${CYAN}./openclaw-manager.sh status${NC}"
    echo
    echo "  3. Access locally:"
    echo -e "     ${CYAN}http://127.0.0.1:${OPENCLAW_PORT}${NC}"
    echo
    echo "  4. Enable remote access (optional):"
    echo -e "     ${CYAN}./tailscale-add-service.sh add${NC}"
    echo
    echo "Documentation:"
    echo "  - README: ${PACKAGE_ROOT}/README.md"
    echo
    
    # Chiedi se abilitare Tailscale subito
    if [[ -d "${PACKAGE_ROOT}/tailscale-funnel-compose" ]]; then
        echo "============================================"
        read -rp "Vuoi configurare Tailscale Funnel ora? (y/n): " configure_ts
        if [[ "$configure_ts" == "y" || "$configure_ts" == "Y" ]]; then
            echo
            log_info "Verifica configurazione Tailscale..."
            "${SCRIPT_DIR}/tailscale-add-service.sh" add || true
        fi
    fi
}

main() {
    print_banner
    
    check_prerequisites
    prompt_configuration
    create_data_directory
    create_configuration
    pull_docker_image
    
    if [[ "$ENABLE_SYSTEMD" == "true" ]]; then
        setup_systemd
    fi
    
    print_next_steps
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --systemd)
            ENABLE_SYSTEMD=true
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Production deployment script for OpenClaw.
Tailscale Funnel is a separate optional module.

Options:
  --systemd             Enable systemd auto-start
  -h, --help            Show this help

Examples:
  # Interactive deployment
  $0
  
  # With systemd auto-start
  $0 --systemd
  
  # Non-interactive (uses .env defaults)
  $0
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
