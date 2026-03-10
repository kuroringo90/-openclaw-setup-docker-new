# QWEN handoff: split tra OpenClaw manager e dipendenza Tailscale Funnel

Questo pacchetto è organizzato per un nuovo branch in cui `tailscale-funnel-compose` diventa un progetto separato e riusabile anche da altri sistemi, mentre la logica OpenClaw resta in una cartella dedicata.

## Nuova struttura

```text
openclaw-tailscale-qwen-branch-separated/
├── openclaw-manager-system/
│   ├── openclaw-manager-tailscale.sh
│   ├── tailscale-add-service.sh
│   ├── README-WRAPPER.md
│   ├── MIGRATION.md
│   └── docker-compose.openclaw.example.yml
├── tailscale-funnel-compose/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── tailscale-funnel-compose.sh
│   ├── README.md
│   └── DEPENDENCY.md
└── MANIFEST.txt
```

## Intento architetturale

### `tailscale-funnel-compose/`

È una dipendenza standalone. Deve poter essere vendorizzata o inclusa da altri progetti senza portarsi dietro codice OpenClaw.

### `openclaw-manager-system/`

Contiene solo la logica specifica di OpenClaw e i wrapper di compatibilità. Deve consumare `tailscale-funnel-compose` come progetto sibling o tramite override `REPO_TS_STACK_DIR`.

## Cosa è già stato fatto

- separati i file OpenClaw in `openclaw-manager-system/`
- mantenuto `tailscale-funnel-compose/` come progetto autonomo
- corretti i path interni degli script per cercare il progetto Tailscale come sibling
- aggiunta documentazione `DEPENDENCY.md` per uso multi-progetto
- mantenuta compatibilità dei comandi operativi esistenti

## Cosa deve fare Qwen nel branch

1. mantenere questa separazione tra manager OpenClaw e progetto Tailscale
2. evitare riferimenti hardcoded che assumono `tailscale-funnel-compose` dentro la cartella OpenClaw
3. trattare `tailscale-funnel-compose` come dipendenza riusabile
4. aggiornare eventuali README del repo reale per riflettere il nuovo layout

## Test rapidi

```bash
chmod +x openclaw-manager-system/openclaw-manager-tailscale.sh \
         openclaw-manager-system/tailscale-add-service.sh \
         tailscale-funnel-compose/tailscale-funnel-compose.sh

cd openclaw-manager-system
./openclaw-manager-tailscale.sh start
./openclaw-manager-tailscale.sh tailscale-add grafana 3000 /grafana
./openclaw-manager-tailscale.sh status-full
```

## Nota di integrazione

Per usare il manager OpenClaw fuori da questo pacchetto, si può impostare:

```bash
export REPO_TS_STACK_DIR=/percorso/al/progetto/tailscale-funnel-compose
```

così gli script OpenClaw non dipendono dalla posizione fisica del repo.
