#!/usr/bin/env bash
#
# Health check and monitoring script for production deployments
# Returns exit codes for monitoring systems (0=healthy, 1=degraded, 2=unhealthy)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS_STACK_DIR="${SCRIPT_DIR}"

# Exit codes
EXIT_HEALTHY=0
EXIT_DEGRADED=1
EXIT_UNHEALTHY=2

# Colors (disabled for monitoring output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Health status
HEALTH_STATUS=$EXIT_HEALTHY
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

log_check() {
    local status="$1"
    local name="$2"
    local message="${3:-}"
    
    case "$status" in
        ok)
            echo -e "${GREEN}[PASS]${NC} $name"
            [[ -n "$message" ]] && echo "       $message"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        warn)
            echo -e "${YELLOW}[WARN]${NC} $name"
            [[ -n "$message" ]] && echo "       $message"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            if [[ $HEALTH_STATUS -eq $EXIT_HEALTHY ]]; then
                HEALTH_STATUS=$EXIT_DEGRADED
            fi
            ;;
        fail)
            echo -e "${RED}[FAIL]${NC} $name"
            [[ -n "$message" ]] && echo "       $message"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            HEALTH_STATUS=$EXIT_UNHEALTHY
            ;;
    esac
}

check_docker_daemon() {
    if docker info >/dev/null 2>&1; then
        local version
        version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
        log_check "ok" "Docker daemon" "v${version}"
    else
        log_check "fail" "Docker daemon" "Not running or not accessible"
    fi
}

check_openclaw_container() {
    local container_name="${OPENCLAW_CONTAINER_NAME:-openclaw}"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        local status
        status="$(docker inspect -f '{{.State.Status}}' "${container_name}" 2>/dev/null || echo 'unknown')"
        local health
        health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_name}" 2>/dev/null || echo 'unknown')"
        
        if [[ "$status" == "running" ]]; then
            if [[ "$health" == "healthy" ]]; then
                log_check "ok" "OpenClaw container" "Running (health: healthy)"
            elif [[ "$health" == "unhealthy" ]]; then
                log_check "warn" "OpenClaw container" "Running but health check failing"
            else
                log_check "ok" "OpenClaw container" "Running (no health check)"
            fi
        else
            log_check "fail" "OpenClaw container" "Status: ${status}"
        fi
    else
        log_check "fail" "OpenClaw container" "Not found"
    fi
}

check_openclaw_http() {
    local port="${OPENCLAW_PORT:-18789}"
    local timeout=5
    
    if curl -fsS --max-time "${timeout}" "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        log_check "ok" "OpenClaw HTTP endpoint" "Responding on port ${port}"
    else
        log_check "warn" "OpenClaw HTTP endpoint" "Not responding on port ${port}"
    fi
}

check_tailscale_container() {
    local container_name="${TS_CONTAINER_NAME:-tailscale-funnel}"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        local status
        status="$(docker inspect -f '{{.State.Status}}' "${container_name}" 2>/dev/null || echo 'unknown')"
        
        if [[ "$status" == "running" ]]; then
            log_check "ok" "Tailscale container" "Running"
        else
            log_check "fail" "Tailscale container" "Status: ${status}"
        fi
    else
        log_check "warn" "Tailscale container" "Not found (may not be configured)"
    fi
}

check_tailscale_connectivity() {
    local container_name="${TS_CONTAINER_NAME:-tailscale-funnel}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return
    fi
    
    if docker exec "${container_name}" tailscale status >/dev/null 2>&1; then
        local ip
        ip="$(docker exec "${container_name}" tailscale ip -4 2>/dev/null || echo 'unknown')"
        log_check "ok" "Tailscale connectivity" "IP: ${ip}"
    else
        log_check "fail" "Tailscale connectivity" "Not connected to tailnet"
    fi
}

check_tailscale_funnel() {
    local container_name="${TS_CONTAINER_NAME:-tailscale-funnel}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return
    fi
    
    if docker exec "${container_name}" tailscale funnel status >/dev/null 2>&1; then
        local status
        status="$(docker exec "${container_name}" tailscale funnel status 2>&1 | head -3)"
        log_check "ok" "Tailscale Funnel" "Active"
    else
        log_check "warn" "Tailscale Funnel" "Not active"
    fi
}

check_disk_space() {
    local threshold=90
    local usage
    usage="$(df "${DATA_DIR}" | tail -1 | awk '{print $5}' | tr -d '%')"
    
    if [[ "$usage" -lt 80 ]]; then
        log_check "ok" "Disk space" "${usage}% used"
    elif [[ "$usage" -lt "$threshold" ]]; then
        log_check "warn" "Disk space" "${usage}% used (warning threshold)"
    else
        log_check "fail" "Disk space" "${usage}% used (critical)"
    fi
}

check_memory_usage() {
    local container_name="${OPENCLAW_CONTAINER_NAME:-openclaw}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return
    fi
    
    local mem_info
    mem_info="$(docker stats --no-stream --format '{{.MemUsage}}' "${container_name}" 2>/dev/null | head -1)"
    
    if [[ -n "$mem_info" ]]; then
        log_check "ok" "Memory usage" "${mem_info}"
    else
        log_check "warn" "Memory usage" "Unable to retrieve"
    fi
}

check_logs_recent() {
    local container_name="${OPENCLAW_CONTAINER_NAME:-openclaw}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return
    fi
    
    # Check for error patterns in recent logs
    local error_count
    error_count="$(docker logs --tail 100 "${container_name}" 2>&1 | grep -ci 'error\|exception\|fatal' || echo 0)"
    
    if [[ "$error_count" -eq 0 ]]; then
        log_check "ok" "Recent logs" "No errors in last 100 lines"
    elif [[ "$error_count" -lt 10 ]]; then
        log_check "warn" "Recent logs" "${error_count} error(s) in last 100 lines"
    else
        log_check "fail" "Recent logs" "${error_count} error(s) - check logs!"
    fi
}

print_summary() {
    echo
    echo "============================================"
    echo "           HEALTH CHECK SUMMARY            "
    echo "============================================"
    echo -e "  ${GREEN}PASSED:${NC}   ${CHECKS_PASSED}"
    echo -e "  ${YELLOW}WARNINGS:${NC}  ${CHECKS_WARNING}"
    echo -e "  ${RED}FAILED:${NC}   ${CHECKS_FAILED}"
    echo "============================================"
    
    case $HEALTH_STATUS in
        $EXIT_HEALTHY)
            echo -e "${GREEN}STATUS: HEALTHY${NC}"
            ;;
        $EXIT_DEGRADED)
            echo -e "${YELLOW}STATUS: DEGRADED${NC} (some checks warning)"
            ;;
        $EXIT_UNHEALTHY)
            echo -e "${RED}STATUS: UNHEALTHY${NC} (action required)"
            ;;
    esac
    echo
}

usage() {
    cat <<EOF
Usage: $0 [options]

Performs health checks on OpenClaw and Tailscale services.

Exit codes:
  0 - Healthy (all checks passed)
  1 - Degraded (some warnings, service still running)
  2 - Unhealthy (critical failures, service impaired)

Options:
  --json              Output in JSON format
  --nagios            Output in Nagios plugin format
  -q, --quiet         Only show summary
  -h, --help          Show this help

Examples:
  $0                  # Full check with colored output
  $0 --json           # JSON output for automation
  $0 --nagios         # Nagios-compatible output
EOF
}

output_json() {
    cat <<EOF
{
  "status": "$(echo $HEALTH_STATUS | awk '{if($1==0)print "healthy"; else if($1==1)print "degraded"; else print "unhealthy"}')",
  "checks": {
    "passed": ${CHECKS_PASSED},
    "warnings": ${CHECKS_WARNING},
    "failed": ${CHECKS_FAILED}
  },
  "timestamp": "$(date -Iseconds)"
}
EOF
}

output_nagios() {
    local status_text
    
    case $HEALTH_STATUS in
        $EXIT_HEALTHY) status_text="OK" ;;
        $EXIT_DEGRADED) status_text="WARNING" ;;
        $EXIT_UNHEALTHY) status_text="CRITICAL" ;;
    esac
    
    echo "${status_text} - OpenClaw: ${CHECKS_PASSED} OK, ${CHECKS_WARNING} warnings, ${CHECKS_FAILED} failed"
    exit $HEALTH_STATUS
}

main() {
    local output_format="text"
    local quiet=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                output_format="json"
                shift
                ;;
            --nagios)
                output_format="nagios"
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ "$quiet" != true ]]; then
        echo "============================================"
        echo "       OPENCLAW HEALTH CHECK               "
        echo "============================================"
        echo
    fi
    
    # Run checks
    check_docker_daemon
    check_openclaw_container
    check_openclaw_http
    check_tailscale_container
    check_tailscale_connectivity
    check_tailscale_funnel
    check_disk_space
    check_memory_usage
    check_logs_recent
    
    if [[ "$quiet" != true ]]; then
        print_summary
    fi
    
    # Output in requested format
    case "$output_format" in
        json)
            output_json
            ;;
        nagios)
            output_nagios
            ;;
    esac
    
    exit $HEALTH_STATUS
}

main "$@"
