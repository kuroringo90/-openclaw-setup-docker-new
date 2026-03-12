# Migrazione OpenClaw + Tailscale

## Cosa cambia

- `openclaw-manager.sh` non crea più il sidecar Tailscale con `docker run`.
- Ora usa il modulo standalone `tailscale-funnel-compose` come dipendenza esterna.
- Il wrapper cerca il modulo in quest'ordine:
  1. `REPO_TS_STACK_DIR`
  2. repo sibling `../tailscale-funnel-compose-standalone`
  3. repo sibling `../tailscale-funnel-compose`
  4. vendor locale `tailscale-funnel-compose/`
  5. installazione `/opt/tailscale-funnel-compose`

## Compatibilità mantenuta

- `start`, `stop`, `restart`, `status`, `status-full`, `tunnel-url`
- bootstrap automatico di Tailscale se `TS_AUTHKEY` è disponibile
- sync variabili `TS_AUTHKEY`, `TS_API_KEY`, `TS_TAILNET`, `TS_HOSTNAME`, `TS_CONTAINER_NAME`
- cleanup duplicati delegato allo stack standalone
- gestione servizi secondari tramite nuovi comandi:
  - `tailscale-add <name> <port> [path]`
  - `tailscale-remove <name>`

## Flusso operativo

```bash
./openclaw-manager.sh start
./openclaw-manager.sh tailscale-add grafana 3000 /grafana
./openclaw-manager.sh status-full
```
