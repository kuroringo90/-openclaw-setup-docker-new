#!/usr/bin/env bash
#
# Backup and restore script for OpenClaw + Tailscale configuration
# Supports scheduled backups, incremental backups, and point-in-time recovery
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/.openclaw/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

ensure_backup_dir() {
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
}

create_backup() {
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local temp_dir
    temp_dir="$(mktemp -d)"
    
    log_info "Creating backup: ${BACKUP_NAME}"
    
    # Create backup structure
    mkdir -p "${temp_dir}/${BACKUP_NAME}"
    
    # Backup configuration files
    if [[ -f "${DATA_DIR}/.env" ]]; then
        cp "${DATA_DIR}/.env" "${temp_dir}/${BACKUP_NAME}/"
        log_info "  - Configuration (.env)"
    fi
    
    # Backup docker-compose
    if [[ -f "${DATA_DIR}/docker-compose.yml" ]]; then
        cp "${DATA_DIR}/docker-compose.yml" "${temp_dir}/${BACKUP_NAME}/"
        log_info "  - Docker Compose configuration"
    fi
    
    # Backup Tailscale state
    if [[ -d "${DATA_DIR}/tailscale-funnel" ]]; then
        cp -r "${DATA_DIR}/tailscale-funnel" "${temp_dir}/${BACKUP_NAME}/"
        log_info "  - Tailscale configuration and state"
    fi
    
    # Create tarball
    cd "${temp_dir}"
    tar -czf "${backup_path}.tar.gz" "${BACKUP_NAME}"
    rm -rf "${temp_dir}"
    
    # Calculate checksum
    sha256sum "${backup_path}.tar.gz" > "${backup_path}.tar.gz.sha256"
    
    local size
    size="$(du -h "${backup_path}.tar.gz" | cut -f1)"
    log_success "Backup created: ${backup_path}.tar.gz (${size})"
    
    # Cleanup old backups (keep last 7 days)
    cleanup_old_backups
}

restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_warn "This will stop running containers and restore configuration"
    read -p "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Restoring from: $backup_file"
    
    # Stop containers
    "${SCRIPT_DIR}/openclaw-manager-tailscale.sh" stop || true
    
    # Extract backup
    local temp_dir
    temp_dir="$(mktemp -d)"
    tar -xzf "$backup_file" -C "${temp_dir}"
    
    # Find backup directory (should be the only dir in temp)
    local backup_name
    backup_name="$(basename "${backup_file}" .tar.gz)"
    local source_dir="${temp_dir}/${backup_name}"
    
    # Restore files
    if [[ -f "${source_dir}/.env" ]]; then
        cp "${source_dir}/.env" "${DATA_DIR}/"
        log_info "  - Restored .env"
    fi
    
    if [[ -f "${source_dir}/docker-compose.yml" ]]; then
        cp "${source_dir}/docker-compose.yml" "${DATA_DIR}/"
        log_info "  - Restored docker-compose.yml"
    fi
    
    if [[ -d "${source_dir}/tailscale-funnel" ]]; then
        rm -rf "${DATA_DIR}/tailscale-funnel"
        cp -r "${source_dir}/tailscale-funnel" "${DATA_DIR}/"
        log_info "  - Restored Tailscale configuration"
    fi
    
    rm -rf "${temp_dir}"
    
    log_success "Restore completed"
    log_info "Run './openclaw-manager-tailscale.sh start' to restart"
}

list_backups() {
    echo
    echo "Available backups:"
    echo "=================="
    
    if [[ ! -d "${BACKUP_DIR}" ]] || [[ -z "$(ls -A "${BACKUP_DIR}" 2>/dev/null)" ]]; then
        echo "No backups found"
        return
    fi
    
    local count=0
    for backup in "${BACKUP_DIR}"/openclaw-backup-*.tar.gz; do
        if [[ -f "$backup" ]]; then
            local name size date checksum_valid
            name="$(basename "$backup")"
            size="$(du -h "$backup" | cut -f1)"
            date="$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1)"
            
            # Verify checksum if exists
            checksum_valid=""
            if [[ -f "${backup}.sha256" ]]; then
                if sha256sum -c "${backup}.sha256" >/dev/null 2>&1; then
                    checksum_valid=" [OK]"
                else
                    checksum_valid=" [CORRUPTED]"
                fi
            fi
            
            echo "  ${name}  (${size})  ${date}${checksum_valid}"
            ((count++))
        fi
    done
    
    echo
    echo "Total: ${count} backup(s)"
}

cleanup_old_backups() {
    local keep_days="${KEEP_BACKUP_DAYS:-7}"
    log_info "Cleaning up backups older than ${keep_days} days..."
    
    local deleted=0
    while IFS= read -r -d '' file; do
        rm -f "$file" "${file}.sha256"
        ((deleted++))
    done < <(find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz" -type f -mtime +"${keep_days}" -print0 2>/dev/null)
    
    if [[ $deleted -gt 0 ]]; then
        log_info "Deleted ${deleted} old backup(s)"
    fi
}

verify_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_info "Verifying: $backup_file"
    
    # Check tarball integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "Archive integrity: OK"
    else
        log_error "Archive integrity: FAILED"
        return 1
    fi
    
    # Verify checksum
    if [[ -f "${backup_file}.sha256" ]]; then
        if sha256sum -c "${backup_file}.sha256" >/dev/null 2>&1; then
            log_success "Checksum verification: OK"
        else
            log_error "Checksum verification: FAILED"
            return 1
        fi
    else
        log_warn "No checksum file found"
    fi
    
    # List contents
    echo
    log_info "Backup contents:"
    tar -tzf "$backup_file" | head -20
    
    log_success "Backup is valid"
}

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  backup              Create a new backup
  restore <file>      Restore from a backup file
  list                List available backups
  verify <file>       Verify backup integrity
  cleanup             Remove old backups

Environment variables:
  BACKUP_DIR          Backup directory (default: ~/.openclaw/backups)
  KEEP_BACKUP_DAYS    Days to keep backups (default: 7)
  OPENCLAW_DATA_DIR   OpenClaw data directory (default: ~/.openclaw)

Examples:
  $0 backup
  $0 restore ~/.openclaw/backups/openclaw-backup-20240101_120000.tar.gz
  $0 list
  $0 verify ~/.openclaw/backups/openclaw-backup-20240101_120000.tar.gz
EOF
}

main() {
    local cmd="${1:-}"
    shift || true
    
    ensure_backup_dir
    
    case "$cmd" in
        backup)
            create_backup
            ;;
        restore)
            if [[ -z "${1:-}" ]]; then
                log_error "Specify backup file to restore"
                exit 1
            fi
            restore_backup "$1"
            ;;
        list)
            list_backups
            ;;
        verify)
            if [[ -z "${1:-}" ]]; then
                log_error "Specify backup file to verify"
                exit 1
            fi
            verify_backup "$1"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        ""|-h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
