# VPS — Working Local

Server setup, infrastructuur en documentatie voor VPS-WORKINGLOCAL.

## Server

| Parameter | Waarde |
|---|---|
| Hostname | VPS-WORKINGLOCAL |
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB |
| CPU | 6× Intel Xeon E5-2680 v2 @ 2.80GHz |

## Stack

```
Internet
    │
    ▼
coolify-proxy (Caddy — SSL + reverse proxy)
    │
    ├── focus.workinglocal.be    → Focus Kiosk app (:3000)
    ├── signage.workinglocal.be  → Xibo CMS (:80)
    ├── metrics.workinglocal.be  → Netdata (:19999)
    └── odoo.workinglocal.be     → Odoo CE (:8069)

Coolify (poort 8000 — bereikbaar via SSH tunnel)
    → beheert alle containers + auto-deploy via GitHub webhooks
```

## Services

| Service | Domein | Repo |
|---|---|---|
| Focus Kiosk app | focus.workinglocal.be | [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) |
| Xibo CMS | signage.workinglocal.be | [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) |
| Netdata monitoring | metrics.workinglocal.be | [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) |
| Odoo CE | odoo.workinglocal.be | [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) |

## Firewall (UFW)

| Poort | Dienst | Opmerking |
|---|---|---|
| 22 | SSH | |
| 80 | HTTP | Caddy redirect naar HTTPS |
| 443 | HTTPS | Caddy |
| 8000 | Coolify dashboard | Alleen via SSH tunnel |
| 9505 | Xibo XMR push | Direct, geen Cloudflare proxy |

## Documentatie

- [docs/new-server-deployment.md](docs/new-server-deployment.md) — **volledig stappenplan voor nieuwe klantuitrol**
- [docs/architecture.md](docs/architecture.md) — serverarchitectuur en stack overzicht
- [docs/dns.md](docs/dns.md) — DNS instellingen per service
- [docs/reinstallation-guide.md](docs/reinstallation-guide.md) — herinstallatie op bestaande Working Local VPS
