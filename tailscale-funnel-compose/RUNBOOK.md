# Production Runbook - OpenClaw + Tailscale Funnel

## Overview

This runbook provides operational procedures for managing OpenClaw with Tailscale Funnel in production environments.

---

## Quick Reference

| Task | Command |
|------|---------|
| Start services | `./openclaw-manager.sh start` |
| Stop services | `./openclaw-manager.sh stop` |
| Check status | `./openclaw-manager.sh status-full` |
| Health check | `./health-check.sh` |
| Get Funnel URL | `./openclaw-manager.sh tunnel-url` |
| View logs | `docker logs -f openclaw` |
| Backup | `./backup.sh backup` |
| Restore | `./backup.sh restore <file>` |

---

## Service Status Codes

### Health Check Exit Codes
- `0` - **HEALTHY**: All checks passed
- `1` - **DEGRADED**: Some warnings, service still running
- `2` - **UNHEALTHY**: Critical failures, action required

### Container States
- `running` - Normal operation
- `restarting` - Container is restarting (check logs)
- `exited` - Container stopped (may be intentional)
- `unhealthy` - Health check failing (investigate)

---

## Common Scenarios

### Scenario 1: Service Won't Start

**Symptoms:** `./openclaw-manager.sh start` fails

**Diagnosis:**
```bash
# Check Docker daemon
docker info

# Check if port is in use
sudo netstat -tlnp | grep 18789

# Check logs
docker logs openclaw 2>&1 | tail -50
```

**Resolution:**
```bash
# Free up port if needed
sudo lsof -ti:18789 | xargs kill -9

# Remove stale container
docker rm -f openclaw 2>/dev/null || true

# Try starting again
./openclaw-manager.sh start
```

---

### Scenario 2: Tailscale Not Connecting

**Symptoms:** Funnel URL not accessible, Tailscale status shows disconnected

**Diagnosis:**
```bash
# Check Tailscale container
docker ps | grep tailscale

# Check Tailscale status
docker exec tailscale-funnel tailscale status

# Check auth status
docker exec tailscale-funnel tailscale status --json
```

**Resolution:**
```bash
# Re-authenticate
cd ~/.openclaw/tailscale-funnel
./tailscale-funnel-compose.sh stop
./tailscale-funnel-compose.sh start openclaw 18789 /

# If still failing, check auth key
nano ~/.openclaw/.env
# Verify TS_AUTHKEY is valid

# Clean up duplicate nodes
./tailscale-funnel-compose.sh cleanup-duplicates
```

---

### Scenario 3: High Disk Usage

**Symptoms:** Health check warns about disk space

**Diagnosis:**
```bash
# Check disk usage
df -h ~/.openclaw

# Check Docker disk usage
docker system df

# Find large files
du -sh ~/.openclaw/* | sort -h
```

**Resolution:**
```bash
# Clean Docker system
docker system prune -af

# Remove old backups (keep last 7 days)
find ~/.openclaw/backups -name "*.tar.gz" -mtime +7 -delete

# Check OpenClaw data size
du -sh ~/.openclaw/data
```

---

### Scenario 4: Container Restarting Loop

**Symptoms:** Container keeps restarting, status shows "Restarting"

**Diagnosis:**
```bash
# Check restart count
docker inspect openclaw --format '{{.RestartCount}}'

# Check last logs
docker logs --tail 100 openclaw

# Check exit code
docker inspect openclaw --format '{{.State.ExitCode}}'
```

**Resolution:**
```bash
# Stop the container
./openclaw-manager.sh stop

# Check configuration
./validate-config.sh

# Fix any issues found

# Start again
./openclaw-manager.sh start
```

---

### Scenario 5: Funnel URL Returns 502/503

**Symptoms:** Funnel URL accessible but returns error

**Diagnosis:**
```bash
# Check if OpenClaw is responding locally
curl -v http://127.0.0.1:18789/

# Check Tailscale serve configuration
docker exec tailscale-funnel tailscale serve status

# Check Funnel status
docker exec tailscale-funnel tailscale funnel status
```

**Resolution:**
```bash
# Reconfigure routing
./openclaw-manager.sh tailscale-config

# Wait 30 seconds and test again
sleep 30
curl -v https://<your-funnel-url>
```

---

## Scheduled Maintenance

### Daily
- [ ] Check health status: `./health-check.sh --quiet`
- [ ] Review error logs: `docker logs --since 24h openclaw | grep -i error`

### Weekly
- [ ] Run full status check: `./openclaw-manager.sh status-full`
- [ ] Verify backup integrity: `./backup.sh verify <latest-backup>`
- [ ] Check disk usage: `df -h ~/.openclaw`

### Monthly
- [ ] Review and rotate Tailscale auth keys
- [ ] Update Docker images: `docker pull ghcr.io/openclaw/openclaw:latest`
- [ ] Test restore procedure in staging environment
- [ ] Review access logs for anomalies

---

## Emergency Procedures

### Complete Service Outage

1. **Assess the situation:**
   ```bash
   ./health-check.sh
   docker ps -a
   ```

2. **Check if it's a Tailscale issue:**
   ```bash
   curl http://127.0.0.1:18789/  # Should work locally
   ```

3. **Restart services:**
   ```bash
   ./openclaw-manager.sh restart
   ```

4. **If still failing, restore from backup:**
   ```bash
   ./backup.sh list
   ./backup.sh restore ~/.openclaw/backups/openclaw-backup-YYYYMMDD_HHMMSS.tar.gz
   ./openclaw-manager.sh start
   ```

---

## Security Procedures

### Rotate Tailscale Auth Key

1. Generate new key at: https://login.tailscale.com/admin/settings/keys
2. Update configuration:
   ```bash
   nano ~/.openclaw/.env
   # Update TS_AUTHKEY
   ```
3. Restart Tailscale:
   ```bash
   cd ~/.openclaw/tailscale-funnel
   ./tailscale-funnel-compose.sh stop
   ./tailscale-funnel-compose.sh start openclaw 18789 /
   ```

### Revoke Compromised Node

1. Revoke key in Tailscale admin console
2. Delete node:
   ```bash
   cd ~/.openclaw/tailscale-funnel
   ./tailscale-funnel-compose.sh cleanup-duplicates
   ```
3. Generate new auth key and re-authenticate

---

## Monitoring Integration

### Prometheus Metrics

The health check script supports JSON output for monitoring systems:

```bash
# Add to prometheus.yml
scrape_configs:
  - job_name: 'openclaw-health'
    static_configs:
      - targets: ['localhost:9100']
    metrics_path: /openclaw-health
    script: /opt/openclaw-manager-system/health-check.sh --json
```

### Nagios/Icinga

```bash
# Add to commands.cfg
define command {
    command_name    check_openclaw
    command_line    /opt/openclaw-manager-system/health-check.sh --nagios
}
```

### Cron Jobs

```bash
# Add to /etc/cron.d/openclaw
# Health check every 5 minutes
*/5 * * * * root /opt/openclaw-manager-system/health-check.sh --nagios || echo "OpenClaw unhealthy" | logger

# Daily backup at 3 AM
0 3 * * * root /opt/openclaw-manager-system/backup.sh backup

# Weekly cleanup on Sunday at 4 AM
0 4 * * 0 root /opt/openclaw-manager-system/backup.sh cleanup
```

---

## Contact & Support

- **GitHub Issues:** https://github.com/kuroringo90/-openclaw-setup-docker-new/issues
- **Documentation:** QWEN.md in repository root
- **Tailscale Docs:** https://tailscale.com/kb/
