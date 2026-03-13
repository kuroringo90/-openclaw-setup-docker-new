#!/usr/bin/env bash
#
# OpenClaw production health check
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${OPENCLAW_DATA_DIR:-${HOME}/.openclaw}"
RUNTIME_ENV="${DATA_DIR}/.env"
DEFAULT_ENV="${SCRIPT_DIR}/.env"

if [[ -f "${DEFAULT_ENV}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${DEFAULT_ENV}"
    set +a
fi

if [[ -f "${RUNTIME_ENV}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${RUNTIME_ENV}"
    set +a
fi

CONTAINER_NAME="${OPENCLAW_CONTAINER_NAME:-openclaw}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
LOCAL_URL="http://127.0.0.1:${OPENCLAW_PORT}"
LOCAL_HEALTH_URL="${LOCAL_URL}/healthz"
MODE="plain"
CHECK_PUBLIC="false"

container_state="unknown"
local_http="unknown"
public_http="skipped"
public_url=""
summary=""

usage() {
    cat <<EOF
Usage: $0 [--json] [--nagios] [--public]

Options:
  --json      Output JSON
  --nagios    Output Nagios-compatible line and exit code
  --public    Also check the public OpenClaw URL via tailscale wrapper
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) MODE="json" ;;
        --nagios) MODE="nagios" ;;
        --public) CHECK_PUBLIC="true" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

check_container() {
    if ! docker info >/dev/null 2>&1; then
        container_state="docker-down"
        return 1
    fi

    local state
    state="$(docker inspect --format '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
    if [[ "${state}" == "running" ]]; then
        container_state="ok"
        return 0
    fi

    container_state="${state:-missing}"
    return 1
}

check_local_http() {
    local code
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 "${LOCAL_HEALTH_URL}" 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
        local_http="ok"
        return 0
    fi
    local_http="${code:-down}"
    return 1
}

resolve_public_url() {
    local wrapper="${SCRIPT_DIR}/tailscale-add-service.sh"
    [[ -x "${wrapper}" ]] || return 1

    while IFS= read -r line; do
        [[ "${line}" == *"#token="* ]] || continue
        public_url="${line%%#*}"
        printf '%s\n' "${public_url}"
        return 0
    done < <("${wrapper}" url 2>/dev/null || true)

    return 1
}

check_public_http() {
    if [[ "${CHECK_PUBLIC}" != "true" ]]; then
        return 0
    fi

    if ! resolve_public_url >/dev/null; then
        public_http="unconfigured"
        return 1
    fi

    local code
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 "${public_url}" 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
        public_http="ok"
        return 0
    fi
    public_http="${code:-down}"
    return 1
}

emit_json() {
    python3 - <<'PY' "${container_state}" "${local_http}" "${public_http}" "${public_url}" "${summary}"
import json
import sys

print(json.dumps({
    "container": sys.argv[1],
    "local_http": sys.argv[2],
    "public_http": sys.argv[3],
    "public_url": sys.argv[4],
    "summary": sys.argv[5],
}, indent=2))
PY
}

rc=0
check_container || rc=2
check_local_http || rc=2
if [[ "${CHECK_PUBLIC}" == "true" ]]; then
    check_public_http || rc=2
fi

summary="container=${container_state}, local=${local_http}, public=${public_http}"

case "${MODE}" in
    json)
        emit_json
        ;;
    nagios)
        if [[ "${rc}" -eq 0 ]]; then
            echo "OK - ${summary}"
        else
            echo "CRITICAL - ${summary}"
        fi
        ;;
    *)
        echo "${summary}"
        ;;
esac

exit "${rc}"
