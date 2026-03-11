# `tailscale-funnel-compose` come dipendenza di altri progetti

Questo progetto è pensato per essere riusato come dipendenza standalone da altri sistemi, non solo OpenClaw.

## Requisiti minimi del progetto consumer

- Docker disponibile
- `docker compose` disponibile
- `python3`
- `curl`
- directory persistenti per `state/` e `config/`

## File che il consumer deve usare

- `docker-compose.yml`
- `.env.example`
- `tailscale-funnel-compose.sh`

## File runtime generati

- `.env`
- `state/`
- `config/services.tsv`

## Pattern di utilizzo consigliato

Il progetto consumer non dovrebbe riscrivere la logica di Funnel. Dovrebbe:

1. copiare o vendorizzare `tailscale-funnel-compose/`
2. valorizzare `.env`
3. richiamare il manager `tailscale-funnel-compose.sh`
4. opzionalmente sincronizzare le sue env interne con quelle richieste da Tailscale

## Bootstrap esempio

```bash
cp .env.example .env
# imposta TS_AUTHKEY
./tailscale-funnel-compose.sh start myapp 8080 /
./tailscale-funnel-compose.sh add grafana 3000 /grafana
./tailscale-funnel-compose.sh add grafana 3000 /grafana serve
./tailscale-funnel-compose.sh status
```

## Pattern di integrazione consigliato

### 1. Wrapper locale del progetto

Crea uno script del progetto che delega al manager Tailscale:

```bash
#!/usr/bin/env bash
set -euo pipefail
TS_DIR="/opt/my-app/tailscale-funnel"
exec "${TS_DIR}/tailscale-funnel-compose.sh" "$@"
```

### 2. Sync environment dal progetto host

Se il progetto host possiede già un `.env`, sincronizza solo le chiavi Tailscale necessarie evitando di sovrascrivere valori runtime con stringhe vuote.

### 3. Mantieni separata la source of truth dei servizi

Il file `config/services.tsv` deve restare gestito solo dal manager Tailscale. Il progetto host non dovrebbe editarlo manualmente.

## Comandi esposti dal manager

```bash
./tailscale-funnel-compose.sh start <main-name> <main-port|target> [main-path=/] [main-mode=funnel|serve]
./tailscale-funnel-compose.sh add <name> <port|target> [path] [mode=funnel|serve]
./tailscale-funnel-compose.sh remove <name>
./tailscale-funnel-compose.sh status
./tailscale-funnel-compose.sh url
./tailscale-funnel-compose.sh logs
./tailscale-funnel-compose.sh shell
./tailscale-funnel-compose.sh cleanup-duplicates
```

## Casi d'uso previsti

- OpenClaw
- dashboard interne come Grafana / Uptime Kuma
- pannelli admin self-hosted
- piccoli gateway HTTP multiprogetto

## Invarianti consigliate per i consumer

- il servizio principale deve stare su `/`
- i servizi secondari devono usare path dedicati
- nome, porta e path devono restare univoci
- il mode di default deve essere esplicito per il consumer; se omesso resta `funnel`
- `serve` va trattato come modalità tailnet-only, non come fallback di errore
- `funnel` e `serve` non vanno mischiati sullo stesso hostname path-based; scegli una sola modalità per stack
- il cleanup duplicati deve essere opzionale ma disponibile
- `state/` e `config/` devono essere persistenti
