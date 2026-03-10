#!/usr/bin/env bash
#
# Production deployment script for OpenClaw + Tailscale
# Automates installation, configuration, and initial setup
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"

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

# Deployment configuration
TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_API_KEY="${TS_API_KEY:-}"
TS_TAILNET="${TS_TAILNET:-}"
ENABLE_SYSTEMD="${ENABLE_SYSTEMD:-false}"
BACKUP_ENABLED="${BACKUP_ENABLED:-true}"

print_banner() {
    cat <<'EOF'
 _____  ____   ____  _     _____ _____ ____  _____ 
|  _  ||  _ \ / ___|| |   | ____| ____|  _ \| ____|
| | | || |_) | |    | |   |  _| |  _| | |_) |  _|  
| |_| ||  __/| |___ | |___| |___| |___|  _ <| |___ 
|_____||_|    \____||_____|_____|_____|_| \_\_____|
                                                    
           PRODUCTION DEPLOYMENT SCRIPT
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
    
    # TS_AUTHKEY
    if [[ -z "$TS_AUTHKEY" ]]; then
        echo -e "${YELLOW}Tailscale Auth Key (TS_AUTHKEY)${NC}"
        echo "Get it from: https://login.tailscale.com/admin/settings/keys"
        echo "Recommended: Create a pre-authenticated key with limited lifetime"
        read -rp "Enter TS_AUTHKEY: " TS_AUTHKEY
        echo
    fi
    
    # TS_API_KEY
    if [[ -z "$TS_API_KEY" ]]; then
        echo -e "${YELLOW}Tailscale API Key (TS_API_KEY)${NC}"
        echo "Optional but recommended for automatic duplicate node cleanup"
        read -rp "Enter TS_API_KEY (or press Enter to skip): " TS_API_KEY
        echo
    fi
    
    # TS_TAILNET
    if [[ -z "$TS_TAILNET" ]]; then
        read -rp "Enter your Tailnet name (or press Enter to auto-detect): " TS_TAILNET
        echo
    fi
    
    # Systemd
    if [[ "$ENABLE_SYSTEMD" != "true" ]]; then
        read -rp "Enable systemd auto-start? (y/n): " enable_systemd
        if [[ "$enable_systemd" == "y" || "$enable_systemd" == "Y" ]]; then
            ENABLE_SYSTEMD=true
        fi
        echo
    fi
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
    log_step "Creating configuration files..."
    
    # Create .env file
    local env_file="${DATA_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        cat > "$env_file" <<EOF
# OpenClaw + Tailscale Production Configuration
# Generated on $(date -Iseconds)

# OpenClaw settings
OPENCLAW_CONTAINER_NAME=openclaw
OPENCLAW_IMAGE_NAME=ghcr.io/openclaw/openclaw:latest
OPENCLAW_DATA_DIR=${DATA_DIR}
OPENCLAW_PORT=18789
OPENCLAW_BIND_ADDRESS=127.0.0.1

# Tailscale settings
TS_AUTHKEY=${TS_AUTHKEY}
TS_API_KEY=${TS_API_KEY}
TS_TAILNET=${TS_TAILNET}
TS_HOSTNAME=openclaw-funnel
TS_CONTAINER_NAME=tailscale-funnel
TS_ENABLE_FUNNEL=true

# Monitoring
LOG_LEVEL=info
ENABLE_HEALTH_CHECK=true
EOF
        chmod 600 "$env_file"
        log_success "Created .env file"
    else
        log_warn ".env file already exists, skipping"
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

install_tailscale_stack() {
    log_step "Installing Tailscale Funnel stack..."
    
    local ts_stack_dir="${DATA_DIR}/tailscale-funnel"
    local repo_ts_dir="${PACKAGE_ROOT}/tailscale-funnel-compose"
    
    mkdir -p "${ts_stack_dir}/state"
    mkdir -p "${ts_stack_dir}/config"
    
    # Copy files from repo
    cp -f "${repo_ts_dir}/docker-compose.yml" "${ts_stack_dir}/"
    cp -f "${repo_ts_dir}/.env.example" "${ts_stack_dir}/.env.example"
    cp -f "${repo_ts_dir}/tailscale-funnel-compose.sh" "${ts_stack_dir}/"
    chmod +x "${ts_stack_dir}/tailscale-funnel-compose.sh"
    
    # Create .env for Tailscale
    cat > "${ts_stack_dir}/.env" <<EOF
# Tailscale Funnel Configuration
# Generated on $(date -Iseconds)

TS_AUTHKEY=${TS_AUTHKEY}
TS_API_KEY=${TS_API_KEY}
TS_TAILNET=${TS_TAILNET}
TS_HOSTNAME=openclaw-funnel
TS_CONTAINER_NAME=tailscale-funnel

TS_DEFAULT_SERVICE_NAME=openclaw
TS_DEFAULT_SERVICE_PORT=18789
TS_DEFAULT_SERVICE_PATH=/

TS_LOG_LEVEL=info
EOF
    chmod 600 "${ts_stack_dir}/.env"
    
    log_success "Tailscale stack installed"
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
        log_info "To enable auto-start, run: sudo ${SCRIPT_DIR}/openclaw-manager-tailscale.sh systemd-install"
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

setup_backup_cron() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        return
    fi
    
    log_step "Setting up automatic backups..."
    
    # Create backup script symlink
    local backup_script="${DATA_DIR}/backup.sh"
    if [[ ! -f "$backup_script" ]]; then
        cp "${SCRIPT_DIR}/backup.sh" "$backup_script"
        chmod +x "$backup_script"
    fi
    
    # Suggest cron job
    log_info "To enable daily backups at 3 AM, add this crontab entry:"
    echo "  0 3 * * * ${backup_script} backup"
    echo
    
    # Create initial backup
    read -rp "Create initial backup now? (y/n): " create_backup
    if [[ "$create_backup" == "y" || "$create_backup" == "Y" ]]; then
        "$backup_script" backup
    fi
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

run_health_check() {
    log_step "Running health check..."
    
    if [[ -f "${SCRIPT_DIR}/health-check.sh" ]]; then
        "${SCRIPT_DIR}/health-check.sh" --quiet || true
    fi
    
    echo
}

print_next_steps() {
    echo
    echo "============================================"
    echo "         DEPLOYMENT COMPLETE!              "
    echo "============================================"
    echo
    echo -e "${GREEN}OpenClaw is ready to start!${NC}"
    echo
    echo "Next steps:"
    echo
    echo "  1. Start the services:"
    echo -e "     ${CYAN}cd ${SCRIPT_DIR}${NC}"
    echo -e "     ${CYAN}./openclaw-manager-tailscale.sh start${NC}"
    echo
    echo "  2. Check status:"
    echo -e "     ${CYAN}./openclaw-manager-tailscale.sh status-full${NC}"
    echo
    echo "  3. Get your Funnel URL:"
    echo -e "     ${CYAN}./openclaw-manager-tailscale.sh tunnel-url${NC}"
    echo
    echo "  4. Monitor health:"
    echo -e "     ${CYAN}./health-check.sh${NC}"
    echo
    echo "Documentation:"
    echo "  - README: ${PACKAGE_ROOT}/QWEN.md"
    echo "  - Migration guide: ${SCRIPT_DIR}/MIGRATION.md"
    echo
    echo "Support:"
    echo "  - GitHub: https://github.com/kuroringo90/-openclaw-setup-docker-new"
    echo
}

main() {
    print_banner
    
    check_prerequisites
    prompt_configuration
    create_data_directory
    create_configuration
    install_tailscale_stack
    pull_docker_image
    
    if [[ "$ENABLE_SYSTEMD" == "true" ]]; then
        setup_systemd
    fi
    
    setup_backup_cron
    run_health_check
    print_next_steps
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --authkey)
            TS_AUTHKEY="$2"
            shift 2
            ;;
        --api-key)
            TS_API_KEY="$2"
            shift 2
            ;;
        --tailnet)
            TS_TAILNET="$2"
            shift 2
            ;;
        --systemd)
            ENABLE_SYSTEMD=true
            shift
            ;;
        --no-backup)
            BACKUP_ENABLED=false
            shift
            ;;
        --non-interactive)
            # For CI/CD usage - requires env vars to be set
            if [[ -z "$TS_AUTHKEY" ]]; then
                log_error "TS_AUTHKEY required for non-interactive mode"
                exit 1
            fi
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $0 [options]

Production deployment script for OpenClaw + Tailscale.

Options:
  --authkey <key>       Tailscale auth key (required for non-interactive)
  --api-key <key>       Tailscale API key (optional)
  --tailnet <name>      Tailnet name (optional, auto-detected)
  --systemd             Enable systemd auto-start
  --no-backup           Skip backup setup
  --non-interactive     Run without prompts (for CI/CD)
  -h, --help            Show this help

Environment variables:
  TS_AUTHKEY, TS_API_KEY, TS_TAILNET, OPENCLAW_DATA_DIR, ENABLE_SYSTEMD

Examples:
  # Interactive deployment
  $0
  
  # Non-interactive deployment
  TS_AUTHKEY=tskey-xxx $0 --non-interactive
  
  # Full automated deployment
  $0 --authkey tskey-xxx --api-key api-xxx --systemd
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
