# Compatibilità `tailscale-add-service.sh`

Questa versione è un wrapper compatibile con il nuovo stack standalone Compose-first.

## Comandi supportati

```bash
./tailscale-add-service.sh grafana 3000 /grafana
./tailscale-add-service.sh add grafana 3000 /grafana
./tailscale-add-service.sh add grafana 3000 /grafana serve
./tailscale-add-service.sh status
./tailscale-add-service.sh remove grafana
./tailscale-add-service.sh remove /grafana
./tailscale-add-service.sh remove
```

## Comportamento

- `add` delega a `tailscale-funnel-compose.sh add`
- se il mode non è specificato, usa `funnel` come default
- `serve` abilita accesso solo tailnet
- il mixed-mode `funnel` + `serve` non è supportato sullo stesso hostname path-based
- mantiene il controllo duplicati del nuovo stack
- `remove /path` risolve il nome servizio dal registry locale
- `remove` senza argomenti esegue un reset totale della configurazione `serve/funnel` per compatibilità con lo script storico

## Risoluzione del modulo

Il wrapper cerca `tailscale-funnel-compose.sh` in questo ordine:

1. `REPO_TS_STACK_DIR`
2. `../tailscale-funnel-compose-standalone`
3. `../tailscale-funnel-compose`
4. `./tailscale-funnel-compose`
5. `/opt/tailscale-funnel-compose`

Il path preferito per sviluppo e produzione di questo repo è il modulo standalone sibling `../tailscale-funnel-compose-standalone`.

## Nota importante

Dopo un `remove` senza argomenti, per ripristinare OpenClaw su `/` esegui:

```bash
./openclaw-manager.sh tailscale-config
```
