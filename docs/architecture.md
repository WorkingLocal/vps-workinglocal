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
coolify-proxy (Traefik — SSL + reverse proxy)
    │
    ├── coolify.workinglocal.be   → coolify container (:8080)
    ├── focus.workinglocal.be     → focus-app container (:3000)
    ├── signage.workinglocal.be   → xibo-cms container (:80)
    ├── metrics.workinglocal.be   → netdata container (:19999)
    ├── odoo.workinglocal.be      → odoo container (:8069)
    └── wordpress.workinglocal.be → wordpress container (:80)

Coolify (https://coolify.workinglocal.be)
    → beheert alle containers + deploys via GitHub
```

## Services — Status

| Service | Container | Domein | Status |
|---|---|---|---|
| Coolify | `coolify` | coolify.workinglocal.be | Live |
| Focus App | `focus-app` | focus.workinglocal.be | Live |
| Xibo CMS | `xibo-cms` + `xibo-db` | signage.workinglocal.be | Live |
| Netdata | `netdata` | metrics.workinglocal.be | Live |
| Odoo CE | `odoo` + `odoo-db` | odoo.workinglocal.be | Live |
| WordPress | `wordpress` + `db` | wordpress.workinglocal.be | Live |

## Repositories

| Repo | Inhoud |
|---|---|
| [focus-workinglocal](https://github.com/WorkingLocal/focus-workinglocal) | Focus Kiosk app (Node.js) |
| [signage-workinglocal](https://github.com/WorkingLocal/signage-workinglocal) | Xibo CMS configuratie |
| [metrics-workinglocal](https://github.com/WorkingLocal/metrics-workinglocal) | Netdata monitoring configuratie |
| [odoo-workinglocal](https://github.com/WorkingLocal/odoo-workinglocal) | Odoo CE + custom coworking addon |
| [wordpress-workinglocal](https://github.com/WorkingLocal/wordpress-workinglocal) | WordPress website workinglocal.be |
| [vps-workinglocal](https://github.com/WorkingLocal/vps-workinglocal) | Server setup & infra docs |

## Firewall

| Poort | Dienst | Publiek |
|---|---|---|
| 22 | SSH | Ja |
| 80 | HTTP | Ja (redirect naar HTTPS) |
| 443 | HTTPS | Ja |
| 9505 | Xibo XMR push | Ja (geen Cloudflare proxy) |
| 8000 | Coolify intern | Nee (via `coolify.workinglocal.be`) |
| 19999 | Netdata intern | Nee (via `metrics.workinglocal.be`) |
| 6001-6002 | Coolify realtime | Nee (intern Docker) |

## Security

| Maatregel | Status |
|---|---|
| UFW firewall | Actief — enkel 22, 80, 443, 9505 publiek |
| Docker iptables | Aan — containers hebben internettoegang nodig |
| DOCKER-USER chain | Geconfigureerd via `/etc/ufw/after.rules` |
| iptables-persistent | Actief — regels bewaard na reboot |
| SSH wachtwoord-login | Uitgeschakeld (`PasswordAuthentication no`) |
| SSH root login | Enkel via key (`PermitRootLogin prohibit-password`) |
| Fail2ban | Actief — SSH brute force, ban na 3 pogingen / 24u |
| Unattended upgrades | Actief — automatische security patches |

## SSL Certificaten

Alle HTTPS-certificaten worden beheerd door Traefik (`coolify-proxy`) via Let's Encrypt.
Certificaten worden automatisch aangevraagd bij de eerste request op een domein.

Configuratiebestand: `/data/coolify/proxy/acme.json`

Bij problemen (DNS was niet actief tijdens eerste request):
```bash
bash setup/reset-acme.sh
```

## Cloudflare DNS instellingen

| Subdomein | Proxy | Reden |
|---|---|---|
| `coolify` | UIT (grijs) | WebSockets voor terminal |
| `metrics` | UIT (grijs) | WebSockets voor live charts |
| `signage` | UIT (grijs) | XMR push poort 9505 |
| `odoo` | UIT (grijs) | WebSockets voor live updates |
| `focus` | UIT (grijs) | WebSockets |
| `wordpress` | UIT (grijs) | Let's Encrypt challenge |

## Notities

- Native Caddy (`/etc/caddy/Caddyfile`) gestopt en uitgeschakeld — vervangen door `coolify-proxy` (Traefik)
- Focus App migratie van PM2 naar Docker container voltooid op 2026-04-10
- PM2 uitgeschakeld op 2026-04-11
- Security hardening uitgevoerd op 2026-04-11
- Coolify dashboard verplaatst van SSH tunnel naar `coolify.workinglocal.be` op 2026-04-11
- WordPress website gemigreerd van Hostinger naar VPS op 2026-04-11
- Docker iptables teruggezet naar `true` op 2026-04-11 (containers hadden geen internettoegang)
