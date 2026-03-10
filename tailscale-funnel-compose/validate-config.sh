#!/usr/bin/env bash
#
# Configuration validation script for production deployments
# Validates .env files, checks security settings, and reports issues
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

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

# Validation counters
ERRORS=0
WARNINGS=0

check_file_exists() {
    local file="$1"
    local description="$2"
    if [[ -f "$file" ]]; then
        log_success "$description: $file"
    else
        log_error "$description mancante: $file"
        ((ERRORS++))
    fi
}

check_env_value() {
    local file="$1"
    local key="$2"
    local required="${3:-false}"
    local sensitive="${4:-false}"
    local value

    if [[ ! -f "$file" ]]; then
        log_error "File .env non trovato"
        ((ERRORS++))
        return
    fi

    value="$(grep -E "^${key}=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"

    if [[ -z "$value" ]]; then
        if [[ "$required" == "true" ]]; then
            log_error "VALORE RICHIESTO: $key non impostato"
            ((ERRORS++))
        else
            log_warn "VALORE OPZIONALE: $key non impostato"
            ((WARNINGS++))
        fi
    else
        if [[ "$sensitive" == "true" ]]; then
            # Mask sensitive values
            local masked
            masked="$(echo "$value" | sed 's/./*/g' | head -c 8)"
            log_success "$key impostato: ${masked}..."
        else
            log_success "$key impostato: $value"
        fi
    fi
}

check_authkey_format() {
    local file="$1"
    local value

    if [[ ! -f "$file" ]]; then
        return
    fi

    value="$(grep -E "^TS_AUTHKEY=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"

    if [[ -n "$value" ]]; then
        # Check for development key format
        if [[ "$value" == tskey-auth-* ]]; then
            log_warn "TS_AUTHKEY usa formato development (tskey-auth-*)"
            log_warn "Per produzione, usa una pre-authenticated key dalla admin console"
            ((WARNINGS++))
        # Check for key length (pre-auth keys are typically 40+ chars)
        elif [[ ${#value} -lt 20 ]]; then
            log_error "TS_AUTHKEY sembra troppo corta (< 20 caratteri)"
            ((ERRORS++))
        else
            log_success "TS_AUTHKEY formato valido"
        fi
    fi
}

check_api_key_permissions() {
    local file="$1"
    local value

    if [[ ! -f "$file" ]]; then
        return
    fi

    value="$(grep -E "^TS_API_KEY=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"

    if [[ -n "$value" ]]; then
        log_info "TS_API_KEY configurato - verifica i permessi:"
        log_info "  - Devices: read, write (per cleanup duplicati)"
        log_info "  - Per production: limita a Devices: write only"
    else
        log_warn "TS_API_KEY non configurato - cleanup duplicati disabilitato"
        ((WARNINGS++))
    fi
}

check_docker_available() {
    if command -v docker >/dev/null 2>&1; then
        log_success "Docker disponibile: $(docker --version)"
    else
        log_error "Docker non trovato nel PATH"
        ((ERRORS++))
    fi

    if docker info >/dev/null 2>&1; then
        log_success "Docker daemon in esecuzione"
    else
        log_error "Docker daemon non risponde"
        ((ERRORS++))
    fi
}

check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        log_success "Docker Compose (plugin): $(docker compose version)"
    elif command -v docker-compose >/dev/null 2>&1; then
        log_warn "docker-compose (standalone) - considera upgrade a plugin"
        ((WARNINGS++))
    else
        log_error "Docker Compose non disponibile"
        ((ERRORS++))
    fi
}

check_python3() {
    if command -v python3 >/dev/null 2>&1; then
        log_success "Python 3 disponibile: $(python3 --version)"
    else
        log_error "Python 3 non trovato (richiesto per gestione config)"
        ((ERRORS++))
    fi
}

check_curl() {
    if command -v curl >/dev/null 2>&1; then
        log_success "curl disponibile: $(curl --version | head -1)"
    else
        log_error "curl non trovato (richiesto per API Tailscale)"
        ((ERRORS++))
    fi
}

check_security_settings() {
    local file="$1"
    local bind_address

    if [[ ! -f "$file" ]]; then
        return
    fi

    bind_address="$(grep -E "^OPENCLAW_BIND_ADDRESS=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"

    if [[ "$bind_address" == "0.0.0.0" ]]; then
        log_warn "OPENCLAW_BIND_ADDRESS=0.0.0.0 espone OpenClaw su tutte le interfacce"
        log_warn "Per produzione, usa OPENCLAW_BIND_ADDRESS=127.0.0.1"
        ((WARNINGS++))
    elif [[ "$bind_address" == "127.0.0.1" ]]; then
        log_success "OPENCLAW_BIND_ADDRESS configurato correttamente (localhost-only)"
    fi
}

check_image_pinning() {
    local file="$1"
    local image

    if [[ ! -f "$file" ]]; then
        return
    fi

    image="$(grep -E "^OPENCLAW_IMAGE_NAME=" "$file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"

    if [[ "$image" == *":latest" ]]; then
        log_warn "OPENCLAW_IMAGE_NAME usa tag :latest"
        log_warn "Per produzione, usa un tag specifico (es: :v1.2.3) o SHA digest"
        ((WARNINGS++))
    elif [[ "$image" == *"@sha256:"* ]]; then
        log_success "OPENCLAW_IMAGE_NAME usa SHA digest (best practice)"
    elif [[ "$image" == *":v"* ]] || [[ "$image" == *":[0-9]."* ]]; then
        log_success "OPENCLAW_IMAGE_NAME usa tag versionato"
    fi
}

print_summary() {
    echo
    echo "============================================"
    echo "           VALIDATION SUMMARY               "
    echo "============================================"
    
    if [[ $ERRORS -gt 0 ]]; then
        log_error "ERRORI: $ERRORS - Configurazione non pronta per produzione"
    else
        log_success "ERRORI: 0"
    fi
    
    if [[ $WARNINGS -gt 0 ]]; then
        log_warn "WARNING: $WARNINGS - Review recommended"
    else
        log_success "WARNING: 0"
    fi
    
    echo
    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        log_success "Configurazione pronta per produzione!"
        return 0
    elif [[ $ERRORS -eq 0 ]]; then
        log_success "Configurazione valida con warning minori"
        return 0
    else
        log_error "Risolvi gli errori prima di deployare in produzione"
        return 1
    fi
}

main() {
    echo "============================================"
    echo "   OPENCLAW CONFIGURATION VALIDATOR        "
    echo "============================================"
    echo
    
    check_file_exists "$ENV_FILE" "File .env"
    
    echo
    echo "--- Validazione parametri Tailscale ---"
    check_env_value "$ENV_FILE" "TS_AUTHKEY" "true" "true"
    check_env_value "$ENV_FILE" "TS_API_KEY" "false" "true"
    check_env_value "$ENV_FILE" "TS_TAILNET" "false"
    check_env_value "$ENV_FILE" "TS_HOSTNAME" "false"
    check_authkey_format "$ENV_FILE"
    check_api_key_permissions "$ENV_FILE"
    
    echo
    echo "--- Validazione parametri OpenClaw ---"
    check_env_value "$ENV_FILE" "OPENCLAW_CONTAINER_NAME" "false"
    check_env_value "$ENV_FILE" "OPENCLAW_IMAGE_NAME" "false"
    check_security_settings "$ENV_FILE"
    check_image_pinning "$ENV_FILE"
    
    echo
    echo "--- Validazione prerequisiti di sistema ---"
    check_docker_available
    check_docker_compose
    check_python3
    check_curl
    
    print_summary
}

main "$@"
