# On-Premise installatie — Working Local

## Overzicht

De On-Premise versie draait dezelfde services als de VPS maar op lokale hardware achter een variabel IP-adres (thuisnetwerk, coworkingspace, kantoor). In plaats van open poorten en vaste DNS gebruikt het een **Cloudflare tunnel** voor veilige bereikbaarheid zonder poorten te openen.

## Verschil VPS vs On-Premise

| Aspect | VPS | On-Premise |
|---|---|---|
| IP-adres | Vast | Variabel |
| Bereikbaarheid | Open poorten + DNS A-records | Cloudflare tunnel (geen open poorten) |
| Firewall | UFW strikt | Minder kritisch (achter router NAT) |
| Backup | Offsite naar iDrive | Ontvangt backups van andere toestellen (Urbackup) + iDrive |
| Extra services | — | Cloudflared, Urbackup |
| Hardware | VPS bij provider | Lokale machine (mini-PC, NAS, server) |

## Architectuur

```
Toestellen (laptop, workstation)
    │ Urbackup client
    ▼
┌─────────────────────────────┐
│  On-Premise machine          │
│                              │
│  Coolify (beheer)            │
│  ├── Odoo                   │
│  ├── Xibo CMS               │
│  ├── WordPress              │
│  ├── Netdata                │
│  ├── Focus App              │
│  ├── Cloudflared ──────────────→ Cloudflare tunnel → Internet
│  └── Urbackup server        │
│                              │
│  iDrive agent ─────────────────→ iDrive cloud (offsite)
└─────────────────────────────┘
```

## Vereisten

- Ubuntu 24.04 LTS (of compatibele distro)
- Minimaal 8 GB RAM, 4 vCPU, 500 GB opslag
- Docker + Docker Compose
- Coolify geïnstalleerd
- Cloudflare account (gratis tier volstaat)
- iDrive account

## Stap 1 — Basisinstallatie

Volg dezelfde stappen als de VPS installatie:

```bash
bash setup/install-docker.sh
bash setup/harden-server.sh
bash setup/install-coolify.sh
```

> `configure-firewall.sh` is optioneel op On-Premise — de router NAT beschermt al.
> Run het wel als de machine direct op internet hangt.

## Stap 2 — Cloudflare tunnel aanmaken

1. Ga naar **Cloudflare dashboard → Zero Trust → Networks → Tunnels**
2. Klik **Create tunnel → Cloudflared**
3. Geef de tunnel een naam, bv. `workinglocal-onpremise`
4. Kopieer het **tunnel token**
5. Voeg **Public Hostnames** toe voor elke service:

| Subdomein | Service | Poort |
|---|---|---|
| `coolify.<domein>` | `http://coolify:8080` | — |
| `odoo.<domein>` | `http://odoo:8069` | — |
| `signage.<domein>` | `http://xibo-cms:80` | — |
| `metrics.<domein>` | `http://netdata:19999` | — |
| `focus.<domein>` | `http://focus-app:3000` | — |
| `wordpress.<domein>` | `http://wordpress:80` | — |
| `backup.<domein>` | `http://urbackup:55414` | — |

> Cloudflare handelt SSL automatisch af — geen Let's Encrypt nodig op On-Premise.

## Stap 3 — .env aanmaken

```bash
cp .env.onpremise.template .env
nano .env
# Vul CLOUDFLARE_TUNNEL_TOKEN in
```

## Stap 4 — On-Premise services starten

```bash
bash setup/setup-onpremise.sh
```

Dit start:
- **Cloudflared** — tunnel naar Cloudflare
- **Urbackup server** — backup target voor andere toestellen
- **iDrive agent** installatie (interactief configureren nadien)

## Stap 5 — Urbackup clients installeren

Installeer de Urbackup client op elk toestel dat gebackupt moet worden:

| Platform | Download |
|---|---|
| Windows | https://www.urbackup.org/download.html |
| macOS | https://www.urbackup.org/download.html |
| Linux | `apt install urbackup-client` |

Configureer de client om te verbinden met het IP van de On-Premise machine.

Beheer via de web UI: `https://backup.<domein>` (via Cloudflare tunnel)

## Stap 6 — iDrive configureren

```bash
idrivem
```

Stel in:
- iDrive account credentials
- Backup pad: `/var/lib/docker/volumes/` (alle Docker volumes)
- Schema: dagelijks, bv. 03:00

## Stap 7 — Netdata alerts aanpassen

Op On-Premise is er geen vast IP voor Netdata SMTP. Configureer alerts:

```bash
bash metrics-workinglocal/deploy-config.sh <lokaal-IP> --smtp-password <wachtwoord>
```

## DNS — Cloudflare tunnel vs A-records

Op de VPS gebruik je A-records die wijzen naar het vaste IP.
Op On-Premise configureert Cloudflare de DNS automatisch via de tunnel hostnames — geen A-records nodig.

| VPS | On-Premise |
|---|---|
| A-record `odoo` → `23.94.220.181` | Tunnel hostname `odoo.<domein>` → `http://odoo:8069` |
| Let's Encrypt via Traefik | SSL via Cloudflare (automatisch) |
| Poorten open in UFW | Geen open poorten nodig |

## Poorten Urbackup (lokaal netwerk)

Urbackup clients in hetzelfde lokale netwerk verbinden via LAN-discovery zonder open poorten.
Voor clients van buiten het netwerk (via internet):

| Poort | Protocol | Doel |
|---|---|---|
| 55413 | TCP | Client discovery |
| 55414 | TCP | Web UI + client communicatie |
| 55415 | TCP | Internet client protocol |

> Open deze poorten enkel in de router als je Urbackup clients van buiten wil toelaten.
> Clients in hetzelfde netwerk werken zonder open poorten.
