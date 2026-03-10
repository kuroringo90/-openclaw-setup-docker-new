# OpenClaw Tailscale Setup - Project Context

## Project Overview

This repository provides a **Docker-based deployment system for OpenClaw** with integrated **Tailscale Funnel** for secure remote access. The project is architecturally split into two independent but cooperating components:

### Architecture

```
openclaw-tailscale-qwen-branch-separated/
├── openclaw-manager-system/          # OpenClaw-specific logic and wrappers
│   ├── openclaw-manager-tailscale.sh # Main orchestration script
│   ├── tailscale-add-service.sh      # Legacy compatibility wrapper
│   ├── docker-compose.openclaw.example.yml
│   ├── README-WRAPPER.md
│   └── MIGRATION.md
├── tailscale-funnel-compose/         # Standalone Tailscale Funnel dependency
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── tailscale-funnel-compose.sh   # Tailscale manager script
│   ├── README.md
│   └── DEPENDENCY.md
└── MANIFEST.txt
```

### Component Responsibilities

| Component | Purpose |
|-----------|---------|
| `tailscale-funnel-compose/` | **Reusable dependency** - Standalone Tailscale Funnel stack that can be vendored/used by other projects independently of OpenClaw |
| `openclaw-manager-system/` | **OpenClaw-specific logic** - Wrapper scripts that orchestrate OpenClaw container and consume Tailscale stack as a sibling dependency |

### Key Design Principles

1. **Separation of concerns**: Tailscale Funnel is a standalone project, not embedded inside OpenClaw
2. **Reusability**: `tailscale-funnel-compose/` can be used by other projects without OpenClaw coupling
3. **Compatibility**: Legacy command interfaces are maintained via wrapper scripts
4. **Runtime isolation**: State persisted in `~/.openclaw/tailscale-funnel/` (separate from repo)

## Technologies Used

- **Docker Compose** - Container orchestration
- **Tailscale** - Secure tunneling via Funnel (requires `TS_AUTHKEY`)
- **Bash** - Orchestration scripts (POSIX-compatible)
- **Python 3** - JSON parsing and config management
- **curl** - Tailscale API calls for duplicate node cleanup

## Building and Running

### Prerequisites

- Docker with `docker compose` support
- Python 3
- curl
- Tailscale auth key (`TS_AUTHKEY`)
- (Optional) Tailscale API key (`TS_API_KEY`) for duplicate node cleanup

### Quick Start

```bash
# 1. Make scripts executable
chmod +x openclaw-manager-system/openclaw-manager-tailscale.sh \
         openclaw-manager-system/tailscale-add-service.sh \
         tailscale-funnel-compose/tailscale-funnel-compose.sh

# 2. Configure environment (edit TS_AUTHKEY)
cp tailscale-funnel-compose/.env.example tailscale-funnel-compose/.env
nano tailscale-funnel-compose/.env

# 3. Start OpenClaw + Tailscale
cd openclaw-manager-system
./openclaw-manager-tailscale.sh start

# 4. Check status
./openclaw-manager-tailscale.sh status-full

# 5. Get Funnel URL
./openclaw-manager-tailscale.sh tunnel-url
```

### Available Commands

#### OpenClaw Manager (`openclaw-manager-tailscale.sh`)

| Command | Description |
|---------|-------------|
| `start` | Start OpenClaw + bootstrap Tailscale |
| `stop` | Stop all containers |
| `restart` | Restart everything |
| `status` | Show OpenClaw status |
| `status-full` | Show OpenClaw + Tailscale status |
| `tunnel-url` | Display Funnel URL |
| `tailscale-config` | Re-apply OpenClaw routing to `/` |
| `tailscale-add <name> <port> [path]` | Add secondary service |
| `tailscale-remove <name>` | Remove secondary service |
| `full-reset` | Complete runtime reset |

#### Tailscale Standalone (`tailscale-funnel-compose.sh`)

| Command | Description |
|---------|-------------|
| `start <name> <port> [path]` | Start Tailscale with main service |
| `stop` | Stop Tailscale container |
| `add <name> <port> [path]` | Add secondary service |
| `remove <name>` | Remove service |
| `status` | Show status |
| `url` | Show Funnel URL |
| `logs` | Stream logs |
| `shell` | Enter container shell |
| `cleanup-duplicates` | Remove duplicate nodes via API |

### Adding Secondary Services

```bash
# Add Grafana on /grafana
./openclaw-manager-tailscale.sh tailscale-add grafana 3000 /grafana

# Add Uptime Kuma on /uptime
./openclaw-manager-tailscale.sh tailscale-add uptime 3001 /uptime
```

## Environment Configuration

### Required Variables (`.env`)

| Variable | Description |
|----------|-------------|
| `TS_AUTHKEY` | Tailscale auth key (required) |
| `TS_API_KEY` | Tailscale API key (for duplicate cleanup) |
| `TS_TAILNET` | Tailnet name (auto-detected if not set) |
| `TS_HOSTNAME` | Node hostname (default: `tailscale-funnel`) |
| `TS_CONTAINER_NAME` | Container name (default: `tailscale-funnel`) |

### Runtime Directories

| Directory | Purpose |
|-----------|---------|
| `~/.openclaw/data` | OpenClaw persistent data |
| `~/.openclaw/tailscale-funnel/state` | Tailscale state (auth, node info) |
| `~/.openclaw/tailscale-funnel/config` | Service registry (`services.tsv`) |

## Development Conventions

### Script Patterns

- All scripts use `set -euo pipefail` for strict error handling
- Functions prefixed with action verbs: `start_`, `stop_`, `ensure_`, `check_`
- Logging functions with colors: `log_info`, `log_success`, `log_warn`, `log_error`
- Environment loading via `set -a; source; set +a` pattern

### Service Registry Format

Services are tracked in `config/services.tsv` (tab-separated):

```
name    port    path
grafana 3000    /grafana
uptime  3001    /uptime
```

### External Integration

To use the OpenClaw manager outside this package structure:

```bash
export REPO_TS_STACK_DIR=/path/to/tailscale-funnel-compose
./openclaw-manager-tailscale.sh start
```

## Testing

```bash
# Full workflow test
cd openclaw-manager-system
./openclaw-manager-tailscale.sh start
./openclaw-manager-tailscale.sh tailscale-add grafana 3000 /grafana
./openclaw-manager-tailscale.sh status-full
./openclaw-manager-tailscale.sh tunnel-url
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `TS_AUTHKEY non impostata` | Set `TS_AUTHKEY` in `.env` file |
| `Docker non è in esecuzione` | Start Docker daemon |
| `tailscaled non pronto` | Wait 30s for container health check |
| Duplicate nodes | Run `cleanup-duplicates` with `TS_API_KEY` set |
| Permission errors on data dir | `sudo chown -R 1000:1000 ~/.openclaw/data` |

## Repository

- **Remote**: `https://github.com/kuroringo90/-openclaw-setup-docker-new.git`
- **Branch**: `main`
