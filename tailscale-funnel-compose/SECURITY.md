# Production Security Guide

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Internet                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Tailscale Funnel (HTTPS)                        │
│              - TLS encryption                                │
│              - Tailscale identity verification               │
│              - Rate limiting                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Tailscale Container                             │
│              - Userspace networking                          │
│              - No privileged access                          │
│              - Isolated state                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenClaw Container                              │
│              - Bound to localhost only                       │
│              - Non-root user                                 │
│              - Read-only root filesystem                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Persistent Data (~/.openclaw/data)              │
│              - UID 1000 ownership                            │
│              - Restricted permissions                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Checklist

### Pre-Deployment

- [ ] Generate dedicated Tailscale auth key (not personal)
- [ ] Set key expiration (recommended: 90 days)
- [ ] Use specific tags for the node (e.g., `tag:production`)
- [ ] Document key rotation procedure
- [ ] Review Docker security options
- [ ] Configure firewall rules
- [ ] Set up monitoring/alerting

### Post-Deployment

- [ ] Verify localhost-only binding
- [ ] Confirm Tailscale Funnel is active
- [ ] Check container user is non-root
- [ ] Validate file permissions
- [ ] Test backup/restore procedure
- [ ] Document access URLs

---

## Hardening Measures

### 1. Container Security

The Docker Compose configuration includes:

```yaml
# OpenClaw - Production Hardening
services:
  openclaw:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    user: "1000:1000"
```

**What this does:**
- `no-new-privileges`: Prevents privilege escalation
- `read_only`: Root filesystem is read-only
- `tmpfs`: Temporary writable directory
- `cap_drop`: Removes all Linux capabilities
- `user`: Runs as non-root

### 2. Network Security

```yaml
# Bind to localhost only
ports:
  - "127.0.0.1:18789:18789"
```

**Why:** Only Tailscale can access OpenClaw, not the local network.

### 3. Tailscale Security

**Recommended settings in Tailscale Admin Console:**

1. **Access Controls (ACLs):**
   ```json
   {
     "hosts": {
       "openclaw": "100.x.y.z"
     },
     "acls": [
       {
         "action": "accept",
         "src": ["autogroup:members"],
         "dst": ["openclaw:443,80"]
       }
     ]
   }
   ```

2. **Tags for node:**
   - `tag:production`
   - `tag:openclaw`

3. **Key settings:**
   - Require approval for new nodes
   - Enable device authorization
   - Set key expiry

---

## Secrets Management

### What NOT to do:

```bash
# ❌ Never commit secrets
git add .env
git commit -m "Add config"

# ❌ Never log secrets
echo "TS_AUTHKEY=$TS_AUTHKEY" >> debug.log

# ❌ Never share via chat
# "Hey, here's the key: tskey-xxx"
```

### Best Practices:

1. **Environment files:**
   ```bash
   # .env is in .gitignore
   chmod 600 ~/.openclaw/.env
   ```

2. **Secrets rotation:**
   ```bash
   # Generate new key
   # Update .env
   # Restart services
   ./openclaw-manager.sh restart
   # Verify old key is revoked
   ```

3. **CI/CD integration:**
   ```yaml
   # GitHub Actions example
   - name: Deploy
     env:
       TS_AUTHKEY: ${{ secrets.TS_AUTHKEY }}
     run: ./deploy.sh --non-interactive
   ```

---

## Audit Logging

### Enable Tailscale Logging

```bash
# In Tailscale admin console:
# Settings > Logging > Enable
```

### Local Log Collection

```bash
# View OpenClaw logs
docker logs openclaw

# View Tailscale logs
docker logs tailscale-funnel

# Export logs for analysis
docker logs --since 24h openclaw > openclaw-$(date +%Y%m%d).log
```

### Log Retention

```bash
# Add to logrotate.d/openclaw
/var/log/openclaw/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
```

---

## Incident Response

### Suspected Unauthorized Access

1. **Immediate actions:**
   ```bash
   # Stop Tailscale Funnel
   cd ~/.openclaw/tailscale-funnel
   ./tailscale-funnel-compose.sh stop
   
   # Revoke Tailscale keys
   # Visit: https://login.tailscale.com/admin/settings/keys
   
   # Check access logs
   docker logs --since 1h openclaw | grep -E "POST|PUT|DELETE"
   ```

2. **Investigation:**
   ```bash
   # Check Tailscale node list
   tailscale status
   
   # Review audit log in admin console
   # https://login.tailscale.com/admin/logs
   ```

3. **Recovery:**
   ```bash
   # Generate new auth key
   # Update configuration
   # Restart services
   ./tailscale-funnel-compose.sh start openclaw 18789 /
   ```

---

## Compliance Considerations

### Data Protection

- OpenClaw data stored locally in `~/.openclaw/data`
- Tailscale encrypts all traffic end-to-end
- No data leaves your infrastructure except via Funnel

### Access Control

- Only authenticated Tailscale users can access
- ACLs can restrict access by user/group
- All access is logged

### Retention

- Configure backup retention per your requirements
- Default: 7 days
- Recommended for production: 30+ days

---

## Security Updates

### Container Images

```bash
# Check for updates weekly
docker pull ghcr.io/openclaw/openclaw:latest
docker pull tailscale/tailscale:latest

# Update running containers
./openclaw-manager.sh restart
```

### Tailscale Client

```bash
# The container uses latest Tailscale
# Updates are automatic on container restart
docker restart tailscale-funnel
```

---

## Security Contacts

- **Tailscale Security:** security@tailscale.com
- **OpenClaw Issues:** https://github.com/openclaw/openclaw/security
- **Your Security Team:** [Add your contact]
