#!/usr/bin/env bash
#
# Aggiungi OpenClaw a Tailscale Funnel
# Script wrapper che usa il modulo tailscale-funnel-compose
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TS_STACK_DIR="${PACKAGE_ROOT}/tailscale-funnel-compose"
TS_MANAGER="${TS_STACK_DIR}/tailscale-funnel-compose.sh"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERRORE]${NC} $*"; }

check_module() {
    if [[ ! -f "$TS_MANAGER" ]]; then
        log_error "Modulo Tailscale non trovato: ${TS_MANAGER}"
        log_info "Per abilitare accesso remoto:"
        log_info "  1. Clona o copia tailscale-funnel-compose/"
        log_info "  2. Configura .env con TS_AUTHKEY"
        log_info "  3. Esegui: ${TS_MANAGER} start openclaw ${OPENCLAW_PORT} /"
        exit 1
    fi
}

check_authkey() {
    local ts_env="${DATA_DIR}/tailscale-funnel/.env"
    if [[ -f "$ts_env" ]]; then
        local authkey
        authkey="$(grep -E "^TS_AUTHKEY=" "$ts_env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"
        if [[ -z "$authkey" ]]; then
            log_error "TS_AUTHKEY non configurata in ${ts_env}"
            log_info "Configura TS_AUTHKEY nel modulo tailscale-funnel-compose/"
            exit 1
        fi
    fi
}

add_openclaw() {
    log_info "Aggiunta OpenClaw a Tailscale Funnel..."
    
    # Check se Tailscale è già attivo
    if docker ps --format '{{.Names}}' | grep -q "^tailscale-funnel$"; then
        log_success "Tailscale Funnel è attivo"
        
        # Chiedi se aggiungere OpenClaw
        read -rp "Aggiungi OpenClaw come servizio su '/'? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Operazione annullata"
            exit 0
        fi
        
        # Aggiungi servizio
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" add openclaw "${OPENCLAW_PORT}" /)
        log_success "OpenClaw aggiunto a Tailscale Funnel"
        
        # Mostra URL
        echo
        log_info "URL Funnel:"
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)
    else
        log_info "Tailscale Funnel non è attivo"
        log_info "Avvio Tailscale Funnel con OpenClaw..."
        
        check_authkey
        
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" start openclaw "${OPENCLAW_PORT}" /)
        log_success "OpenClaw esposto su Tailscale Funnel"
        
        # Mostra URL
        echo
        log_info "URL Funnel:"
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)
    fi
}

remove_openclaw() {
    log_info "Rimozione OpenClaw da Tailscale Funnel..."
    
    if [[ ! -f "$TS_MANAGER" ]]; then
        log_warn "Modulo Tailscale non trovato"
        return 0
    fi
    
    (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" remove openclaw) || true
    log_success "OpenClaw rimosso da Tailscale Funnel"
}

show_url() {
    if [[ -f "$TS_MANAGER" ]]; then
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)
    else
        log_warn "Modulo Tailscale non configurato"
    fi
}

status() {
    echo -e "${CYAN}=== OpenClaw ===${NC}"
    docker ps --filter "name=openclaw" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    
    echo
    echo -e "${CYAN}=== Tailscale Funnel ===${NC}"
    if [[ -f "$TS_MANAGER" ]]; then
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" status)
    else
        log_info "Modulo Tailscale non configurato"
    fi
}

usage() {
    cat <<EOF
Uso: $0 <comando>

Comandi:
  add     Aggiungi OpenClaw a Tailscale Funnel
  remove  Rimuovi OpenClaw da Tailscale Funnel
  url     Mostra URL Funnel
  status  Mostra stato OpenClaw + Tailscale

Esempi:
  $0 add      # Aggiungi OpenClaw a Funnel
  $0 url      # Mostra URL pubblico
  $0 status   # Mostra stato completo
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    add) add_openclaw ;;
    remove) remove_openclaw ;;
    url) show_url ;;
    status) status ;;
    ""|-h|--help|help) usage ;;
    *) log_error "Comando sconosciuto: ${cmd}"; usage; exit 1 ;;
esac
