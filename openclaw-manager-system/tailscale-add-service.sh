#!/usr/bin/env bash
#
# Aggiungi OpenClaw a Tailscale Funnel
# Script wrapper che usa il modulo tailscale-funnel-compose
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
OPENCLAW_CONFIG_FILE="${DATA_DIR}/data/openclaw.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERRORE]${NC} $*"; }

resolve_ts_stack_dir() {
    local candidate

    if [[ -n "${REPO_TS_STACK_DIR:-}" ]]; then
        candidate="${REPO_TS_STACK_DIR}"
        [[ -f "${candidate}/tailscale-funnel-compose.sh" ]] && { printf '%s\n' "${candidate}"; return 0; }
    fi

    for candidate in \
        "${PACKAGE_ROOT}/../tailscale-funnel-compose-standalone" \
        "${PACKAGE_ROOT}/../tailscale-funnel-compose" \
        "${PACKAGE_ROOT}/tailscale-funnel-compose" \
        "/opt/tailscale-funnel-compose"
    do
        [[ -f "${candidate}/tailscale-funnel-compose.sh" && -f "${candidate}/.env" ]] && { printf '%s\n' "${candidate}"; return 0; }
    done

    for candidate in \
        "${PACKAGE_ROOT}/../tailscale-funnel-compose-standalone" \
        "${PACKAGE_ROOT}/../tailscale-funnel-compose" \
        "${PACKAGE_ROOT}/tailscale-funnel-compose" \
        "/opt/tailscale-funnel-compose"
    do
        [[ -f "${candidate}/tailscale-funnel-compose.sh" ]] && { printf '%s\n' "${candidate}"; return 0; }
    done

    return 1
}

TS_STACK_DIR="$(resolve_ts_stack_dir || true)"
TS_MANAGER="${TS_STACK_DIR:+${TS_STACK_DIR}/tailscale-funnel-compose.sh}"

get_openclaw_token() {
    if [[ -f "${OPENCLAW_CONFIG_FILE}" ]]; then
        OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_FILE}" python3 - <<'PY' 2>/dev/null || true
import json
import os
from pathlib import Path
path = Path(os.environ["OPENCLAW_CONFIG_FILE"])
try:
    data = json.loads(path.read_text())
    token = (((data.get("gateway") or {}).get("auth") or {}).get("token") or "").strip()
    if token:
        print(token)
except Exception:
    pass
PY
    fi
}

show_openclaw_dashboard_url() {
    local base_url="$1"
    local service_path="${2:-/}"
    local token
    token="$(get_openclaw_token)"
    service_path="${service_path%/}"

    if [[ -z "${service_path}" ]]; then
        service_path="/"
    fi

    if [[ -n "$token" ]]; then
        if [[ "${service_path}" == "/" ]]; then
            echo "${base_url}/#token=${token}"
        else
            echo "${base_url}${service_path}/#token=${token}"
        fi
    else
        if [[ "${service_path}" == "/" ]]; then
            echo "${base_url}/"
        else
            echo "${base_url}${service_path}/"
        fi
    fi
}

get_openclaw_service_path() {
    local registry_file="${TS_STACK_DIR}/config/services.tsv"
    [[ -f "${registry_file}" ]] || return 1

    while IFS=$'\t' read -r name _target path _mode; do
        [[ "${name}" == "openclaw" ]] || continue
        printf '%s\n' "${path}"
        return 0
    done < "${registry_file}"

    return 1
}

show_openclaw_public_url() {
    local openclaw_path
    local base_urls

    [[ -f "$TS_MANAGER" ]] || return 1

    openclaw_path="$(get_openclaw_service_path || true)"
    [[ -n "${openclaw_path}" ]] || return 1

    base_urls="$(cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)"
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        if [[ "${openclaw_path}" == "/" && "$url" =~ ^https://[^/]+/?$ ]]; then
            local base_url="${url%/}"
            show_openclaw_dashboard_url "${base_url}" "${openclaw_path}"
            return 0
        fi
        if [[ "${openclaw_path}" != "/" && ( "$url" == *"${openclaw_path%/}" || "$url" == *"${openclaw_path%/}/" ) ]]; then
            local base_url="${url%"${openclaw_path%/}/"}"
            base_url="${base_url%"${openclaw_path%/}"}"
            show_openclaw_dashboard_url "${base_url}" "${openclaw_path}"
            return 0
        fi
    done <<< "${base_urls}"

    return 1
}

check_module() {
    if [[ ! -f "$TS_MANAGER" ]]; then
        log_error "Modulo Tailscale non trovato: ${TS_MANAGER}"
        log_info "Per abilitare accesso remoto:"
        log_info "  1. Clona il repo modulo tailscale-funnel-compose"
        log_info "  2. Oppure imposta REPO_TS_STACK_DIR verso il modulo standalone"
        log_info "  3. Path cercati automaticamente:"
        log_info "     - ${PACKAGE_ROOT}/../tailscale-funnel-compose-standalone"
        log_info "     - ${PACKAGE_ROOT}/../tailscale-funnel-compose"
        log_info "     - /opt/tailscale-funnel-compose"
        log_info "  4. Configura .env con TS_AUTHKEY"
        exit 1
    fi
}

check_authkey() {
    local ts_env="${TS_STACK_DIR}/.env"
    if [[ ! -f "$ts_env" ]]; then
        ts_env="${DATA_DIR}/tailscale-funnel/.env"
    fi
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

add_service() {
    local service_name="${1:-openclaw}"
    local service_target="${2:-${OPENCLAW_PORT}}"
    local service_path="${3:-/}"
    local service_mode="${4:-funnel}"

    if [[ "${service_name}" == "openclaw" && "${service_path}" == "/openclaw" ]]; then
        service_path="/openclaw/"
    fi

    log_info "Aggiunta servizio a Tailscale: ${service_name} -> ${service_target} (${service_path}, mode=${service_mode})"
    
    # Check se modulo esiste
    if [[ ! -f "$TS_MANAGER" ]]; then
        log_error "Modulo Tailscale non trovato: ${TS_MANAGER}"
        log_info "Per abilitare accesso remoto:"
        log_info "  1. Clona il modulo standalone o imposta REPO_TS_STACK_DIR"
        log_info "  2. Configura .env con TS_AUTHKEY"
        exit 1
    fi
    
    # Check configurazione Tailscale
    local ts_env="${TS_STACK_DIR}/.env"
    if [[ ! -f "$ts_env" ]]; then
        ts_env="${DATA_DIR}/tailscale-funnel/.env"
    fi
    local authkey=""
    
    if [[ -f "$ts_env" ]]; then
        authkey="$(grep -E "^TS_AUTHKEY=" "$ts_env" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)"
    fi
    
    # Se Tailscale è già attivo, aggiungi servizio
    if docker ps --format '{{.Names}}' | grep -q "^tailscale-funnel$"; then
        log_success "Tailscale Funnel è attivo"
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" add "${service_name}" "${service_target}" "${service_path}" "${service_mode}")
        log_success "Servizio aggiunto a Tailscale Funnel"
        echo
        log_info "URL Funnel:"
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)
        return 0
    fi
    
    # Tailscale non attivo - check se è configurato
    if [[ -n "$authkey" ]]; then
        log_info "Tailscale non attivo ma configurato - avvio automatico..."
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" start "${service_name}" "${service_target}" "${service_path}" "${service_mode}")
        log_success "Servizio esposto su Tailscale Funnel"
        echo
        log_info "URL Funnel:"
        (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)
        return 0
    fi
    
    # Tailscale non configurato
    log_error "TS_AUTHKEY non configurata"
    log_info "Per abilitare accesso remoto:"
    echo
    log_info "1. Configura TS_AUTHKEY:"
    echo -e "   ${BLUE}cd ${TS_STACK_DIR:-/percorso/al/modulo/tailscale-funnel-compose}${NC}"
    echo -e "   ${BLUE}cp .env.example .env${NC}"
    echo -e "   ${BLUE}nano .env  # Imposta TS_AUTHKEY${NC}"
    echo
    log_info "2. Poi esegui:"
    echo -e "   ${BLUE}./start-service.sh ${service_name} ${service_target} ${service_path} ${service_mode}${NC}"
    echo
    log_info "Oppure ottieni una chiave da:"
    echo -e "   ${BLUE}https://login.tailscale.com/admin/settings/keys${NC}"
    
    return 1
}

remove_openclaw() {
    local name="${1:-openclaw}"
    log_info "Rimozione ${name} da Tailscale Funnel..."
    
    if [[ ! -f "$TS_MANAGER" ]]; then
        log_warn "Modulo Tailscale non trovato"
        return 0
    fi
    
    (cd "${TS_STACK_DIR}" && "${TS_MANAGER}" remove "${name}") || true
    log_success "${name} rimosso da Tailscale Funnel"
}

show_url() {
    if [[ -f "$TS_MANAGER" ]]; then
        local base_urls
        local openclaw_path
        base_urls="$(cd "${TS_STACK_DIR}" && "${TS_MANAGER}" url)"
        openclaw_path="$(get_openclaw_service_path || true)"
        if [[ -n "$base_urls" ]]; then
            while IFS= read -r url; do
                [[ -n "$url" ]] || continue
                if [[ -n "${openclaw_path}" && "${openclaw_path}" == "/" && "$url" =~ ^https://[^/]+/?$ ]]; then
                    local base_url="${url%/}"
                    show_openclaw_dashboard_url "${base_url}" "${openclaw_path}"
                elif [[ "$url" == */openclaw || "$url" == */openclaw/ ]]; then
                    local base_url="${url%/openclaw/}"
                    base_url="${base_url%/openclaw}"
                    show_openclaw_dashboard_url "${base_url}" "/openclaw"
                else
                    echo "$url"
                fi
            done <<< "$base_urls"
        fi
    else
        log_warn "Modulo Tailscale non configurato"
    fi
}

status() {
    echo -e "${CYAN}=== OpenClaw ===${NC}"
    docker ps --filter "name=openclaw" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

    echo
    echo -e "${CYAN}=== OpenClaw Dashboard URL ===${NC}"
    show_openclaw_public_url || true
    
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
  $0 add openclaw 18789 / serve
  $0 url      # Mostra URL pubblico
  $0 status   # Mostra stato completo
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    add) add_service "$@" ;;
    remove) remove_openclaw "${1:-}" ;;
    url) show_url ;;
    status) status ;;
    ""|-h|--help|help) usage ;;
    *) log_error "Comando sconosciuto: ${cmd}"; usage; exit 1 ;;
esac
