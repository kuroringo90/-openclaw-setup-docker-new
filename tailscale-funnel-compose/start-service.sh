#!/usr/bin/env bash
#
# Start Tailscale Funnel with a service
# Helper script for starting Tailscale before or after the main service
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER="${SCRIPT_DIR}/tailscale-funnel-compose.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERRORE]${NC} $*"; }

usage() {
    cat <<EOF
Uso: $0 <service-name> <port> [path]

Avvia Tailscale Funnel ed espone un servizio locale.

Argomenti:
  service-name  Nome del servizio (es: openclaw, grafana)
  port          Porta del servizio locale
  path          Path URL (default: /<service-name>)

Esempi:
  # Avvia Tailscale con OpenClaw su /
  $0 openclaw 18789 /
  
  # Avvia Tailscale con Grafana su /grafana
  $0 grafana 3000 /grafana
  
  # Avvia solo Tailscale (nessun servizio)
  $0 --only

Note:
  - Richiede TS_AUTHKEY configurata in .env
  - Se il container è già attivo, aggiunge il servizio
  - Se il container non esiste, lo crea e avvia
EOF
}

start_tailscale() {
    local name="${1:-}"
    local port="${2:-}"
    local path="${3:-}"
    
    # Check se .env esiste
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        log_error ".env non trovato in ${SCRIPT_DIR}"
        log_info "Copia .env.example in .env e configura TS_AUTHKEY"
        exit 1
    fi
    
    # Check se TS_AUTHKEY è configurata
    local authkey
    authkey="$(grep -E "^TS_AUTHKEY=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"
    if [[ -z "$authkey" ]]; then
        log_error "TS_AUTHKEY non configurata in ${SCRIPT_DIR}/.env"
        log_info "Ottieni una chiave da: https://login.tailscale.com/admin/settings/keys"
        exit 1
    fi
    
    # Check se container è già attivo
    if docker ps --format '{{.Names}}' | grep -q "^tailscale-funnel$"; then
        log_success "Tailscale Funnel è già attivo"
        
        if [[ -n "$name" && -n "$port" ]]; then
            # Aggiungi servizio
            log_info "Aggiunta servizio: ${name} -> ${port}"
            "${MANAGER}" add "$name" "$port" "${path:-/$name}"
        fi
    else
        # Avvia Tailscale
        if [[ -n "$name" && -n "$port" ]]; then
            log_info "Avvio Tailscale Funnel con servizio: ${name} -> ${port}"
            "${MANAGER}" start "$name" "$port" "${path:-/$name}"
        else
            log_info "Avvio solo Tailscale Funnel (nessun servizio)"
            log_info "Aggiungi servizi dopo con: $0 <name> <port> [path]"
            "${MANAGER}" start dummy 9999 /placeholder
            log_warn "Servizio placeholder attivo - aggiungine uno reale e rimuovi questo"
        fi
    fi
    
    # Mostra URL
    echo
    log_info "URL Funnel:"
    "${MANAGER}" url
}

start_only() {
    log_info "Avvio Tailscale Funnel..."
    start_tailscale "" ""
}

cmd="${1:-}"
shift || true

case "$cmd" in
    -h|--help|help)
        usage
        ;;
    --only)
        start_only
        ;;
    *)
        if [[ $# -lt 2 ]]; then
            log_error "Servono almeno nome e porta"
            usage
            exit 1
        fi
        start_tailscale "$@"
        ;;
esac
