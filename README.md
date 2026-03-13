# OpenClaw Manager + External Tailscale Module

> **OpenClaw application repo with optional remote exposure through the external `tailscale-funnel-compose` module**

[![GitHub](https://img.shields.io/github/repo-size/kuroringo90/-openclaw-setup-docker-new)](https://github.com/kuroringo90/-openclaw-setup-docker-new)
[![Docker](https://img.shields.io/badge/docker-required-blue)](https://docs.docker.com/get-docker/)
[![Tailscale](https://img.shields.io/badge/tailscale-funnel-5555ff)](https://tailscale.com/)

---

## 🚀 Quick Start

### Prerequisites

- Docker with Compose support
- Linux, macOS, or Windows with WSL2
- Tailscale account (optional, for remote access)

### 5-Minute Deployment

```bash
# 1. Clone the repository
git clone https://github.com/kuroringo90/-openclaw-setup-docker-new.git
cd openclaw-tailscale-qwen-branch-separated/openclaw-manager-system

# 2. Edit configuration (set TS_AUTHKEY only if you want Tailscale)
nano .env

# 3. Deploy
./deploy.sh

# 4. Start OpenClaw
./openclaw-manager.sh start

# 5. Access locally
curl http://127.0.0.1:18789/

# 6. Get your URL summary
./openclaw-manager.sh tunnel-url
```

### Repository Model

- this repository is the OpenClaw consumer application
- the reusable Tailscale source of truth lives in the standalone repo `tailscale-funnel-compose`
- Tailscale integration is optional; local app runtime remains the default
- the vendored `tailscale-funnel-compose/` directory in this repo is compatibility-only, not the preferred module source

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
│              Tailscale Funnel (optional)                 │
│         external module, *.ts.net with TLS              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│         tailscale-funnel container                       │
│    - Userspace networking (no TUN required)             │
│    - Managed by external standalone module              │
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

### tailscale-funnel-compose (Standalone Module)

Modulo indipendente e riutilizzabile per qualsiasi progetto. Questo repo lo consuma come dipendenza esterna.

| Script | Purpose |
|--------|---------|
| `tailscale-funnel-compose.sh` | Tailscale stack manager |
| `health-check.sh` | Monitoring e health check |
| `backup.sh` | Backup e restore operations |
| `validate-config.sh` | Configuration validation |

**Source of truth:**
- standalone repo: `https://github.com/kuroringo90/tailscale-funnel-compose`
- local sibling preferred by this repo: `../tailscale-funnel-compose-standalone`
- vendored copy in this repo: compatibility fallback only

### OpenClaw Manager System

Script specifici per OpenClaw che consumano il modulo Tailscale.

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Automated production deployment |
| `openclaw-manager.sh` | Main orchestration script |
| `tailscale-add-service.sh` | Legacy compatibility wrapper |

---

## 🔧 Configuration

### OpenClaw (Required)

Edit `openclaw-manager-system/.env`:

```bash
# OpenClaw settings (defaults work out-of-the-box)
OPENCLAW_CONTAINER_NAME=openclaw
OPENCLAW_IMAGE_NAME=ghcr.io/openclaw/openclaw:latest
OPENCLAW_PORT=18789

# Tailscale (OPTIONAL - leave empty for local-only access)
TS_AUTHKEY=         # Set to enable Tailscale Funnel
TS_API_KEY=         # Optional, for node cleanup
TS_TAILNET=         # Optional, auto-detected
```

### Tailscale (Optional)

If you set `TS_AUTHKEY`, the Tailscale module can be used.
Configuration is handled in the external module `.env`, resolved in this order:

1. `REPO_TS_STACK_DIR`
2. `../tailscale-funnel-compose-standalone`
3. `../tailscale-funnel-compose`
4. `./tailscale-funnel-compose`
5. `/opt/tailscale-funnel-compose`

### Validation

Before deploying, validate your configuration:

```bash
cd openclaw-manager-system
${REPO_TS_STACK_DIR:-../tailscale-funnel-compose-standalone}/validate-config.sh
```

---

## 🎯 Common Operations

### Starting/Stopping

```bash
# Start all services
./openclaw-manager.sh start

# Stop all services
./openclaw-manager.sh stop

# Restart
./openclaw-manager.sh restart

# Pull and apply a newer OpenClaw image only if needed
./openclaw-manager.sh update-image
```

### Status & Monitoring

```bash
# Full status (OpenClaw + Tailscale)
./openclaw-manager.sh status-full

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
./openclaw-manager.sh tailscale-add grafana 3000 /grafana

# Add Uptime Kuma on /uptime
./openclaw-manager.sh tailscale-add uptime 3001 /uptime

# Add a tailnet-only service
./openclaw-manager.sh tailscale-add admin 8081 /admin serve

# View status
./openclaw-manager.sh status-full
```

Default behavior:

- omitted mode => `funnel` (public on Internet)
- explicit `serve` => tailnet-only
- `funnel` and `serve` should not be mixed on the same path-based hostname; choose one mode per stack

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
- [ ] Review OpenClaw remote-access tradeoff documented below before exposing the dashboard publicly
- [ ] Review Tailscale Funnel runtime observations documented below before public exposure

### OpenClaw Remote Access Note

Observed in runtime validation:

- OpenClaw dashboard works correctly behind Funnel only when exposed on `/openclaw/` with trailing slash
- the dashboard URL must include the gateway token, for example `https://<funnel-host>/openclaw/#token=...`
- the current production integration enables `gateway.bind=lan`
- the current production integration also enables `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true`

Security implication:

- this fallback weakens origin validation for the Control UI and should be treated as a temporary compatibility setting, not a final hardening state
- a stricter follow-up should replace it with explicit `gateway.controlUi.allowedOrigins` matching the final public URL(s)

### Tailscale Funnel Runtime Note

Observed in runtime validation:

- `tailscale funnel` is the correct public exposure mode; `tailscale serve` remains tailnet-only
- path-based public exposure is sensitive to the backend application path model
- applications using relative frontend assets may require a trailing slash on the public path, as seen with OpenClaw on `/openclaw/`
- public edge behavior can be temporarily inconsistent immediately after route changes or resets

Security implication:

- do not treat transient Funnel edge propagation or tailnet policy behavior as an application bug without checking `tailscale funnel status`
- verify both the HTML entrypoint and public static assets after every path-based change
- keep public routes minimal and explicit; avoid exposing unnecessary default paths until a deliberate landing page is introduced

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
sudo ./openclaw-manager.sh systemd-install

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
| **[ARCHITECTURE.md](./ARCHITECTURE.md)** | **Complete architecture and project structure** |
| [RUNBOOK.md](./tailscale-funnel-compose/RUNBOOK.md) | Operational procedures and troubleshooting |
| [SECURITY.md](./tailscale-funnel-compose/SECURITY.md) | Security guide and hardening measures |
| [PRODUCTION-CHECKLIST.md](./tailscale-funnel-compose/PRODUCTION-CHECKLIST.md) | Production deployment checklist |
| [MIGRATION.md](./openclaw-manager-system/MIGRATION.md) | Migration guide from previous versions |
| [QWEN.md](./QWEN.md) | Project context and AI instructions |

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
