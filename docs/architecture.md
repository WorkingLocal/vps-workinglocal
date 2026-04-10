# VPS-WORKINGLOCAL — Architectuur

## Server

| Parameter | Waarde |
|---|---|
| Hostname | VPS-WORKINGLOCAL |
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| Tijdzone | Europe/Brussels (CEST) |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB |
| CPU | 6x Intel Xeon E5-2680 v2 @ 2.80GHz |
| Node | AMS108KVM |

## Stack

```
Internet
    │
    ▼
coolify-proxy (Caddy — SSL + reverse proxy)
    │
    ├── focus.workinglocal.be    → focus-app container (:3000)
    ├── signage.workinglocal.be  → xibo-cms container (:80)
    ├── metrics.workinglocal.be  → netdata container (:19999)
    └── odoo.workinglocal.be     → odoo container (:8069)

Coolify (poort 8000 — intern via SSH tunnel bereikbaar)
    → beheert alle containers + deploys via GitHub webhooks
```

## Services — Status

| Service | Container | Domein | Status |
|---|---|---|---|
| Focus App | `focus-app` | focus.workinglocal.be | Live |
| Xibo CMS | `xibo-cms` + `xibo-db` | signage.workinglocal.be | Live |
| Netdata | `netdata` | metrics.workinglocal.be | Live |
| Odoo CE | `odoo` + `odoo-db` | odoo.workinglocal.be | Live |

## Repositories

| Repo | Inhoud |
|---|---|
| [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) | Focus Kiosk app (Node.js) |
| [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) | Xibo CMS configuratie |
| [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) | Netdata monitoring configuratie |
| [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) | Odoo CE + custom coworking addon |
| [vps-workinglocal](https://github.com/WorkingLocal/vps-workinglocal) | Server setup & infra docs |

## Firewall (UFW)

| Poort | Dienst | Opmerking |
|---|---|---|
| 22 | SSH | |
| 80 | HTTP | Caddy redirect naar HTTPS |
| 443 | HTTPS | Caddy |
| 8000 | Coolify dashboard | Alleen bereikbaar via SSH tunnel |
| 9505 | Xibo XMR push | Direct, geen Cloudflare proxy |
| 19999 | Netdata | Intern, via Coolify/Caddy naar buiten |

## Notities

- Native Caddy (`/etc/caddy/Caddyfile`) gestopt en uitgeschakeld — vervangen door `coolify-proxy`
- Focus App migratie van PM2 naar Docker container voltooid op 2026-04-10
- Tijdzone ingesteld op `Europe/Brussels` op 2026-04-10
