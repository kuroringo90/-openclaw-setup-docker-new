# tailscale-funnel-compose

Stack standalone Tailscale Funnel con Docker Compose.

## Obiettivi

- usare Tailscale Funnel come progetto separato e riusabile
- persistere stato e registry locale servizi
- supportare servizio principale su `/`
- supportare servizi secondari via path
- includere cleanup duplicati tramite API Tailscale

## Quick start

```bash
cp .env.example .env
# imposta TS_AUTHKEY
./tailscale-funnel-compose.sh start openclaw 18789 /
./tailscale-funnel-compose.sh add grafana 3000 /grafana
./tailscale-funnel-compose.sh status
```

## Requisiti

- Docker con `docker compose`
- `curl`
- `python3`

## Persistenza

- `state/` -> stato tailscaled
- `config/services.tsv` -> registry locale servizi
