# Backup and Scheduling Options

Questo documento separa le opzioni operative per backup, health-check e scheduling del progetto, così possono essere studiate a parte rispetto alla README principale.

## 1. Docker Healthcheck and Restart Policy

- già fatto
- copre solo liveness/readiness del container
- non risolve backup schedulato

## 2. Scheduler Del Host

- `cron`, `systemd timer`, Jenkins, Nomad periodic, ecc.
- è ancora esterno, ma è il modo classico e robusto se il container gira su una VM o su un server dedicato

## 3. Container Dedicato Di Maintenance

- è l’alternativa più coerente col modello containerizzato
- aggiungi un secondo container tipo `openclaw-maintenance`
- monta gli stessi volumi dati
- esegue `backup` e `health-check` su schedule interna o con un piccolo supervisor
- vantaggio: tutto resta nel progetto Docker
- svantaggio: devi gestire scheduling e logging dentro un container in più

## 4. Orchestratore Container-Native

- Docker Swarm cron pattern, Kubernetes `CronJob`, Nomad periodic job
- se sei già su orchestratore, è la scelta giusta
- se sei su singolo host Docker Compose, spesso è overkill

## 5. Piattaforma Di Backup Volume-Level

- snapshot filesystem/LVM/ZFS/Btrfs
- snapshot del disco, della VM o del cloud volume
- è più infrastrutturale che applicativa
- ottimo per disaster recovery
- meno preciso per restore logico applicazione-specifico se usato da solo

## 6. Sidecar o Agent Di Backup

- Restic, Borg, Kopia, pattern tipo Velero
- un container o agent osserva i volumi e spedisce backup a S3, Backblaze o storage equivalente
- molto buono in produzione vera
- più serio di uno script `tar` locale
- richiede repository backup, retention e credenziali

## Scelte Sensate Per Questo Repo

- semplice e solida: `backup.sh` + scheduler host
- più cloud-native: maintenance container o agent tipo Restic/Kopia

## Raccomandazione Pratica

- tenere `backup.sh` e `health-check.sh` come primitive operative
- tenere `docker healthcheck` nel container principale
- se vuoi evitare scheduler host, aggiungere un container maintenance dedicato

Questa è l’alternativa non esterna che ha più senso per questo consumer repo.
