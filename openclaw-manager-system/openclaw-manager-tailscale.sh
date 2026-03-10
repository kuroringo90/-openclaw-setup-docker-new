#!/usr/bin/env bash
#
# OpenClaw Docker Manager
# Gestisce solo OpenClaw - Tailscale è un modulo separato
#
set -euo pipefail

# ============================================
# CONFIGURAZIONE
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="${OPENCLAW_CONTAINER_NAME:-openclaw}"
IMAGE_NAME="${OPENCLAW_IMAGE_NAME:-ghcr.io/openclaw/openclaw:latest}"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
ENV_FILE="${DATA_DIR}/.env"
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

check_openclaw_health() {
    curl -fsS --max-time 3 "http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}" >/dev/null 2>&1
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
# OpenClaw settings
OPENCLAW_CONTAINER_NAME=openclaw
OPENCLAW_IMAGE_NAME=ghcr.io/openclaw/openclaw:latest
OPENCLAW_DATA_DIR=${HOME}/.openclaw
OPENCLAW_PORT=18789
EOF_ENV
        log_success "Creato ${ENV_FILE}"
    fi
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

    sleep 2
    if check_openclaw_health; then
        log_success "OpenClaw raggiungibile su http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}"
    else
        log_warn "OpenClaw avviato ma healthcheck HTTP non ancora pronto"
    fi

    # Info su accesso remoto
    echo
    log_info "OpenClaw è accessibile in locale su: http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}"
    log_info "Per abilitare accesso remoto con Tailscale Funnel:"
    log_info "  1. Configura il modulo tailscale-funnel-compose/"
    log_info "  2. Esegui: ./openclaw-manager-tailscale.sh tailscale-add"
}

stop_openclaw() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        export IMAGENAME="${IMAGE_NAME}"
        compose_cmd -f "${COMPOSE_FILE}" down || true
        log_success "OpenClaw fermato"
    else
        log_warn "Compose OpenClaw non trovato"
    fi
}

restart_openclaw() {
    stop_openclaw
    sleep 2
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

logs_openclaw() {
    if [[ -f "${COMPOSE_FILE}" ]]; then
        export IMAGENAME="${IMAGE_NAME}"
        compose_cmd -f "${COMPOSE_FILE}" logs -f
    else
        log_error "Compose OpenClaw non trovato"
    fi
}

full_reset() {
    log_warn "Reset completo OpenClaw"
    stop_openclaw || true
    rm -f "${COMPOSE_FILE}"
    log_success "Reset completato"
}

usage() {
    cat <<EOF
Uso: $0 <comando>

Comandi principali:
  start       Avvia OpenClaw
  stop        Ferma OpenClaw
  restart     Riavvia OpenClaw
  status      Mostra stato OpenClaw
  logs        Mostra log in tempo reale
  full-reset  Reset completo runtime

Accesso remoto (Tailscale Funnel):
  OpenClaw di base è accessibile solo in locale (127.0.0.1:${DEFAULT_OPENCLAW_PORT})
  Per abilitare accesso remoto, usa il modulo tailscale-funnel-compose/
  
  Vedi: ../tailscale-funnel-compose/README.md
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    start) start_openclaw ;;
    stop) stop_openclaw ;;
    restart) restart_openclaw ;;
    status) status_openclaw ;;
    logs) logs_openclaw ;;
    full-reset) full_reset ;;
    ""|-h|--help|help) usage ;;
    *) log_error "Comando sconosciuto: ${cmd}"; usage; exit 1 ;;
esac
