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

| Service | Domein | Repo |
|---|---|---|
| Coolify | coolify.workinglocal.be | — |
| Focus Kiosk app | focus.workinglocal.be | [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) |
| Xibo CMS | signage.workinglocal.be | [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) |
| Netdata monitoring | metrics.workinglocal.be | [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) |
| Odoo CE | odoo.workinglocal.be | [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) |
| WordPress | wordpress.workinglocal.be | [wordpress-workinglocal](https://github.com/WorkingLocal/wordpress-workinglocal) |
| Urbackup | backup.workinglocal.be | [backup-workinglocal](https://github.com/WorkingLocal/backup-workinglocal) |

## Repository structuur

```
vps-workinglocal/
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
