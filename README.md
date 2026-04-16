# VPS — Working Local

Server setup, infrastructuur en documentatie voor VPS-WORKINGLOCAL.

> On-Premise installaties staan in [onpremise-workinglocal](https://github.com/WorkingLocal/onpremise-workinglocal).

## Huidige VPS — VPS-WORKINGLOCAL

| Parameter | Waarde |
|---|---|
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB |
| CPU | 6× Intel Xeon E5-2680 v2 @ 2.80GHz |

## Services

| Service | Domein / Poort | Repo |
|---|---|---|
| Coolify | coolify.workinglocal.be | — |
| Focus Kiosk app | focus.workinglocal.be | [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) |
| Xibo CMS | signage.workinglocal.be | [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) |
| Netdata monitoring | metrics.workinglocal.be | [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) |
| Odoo CE | odoo.workinglocal.be | [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) |
| WordPress | wordpress.workinglocal.be | [wordpress-workinglocal](https://github.com/WorkingLocal/wordpress-workinglocal) |
| Urbackup | backup.workinglocal.be | [backup-workinglocal](https://github.com/WorkingLocal/backup-workinglocal) |
| **Blog Convertor** | **:3456** (intern, geen domein) | deze repo (`apps/blog-convertor/`) |

## Repository structuur

```
vps-workinglocal/
├── apps/
│   └── blog-convertor/
│       ├── server.js               # Node.js webapplicatie (geen npm)
│       ├── blog-convertor.service  # systemd unit file (service naam: blog-ui)
│       └── install.sh              # Installatiescript
├── setup/
│   ├── install-docker.sh           # Docker installeren
│   ├── install-coolify.sh          # Coolify installeren
│   ├── harden-server.sh            # Security hardening
│   ├── configure-firewall.sh       # UFW firewall
│   ├── configure-coolify-domain.sh # Coolify achter subdomein
│   ├── reset-acme.sh               # SSL certificaten resetten
│   └── new-customer.sh             # Nieuwe klant uitrollen via Coolify API
└── docs/
    ├── new-server-deployment.md    # Volledig stappenplan nieuwe VPS
    ├── architecture.md             # Serverarchitectuur en stack overzicht
    ├── dns.md                      # DNS instellingen per service
    └── reinstallation-guide.md     # Herinstallatie op bestaande VPS
```

## Snel starten

```bash
bash setup/install-docker.sh
bash setup/configure-firewall.sh
bash setup/harden-server.sh
bash setup/install-coolify.sh
bash setup/configure-coolify-domain.sh <domein>
```

Zie [docs/new-server-deployment.md](docs/new-server-deployment.md) voor het volledige stappenplan.

## Blog Convertor UI

De Blog Convertor UI (`apps/blog-convertor/`) is een lichtgewicht Node.js webserver (geen npm, geen framework) die draait als systemd service `blog-ui` op poort 3456.

### Installatie

```bash
# Op de VPS (als root):
bash apps/blog-convertor/install.sh
```

### Wat het doet

- Formulier om een artikel-URL in te sturen met modelkeuzes
- Stuurt de aanvraag door naar n8n (`POST /webhook/blogartikel`)
- Volgt de voortgang via n8n's PostgreSQL database
- Toont RAM/CPU-gebruik van de AI Engine in realtime (via Stats Service poort 11435)
- Downloadknop voor vision-omschrijvingen van afbeeldingen per verwerkt artikel

### Configuratie in server.js

| Constante | Waarde | Beschrijving |
|---|---|---|
| `PORT` | `3456` | Poort waarop de UI luistert |
| `N8N_HOST` | `172.18.0.3` | Docker IP van n8n container |
| `N8N_PORT` | `5678` | n8n poort |
| `LITELLM_HOST` | `100.80.180.55` | AI Engine Tailscale IP |
| `LITELLM_PORT` | `4000` | LiteLLM proxy poort |
| `DB_CONTAINER` | `n8n-db-qmj0e07xtzyzn0rhfwh32ux4` | PostgreSQL container naam |

### API-routes

| Route | Methode | Beschrijving |
|---|---|---|
| `/` | GET | Serveert de HTML-UI |
| `/submit` | POST | Stuurt artikel door naar n8n, geeft `{ ok, jobId }` terug |
| `/api/status` | GET | Lijst van alle jobs met status en voortgang |
| `/api/models` | GET | Beschikbare tekstmodellen via LiteLLM (vision model gefilterd) |
| `/api/vision-models` | GET | Beschikbare vision modellen |
| `/api/system` | GET | RAM/CPU stats van AI Engine |
| `/api/descriptions` | POST | Callback van n8n met vision-omschrijvingen per uitvoering |
| `/api/descriptions/:execId` | GET | Download omschrijvingen als JSON-bestand |

### Webhook payload naar n8n

```json
{
  "source_url":    "https://example.com/artikel",
  "model":         "qwen2.5-7b",
  "vision_model":  "qwen2.5vl-7b",
  "image_backend": "local",
  "image_model":   "sdxl",
  "replicate_key": ""
}
```

### Deployen na wijzigingen

```bash
scp apps/blog-convertor/server.js root@23.94.220.181:/opt/blog-ui/server.js
ssh root@23.94.220.181 "systemctl restart blog-ui"
```

---

## Gerelateerde repositories

| Repo | Inhoud |
|---|---|
| [onpremise-workinglocal](https://github.com/WorkingLocal/onpremise-workinglocal) | On-Premise installatie + USB media |
| [backup-workinglocal](https://github.com/WorkingLocal/backup-workinglocal) | Urbackup server |
| [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) | Odoo CE + coworking addon |
| [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) | Xibo CMS |
| [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) | Netdata monitoring |
| [wordpress-workinglocal](https://github.com/WorkingLocal/wordpress-workinglocal) | WordPress website |
| [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) | Focus Kiosk app |
