# Tailscale Funnel Compose

> **Standalone Tailscale Funnel module for secure remote access to any local service**

[![Docker](https://img.shields.io/badge/docker-required-blue)](https://docs.docker.com/get-docker/)
[![Tailscale](https://img.shields.io/badge/tailscale-funnel-5555ff)](https://tailscale.com/)

---

## Overview

This is a **standalone, reusable module** that adds Tailscale Funnel remote access to any local service. It can be used independently or as a dependency by other projects.

### Key Features

- 🔒 **Secure HTTPS access** via Tailscale Funnel
- 🔄 **Path-based routing** for multiple services
- 💾 **Automated backups** with retention policy
- 🏥 **Health monitoring** with multiple output formats
- ✅ **Configuration validation** for production readiness
- 📖 **Complete documentation** with runbooks and security guide

---

## Quick Start

```bash
# 1. Configure
cp .env.example .env
nano .env  # Set TS_AUTHKEY

# 2. Start with main service
./tailscale-funnel-compose.sh start myservice 8080 /

# 3. Add secondary services
./tailscale-funnel-compose.sh add grafana 3000 /grafana
./tailscale-funnel-compose.sh add uptime 3001 /uptime

# 4. Check status
./tailscale-funnel-compose.sh status

# 5. Get your Funnel URL
./tailscale-funnel-compose.sh url
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Internet                              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Tailscale Funnel (HTTPS)                    │
│         *.ts.net with automatic TLS                      │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│         tailscale-funnel container                       │
│    - Userspace networking (no TUN required)             │
│    - Routes traffic by path                             │
│    - Multiple backend services                          │
└─────────────────────────────────────────────────────────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
      :8080 (/)    :3000 (/grafana)  :3001 (/uptime)
```

---

## Scripts

### Core Scripts

| Script | Description |
|--------|-------------|
| `tailscale-funnel-compose.sh` | Main orchestration script |
| `health-check.sh` | Production health monitoring |
| `backup.sh` | Backup and restore operations |
| `validate-config.sh` | Configuration validation |

### tailscale-funnel-compose.sh Commands

```bash
./tailscale-funnel-compose.sh start <name> <port> [path=/]   # Start with main service
./tailscale-funnel-compose.sh add <name> <port> [path]       # Add secondary service
./tailscale-funnel-compose.sh remove <name>                  # Remove service
./tailscale-funnel-compose.sh stop                           # Stop container
./tailscale-funnel-compose.sh status                         # Show status
./tailscale-funnel-compose.sh url                            # Show Funnel URL
./tailscale-funnel-compose.sh logs                           # Stream logs
./tailscale-funnel-compose.sh shell                          # Enter container
./tailscale-funnel-compose.sh cleanup-duplicates             # Remove duplicate nodes
```

### health-check.sh Commands

```bash
./health-check.sh              # Full health check with colors
./health-check.sh --quiet      # Summary only
./health-check.sh --json       # JSON output for Prometheus
./health-check.sh --nagios     # Nagios-compatible output
```

Exit codes: `0` = Healthy, `1` = Degraded, `2` = Unhealthy

### backup.sh Commands

```bash
./backup.sh backup                          # Create backup
./backup.sh restore <file.tar.gz>           # Restore from backup
./backup.sh list                            # List available backups
./backup.sh verify <file.tar.gz>            # Verify backup integrity
./backup.sh cleanup                         # Remove old backups
```

---

## Configuration

### Required Variables

Edit `.env`:

```bash
# Required: Tailscale authentication key
# Get from: https://login.tailscale.com/admin/settings/keys
TS_AUTHKEY=tskey-auth-xxx

# Optional: API key for duplicate node cleanup
# Create at: https://login.tailscale.com/admin/settings/keys
TS_API_KEY=xxx

# Optional: Your tailnet name (auto-detected if not set)
TS_TAILNET=example.com

# Optional: Node hostname (default: tailscale-funnel)
TS_HOSTNAME=tailscale-funnel

# Optional: Container name (default: tailscale-funnel)
TS_CONTAINER_NAME=tailscale-funnel
```

### Validate Configuration

```bash
./validate-config.sh
```

---

## Examples

### Example 1: Single Service on Root

```bash
# Expose OpenClaw on port 18789 at /
./tailscale-funnel-compose.sh start openclaw 18789 /
```

### Example 2: Multiple Services

```bash
# Start with main service
./tailscale-funnel-compose.sh start main 8080 /

# Add Grafana
./tailscale-funnel-compose.sh add grafana 3000 /grafana

# Add Uptime Kuma
./tailscale-funnel-compose.sh add uptime 3001 /uptime

# Add Admin panel
./tailscale-funnel-compose.sh add admin 8081 /admin
```

### Example 3: Health Check Integration

```bash
# Cron job for monitoring
*/5 * * * * /opt/tailscale-funnel-compose/health-check.sh --nagios

# Prometheus scrape
curl -s http://localhost:9100/metrics
```

### Example 4: Automated Backups

```bash
# Daily backup at 3 AM
0 3 * * * /opt/tailscale-funnel-compose/backup.sh backup

# Weekly cleanup on Sunday
0 4 * * 0 /opt/tailscale-funnel-compose/backup.sh cleanup
```

---

## As a Dependency

This module is designed to be reused by other projects.

### Option 1: Git Submodule

```bash
cd your-project
git submodule add https://github.com/kuroringo90/-openclaw-setup-docker-new.git tailscale-funnel-compose
cd tailscale-funnel-compose
cp .env.example .env
# Configure and use
```

### Option 2: Copy/Vendor

```bash
cp -r tailscale-funnel-compose /opt/your-app/
cd /opt/your-app/tailscale-funnel-compose
cp .env.example .env
# Configure and use
```

### Option 3: Runtime Reference

```bash
# Set environment variable to point to installed location
export TAILSCALE_STACK_DIR=/opt/tailscale-funnel-compose
./your-app-manager.sh start
```

---

## Service Registry

Services are tracked in `config/services.tsv`:

```
name        port    path
main        8080    /
grafana     3000    /grafana
uptime      3001    /uptime
admin       8081    /admin
```

**Format:** Tab-separated values (name, port, path)

---

## Monitoring

### Health Check Output

```bash
$ ./health-check.sh
============================================
       OPENCLAW HEALTH CHECK
============================================

[PASS] Docker daemon
       v24.0.7
[PASS] Tailscale container
       Running
[PASS] Tailscale connectivity
       IP: 100.x.y.z
[PASS] Tailscale Funnel
       Active
[PASS] Disk space
       45% used

============================================
           HEALTH CHECK SUMMARY
============================================
  PASSED:   5
  WARNINGS: 0
  FAILED:   0
============================================
STATUS: HEALTHY
```

### JSON Output (for Prometheus)

```json
{
  "status": "healthy",
  "checks": {
    "passed": 5,
    "warnings": 0,
    "failed": 0
  },
  "timestamp": "2024-01-15T10:30:00+00:00"
}
```

### Nagios Output

```
OK - Tailscale: 5 OK, 0 warnings, 0 failed
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [RUNBOOK.md](./RUNBOOK.md) | Operational procedures and troubleshooting |
| [SECURITY.md](./SECURITY.md) | Security guide and hardening measures |
| [PRODUCTION-CHECKLIST.md](./PRODUCTION-CHECKLIST.md) | Pre/post deployment checklist |

---

## Troubleshooting

### Tailscale Not Connecting

```bash
# Check status
docker exec tailscale-funnel tailscale status

# Re-authenticate
./tailscale-funnel-compose.sh stop
./tailscale-funnel-compose.sh start openclaw 18789 /
```

### Duplicate Nodes

```bash
# Clean up duplicates (requires TS_API_KEY)
./tailscale-funnel-compose.sh cleanup-duplicates
```

### Service Not Accessible

```bash
# Check if backend is responding locally
curl http://127.0.0.1:8080/

# Check Tailscale routing
docker exec tailscale-funnel tailscale serve status
docker exec tailscale-funnel tailscale funnel status
```

---

## Security

- ✅ Non-root container execution
- ✅ Userspace networking (no TUN device)
- ✅ Isolated state persistence
- ✅ Encrypted traffic (TLS via Tailscale)
- ✅ Automatic certificate management

See [SECURITY.md](./SECURITY.md) for detailed security guide.

---

## Requirements

- Docker with Compose support
- Python 3 (for configuration management)
- curl (for API calls)
- Tailscale account (free tier works)

---

## License

This module is provided as-is for adding Tailscale Funnel remote access to any service.

---

## Support

- **GitHub Issues:** https://github.com/kuroringo90/-openclaw-setup-docker-new/issues
- **Tailscale Docs:** https://tailscale.com/kb/
