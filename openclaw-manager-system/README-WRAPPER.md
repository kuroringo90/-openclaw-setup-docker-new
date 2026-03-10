# Compatibilità `tailscale-add-service.sh`

Questa versione è un wrapper compatibile con il nuovo stack standalone Compose-first.

## Comandi supportati

```bash
./tailscale-add-service.sh grafana 3000 /grafana
./tailscale-add-service.sh add grafana 3000 /grafana
./tailscale-add-service.sh status
./tailscale-add-service.sh remove grafana
./tailscale-add-service.sh remove /grafana
./tailscale-add-service.sh remove
```

## Comportamento

- `add` delega a `tailscale-funnel-compose.sh add`
- mantiene il controllo duplicati del nuovo stack
- `remove /path` risolve il nome servizio dal registry locale
- `remove` senza argomenti esegue un reset totale della configurazione `serve/funnel` per compatibilità con lo script storico

## Nota importante

Dopo un `remove` senza argomenti, per ripristinare OpenClaw su `/` esegui:

```bash
./openclaw-manager.sh tailscale-config
```
