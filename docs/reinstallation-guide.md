# VPS-WORKINGLOCAL — Volledige Herinstallatiegids

Dit document beschrijft hoe je de volledige Working Local VPS-stack opnieuw opzet op een nieuwe server.

## Vereisten

- Ubuntu 24.04 LTS (fresh install)
- Root SSH toegang
- Domeinen in Cloudflare met DNS A-records (zie [dns.md](dns.md))

---

## Stap 1 — Tijdzone instellen

```bash
timedatectl set-timezone Europe/Brussels
timedatectl
```

---

## Stap 2 — Docker installeren

```bash
bash setup/install-docker.sh
```

---

## Stap 3 — Firewall instellen

```bash
bash setup/configure-firewall.sh
```

---

## Stap 4 — Coolify installeren

```bash
bash setup/install-coolify.sh
```

Na installatie is Coolify bereikbaar op `http://<VPS-IP>:8000`.

> **Let op:** Poort 8000 is publiek toegankelijk tijdens de eerste setup. Na registratie is die alleen nog via SSH tunnel bereikbaar.

---

## Stap 5 — Coolify eerste setup

1. Ga naar `http://<VPS-IP>:8000/register`
2. Maak een admin account aan
3. Ga naar **Servers → Add Server → Localhost**
4. Valideer de server — als er een foutmelding verschijnt over poort 80:
   ```bash
   systemctl stop caddy
   systemctl disable caddy
   ```
   Valideer daarna opnieuw.
5. Hernoem het standaardproject naar **Working Local**

---

## Stap 6 — GitHub koppeling

1. In Coolify: **Settings → Source Control → GitHub**
2. Kies **GitHub App → New GitHub App**
3. Naam: `WorkingLocal`, Organisatie: `WorkingLocal`
4. Of gebruik **Public Repository** voor publieke repos (geen auth nodig)

---

## Stap 7 — Services deployen

Deploy in deze volgorde via **Projects → Working Local → production → + New Resource**:

### 7a — Focus App (Application)
- Source: GitHub → `WorkingLocal/focus-workinglocal`
- Branch: `master`
- Build Pack: `Dockerfile`
- Domain: `https://focus.workinglocal.be`
- Port: `3000`

### 7b — Netdata (Docker Compose)
- Plak inhoud van `metrics-workinglocal/docker-compose.yml`
- Name: `netdata-workinglocal`
- Domain: `https://metrics.workinglocal.be`

### 7c — Xibo CMS (Docker Compose)
- Plak inhoud van `signage-workinglocal/docker-compose.yml`
- Name: `xibo-workinglocal`
- Domain: `https://signage.workinglocal.be`
- Environment variabelen: zie `signage-workinglocal/config.env.template`

> **Let op:** Gebruik `mariadb:10.11` — MySQL 8.0 is niet compatibel met Xibo.
> **Let op:** Bind poort 8080 niet — conflicteert met `coolify-proxy`.

### 7d — Odoo CE (Docker Compose)
- Plak inhoud van `odoo-workinglocal/docker-compose.yml`
- Name: `odoo-workinglocal`
- Domain: `https://odoo.workinglocal.be`
- Environment variabelen: zie `odoo-workinglocal/.env.template`

---

## Stap 8 — Coolify dashboard beveiligen

Na de volledige setup: poort 8000 is al geblokkeerd door UFW.
Bereik het dashboard alleen via SSH tunnel:

```bash
ssh -L 8000:localhost:8000 root@<VPS-IP>
```

Dan: `http://localhost:8000`

---

## Verificatie

```bash
# Alle containers draaien?
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Services bereikbaar?
curl -sk https://focus.workinglocal.be -o /dev/null -w "%{http_code}\n"
curl -sk https://signage.workinglocal.be -o /dev/null -w "%{http_code}\n"
curl -sk https://metrics.workinglocal.be -o /dev/null -w "%{http_code}\n"
curl -sk https://odoo.workinglocal.be -o /dev/null -w "%{http_code}\n"

# Firewall correct?
ufw status verbose
```
