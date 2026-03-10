# OpenClaw + Tailscale - Architettura del Progetto

## 📁 Struttura del Repository

```
openclaw-tailscale-qwen-branch-separated/
│
├── README.md                           # Documentazione principale
├── QWEN.md                             # Context per AI assistant
├── QWEN.MD                             # Note architetturali (legacy)
├── MANIFEST.txt                        # Lista file del repo
├── .gitignore                          # File ignorati da Git
│
├── openclaw-manager-system/            # MODULO OPENCLAW
││
│   ├── .env                            # Configurazione default OpenClaw
│   ├── .env.example                    # Template configurazione
│   ├── deploy.sh                       # Script di deployment
│   ├── docker-compose.openclaw.example.yml
│   ├── openclaw-manager.sh             # Manager principale OpenClaw
│   ├── openclaw.service                # Systemd service (auto-start)
│   ├── tailscale-add-service.sh        # Integrazione con Tailscale
│   ├── MIGRATION.md                    # Guida migrazione
│   └── README-WRAPPER.md               # Documentazione wrapper legacy
│
└── tailscale-funnel-compose/           # MODULO TAILSCALE (indipendente)
    │
    ├── .env.example                    # Template configurazione Tailscale
    ├── docker-compose.yml              # Compose per container Tailscale
    ├── tailscale-funnel-compose.sh     # Manager Tailscale completo
    ├── start-service.sh                # Start rapido servizi
    │
    ├── backup.sh                       # Backup & restore
    ├── health-check.sh                 # Health monitoring
    ├── validate-config.sh              # Validazione configurazione
    │
    ├── README.md                       # Documentazione modulo
    ├── DEPENDENCY.md                   # Uso come dipendenza
    ├── RUNBOOK.md                      # Procedure operative
    ├── SECURITY.md                     # Security guide
    └── PRODUCTION-CHECKLIST.md         # Checklist production
```

---

## 🏗️ Architettura del Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                             │
│                    (Linux / macOS / WSL2)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    REPOSITORY ROOT                              │
│                                                                 │
│  ┌────────────────────────────┐  ┌──────────────────────────┐  │
│  │  openclaw-manager-system/  │  │ tailscale-funnel-compose/│  │
│  │                            │  │                          │  │
│  │  OPENCLAW MODULE           │  │ TAILSCALE MODULE         │  │
│  │                            │  │                          │  │
│  │  • Deploy OpenClaw         │  │ • Tailscale Funnel       │  │
│  │  • Gestione container      │  │ • Remote access          │  │
│  │  • Config locale           │  │ • Multi-service          │  │
│  │  • Solo localhost          │  │ • HTTPS automatico       │  │
│  │                            │  │                          │  │
│  │  Script:                   │  │  Script:                 │  │
│  │  - deploy.sh               │  │  - tailscale-funnel-     │  │
│  │  - openclaw-manager.sh     │  │    compose.sh            │  │
│  │  - tailscale-add-service.sh│  │  - start-service.sh      │  │
│  │                            │  │  - health-check.sh       │  │
│  │  Config:                   │  │  - backup.sh             │  │
│  │  - .env (OpenClaw only)    │  │  - validate-config.sh    │  │
│  └────────────┬───────────────┘  │                          │  │
│               │                  │  Config:                 │  │
│               │  (opzionale)     │  - .env (Tailscale)      │  │
│               └─────────────────►│                          │  │
│                                  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Flussi Operativi

### 1. OpenClaw-First (Locale → Remoto)

```bash
# Step 1: Deploy
cd openclaw-manager-system
./deploy.sh
# → Prompt: "Vuoi configurare Tailscale Funnel ora? (y/n)"

# Step 2: Start OpenClaw
./openclaw-manager.sh start
# → OpenClaw attivo su http://127.0.0.1:18789

# Step 3: (Opzionale) Aggiungi Tailscale
./tailscale-add-service.sh add
# → Se TS_AUTHKEY configurata: avvia e aggiunge OpenClaw
# → Se non configurata: mostra istruzioni
```

### 2. Tailscale-First (Remoto → Servizi)

```bash
# Step 1: Configura Tailscale
cd tailscale-funnel-compose
cp .env.example .env
nano .env  # Imposta TS_AUTHKEY

# Step 2: Avvia Tailscale con OpenClaw
./start-service.sh openclaw 18789 /

# Step 3: (Opzionale) Aggiungi altri servizi
./start-service.sh grafana 3000 /grafana
```

### 3. Tailscale-Only (Solo modulo)

```bash
# Avvia solo Tailscale
cd tailscale-funnel-compose
./start-service.sh --only

# Aggiungi servizi quando vuoi
./tailscale-funnel-compose.sh add myservice 8080 /myservice
```

---

## 📦 Componenti e Responsabilità

### OpenClaw Manager System

| Componente | Scopo | Dipendenze |
|------------|-------|------------|
| `deploy.sh` | Deploy iniziale OpenClaw | Docker, modulo Tailscale (opzionale) |
| `openclaw-manager.sh` | Start/stop/status OpenClaw | Docker |
| `tailscale-add-service.sh` | Integrazione con Tailscale | Modulo Tailscale |
| `.env` | Configurazione OpenClaw | Nessuna |
| `openclaw.service` | Systemd auto-start | systemd |

### Tailscale Funnel Compose

| Componente | Scopo | Dipendenze |
|------------|-------|------------|
| `tailscale-funnel-compose.sh` | Manager completo Tailscale | Docker, TS_AUTHKEY |
| `start-service.sh` | Start rapido servizi | Docker, TS_AUTHKEY |
| `docker-compose.yml` | Container Tailscale | Docker Compose |
| `backup.sh` | Backup & restore | Python 3 |
| `health-check.sh` | Health monitoring | Docker, curl |
| `validate-config.sh` | Validazione config | Python 3 |

---

## 🔑 Separazione Chiave

| Aspetto | OpenClaw | Tailscale |
|---------|----------|-----------|
| **Config** | `openclaw-manager-system/.env` | `tailscale-funnel-compose/.env` |
| **Script** | `openclaw-manager.sh` | `start-service.sh` |
| **Accesso** | Locale (127.0.0.1) | Remoto (Funnel HTTPS) |
| **Dipendenze** | Docker | Docker + TS_AUTHKEY |
| **Stato** | `~/.openclaw/data` | `~/.openclaw/tailscale-funnel/` |

---

## 🛣️ Data Flow

```
┌──────────────────────────────────────────────────────────────┐
│                      UTENTE                                  │
└─────────────────────┬────────────────────────────────────────┘
                      │
         ┌────────────┼────────────┐
         │            │            │
         ▼            ▼            ▼
   ┌─────────┐  ┌──────────┐  ┌──────────┐
   │ deploy  │  │ manager  │  │ add-svc  │
   │   .sh   │  │    .sh   │  │    .sh   │
   └────┬────┘  └────┬─────┘  └────┬─────┘
        │            │             │
        │            │             │ (se configurato)
        │            │             ▼
        │            │    ┌────────────────────┐
        │            │    │ tailscale-funnel-  │
        │            │    │ compose/           │
        │            │    │ - start-service.sh │
        │            │    │ - compose.sh       │
        │            │    └────────────────────┘
        ▼            ▼
   ┌──────────────────────────┐
   │   Runtime Directory      │
   │   ~/.openclaw/           │
   │                          │
   │   ├── data/              │ ← OpenClaw persistent data
   │   ├── .env               │ ← OpenClaw runtime config
   │   ├── docker-compose.yml │ ← OpenClaw container
   │   │                      │
   │   └── tailscale-funnel/  │ ← Tailscale runtime
   │       ├── state/         │ ← Tailscale state
   │       ├── config/        │ ← Service registry
   │       └── .env           │ ← Tailscale config
   └──────────────────────────┘
```

---

## 🔐 Security Model

```
┌─────────────────────────────────────────────────────────┐
│                    Internet                              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │  Tailscale Funnel    │
          │  - HTTPS automatico  │
          │  - Auth Tailscale    │
          │  - TLS gestito       │
          └──────────┬───────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │  tailscale-funnel    │
          │  container           │
          │  - Userspace net     │
          │  - No privilegi      │
          └──────────┬───────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │  127.0.0.1:18789     │ ← Localhost only
          └──────────┬───────────┘
                     │
                     ▼
          ┌──────────────────────┐
          │  openclaw container  │
          │  - UID 1000          │
          │  - Read-only FS      │
          │  - No capabilities   │
          └──────────────────────┘
```

---

## 📊 Matrice Decisionale

| Scenario | Script da usare | Risultato |
|----------|-----------------|-----------|
| Deploy iniziale | `./deploy.sh` | OpenClaw pronto + prompt Tailscale |
| Start quotidiano | `./openclaw-manager.sh start` | OpenClaw attivo (no prompt) |
| Aggiungi Tailscale | `./tailscale-add-service.sh add` | OpenClaw + Tailscale |
| Solo Tailscale | `cd tailscale-funnel-compose && ./start-service.sh --only` | Solo Tailscale |
| Aggiungi servizio | `./start-service.sh <name> <port>` | Nuovo servizio su Funnel |
| Health check | `./health-check.sh` | Stato salute sistema |
| Backup | `./backup.sh backup` | Backup configurato |

---

## 🚀 Produzione

### Prerequisiti
- Docker con Compose
- Python 3 (per script ausiliari)
- curl (per health check)
- Tailscale account (per accesso remoto)

### Checklist Deploy
1. ✅ Docker installato e attivo
2. ✅ Modulo Tailscale presente (se serve accesso remoto)
3. ✅ TS_AUTHKEY configurata (se serve Tailscale)
4. ✅ Permessi directory corretti
5. ✅ Health check passa

### Monitoring
```bash
# Health check
./health-check.sh

# Log OpenClaw
docker logs -f openclaw

# Log Tailscale
docker logs -f tailscale-funnel

# Status completo
./openclaw-manager.sh status
```

---

## 📖 Documentazione

| Documento | Percorso | Scopo |
|-----------|----------|-------|
| README | `./README.md` | Guida principale |
| Runbook | `tailscale-funnel-compose/RUNBOOK.md` | Procedure operative |
| Security | `tailscale-funnel-compose/SECURITY.md` | Security guide |
| Checklist | `tailscale-funnel-compose/PRODUCTION-CHECKLIST.md` | Deploy production |
| Dependency | `tailscale-funnel-compose/DEPENDENCY.md` | Uso come modulo |
| Migration | `openclaw-manager-system/MIGRATION.md` | Migrazione |

---

## 🔄 Versioning

- **OpenClaw**: Indipendente da Tailscale
- **Tailscale Module**: Riusabile da altri progetti
- **Integrazione**: Opzionale, configurata dall'utente

---

## 📝 Note

- OpenClaw funziona **sempre** in locale, anche senza Tailscale
- Tailscale è un **modulo opzionale** che può essere usato da solo
- Le configurazioni sono **completamente separate**
- Non ci sono dipendenze circolari tra i moduli
