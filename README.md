# OpenClaw + Tailscale Funnel - Production Deployment Guide

> **Production-ready deployment system for OpenClaw with secure remote access via Tailscale Funnel**

[![GitHub](https://img.shields.io/github/repo-size/kuroringo90/-openclaw-setup-docker-new)](https://github.com/kuroringo90/-openclaw-setup-docker-new)
[![Docker](https://img.shields.io/badge/docker-required-blue)](https://docs.docker.com/get-docker/)
[![Tailscale](https://img.shields.io/badge/tailscale-funnel-5555ff)](https://tailscale.com/)

---

## 🚀 Quick Start

### Prerequisites

- Docker with Compose support
- Linux, macOS, or Windows with WSL2
- Tailscale account (free tier works)

### 5-Minute Deployment

```bash
# 1. Clone the repository
git clone https://github.com/kuroringo90/-openclaw-setup-docker-new.git
cd openclaw-tailscale-qwen-branch-separated/openclaw-manager-system

# 2. Run the deployment script
./deploy.sh

# 3. Start services
./openclaw-manager-tailscale.sh start

# 4. Get your secure URL
./openclaw-manager-tailscale.sh tunnel-url
```

---

## 📋 What You Get

| Feature | Description |
|---------|-------------|
| 🔒 **Secure Access** | Tailscale Funnel with HTTPS encryption |
| 🔄 **Auto-start** | Systemd service for boot persistence |
| 💾 **Backups** | Automated daily backups with retention |
| 🏥 **Health Checks** | Production monitoring with exit codes |
| 📊 **Monitoring** | Prometheus/Nagios integration ready |
| 🔐 **Hardening** | Non-root containers, read-only filesystems |
| 📖 **Documentation** | Runbooks, security guide, troubleshooting |

---

## 🏗️ Architecture

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
│    - Routes traffic to OpenClaw                         │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│         openclaw container                               │
│    - Bound to 127.0.0.1 (localhost only)                │
│    - Non-root user (UID 1000)                           │
│    - Read-only root filesystem                          │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Components

### OpenClaw Manager System

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Automated production deployment |
| `openclaw-manager-tailscale.sh` | Main orchestration script |
| `health-check.sh` | Monitoring and health checks |
| `backup.sh` | Backup and restore operations |
| `validate-config.sh` | Configuration validation |

### Tailscale Funnel Compose

| Script | Purpose |
|--------|---------|
| `tailscale-funnel-compose.sh` | Tailscale stack manager |

---

## 🔧 Configuration

### Environment Variables

Create `~/.openclaw/.env`:

```bash
# Required: Tailscale authentication
TS_AUTHKEY=tskey-auth-xxx  # Get from tailscale.com/admin

# Optional: API key for node cleanup
TS_API_KEY=xxx

# Optional: Your tailnet name
TS_TAILNET=example.com

# OpenClaw settings
OPENCLAW_PORT=18789
OPENCLAW_BIND_ADDRESS=127.0.0.1
```

### Validation

Before deploying, validate your configuration:

```bash
./validate-config.sh
```

---

## 🎯 Common Operations

### Starting/Stopping

```bash
# Start all services
./openclaw-manager-tailscale.sh start

# Stop all services
./openclaw-manager-tailscale.sh stop

# Restart
./openclaw-manager-tailscale.sh restart
```

### Status & Monitoring

```bash
# Full status (OpenClaw + Tailscale)
./openclaw-manager-tailscale.sh status-full

# Health check (for monitoring)
./health-check.sh

# Health check (JSON output)
./health-check.sh --json

# Health check (Nagios format)
./health-check.sh --nagios
```

### Backups

```bash
# Create backup
./backup.sh backup

# List backups
./backup.sh list

# Restore from backup
./backup.sh restore ~/.openclaw/backups/openclaw-backup-20240101_120000.tar.gz

# Verify backup
./backup.sh verify ~/.openclaw/backups/openclaw-backup-20240101_120000.tar.gz
```

### Adding Secondary Services

```bash
# Add Grafana on /grafana
./openclaw-manager-tailscale.sh tailscale-add grafana 3000 /grafana

# Add Uptime Kuma on /uptime
./openclaw-manager-tailscale.sh tailscale-add uptime 3001 /uptime

# View status
./openclaw-manager-tailscale.sh status-full
```

---

## 🔐 Security

### Hardening Features

- ✅ Non-root container execution
- ✅ Read-only root filesystem
- ✅ Localhost-only binding
- ✅ No Linux capabilities
- ✅ Encrypted traffic via Tailscale
- ✅ Automatic TLS certificates

### Security Checklist

- [ ] Generate dedicated Tailscale auth key
- [ ] Set key expiration (90 days recommended)
- [ ] Use tags for node identification
- [ ] Enable ACLs in Tailscale admin
- [ ] Configure firewall rules
- [ ] Set up monitoring/alerting

See [SECURITY.md](./SECURITY.md) for detailed security guide.

---

## 📊 Monitoring Integration

### Prometheus

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'openclaw'
    static_configs:
      - targets: ['localhost:9100']
    metrics_path: /openclaw-health
```

### Nagios/Icinga

```bash
# commands.cfg
define command {
    command_name    check_openclaw
    command_line    /opt/openclaw-manager-system/health-check.sh --nagios
}
```

### Cron Jobs

```bash
# /etc/cron.d/openclaw
*/5 * * * * root /opt/openclaw-manager-system/health-check.sh --nagios
0 3 * * * root /opt/openclaw-manager-system/backup.sh backup
```

---

## 🔧 Systemd Auto-Start

Enable automatic start on boot:

```bash
# Install service (requires sudo)
sudo ./openclaw-manager-tailscale.sh systemd-install

# Or manually
sudo cp openclaw.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw
```

---

## 📖 Documentation

| Document | Purpose |
|----------|---------|
| [RUNBOOK.md](./RUNBOOK.md) | Operational procedures and troubleshooting |
| [SECURITY.md](./SECURITY.md) | Security guide and hardening measures |
| [MIGRATION.md](./MIGRATION.md) | Migration guide from previous versions |
| [QWEN.md](../QWEN.md) | Project context and architecture |

---

## 🐛 Troubleshooting

### Service won't start

```bash
# Check Docker
docker info

# Check configuration
./validate-config.sh

# View logs
docker logs openclaw
docker logs tailscale-funnel
```

### Tailscale not connecting

```bash
# Check status
docker exec tailscale-funnel tailscale status

# Re-authenticate
cd ~/.openclaw/tailscale-funnel
./tailscale-funnel-compose.sh stop
./tailscale-funnel-compose.sh start openclaw 18789 /
```

### Health check failing

```bash
# Run detailed health check
./health-check.sh

# Check recent logs for errors
docker logs --tail 100 openclaw | grep -i error
```

---

## 🆘 Getting Help

- **GitHub Issues:** https://github.com/kuroringo90/-openclaw-setup-docker-new/issues
- **Tailscale Docs:** https://tailscale.com/kb/
- **OpenClaw Docs:** https://github.com/openclaw/openclaw

---

## 📝 License

This deployment system is provided as-is for deploying OpenClaw with Tailscale Funnel.

---

## 🙏 Acknowledgments

- [OpenClaw](https://github.com/openclaw/openclaw) - The main application
- [Tailscale](https://tailscale.com/) - Secure tunneling service
- [Docker](https://docker.com/) - Container platform
