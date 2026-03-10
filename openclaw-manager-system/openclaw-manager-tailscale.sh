#!/usr/bin/env bash
#
# OpenClaw Docker Manager + Tailscale Funnel Compose
# Compatibile con la nuova struttura standalone Compose-first.
#
# Mantiene i comandi storici ma delega la gestione Tailscale allo stack:
#   tailscale-funnel-compose/tailscale-funnel-compose.sh
#
set -euo pipefail

# ============================================
# CONFIGURAZIONE
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_TS_STACK_DIR="${REPO_TS_STACK_DIR:-${PACKAGE_ROOT}/tailscale-funnel-compose}"
TS_MANAGER_SCRIPT_NAME="tailscale-funnel-compose.sh"

CONTAINER_NAME="${OPENCLAW_CONTAINER_NAME:-openclaw}"
IMAGE_NAME="${OPENCLAW_IMAGE_NAME:-ghcr.io/openclaw/openclaw:latest}"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
ENV_FILE="${DATA_DIR}/.env"
TS_STACK_DIR="${TAILSCALE_STACK_DIR:-${DATA_DIR}/tailscale-funnel}"
TS_STACK_ENV_FILE="${TS_STACK_DIR}/.env"
TS_STATE_DIR="${TS_STACK_DIR}/state"
TS_CONFIG_DIR="${TS_STACK_DIR}/config"
TS_RUNTIME_MANAGER="${TS_STACK_DIR}/${TS_MANAGER_SCRIPT_NAME}"
DEFAULT_OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

# Colori
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

# Carica config esistente OpenClaw
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        log_error "docker compose / docker-compose non disponibile"
        exit 1
    fi
}

check_prereqs() {
    command -v docker >/dev/null 2>&1 || { log_error "Docker non trovato"; exit 1; }
    docker info >/dev/null 2>&1 || { log_error "Docker non è in esecuzione"; exit 1; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3 non trovato"; exit 1; }
    log_success "Prerequisiti OK"
}

check_image() {
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
        log_error "Immagine ${IMAGE_NAME} non trovata localmente"
        log_info "Scaricala con: docker pull ${IMAGE_NAME}"
        exit 1
    fi
    log_success "Immagine locale trovata"
}

is_openclaw_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

check_openclaw_health() {
    curl -fsS --max-time 3 "http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}" >/dev/null 2>&1
}

runtime_tailscale_installed() {
    [[ -x "${TS_RUNTIME_MANAGER}" && -f "${TS_STACK_DIR}/docker-compose.yml" ]]
}

repo_tailscale_available() {
    [[ -x "${REPO_TS_STACK_DIR}/${TS_MANAGER_SCRIPT_NAME}" && -f "${REPO_TS_STACK_DIR}/docker-compose.yml" && -f "${REPO_TS_STACK_DIR}/.env.example" ]]
}

ensure_openclaw_dirs() {
    mkdir -p "${DATA_DIR}/data"
    local uid
    uid="$(id -u)"
    if [[ "$uid" != "1000" ]]; then
        log_warn "Il tuo UID è $uid, ma il container usa UID 1000"
        log_warn "Potresti avere problemi di permessi su ${DATA_DIR}/data"
        log_warn "Soluzione: sudo chown -R 1000:1000 ${DATA_DIR}/data"
    fi
}

ensure_openclaw_compose() {
    cat > "${COMPOSE_FILE}" <<EOF_COMPOSE
services:
  openclaw:
    image: \${IMAGENAME}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${DEFAULT_OPENCLAW_PORT}:${DEFAULT_OPENCLAW_PORT}"
    volumes:
      - ${DATA_DIR}/data:/home/node/.openclaw
    environment:
      - NODE_ENV=production
      - OPENCLAW_GATEWAY_PORT=${DEFAULT_OPENCLAW_PORT}
      - OPENCLAW_GATEWAY_BIND=lan
    stdin_open: true
    tty: true
EOF_COMPOSE
}

ensure_openclaw_env() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        cat > "${ENV_FILE}" <<'EOF_ENV'
# OpenClaw + Tailscale settings
TS_AUTHKEY=
TS_API_KEY=
TS_TAILNET=
TS_HOSTNAME=openclaw
TS_CONTAINER_NAME=tailscale-funnel
EOF_ENV
        log_success "Creato ${ENV_FILE}"
    fi
}

upsert_env_value() {
    local file="$1" key="$2" value="$3"
    touch "$file"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        python3 - "$file" "$key" "$value" <<'PY'
import sys
path, key, value = sys.argv[1:4]
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
with open(path, 'w', encoding='utf-8') as f:
    done = False
    for line in lines:
        if line.startswith(f"{key}=") and not done:
            f.write(f"{key}={value}\n")
            done = True
        else:
            f.write(line)
    if not done:
        f.write(f"{key}={value}\n")
PY
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

get_env_value() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    python3 - "$file" "$key" <<'PY'
import sys
path, key = sys.argv[1:3]
try:
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if line.startswith(f"{key}="):
                print(line.split('=', 1)[1].strip().strip('"'))
                break
except FileNotFoundError:
    pass
PY
}

ensure_tailscale_runtime() {
    if runtime_tailscale_installed; then
        mkdir -p "${TS_STATE_DIR}" "${TS_CONFIG_DIR}"
        return 0
    fi

    if ! repo_tailscale_available; then
        log_error "Nuova struttura Tailscale non trovata"
        log_info "Atteso: ${REPO_TS_STACK_DIR}"
        exit 1
    fi

    log_info "Installo stack Tailscale standalone in ${TS_STACK_DIR}"
    mkdir -p "${TS_STACK_DIR}"
    cp -f "${REPO_TS_STACK_DIR}/docker-compose.yml" "${TS_STACK_DIR}/docker-compose.yml"
    cp -f "${REPO_TS_STACK_DIR}/.env.example" "${TS_STACK_DIR}/.env.example"
    cp -f "${REPO_TS_STACK_DIR}/${TS_MANAGER_SCRIPT_NAME}" "${TS_RUNTIME_MANAGER}"
    chmod +x "${TS_RUNTIME_MANAGER}"
    mkdir -p "${TS_STATE_DIR}" "${TS_CONFIG_DIR}"
    log_success "Stack Tailscale installato"
}

sync_openclaw_env_to_tailscale() {
    ensure_tailscale_runtime

    if [[ ! -f "${TS_STACK_ENV_FILE}" ]]; then
        cp -f "${TS_STACK_DIR}/.env.example" "${TS_STACK_ENV_FILE}"
        log_success "Creato ${TS_STACK_ENV_FILE}"
    fi

    local openclaw_authkey openclaw_api_key openclaw_tailnet openclaw_hostname openclaw_container_name
    local stack_authkey stack_api_key stack_tailnet stack_hostname stack_container_name
    local final_authkey final_api_key final_tailnet final_hostname final_container_name

    openclaw_authkey="$(get_env_value "${ENV_FILE}" TS_AUTHKEY)"
    openclaw_api_key="$(get_env_value "${ENV_FILE}" TS_API_KEY)"
    openclaw_tailnet="$(get_env_value "${ENV_FILE}" TS_TAILNET)"
    openclaw_hostname="$(get_env_value "${ENV_FILE}" TS_HOSTNAME)"
    openclaw_container_name="$(get_env_value "${ENV_FILE}" TS_CONTAINER_NAME)"

    stack_authkey="$(get_env_value "${TS_STACK_ENV_FILE}" TS_AUTHKEY)"
    stack_api_key="$(get_env_value "${TS_STACK_ENV_FILE}" TS_API_KEY)"
    stack_tailnet="$(get_env_value "${TS_STACK_ENV_FILE}" TS_TAILNET)"
    stack_hostname="$(get_env_value "${TS_STACK_ENV_FILE}" TS_HOSTNAME)"
    stack_container_name="$(get_env_value "${TS_STACK_ENV_FILE}" TS_CONTAINER_NAME)"

    final_authkey="${openclaw_authkey:-$stack_authkey}"
    final_api_key="${openclaw_api_key:-$stack_api_key}"
    final_tailnet="${openclaw_tailnet:-$stack_tailnet}"
    final_hostname="${openclaw_hostname:-${stack_hostname:-openclaw}}"
    final_container_name="${openclaw_container_name:-${stack_container_name:-tailscale-funnel}}"

    upsert_env_value "${TS_STACK_ENV_FILE}" TS_AUTHKEY "$final_authkey"
    upsert_env_value "${TS_STACK_ENV_FILE}" TS_API_KEY "$final_api_key"
    upsert_env_value "${TS_STACK_ENV_FILE}" TS_TAILNET "$final_tailnet"
    upsert_env_value "${TS_STACK_ENV_FILE}" TS_HOSTNAME "$final_hostname"
    upsert_env_value "${TS_STACK_ENV_FILE}" TS_CONTAINER_NAME "$final_container_name"

    log_success "Configurazione Tailscale sincronizzata"
}

tailscale_runtime_cmd() {
    ensure_tailscale_runtime
    sync_openclaw_env_to_tailscale
    (cd "${TS_STACK_DIR}" && "${TS_RUNTIME_MANAGER}" "$@")
}

start_openclaw() {
    check_prereqs
    check_image
    ensure_openclaw_dirs
    ensure_openclaw_env
    ensure_openclaw_compose

    export IMAGENAME="${IMAGE_NAME}"
    log_info "Avvio OpenClaw..."
    compose_cmd -f "${COMPOSE_FILE}" up -d
    log_success "OpenClaw avviato"

    if check_openclaw_health; then
        log_success "OpenClaw raggiungibile su http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}"
    else
        log_warn "OpenClaw avviato ma healthcheck HTTP non ancora pronto"
    fi

    # Check Tailscale module and ask user
    check_tailscale_and_ask
}

check_tailscale_and_ask() {
    local ts_available=false
    local ts_running=false
    
    # Check if Tailscale module exists
    if repo_tailscale_available; then
        ts_available=true
    fi
    
    # Check if Tailscale container is running
    if runtime_tailscale_installed && docker ps --format '{{.Names}}' | grep -q "^${TS_CONTAINER_NAME}$"; then
        ts_running=true
    fi
    
    # Decide what to do
    if [[ "$ts_running" == true ]]; then
        # Tailscale is already running - ask to add OpenClaw as service
        echo
        log_info "Tailscale Funnel è già attivo (${TS_CONTAINER_NAME})"
        read -rp "Vuoi aggiungere OpenClaw come servizio su '/'? (y/n): " add_ts
        if [[ "$add_ts" == "y" || "$add_ts" == "Y" ]]; then
            ensure_tailscale_runtime
            sync_openclaw_env_to_tailscale
            tailscale_runtime_cmd start openclaw "${DEFAULT_OPENCLAW_PORT}" /
        fi
    elif [[ "$ts_available" == true ]]; then
        # Tailscale module exists but not running - ask to start
        echo
        log_info "Modulo Tailscale Funnel disponibile ma non attivo"
        read -rp "Vuoi avviare Tailscale Funnel ed esporre OpenClaw? (y/n): " start_ts
        if [[ "$start_ts" == "y" || "$start_ts" == "Y" ]]; then
            # Check if TS_AUTHKEY is configured
            local authkey
            authkey="$(get_env_value "${ENV_FILE}" TS_AUTHKEY)"
            if [[ -z "$authkey" ]]; then
                log_error "TS_AUTHKEY non configurata in ${ENV_FILE}"
                log_info "Impostala in ${SCRIPT_DIR}/.env e riprova"
                return 0
            fi
            ensure_tailscale_runtime
            sync_openclaw_env_to_tailscale
            tailscale_runtime_cmd start openclaw "${DEFAULT_OPENCLAW_PORT}" /
        fi
    else
        # No Tailscale module - just inform user
        echo
        log_warn "Modulo Tailscale non trovato: OpenClaw accessibile solo in locale"
        log_info "Per abilitare accesso remoto, copia il modulo tailscale-funnel-compose/"
    fi
}

stop_openclaw() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        export IMAGENAME="${IMAGE_NAME}"
        compose_cmd -f "${COMPOSE_FILE}" down || true
        log_success "OpenClaw fermato"
    else
        log_warn "Compose OpenClaw non trovato"
    fi
    if runtime_tailscale_installed; then
        (cd "${TS_STACK_DIR}" && "${TS_RUNTIME_MANAGER}" stop) || true
    fi
}

restart_openclaw() {
    stop_openclaw
    start_openclaw
}

status_openclaw() {
    echo -e "${CYAN}=== OpenClaw ===${NC}"
    if [[ -f "${COMPOSE_FILE}" ]]; then
        export IMAGENAME="${IMAGE_NAME}"
        compose_cmd -f "${COMPOSE_FILE}" ps
        echo
        echo -e "${BLUE}Docker ps (Ports incluse):${NC}"
        docker ps --filter "name=^/${CONTAINER_NAME}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    else
        log_warn "Compose OpenClaw non trovato"
    fi
}

status_full() {
    status_openclaw
    echo
    echo -e "${CYAN}=== Tailscale Funnel ===${NC}"
    if runtime_tailscale_installed; then
        tailscale_runtime_cmd status
    else
        log_warn "Stack Tailscale non installato"
    fi
}

show_tunnel_url() {
    if runtime_tailscale_installed; then
        tailscale_runtime_cmd url
    else
        log_warn "Stack Tailscale non installato"
    fi
}

tailscale_config() {
    tailscale_runtime_cmd start openclaw "${DEFAULT_OPENCLAW_PORT}" /
}

tailscale_start_only() {
    tailscale_runtime_cmd start openclaw "${DEFAULT_OPENCLAW_PORT}" /
}

full_reset() {
    log_warn "Reset completo OpenClaw + Tailscale"
    stop_openclaw || true
    rm -rf "${TS_STACK_DIR}"
    rm -f "${COMPOSE_FILE}"
    log_success "Reset completato"
}

usage() {
    cat <<EOF
Uso: $0 <comando> [argomenti]

Comandi principali:
  start                  Avvia OpenClaw e bootstrap Tailscale
  stop                   Ferma OpenClaw e Tailscale
  restart                Riavvia tutto
  status                 Stato OpenClaw
  status-full            Stato OpenClaw + Tailscale
  tunnel-url             Mostra URL Funnel
  tailscale-start        Avvia/configura solo lo stack Tailscale
  tailscale-config       Re-applica routing OpenClaw -> /
  full-reset             Reset completo runtime

Compatibilità servizi secondari:
  tailscale-add <name> <port> [path]
  tailscale-remove <name>
  tailscale-logs
  tailscale-shell
  tailscale-cleanup
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    start) start_openclaw ;;
    stop) stop_openclaw ;;
    restart) restart_openclaw ;;
    status) status_openclaw ;;
    status-full) status_full ;;
    tunnel-url|url) show_tunnel_url ;;
    tailscale-start) tailscale_start_only ;;
    tailscale-config) tailscale_config ;;
    tailscale-add) tailscale_runtime_cmd add "$@" ;;
    tailscale-remove) tailscale_runtime_cmd remove "$@" ;;
    tailscale-logs) tailscale_runtime_cmd logs ;;
    tailscale-shell) tailscale_runtime_cmd shell ;;
    tailscale-cleanup) tailscale_runtime_cmd cleanup-duplicates ;;
    full-reset) full_reset ;;
    ""|-h|--help|help) usage ;;
    *) log_error "Comando sconosciuto: ${cmd}"; usage; exit 1 ;;
esac
