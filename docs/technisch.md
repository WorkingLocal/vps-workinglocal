# Technische documentatie — VPS-WORKINGLOCAL

## Server

| Parameter | Waarde |
|---|---|
| Hostname | VPS-WORKINGLOCAL |
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| Tijdzone | Europe/Brussels (CEST) |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB SSD |
| CPU | 6× Intel Xeon E5-2680 v2 @ 2.80GHz |
| Provider | Hostinger KVM VPS |

## Architectuur

```
Internet
    │
    ▼
Cloudflare DNS (proxy UIT voor alle subdomeinen)
    │
    ▼
coolify-proxy (Traefik v3)
    │   SSL via Let's Encrypt (acme.json)
    │
    ├── coolify.workinglocal.be    → coolify:8080
    ├── odoo.workinglocal.be       → odoo:8069
    ├── signage.workinglocal.be    → xibo-cms:80
    ├── metrics.workinglocal.be    → netdata:19999
    ├── focus.workinglocal.be      → focus-app:3000
    ├── wordpress.workinglocal.be  → wordpress:80
    └── backup.workinglocal.be     → urbackup:55414

Coolify (https://coolify.workinglocal.be)
    → beheert alle Docker containers
    → auto-deploy via GitHub webhooks
```

## Stack

| Laag | Technologie | Versie |
|---|---|---|
| Container beheer | Coolify | 4.x |
| Reverse proxy + SSL | Traefik | v3 |
| Container runtime | Docker + Docker Compose | 27.x |
| OS | Ubuntu | 24.04 LTS |

## Services

| Service | Container / Proces | Poort intern | Repo |
|---|---|---|---|
| Coolify | `coolify` | 8080 | — |
| Odoo CE | `odoo` + `odoo-db` | 8069 | odoo-workinglocal |
| Xibo CMS | `xibo-cms` + `xibo-db` | 80 / 9505 | signage-workinglocal |
| Netdata | `netdata` | 19999 | metrics-workinglocal |
| Focus App | `focus-app` | 3000 | focus-workinglocal |
| WordPress | `wordpress` + `db` | 80 | wordpress-workinglocal |
| Urbackup | `urbackup` | 55414 | backup-workinglocal |
| **Blog Convertor** | systemd `blog-ui` (Node.js) | **3456** | vps-workinglocal `apps/blog-convertor/` |

## Blog Convertor

De Blog Convertor is een interne webapplicatie voor het automatisch herschrijven van Engelstalige blogartikelen naar Nederlands en het publiceren als concept in WordPress.

### Architectuur

```
Browser
  └─► http://VPS:3456   (Blog Convertor UI)
        └─► Node.js server (systemd service blog-ui)
              ├─► n8n webhook (docker intern: 172.18.0.3:5678)
              ├─► LiteLLM /models (Tailscale: 100.80.180.55:4000) — modellijst ophalen
              └─► Stats Service (Tailscale: 100.80.180.55:11435) — RAM/CPU visualisatie
```

### Bestandslocaties op VPS

| Bestand | Pad |
|---|---|
| Server script | `/opt/blog-ui/server.js` |
| Logo (wit) | `/opt/blog-ui/logo-white.png` |
| Systemd service | `/etc/systemd/system/blog-ui.service` |

### Beheer

```bash
# Status
systemctl status blog-ui

# Logs (live)
journalctl -u blog-ui -f

# Herstarten na update
cp server.js /opt/blog-ui/server.js
systemctl restart blog-ui
```

### Configuratie (constanten in server.js)

| Constante | Waarde | Omschrijving |
|---|---|---|
| `PORT` | `3456` | Luisterpoort webapplicatie |
| `N8N_HOST` | `172.18.0.3` | Interne Docker IP van n8n container |
| `N8N_PORT` | `5678` | n8n poort |
| `WORKFLOW_ID` | `kTy9n74V2kWvLMMM` | n8n workflow ID |
| `DB_CONTAINER` | `n8n-db-qmj...` | PostgreSQL container naam |
| `LITELLM_URL` | `http://100.80.180.55:4000` | LiteLLM via Tailscale |
| `LITELLM_KEY` | `HostingLocal2024` | LiteLLM master key |

### Afhankelijkheden (AI Engine)

De Blog Convertor communiceert via Tailscale met de AI Engine op `100.80.180.55`:

| Service | Poort | Gebruik |
|---|---|---|
| Ollama | 11434 | Modellen downloaden/beheren |
| LiteLLM | 4000 | OpenAI-compatibele proxy naar Ollama |
| Stats Service | 11435 | RAM/CPU visualisatie in UI |
| Image Gen Service | 11436 | Afbeeldingen genereren (SDXL / Replicate) |

---

## Firewall (UFW)

| Poort | Protocol | Dienst | Publiek |
|---|---|---|---|
| 22 | TCP | SSH | Ja |
| 80 | TCP | HTTP → HTTPS redirect | Ja |
| 443 | TCP/UDP | HTTPS | Ja |
| 9505 | TCP | Xibo XMR push | Ja |
| 55413 | TCP | Urbackup client discovery | Ja |
| 55415 | TCP | Urbackup internet clients | Ja |
| 8000 | TCP | Coolify intern | Nee |
| 19999 | TCP | Netdata intern | Nee |
| 6001-6002 | TCP | Coolify realtime | Nee |

## Security

| Maatregel | Configuratie |
|---|---|
| Firewall | UFW — standaard deny incoming |
| Docker poortbeveiliging | DOCKER-USER chain in `/etc/ufw/after.rules` |
| iptables persistent | `/etc/iptables/rules.v4` |
| SSH | `PasswordAuthentication no`, `PermitRootLogin prohibit-password` |
| SSH brute force | Fail2ban — ban na 3 pogingen / 24u |
| Automatische updates | unattended-upgrades actief |

## SSL certificaten

Beheerd door Traefik via Let's Encrypt ACME protocol.

- Configuratiebestand: `/data/coolify/proxy/acme.json`
- Vernieuwing: automatisch (30 dagen voor vervaldatum)
- Bij problemen: `bash setup/reset-acme.sh`

## Cloudflare DNS

Alle subdomeinen wijzen met **proxy UIT** (grijs wolkje) rechtstreeks naar `23.94.220.181`.

Redenen voor proxy UIT:
- WebSockets (Coolify terminal, Netdata live charts, Xibo XMR)
- Let's Encrypt HTTP challenge werkt niet via Cloudflare proxy
- Xibo XMR poort 9505 is niet beschikbaar via Cloudflare proxy

## Docker configuratie

```json
// /etc/docker/daemon.json
{
  "iptables": true
}
```

Docker iptables staat **aan** zodat containers externe diensten kunnen bereiken (WordPress admin updates, Odoo, etc.). Poortbeveiliging loopt via de DOCKER-USER iptables chain.

## Coolify configuratie

| Instelling | Waarde |
|---|---|
| FQDN | `https://coolify.workinglocal.be` |
| API | Ingeschakeld |
| Proxy | Traefik v3 (coolify-proxy container) |
| SSL | Let's Encrypt via Traefik |
| Database | PostgreSQL (coolify-db container) |

## Setup scripts

| Script | Doel |
|---|---|
| `setup/install-docker.sh` | Docker Engine + Docker Compose installeren |
| `setup/install-coolify.sh` | Coolify installeren |
| `setup/configure-firewall.sh` | UFW firewall configureren |
| `setup/harden-server.sh` | Security hardening (Fail2ban, SSH, Docker, DOCKER-USER) |
| `setup/configure-coolify-domain.sh` | Coolify achter subdomein zetten |
| `setup/reset-acme.sh` | Let's Encrypt certificaten resetten |
| `setup/new-customer.sh` | Nieuwe klant automatisch uitrollen via Coolify API |

## Klantuitrol

Het script `setup/new-customer.sh` gebruikt de Coolify API om automatisch een volledig klantplatform uit te rollen:

1. Nieuw project aanmaken in Coolify
2. Docker Compose services deployen (Odoo, Xibo, Netdata, Focus)
3. Environment variables instellen (gegenereerde wachtwoorden)
4. Services starten
5. Config opslaan in `customers/<naam>/config.env`

Vereisten: actieve SSH tunnel naar Coolify (poort 8000) of Coolify bereikbaar via subdomein.
