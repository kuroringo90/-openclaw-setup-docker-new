#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"
STATE_DIR="${BASE_DIR}/state"
CONFIG_DIR="${BASE_DIR}/config"
SERVICES_FILE="${CONFIG_DIR}/services.tsv"
SERVICE_NAME="tailscale-funnel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err() { echo -e "${RED}[ERRORE]${NC} $*"; }

dc() {
  docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

load_env() {
  mkdir -p "${STATE_DIR}" "${CONFIG_DIR}"
  touch "${SERVICES_FILE}"
  if [[ ! -f "${ENV_FILE}" ]]; then
    if [[ -f "${BASE_DIR}/.env.example" ]]; then
      cp "${BASE_DIR}/.env.example" "${ENV_FILE}"
      log_warn "Creato ${ENV_FILE}; compila TS_AUTHKEY prima di avviare."
    else
      log_err "${ENV_FILE} non trovato"
      exit 1
    fi
  fi
  set -a
  source "${ENV_FILE}"
  set +a
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { log_err "Comando richiesto mancante: $1"; exit 1; }
}

check_prereqs() {
  require_bin docker
  require_bin python3
  require_bin curl
  docker info >/dev/null 2>&1 || { log_err "Docker non è in esecuzione"; exit 1; }
  [[ -n "${TS_AUTHKEY:-}" ]] || { log_err "TS_AUTHKEY non impostata in ${ENV_FILE}"; exit 1; }
}

container_running() {
  dc ps --status running --services 2>/dev/null | grep -qx "${SERVICE_NAME}"
}

wait_tailscaled() {
  local i
  for i in $(seq 1 30); do
    if dc exec -T "${SERVICE_NAME}" tailscale status >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

get_dns_name() {
  dc exec -T "${SERVICE_NAME}" tailscale status --json 2>/dev/null | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
    print((data.get("Self") or {}).get("DNSName", "").rstrip("."))
except Exception:
    pass
' || true
}

get_tailnet_name() {
  if [[ -n "${TS_TAILNET:-}" ]]; then
    printf '%s\n' "${TS_TAILNET}"
    return 0
  fi
  local dns
  dns="$(get_dns_name)"
  [[ -n "$dns" ]] && printf '%s\n' "$(printf '%s' "$dns" | cut -d'.' -f2)"
}

print_public_urls() {
  local dns="$1"
  [[ -n "$dns" ]] || return 0
  [[ "$(get_registry_exposure_mode)" == "funnel" ]] || return 0

  if [[ -s "$SERVICES_FILE" ]]; then
    while IFS=$'\t' read -r name target path exposure; do
      [[ -n "$name" && -n "$path" ]] || continue
      echo "https://${dns}${path}"
    done < "$SERVICES_FILE"
  fi
}

print_tailnet_urls() {
  local dns="$1"
  [[ -n "$dns" ]] || return 0
  [[ "$(get_registry_exposure_mode)" == "serve" ]] || return 0

  if [[ -s "$SERVICES_FILE" ]]; then
    while IFS=$'\t' read -r name target path exposure; do
      [[ -n "$name" && -n "$path" ]] || continue
      echo "https://${dns}${path}"
    done < "$SERVICES_FILE"
  fi
}

normalize_exposure_mode() {
  local mode="${1:-${TS_DEFAULT_EXPOSURE_MODE:-funnel}}"
  mode="$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    ""|public|internet|funnel) echo "funnel" ;;
    tailnet|private|serve) echo "serve" ;;
    *) log_err "Modalità esposizione non valida: $mode (usa funnel|serve)"; exit 1 ;;
  esac
}

apply_service_route() {
  local target="$1" path="$2" exposure="$3"
  exposure="$(normalize_exposure_mode "$exposure")"
  case "$exposure" in
    funnel) dc exec -T "${SERVICE_NAME}" tailscale funnel --bg --set-path "$path" "$target" >/dev/null ;;
    serve) dc exec -T "${SERVICE_NAME}" tailscale serve --bg --set-path "$path" "$target" >/dev/null ;;
  esac
}

get_registry_exposure_mode() {
  local mode=""
  if [[ -s "$SERVICES_FILE" ]]; then
    while IFS=$'\t' read -r name target path exposure; do
      [[ -n "$name" ]] || continue
      exposure="$(normalize_exposure_mode "${exposure:-funnel}")"
      if [[ -z "$mode" ]]; then
        mode="$exposure"
      elif [[ "$mode" != "$exposure" ]]; then
        log_warn "Registry servizi in mixed-mode non supportato: ${mode} + ${exposure}"
        echo "mixed"
        return 0
      fi
    done < "$SERVICES_FILE"
  fi
  echo "${mode:-$(normalize_exposure_mode "${TS_DEFAULT_EXPOSURE_MODE:-funnel}")}"
}

enforce_stack_exposure_mode() {
  local requested="$1"
  local current
  requested="$(normalize_exposure_mode "$requested")"
  current="$(get_registry_exposure_mode)"
  if [[ "$current" == "mixed" ]]; then
    log_err "Il registry contiene modalità miste non supportate; riallinea i servizi a una sola modalità prima di continuare"
    exit 1
  fi
  if [[ -s "$SERVICES_FILE" && "$current" != "$requested" ]]; then
    log_err "Modalità mista non supportata sullo stesso hostname: stack=${current}, richiesta=${requested}"
    log_info "Usa una sola modalità per tutto lo stack: funnel (pubblico) oppure serve (tailnet-only)"
    exit 1
  fi
}

cleanup_duplicate_nodes_api() {
  local hostname="${TS_HOSTNAME:-tailscale-funnel}"
  local api_key="${TS_API_KEY:-}"
  local tailnet="${TS_TAILNET:-}"
  local devices matching count first=true

  if [[ -z "$api_key" ]]; then
    log_warn "TS_API_KEY non impostata: skip cleanup duplicati"
    return 0
  fi

  if [[ -z "$tailnet" ]]; then
    tailnet="$(get_tailnet_name)"
    if [[ -z "$tailnet" ]]; then
      log_warn "TS_TAILNET non impostata e non auto-rilevabile: skip cleanup duplicati"
      return 0
    fi
  fi

  log_info "Verifica nodi duplicati per hostname: ${hostname}"
  devices="$(curl -fsS -u "${api_key}:" "https://api.tailscale.com/api/v2/tailnet/${tailnet}/devices" -H 'Accept: application/json' 2>/dev/null || true)"
  [[ -n "$devices" ]] || { log_warn "API Tailscale non raggiungibile o risposta vuota"; return 0; }

  matching="$(MATCH_HOSTNAME="$hostname" printf '%s' "$devices" | python3 -c '
import json,sys,os
hostname=os.environ.get("MATCH_HOSTNAME", "")
try:
    data=json.load(sys.stdin)
    nodes=[]
    for d in data.get("devices", []):
        name=d.get("name", "")
        if name.startswith(hostname):
            nodes.append({"id": d.get("id", ""), "name": name, "lastSeen": d.get("lastSeen", "")})
    nodes.sort(key=lambda x: x["lastSeen"] or "", reverse=True)
    for n in nodes:
        print(f"{n['id']}|{n['name']}|{n['lastSeen'] or 'never'}")
except Exception:
    pass
')"

  [[ -n "$matching" ]] || { log_ok "Nessun nodo duplicato trovato"; return 0; }
  count="$(printf '%s\n' "$matching" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" -gt 1 ]] || { log_ok "Nessun nodo duplicato trovato"; return 0; }

  log_warn "Trovati ${count} nodi con hostname '${hostname}'"
  while IFS='|' read -r id name last; do
    [[ -n "$id" ]] || continue
    if [[ "$first" == true ]]; then
      first=false
      log_info "Mantengo nodo: ${name}"
    else
      log_info "Elimino nodo duplicato: ${name}"
      curl -fsS -X DELETE -u "${api_key}:" "https://api.tailscale.com/api/v2/device/${id}" >/dev/null 2>&1 \
        && log_ok "Eliminato: ${name}" \
        || log_warn "Eliminazione fallita: ${name}"
    fi
  done <<< "$matching"
}

is_logged_in() {
  dc exec -T "${SERVICE_NAME}" tailscale ip -4 >/dev/null 2>&1
}

tailscale_up() {
  local hostname="${TS_HOSTNAME:-tailscale-funnel}"
  if is_logged_in; then
    log_ok "Nodo Tailscale già autenticato"
    return 0
  fi
  log_info "Autenticazione Tailscale..."
  if [[ -n "${TS_ADVERTISE_TAGS:-}" ]]; then
    dc exec -T "${SERVICE_NAME}" tailscale up \
      --authkey="${TS_AUTHKEY}" \
      --hostname="${hostname}" \
      --advertise-tags="${TS_ADVERTISE_TAGS}" >/dev/null
  else
    dc exec -T "${SERVICE_NAME}" tailscale up \
      --authkey="${TS_AUTHKEY}" \
      --hostname="${hostname}" >/dev/null
  fi
  log_ok "Autenticazione completata"
}

ensure_main_service() {
  local name="${1:-${TS_DEFAULT_SERVICE_NAME:-funnel}}"
  local target="${2:-${TS_DEFAULT_SERVICE_PORT:-18789}}"
  local path="${3:-${TS_DEFAULT_SERVICE_PATH:-/}}"
  local exposure="${4:-${TS_DEFAULT_EXPOSURE_MODE:-funnel}}"

  exposure="$(normalize_exposure_mode "$exposure")"
  enforce_stack_exposure_mode "$exposure"
  apply_service_route "$target" "$path" "$exposure"

  grep -Fq "$name	$target	$path	$exposure" "$SERVICES_FILE" 2>/dev/null || echo -e "$name\t$target\t$path\t$exposure" >> "$SERVICES_FILE"
  log_ok "Servizio principale configurato: ${name} -> ${target} (${path}, mode=${exposure})"
}

service_exists() {
  local name="$1" target="$2" path="$3"
  awk -F '\t' -v n="$name" -v t="$target" -v x="$path" '
    $1==n || $2==t || $3==x { found=1 }
    END { exit found ? 0 : 1 }
  ' "$SERVICES_FILE"
}

add_service() {
  local name="${1:-}" target="${2:-}" path="${3:-}" exposure="${4:-${TS_DEFAULT_EXPOSURE_MODE:-funnel}}"
  [[ -n "$name" && -n "$target" ]] || { log_err "Uso: $0 add <name> <port|target> [path]"; exit 1; }
  path="${path:-/$name}"
  [[ "$path" == /* ]] || { log_err "Il path deve iniziare con /"; exit 1; }
  exposure="$(normalize_exposure_mode "$exposure")"
  enforce_stack_exposure_mode "$exposure"

  if service_exists "$name" "$target" "$path"; then
    log_err "Duplicato rilevato: nome, porta o path già presente"
    awk -F '\t' -v n="$name" -v t="$target" -v x="$path" '$1==n || $2==t || $3==x {print "  - "$1"\ttarget=" $2 "\tpath=" $3}' "$SERVICES_FILE"
    exit 1
  fi

  apply_service_route "$target" "$path" "$exposure"
  echo -e "$name\t$target\t$path\t$exposure" >> "$SERVICES_FILE"

  local dns
  dns="$(get_dns_name)"
  log_ok "Servizio aggiunto: ${name} -> ${target} (${path}, mode=${exposure})"
  [[ -n "$dns" ]] && echo -e "${GREEN}URL:${NC} https://${dns}${path}"
}

rebuild_routes() {
  dc exec -T "${SERVICE_NAME}" tailscale funnel reset >/dev/null 2>&1 || true
  dc exec -T "${SERVICE_NAME}" tailscale serve reset >/dev/null 2>&1 || true
  while IFS=$'\t' read -r name target path exposure; do
    [[ -n "$name" ]] || continue
    apply_service_route "$target" "$path" "${exposure:-funnel}"
  done < "$SERVICES_FILE"
}

remove_service() {
  local name="${1:-}"
  [[ -n "$name" ]] || { log_err "Uso: $0 remove <name>"; exit 1; }
  grep -q "^${name}[[:space:]]" "$SERVICES_FILE" || { log_err "Servizio non trovato: ${name}"; exit 1; }
  awk -F '\t' -v n="$name" '$1!=n' "$SERVICES_FILE" > "${SERVICES_FILE}.tmp"
  mv "${SERVICES_FILE}.tmp" "$SERVICES_FILE"
  rebuild_routes
  log_ok "Servizio rimosso: ${name}"
}

status_cmd() {
  echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   TAILSCALE FUNNEL COMPOSE STATUS     ║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
  echo
  dc ps
  echo
  if container_running; then
    local dns
    local registry_mode
    dns="$(get_dns_name)"
    registry_mode="$(get_registry_exposure_mode)"
    echo -e "${BLUE}Hostname:${NC} ${dns}"
    echo -e "${BLUE}Mode stack:${NC} ${registry_mode}"
    echo -e "${BLUE}URL pubblici:${NC}"
    local public_urls tailnet_urls
    public_urls="$(print_public_urls "$dns")"
    tailnet_urls="$(print_tailnet_urls "$dns")"
    [[ -n "$public_urls" ]] && printf '%s\n' "$public_urls" || echo "(nessuno)"
    echo
    echo -e "${BLUE}URL tailnet:${NC}"
    [[ -n "$tailnet_urls" ]] && printf '%s\n' "$tailnet_urls" || echo "(nessuno)"
    echo
    echo -e "${BLUE}Funnel:${NC}"
    dc exec -T "${SERVICE_NAME}" tailscale funnel status || true
    echo
    echo -e "${BLUE}Serve:${NC}"
    dc exec -T "${SERVICE_NAME}" tailscale serve status || true
    echo
    echo -e "${BLUE}Registry locale servizi:${NC}"
    if [[ -s "$SERVICES_FILE" ]]; then
      column -t -s $'\t' "$SERVICES_FILE"
    else
      echo "(vuoto)"
    fi
  fi
}

url_cmd() {
  local dns
  dns="$(get_dns_name)"
  if [[ -z "$dns" ]]; then
    log_warn "DNS Tailscale non ancora disponibile"
    return 0
  fi
  print_public_urls "$dns"
  print_tailnet_urls "$dns"
}

start_cmd() {
  local main_name="${1:-funnel}" main_target="${2:-18789}" main_path="${3:-/}" main_exposure="${4:-${TS_DEFAULT_EXPOSURE_MODE:-funnel}}"
  load_env
  check_prereqs
  dc up -d
  wait_tailscaled || { log_err "tailscaled non pronto"; exit 1; }
  cleanup_duplicate_nodes_api
  tailscale_up
  ensure_main_service "$main_name" "$main_target" "$main_path" "$main_exposure"
  status_cmd
}

stop_cmd() {
  load_env
  dc down
}

logs_cmd() {
  load_env
  dc logs -f
}

shell_cmd() {
  load_env
  dc exec "${SERVICE_NAME}" sh
}

reset_cmd() {
  load_env
  dc exec -T "${SERVICE_NAME}" tailscale funnel reset >/dev/null 2>&1 || true
  dc exec -T "${SERVICE_NAME}" tailscale serve reset >/dev/null 2>&1 || true
  : > "$SERVICES_FILE"
  log_ok "Configurazione serve/funnel resettata"
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    start) start_cmd "$@" ;;
    stop) stop_cmd ;;
    add) load_env; add_service "$@" ;;
    remove) load_env; remove_service "$@" ;;
    reset) reset_cmd ;;
    status) load_env; status_cmd ;;
    url) load_env; url_cmd ;;
    logs) logs_cmd ;;
    shell) shell_cmd ;;
    cleanup-duplicates) load_env; cleanup_duplicate_nodes_api ;;
    help|-h|--help|"")
      cat <<EOF
Uso: $0 <comando>
  start <main-name> <main-port|target> [main-path=/] [main-mode=funnel|serve]
  stop
  add <name> <port|target> [path] [mode=funnel|serve]
  remove <name>
  reset
  status
  url
  logs
  shell
  cleanup-duplicates
EOF
      ;;
    *) log_err "Comando sconosciuto: $cmd"; exit 1 ;;
  esac
}

main "$@"
