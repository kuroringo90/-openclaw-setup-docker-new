#!/bin/sh
set -eu

STATE_FILE="${TS_STATE_DIR:-/var/lib/tailscale}/tailscaled.state"
SERVICES_FILE="/config/services.tsv"
HOSTNAME_VALUE="${TS_HOSTNAME:-tailscale-funnel}"
ADVERTISE_TAGS="${TS_ADVERTISE_TAGS:-}"

normalize_mode() {
  mode="$(printf '%s' "${1:-funnel}" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    ""|public|internet|funnel) printf '%s\n' "funnel" ;;
    tailnet|private|serve) printf '%s\n' "serve" ;;
    *) printf '%s\n' "funnel" ;;
  esac
}

wait_for_network() {
  i=0
  while [ "$i" -lt 60 ]; do
    if ip route show default 2>/dev/null | grep -q '^default'; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}

wait_for_tailscaled() {
  i=0
  while [ "$i" -lt 60 ]; do
    if tailscale version >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  return 1
}

is_logged_out() {
  status_output="$(tailscale status 2>&1 || true)"
  printf '%s' "$status_output" | grep -Eq 'Logged out\.|Log in at:' 
}

tailscale_login() {
  i=0
  while [ "$i" -lt 30 ]; do
    if ! is_logged_out && tailscale ip -4 >/dev/null 2>&1; then
      return 0
    fi

    if [ -n "$ADVERTISE_TAGS" ]; then
      tailscale up --reset --authkey="${TS_AUTHKEY}" --hostname="${HOSTNAME_VALUE}" --advertise-tags="${ADVERTISE_TAGS}" >/tmp/tailscale-up.log 2>&1 || true
    else
      tailscale up --reset --authkey="${TS_AUTHKEY}" --hostname="${HOSTNAME_VALUE}" >/tmp/tailscale-up.log 2>&1 || true
    fi

    j=0
    while [ "$j" -lt 10 ]; do
      if ! is_logged_out && tailscale ip -4 >/dev/null 2>&1; then
        return 0
      fi
      j=$((j + 1))
      sleep 1
    done

    i=$((i + 1))
    sleep 2
  done

  cat /tmp/tailscale-up.log >&2 || true
  return 1
}

reapply_routes() {
  [ -f "$SERVICES_FILE" ] || return 0

  tailscale funnel reset >/dev/null 2>&1 || true
  tailscale serve reset >/dev/null 2>&1 || true

  while IFS='	' read -r name target path exposure; do
    [ -n "${name:-}" ] || continue
    mode="$(normalize_mode "${exposure:-funnel}")"
    if [ "$mode" = "serve" ]; then
      tailscale serve --bg --set-path "$path" "$target" </dev/null >/dev/null
    else
      tailscale funnel --bg --set-path "$path" "$target" </dev/null >/dev/null
    fi
  done < "$SERVICES_FILE"
}

tailscaled --tun=userspace-networking --state="${STATE_FILE}" &
TS_PID=$!

trap 'kill "$TS_PID" 2>/dev/null || true' INT TERM

wait_for_network || echo "WARN: network default route not ready after timeout" >&2
wait_for_tailscaled || {
  echo "ERROR: tailscaled non pronto" >&2
  wait "$TS_PID"
  exit 1
}

if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale_login || echo "WARN: tailscale up failed during bootstrap" >&2
fi

if tailscale ip -4 >/dev/null 2>&1; then
  reapply_routes || echo "WARN: route restore failed during bootstrap" >&2
fi

wait "$TS_PID"
