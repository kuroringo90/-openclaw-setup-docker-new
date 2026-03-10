#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_TS_STACK_DIR="${REPO_TS_STACK_DIR:-${PACKAGE_ROOT}/tailscale-funnel-compose}"
MANAGER="${REPO_TS_STACK_DIR}/tailscale-funnel-compose.sh"
SERVICES_FILE="${TAILSCALE_STACK_DIR:-${HOME}/.openclaw/tailscale-funnel}/config/services.tsv"

err() { echo "[ERRORE] $*" >&2; }

[[ -x "$MANAGER" ]] || { err "Manager Tailscale non trovato: $MANAGER"; exit 1; }

resolve_name_from_path() {
  local path="$1"
  [[ -f "$SERVICES_FILE" ]] || return 1
  awk -F '\t' -v p="$path" '$3==p { print $1; exit }' "$SERVICES_FILE"
}

cmd="${1:-}"
case "$cmd" in
  add)
    shift
    exec "$MANAGER" add "$@"
    ;;
  status)
    exec "$MANAGER" status
    ;;
  remove)
    shift || true
    target="${1:-}"
    if [[ -z "$target" ]]; then
      exec "$MANAGER" reset
    fi
    if [[ "$target" == /* ]]; then
      name="$(resolve_name_from_path "$target" || true)"
      [[ -n "$name" ]] || { err "Path non trovato nel registry: $target"; exit 1; }
      exec "$MANAGER" remove "$name"
    fi
    exec "$MANAGER" remove "$target"
    ;;
  help|-h|--help|"")
    cat <<EOF
Uso:
  $0 <name> <port> [path]
  $0 add <name> <port> [path]
  $0 status
  $0 remove <name>
  $0 remove /path
  $0 remove
EOF
    ;;
  *)
    if [[ $# -ge 2 ]]; then
      exec "$MANAGER" add "$@"
    fi
    err "Comando non riconosciuto: $cmd"
    exit 1
    ;;
esac
