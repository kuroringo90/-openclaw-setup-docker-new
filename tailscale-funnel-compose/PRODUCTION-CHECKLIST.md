# Production Deployment Checklist

Use this checklist before deploying to production.

## Pre-Deployment

### Environment Setup

- [ ] Docker installed and running
- [ ] Docker Compose available
- [ ] Python 3 installed
- [ ] curl installed
- [ ] At least 1GB free disk space
- [ ] System user created for running service

### Tailscale Configuration

- [ ] Tailscale account created
- [ ] Pre-authenticated key generated
- [ ] Key has expiration set (recommended: 90 days)
- [ ] Key has tags assigned (e.g., `tag:production`, `tag:openclaw`)
- [ ] API key generated for cleanup (optional but recommended)
- [ ] Tailnet name documented

### Security

- [ ] `.env` file permissions set to 600
- [ ] Auth keys stored securely (not in repo)
- [ ] Firewall rules configured
- [ ] ACLs configured in Tailscale admin
- [ ] Security review completed (see SECURITY.md)

### Configuration

- [ ] `.env` file created from `.env.example`
- [ ] All required values set
- [ ] Configuration validated with `./validate-config.sh`
- [ ] Image tag pinned to specific version (not `:latest`)

## Deployment

### Installation

- [ ] `./deploy.sh` executed successfully
- [ ] Data directory created with correct permissions
- [ ] Tailscale stack installed
- [ ] Docker image pulled

### Initial Start

- [ ] Services started with `./openclaw-manager.sh start`
- [ ] Health check passes: `./health-check.sh`
- [ ] Funnel URL accessible
- [ ] OpenClaw UI loads correctly
- [ ] OpenClaw dashboard tested with tokenized URL `.../openclaw/#token=...`
- [ ] OpenClaw dashboard tested with trailing slash path `/openclaw/`
- [ ] Temporary security tradeoff accepted or replaced: `gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true`
- [ ] Public route type verified as Funnel, not Serve

### Verification

- [ ] Tailscale node appears in admin console
- [ ] Funnel endpoint is active
- [ ] Local health check passes (http://127.0.0.1:18789)
- [ ] Remote access via Funnel URL works
- [ ] Remote OpenClaw JS/CSS assets load correctly under `/openclaw/assets/...`
- [ ] `tailscale funnel status` reviewed after the last route change
- [ ] At least one public Funnel edge IP tested after route changes when behavior looks inconsistent

## Post-Deployment

### Monitoring

- [ ] Health check integrated with monitoring system
- [ ] Alert thresholds configured
- [ ] Log collection enabled
- [ ] Dashboard created (if applicable)

### Backup

- [ ] Initial backup created
- [ ] Backup verified
- [ ] Retention policy configured
- [ ] Cron job for automated backups

### Auto-Start (Optional)

- [ ] Systemd service installed
- [ ] Service enabled
- [ ] Service tested: `systemctl start/stop/status`
- [ ] Boot start verified

### Documentation

- [ ] Access URLs documented
- [ ] Credentials stored in password manager
- [ ] Runbook accessible to team
- [ ] Contact information updated

### Handover

- [ ] Team trained on basic operations
- [ ] Escalation procedure documented
- [ ] On-call rotation updated (if applicable)

## Ongoing Maintenance

### Daily

- [ ] Health check passes
- [ ] No errors in logs

### Weekly

- [ ] Full status review
- [ ] Backup integrity verified
- [ ] Disk usage checked

### Monthly

- [ ] Security updates applied
- [ ] Images updated
- [ ] Access review completed
- [ ] Restore test performed (quarterly)

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deployer | | | |
| Reviewer | | | |
| Security | | | |

---

**Deployment Date:** _______________

**Version Deployed:** _______________

**Notes:**
