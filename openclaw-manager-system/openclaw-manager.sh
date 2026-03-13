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
IMAGE_NAME="${OPENCLAW_IMAGE_NAME:-ghcr.io/openclaw/openclaw@sha256:f4f1e98439a9880c063ce95a194cdce3988757772fd0ac78ead1f45475006e5e}"
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

build_json_array_from_csv() {
    local csv="${1:-}"
    python3 - "$csv" <<'PY'
import json
import sys

raw = sys.argv[1].strip()
items = []
if raw:
    for part in raw.split(","):
        value = part.strip()
        if value and value not in items:
            items.append(value)
print(json.dumps(items))
PY
}

resolve_openclaw_allowed_origins() {
    local origins=(
        "http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}"
        "http://localhost:${DEFAULT_OPENCLAW_PORT}"
    )
    local seen=",${origins[0]},${origins[1]},"

    if [[ -n "${OPENCLAW_ALLOWED_ORIGINS:-}" ]]; then
        local item
        IFS=',' read -r -a extra <<< "${OPENCLAW_ALLOWED_ORIGINS}"
        for item in "${extra[@]}"; do
            item="${item## }"
            item="${item%% }"
            [[ -n "${item}" ]] || continue
            [[ "${seen}" == *",${item},"* ]] && continue
            origins+=("${item}")
            seen+="${item},"
        done
    elif [[ -x "${SCRIPT_DIR}/tailscale-add-service.sh" ]]; then
        local public_url
        while IFS= read -r public_url; do
            [[ "${public_url}" == *"#token="* ]] || continue
            public_url="${public_url%%#*}"
            public_url="${public_url%/}"
            [[ -n "${public_url}" ]] || continue
            [[ "${seen}" == *",${public_url},"* ]] && continue
            origins+=("${public_url}")
            seen+="${public_url},"
        done < <("${SCRIPT_DIR}/tailscale-add-service.sh" url 2>/dev/null || true)
    fi

    local joined=""
    local origin
    for origin in "${origins[@]}"; do
        if [[ -n "${joined}" ]]; then
            joined+=","
        fi
        joined+="${origin}"
    done
    printf '%s\n' "${joined}"
}

resolve_openclaw_trusted_proxies() {
    if [[ -n "${OPENCLAW_TRUSTED_PROXIES:-}" ]]; then
        printf '%s\n' "${OPENCLAW_TRUSTED_PROXIES}"
        return 0
    fi

    local csv="127.0.0.1/32"
    local networks_json
    networks_json="$(docker inspect "${CONTAINER_NAME}" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null || true)"
    if [[ -n "${networks_json}" && "${networks_json}" != "null" ]]; then
        local subnets
        subnets="$(NETWORKS_JSON="${networks_json}" python3 - <<'PY'
import json
import os
import subprocess

networks = json.loads(os.environ["NETWORKS_JSON"])
subnets = []
for name in networks:
    try:
        out = subprocess.check_output(
            ["docker", "network", "inspect", name, "--format", "{{json .IPAM.Config}}"],
            text=True,
        ).strip()
    except Exception:
        continue
    if not out or out == "null":
        continue
    try:
        cfg = json.loads(out)
    except Exception:
        continue
    for entry in cfg or []:
        subnet = (entry or {}).get("Subnet")
        if subnet and subnet not in subnets:
            subnets.append(subnet)
print(",".join(subnets))
PY
)"
        if [[ -n "${subnets}" ]]; then
            csv+=",${subnets}"
        fi
    fi

    printf '%s\n' "${csv}"
}

persist_env_var() {
    local key="$1" value="$2"
    python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import pathlib
import re
import sys

env_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

content = env_path.read_text() if env_path.exists() else ""
pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
line = f"{key}={value}"

if pattern.search(content):
    content = pattern.sub(line, content)
else:
    if content and not content.endswith("\n"):
        content += "\n"
    content += line + "\n"

env_path.write_text(content)
PY
}

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
    curl -fsS --max-time 3 "http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}/healthz" >/dev/null 2>&1
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

ensure_openclaw_runtime_config() {
    local config_file="${DATA_DIR}/data/openclaw.json"
    local allowed_origins_csv
    local trusted_proxies_csv
    local host_header_fallback="${OPENCLAW_ALLOW_HOST_HEADER_ORIGIN_FALLBACK:-false}"

    allowed_origins_csv="$(resolve_openclaw_allowed_origins)"
    trusted_proxies_csv="$(resolve_openclaw_trusted_proxies)"

    OPENCLAW_ALLOWED_ORIGINS_JSON="$(build_json_array_from_csv "${allowed_origins_csv}")" \
    OPENCLAW_TRUSTED_PROXIES_JSON="$(build_json_array_from_csv "${trusted_proxies_csv}")" \
    OPENCLAW_HOST_HEADER_FALLBACK="${host_header_fallback}" \
    python3 - "$config_file" <<'PY'
import json
import os
import sys

path = sys.argv[1]
data = {}

if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as fh:
        try:
            data = json.load(fh)
        except Exception:
            data = {}

gateway = data.setdefault("gateway", {})
gateway["bind"] = "lan"
gateway["trustedProxies"] = json.loads(os.environ["OPENCLAW_TRUSTED_PROXIES_JSON"])
control_ui = gateway.setdefault("controlUi", {})
control_ui["allowedOrigins"] = json.loads(os.environ["OPENCLAW_ALLOWED_ORIGINS_JSON"])

if os.environ.get("OPENCLAW_HOST_HEADER_FALLBACK", "").lower() == "true":
    control_ui["dangerouslyAllowHostHeaderOriginFallback"] = True
else:
    control_ui.pop("dangerouslyAllowHostHeaderOriginFallback", None)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

ensure_openclaw_compose() {
    cat > "${COMPOSE_FILE}" <<EOF_COMPOSE
services:
  openclaw:
    image: \${IMAGENAME}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    init: true
    ports:
      - "127.0.0.1:${DEFAULT_OPENCLAW_PORT}:${DEFAULT_OPENCLAW_PORT}"
    volumes:
      - ${DATA_DIR}/data:/home/node/.openclaw
    environment:
      - NODE_ENV=production
      - OPENCLAW_GATEWAY_PORT=${DEFAULT_OPENCLAW_PORT}
      - OPENCLAW_GATEWAY_BIND=lan
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=256m
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}/healthz >/dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s
    stdin_open: true
    tty: true
EOF_COMPOSE
}

ensure_openclaw_env() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        cat > "${ENV_FILE}" <<'EOF_ENV'
# OpenClaw settings
OPENCLAW_CONTAINER_NAME=openclaw
OPENCLAW_IMAGE_NAME=ghcr.io/openclaw/openclaw@sha256:f4f1e98439a9880c063ce95a194cdce3988757772fd0ac78ead1f45475006e5e
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
    ensure_openclaw_runtime_config
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
    log_info "Per abilitare accesso remoto: ./tailscale-add-service.sh add"
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

update_openclaw_image() {
    local requested_image="${1:-${IMAGE_NAME}}"
    local previous_image_id=""
    local current_container_image_id=""
    local pulled_image_id=""

    check_prereqs
    ensure_openclaw_env

    previous_image_id="$(docker image inspect --format '{{.Id}}' "${requested_image}" 2>/dev/null || true)"
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        current_container_image_id="$(docker inspect --format '{{.Image}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
    fi

    log_info "Aggiorno immagine OpenClaw: ${requested_image}"
    if [[ "${requested_image}" == *":latest" ]]; then
        log_warn "Stai usando un tag floating (:latest); per produzione è preferibile un digest o una release taggata"
    fi
    docker pull "${requested_image}"
    pulled_image_id="$(docker image inspect --format '{{.Id}}' "${requested_image}" 2>/dev/null || true)"

    if [[ -n "${pulled_image_id}" ]] && [[ "${previous_image_id}" == "${pulled_image_id}" ]] && [[ "${current_container_image_id}" == "${pulled_image_id}" ]]; then
        log_success "Nessun update necessario: immagine locale e container sono già allineati"
        return 0
    fi

    persist_env_var "OPENCLAW_IMAGE_NAME" "${requested_image}"
    IMAGE_NAME="${requested_image}"
    export OPENCLAW_IMAGE_NAME="${requested_image}"

    ensure_openclaw_dirs
    ensure_openclaw_runtime_config
    ensure_openclaw_compose

    export IMAGENAME="${IMAGE_NAME}"
    log_info "Ricreo il container OpenClaw con l'immagine aggiornata..."
    compose_cmd -f "${COMPOSE_FILE}" up -d --force-recreate

    sleep 2
    if check_openclaw_health; then
        log_success "OpenClaw raggiungibile su http://127.0.0.1:${DEFAULT_OPENCLAW_PORT}"
    else
        log_warn "Container aggiornato ma healthcheck HTTP non ancora pronto"
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
  start           Avvia OpenClaw
  stop            Ferma OpenClaw
  restart         Riavvia OpenClaw
  update-image [image]  Aggiorna immagine Docker OpenClaw e ricrea se serve
  status          Mostra stato OpenClaw
  status-full     Mostra stato OpenClaw + Tailscale
  logs            Mostra log in tempo reale
  full-reset      Reset completo runtime
  tunnel-url      Mostra URL Funnel Tailscale

Gestione Tailscale:
  tailscale-add <name> <port|target> [path] [mode]   Aggiungi servizio a Tailscale
  tailscale-remove <name>                Rimuovi servizio da Funnel

Esempi:
  $0 start
  $0 update-image
  $0 update-image ghcr.io/openclaw/openclaw:latest
  $0 tailscale-add grafana 3000 /grafana
  $0 tailscale-add grafana 3000 /grafana serve
  $0 tunnel-url
EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
    start) start_openclaw ;;
    stop) stop_openclaw ;;
    restart) restart_openclaw ;;
    update-image) update_openclaw_image "$@" ;;
    status) status_openclaw ;;
    status-full) 
        status_openclaw
        echo
        "${SCRIPT_DIR}/tailscale-add-service.sh" status 2>/dev/null || true
        ;;
    logs) logs_openclaw ;;
    full-reset) full_reset ;;
    tunnel-url) "${SCRIPT_DIR}/tailscale-add-service.sh" url ;;
    tailscale-add) 
        "${SCRIPT_DIR}/tailscale-add-service.sh" add "$@"
        ;;
    tailscale-remove) 
        "${SCRIPT_DIR}/tailscale-add-service.sh" remove "$@"
        ;;
    ""|-h|--help|help) usage ;;
    *) log_error "Comando sconosciuto: ${cmd}"; usage; exit 1 ;;
esac
