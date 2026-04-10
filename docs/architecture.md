# VPS-WORKINGLOCAL — Architectuur

## Server

| Parameter | Waarde |
|---|---|
| Hostname | VPS-WORKINGLOCAL |
| IP | 23.94.220.181 |
| OS | Ubuntu 24.04.4 LTS |
| RAM | 8 GB + 4 GB swap |
| Opslag | 150 GB |
| Node | AMS108KVM |

## Stack

```
Internet
    │
    ▼
Caddy (reverse proxy + automatisch SSL)  ← beheerd door Coolify
    │
    ├── focus.workinglocal.be    → Focus App container (:3000)
    ├── signage.workinglocal.be  → Xibo CMS container (:80)
    └── metrics.workinglocal.be  → Netdata container (:19999)

Coolify
    → beheert alle containers + deploys via GitHub webhooks
```

## Repositories

| Repo | Inhoud |
|---|---|
| [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) | Focus Kiosk app (Node.js) |
| [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) | Xibo CMS configuratie |
| [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) | Netdata monitoring configuratie |
| [vps-workinglocal](https://github.com/WorkingLocal/vps-workinglocal) | Server setup & infra docs |

## Firewall (UFW)

| Poort | Dienst |
|---|---|
| 22 | SSH |
| 80 | HTTP (Caddy redirect) |
| 443 | HTTPS (Caddy) |
| 8000 | Coolify dashboard (alleen lokaal via SSH tunnel) |
| 9505 | Xibo XMR push (direct, geen Cloudflare proxy) |
| 19999 | Netdata (intern, via Coolify/Caddy naar buiten) |
