# Migrazione OpenClaw + Tailscale

## Cosa cambia

- `openclaw-manager.sh` non crea più il sidecar Tailscale con `docker run`.
- Ora installa e usa lo stack standalone in `~/.openclaw/tailscale-funnel`.
- I file sorgente dello stack vengono presi dalla cartella repo `tailscale-funnel-compose/`.

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
