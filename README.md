# VPS / On-Premise — Working Local

Server setup, infrastructuur en documentatie voor Working Local platformen.
Beschikbaar in twee varianten: **VPS** (vast IP bij provider) en **On-Premise** (lokale hardware achter variabel IP).

## Varianten

| | VPS | On-Premise |
|---|---|---|
| Hardware | VPS bij provider | Lokale machine |
| IP | Vast | Variabel |
| Bereikbaarheid | Open poorten + DNS A-records | Cloudflare tunnel |
| Extra services | — | Cloudflared, Urbackup |
| Backup | iDrive (offsite) | Urbackup (target) + iDrive |

## Huidige VPS — VPS-WORKINGLOCAL

| Parameter | Waarde |
|---|---|
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB |
| CPU | 6× Intel Xeon E5-2680 v2 @ 2.80GHz |

## Services

| Service | Domein | Repo |
|---|---|---|
| Coolify | coolify.workinglocal.be | — |
| Focus Kiosk app | focus.workinglocal.be | [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) |
| Xibo CMS | signage.workinglocal.be | [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) |
| Netdata monitoring | metrics.workinglocal.be | [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) |
| Odoo CE | odoo.workinglocal.be | [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) |
| WordPress | wordpress.workinglocal.be | [wordpress-workinglocal](https://github.com/WorkingLocal/wordpress-workinglocal) |

## Repository structuur

```
vps-workinglocal/
├── docker-compose.onpremise.yml    # On-Premise extras (Cloudflared + Urbackup)
├── .env.onpremise.template         # Environment variables template voor On-Premise
├── setup/
│   ├── install-docker.sh           # Docker installeren (beide varianten)
│   ├── install-coolify.sh          # Coolify installeren (beide varianten)
│   ├── harden-server.sh            # Security hardening (beide varianten)
│   ├── configure-firewall.sh       # UFW firewall (VPS)
│   ├── configure-coolify-domain.sh # Coolify achter subdomein (VPS)
│   ├── reset-acme.sh               # SSL certificaten resetten (VPS)
│   ├── new-customer.sh             # Nieuwe klant uitrollen via Coolify API
│   └── setup-onpremise.sh          # On-Premise extras installeren
└── docs/
    ├── new-server-deployment.md    # Volledig stappenplan nieuwe VPS
    ├── onpremise.md                # On-Premise installatie en configuratie
    ├── architecture.md             # Serverarchitectuur en stack overzicht
    ├── dns.md                      # DNS instellingen per service
    └── reinstallation-guide.md     # Herinstallatie op bestaande VPS
```

## Snel starten

### VPS

```bash
bash setup/install-docker.sh
bash setup/configure-firewall.sh
bash setup/harden-server.sh
bash setup/install-coolify.sh
bash setup/configure-coolify-domain.sh <domein>
```

Zie [docs/new-server-deployment.md](docs/new-server-deployment.md) voor het volledige stappenplan.

### On-Premise

```bash
bash setup/install-docker.sh
bash setup/harden-server.sh
bash setup/install-coolify.sh
cp .env.onpremise.template .env
# Vul CLOUDFLARE_TUNNEL_TOKEN in
bash setup/setup-onpremise.sh
```

Zie [docs/onpremise.md](docs/onpremise.md) voor de volledige gids inclusief Cloudflare tunnel en Urbackup configuratie.
