# Stappenplan — Nieuwe server uitrollen

Dit document beschrijft het volledige proces om een Working Local platform op te zetten voor een nieuwe klant, van lege VPS tot volledig operationeel systeem.

---

## Overzicht

| Fase | Wat |
|---|---|
| 1 | VPS bestellen en toegang |
| 2 | Server basisinstallatie |
| 3 | Coolify installeren en subdomein instellen |
| 4 | DNS instellen |
| 5 | Services uitrollen via script |
| 6 | Services configureren (Odoo, Xibo, WordPress) |
| 7 | Verificatie |

---

## Vereisten

- Ubuntu 24.04 LTS VPS met minimaal **4 GB RAM**, **50 GB opslag**
- Root SSH toegang
- Domein beheerd in Cloudflare
- Lokaal: `bash`, `curl`, `jq`, `openssl` beschikbaar
- De `vps-workinglocal` repo gecloned:
  ```bash
  git clone https://github.com/WorkingLocal/vps-workinglocal.git
  cd vps-workinglocal
  ```

---

## Fase 1 — VPS bestellen en toegang

1. Bestel een VPS bij een provider naar keuze (bv. Hetzner, OVH, Hostinger)
   - OS: **Ubuntu 24.04 LTS**
   - Minimaal: 4 GB RAM, 2 vCPU, 50 GB opslag
2. Noteer het **IP-adres** van de VPS
3. Test SSH toegang:
   ```bash
   ssh root@<VPS-IP>
   ```

---

## Fase 2 — Server basisinstallatie

Voer alle commando's uit als `root` op de VPS.

### 2.1 — Tijdzone instellen

```bash
timedatectl set-timezone Europe/Brussels
timedatectl
```

### 2.2 — Docker installeren

```bash
bash setup/install-docker.sh
```

> **Verificatie:**
> ```bash
> docker --version
> docker compose version
> ```

### 2.3 — Firewall instellen

```bash
bash setup/configure-firewall.sh
```

Dit opent poorten 22 (SSH), 80 (HTTP), 443 (HTTPS), 9505 (Xibo XMR).

> **Verificatie:**
> ```bash
> ufw status verbose
> ```

### 2.4 — Security hardening

```bash
bash setup/harden-server.sh
```

Dit script voert automatisch uit:
- **Fail2ban** — blokkeert IP's na herhaalde mislukte SSH pogingen
- **SSH hardening** — wachtwoord-login uit, root enkel via key
- **Docker iptables** — aan laten staan (containers hebben internettoegang nodig voor updates e.d.)
- **DOCKER-USER chain** — poortbeveiliging via `/etc/ufw/after.rules`
- **iptables-persistent** — regels bewaard na reboot
- **PM2** uitschakelen indien aanwezig

> **Verificatie:**
> ```bash
> fail2ban-client status sshd
> grep -E 'PasswordAuthentication|PermitRootLogin' /etc/ssh/sshd_config
> cat /etc/docker/daemon.json
> ```

---

## Fase 3 — Coolify installeren en configureren

### 3.1 — Coolify installeren

```bash
bash setup/install-coolify.sh
```

Coolify installeert automatisch en start op poort 8000.

### 3.2 — Admin account aanmaken via SSH tunnel

Coolify is nog niet via een domein bereikbaar. Open tijdelijk een SSH tunnel:

```bash
ssh -L 8000:localhost:8000 root@<VPS-IP> -N
```

Ga naar **http://localhost:8000/register**, maak een admin account aan en log in.

### 3.3 — Localhost server toevoegen

1. Ga naar **Servers → Add New Server → Localhost**
2. Klik **Validate Server**

Als er een fout verschijnt over poort 80:
```bash
systemctl stop caddy && systemctl disable caddy
```

### 3.4 — API token aanmaken

1. Ga naar **Keys & Tokens → API Tokens → + New Token**
2. Naam: `deployment-script`
3. Kopieer het token — **je ziet het maar één keer**

### 3.5 — Coolify achter subdomein zetten

Voeg eerst een DNS A-record toe in Cloudflare:
```
Type: A | Naam: coolify | Waarde: <VPS-IP> | Proxy: UIT (grijs wolkje)
```

Voer daarna uit op de VPS:
```bash
bash setup/configure-coolify-domain.sh <DOMEIN>
# Voorbeeld: bash setup/configure-coolify-domain.sh workinglocal.be
```

Wacht tot het Let's Encrypt certificaat aangevraagd is (1-2 minuten), dan is Coolify bereikbaar via `https://coolify.<DOMEIN>`.

> Als HTTPS niet werkt (certificaatfout), run dan:
> ```bash
> bash setup/reset-acme.sh
> ```

---

## Fase 4 — DNS instellen

Voeg A-records toe in Cloudflare voor alle services:

| Type | Naam | Waarde | Proxy |
|---|---|---|---|
| A | `coolify` | `<VPS-IP>` | UIT (grijs) |
| A | `odoo` | `<VPS-IP>` | UIT (grijs) |
| A | `signage` | `<VPS-IP>` | UIT (grijs) |
| A | `metrics` | `<VPS-IP>` | UIT (grijs) |
| A | `focus` | `<VPS-IP>` | UIT (grijs) |
| A | `wordpress` | `<VPS-IP>` | UIT (grijs) |

> **Belangrijk:** Proxy moet **UIT** voor alle subdomeinen. Xibo XMR (poort 9505) en Coolify/Netdata (WebSockets) werken niet met Cloudflare proxy.

> **Verificatie:**
> ```bash
> dig odoo.<DOMEIN> +short
> ```

---

## Fase 5 — Services uitrollen via script

```bash
bash setup/new-customer.sh
```

Het script vraagt interactief om klantnaam, domein, VPS-IP en Coolify API token, en deployt automatisch:
- **Odoo CE** + custom coworking addon
- **Xibo CMS** + database
- **Netdata** monitoring
- **Focus App**

Config wordt opgeslagen in `customers/<naam>/config.env` (staat in `.gitignore`).

---

## Fase 6 — Services configureren

### 6.1 — WordPress deployen (website)

WordPress draait apart van de klantscripts. Deploy via Coolify:

1. **New Resource → Docker Compose**
2. Plak de inhoud van `wordpress-workinglocal/docker-compose.yml`
   - Geen `ports` sectie — Traefik routeert intern
3. Environment variables instellen:
   ```
   DB_NAME=wordpress
   DB_USER=wordpress
   DB_PASSWORD=<genereer: openssl rand -base64 32>
   DB_ROOT_PASSWORD=<genereer: openssl rand -base64 32>
   WP_TABLE_PREFIX=wp_
   ```
4. Domein instellen: `https://wordpress.<DOMEIN>` (zonder poortnummer)
5. Deploy

> Zie [wordpress-workinglocal/docs/migration.md](https://github.com/WorkingLocal/wordpress-workinglocal/blob/main/docs/migration.md) voor de volledige migratiestappen.

### 6.2 — Odoo: eerste database aanmaken

1. Ga naar `https://odoo.<DOMEIN>/web/database/manager`
2. **Create Database** — gebruik `ODOO_MASTER_PASSWORD` uit `customers/<naam>/config.env`
3. Taal: Nederlands, Land: Belgium

### 6.3 — Odoo: custom addon installeren

1. Ga naar `https://odoo.<DOMEIN>/web?debug=1` → **Apps → Update Apps List**
2. Zoek op `coworking` → **Installeer Working Local — Coworking Reservaties**

### 6.4 — Xibo: eerste login

1. Ga naar `https://signage.<DOMEIN>`
2. Login: `xibo_admin` / `password`
3. **Wijzig het wachtwoord onmiddellijk**

### 6.5 — Netdata alerts configureren

```bash
bash metrics-workinglocal/deploy-config.sh <VPS-IP> --smtp-password <smtp-wachtwoord>
```

### 6.6 — SSL certificaten

Als certificaten niet automatisch aangevraagd worden (DNS was te traag):
```bash
bash setup/reset-acme.sh
```

---

## Fase 7 — Verificatie

### Containers controleren

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

### Services bereikbaar

```bash
DOMEIN="<domein>"
for sub in coolify odoo signage metrics focus wordpress; do
    CODE=$(curl -sk "https://${sub}.${DOMEIN}" -o /dev/null -w "%{http_code}")
    echo "${sub}.${DOMEIN} → HTTP ${CODE}"
done
```

### Internettoegang containers testen

```bash
docker exec <wordpress-container> curl -s --max-time 5 https://api.wordpress.org/ -o /dev/null -w '%{http_code}'
# Verwacht: 200
```

### Firewall

```bash
ufw status verbose
```

---

## Problemen oplossen

### Services niet bereikbaar van buitenaf (maar containers draaien wel)

**Symptoom:** `curl https://<service>.<domein>` time-out, SSH werkt nog wel.

**Oorzaak:** De DOCKER-USER iptables chain blokkeert extern verkeer naar Docker-containers.
Dit treedt op als UFW verwijderd of gereset werd terwijl `iptables-persistent` de DROP-regels
bleef laden met een lege `ufw-user-forward` chain.

**Diagnose:**
```bash
# Controleer of pakketjes worden gedropped naar Docker-interne IPs
iptables -L DOCKER-USER -n -v | grep DROP
# Als pkts > 0 bij de DROP regels voor 10.0.0.0/8 → dit is het probleem

# Controleer ufw-user-forward chain
iptables -L ufw-user-forward -n -v
# Moet ACCEPT regels hebben voor poort 80/443
```

**Fix:**
```bash
# Poorten 80/443/9505 direct accepteren in ufw-user-forward
iptables -I ufw-user-forward 1 -p tcp --dport 443 -j ACCEPT
iptables -I ufw-user-forward 1 -p udp --dport 443 -j ACCEPT
iptables -I ufw-user-forward 1 -p tcp --dport 80 -j ACCEPT
iptables -I ufw-user-forward 1 -p tcp --dport 9505 -j ACCEPT
# Persistent opslaan
iptables-save > /etc/iptables/rules.v4
```

**Permanente fix (als UFW beschikbaar):**
```bash
apt-get install -y ufw
bash setup/configure-firewall.sh   # includeert ufw route allow
bash setup/harden-server.sh        # herlaadt DOCKER-USER met directe ACCEPT regels
```

> **Opmerking:** Zowel `configure-firewall.sh` als `harden-server.sh` zijn nu bijgewerkt
> zodat dit bij een nieuwe installatie niet meer voorkomt. `harden-server.sh` bakt de
> ACCEPT regels direct in DOCKER-USER (niet via UFW), zodat ze ook overleven als UFW
> later verwijderd wordt.

### SSL certificaat niet aangevraagd

DNS was nog niet gepropageerd toen Traefik het certificaat probeerde aan te vragen:
```bash
bash setup/reset-acme.sh
```

### SSL certificaat Traefik ACME time-out (specifieke service)

**Symptoom:** Traefik logs tonen herhaalde `Timeout during connect` voor één service,
andere services krijgen wél een cert.

**Oorzaak:** Traefik's ingebouwde ACME HTTP-01 challenge werkt niet voor die service
(bekende intermittente bug). Certbot standalone werkt wél.

**Fix:**
```bash
docker stop coolify-proxy
certbot certonly --standalone --non-interactive --agree-tos \
    -m <email> -d <subdomein>.<domein>
docker start coolify-proxy

# Cert beschikbaar maken voor Traefik via file provider
mkdir -p /data/coolify/proxy/certs/<subdomein>.<domein>
cp /etc/letsencrypt/live/<subdomein>.<domein>/fullchain.pem /data/coolify/proxy/certs/<subdomein>.<domein>/
cp /etc/letsencrypt/live/<subdomein>.<domein>/privkey.pem /data/coolify/proxy/certs/<subdomein>.<domein>/
chmod 600 /data/coolify/proxy/certs/<subdomein>.<domein>/privkey.pem

cat > /data/coolify/proxy/dynamic/<subdomein>-cert.yaml << EOF
tls:
  certificates:
    - certFile: /traefik/certs/<subdomein>.<domein>/fullchain.pem
      keyFile: /traefik/certs/<subdomein>.<domein>/privkey.pem
EOF
```

Certbot renewal hooks instellen zodat het cert automatisch verlengd wordt:
```bash
# /etc/letsencrypt/renewal-hooks/pre/stop-traefik.sh
echo '#!/bin/bash
docker stop coolify-proxy && sleep 2' > /etc/letsencrypt/renewal-hooks/pre/stop-traefik.sh

# /etc/letsencrypt/renewal-hooks/post/start-traefik.sh
echo '#!/bin/bash
docker start coolify-proxy' > /etc/letsencrypt/renewal-hooks/post/start-traefik.sh

# /etc/letsencrypt/renewal-hooks/deploy/copy-cert.sh
cat > /etc/letsencrypt/renewal-hooks/deploy/copy-cert.sh << 'HOOK'
#!/bin/bash
SUBDOMAIN=$(basename "$RENEWED_LINEAGE")
if [ -d "/data/coolify/proxy/certs/$SUBDOMAIN" ]; then
    cp "$RENEWED_LINEAGE/fullchain.pem" "/data/coolify/proxy/certs/$SUBDOMAIN/"
    cp "$RENEWED_LINEAGE/privkey.pem" "/data/coolify/proxy/certs/$SUBDOMAIN/"
    chmod 600 "/data/coolify/proxy/certs/$SUBDOMAIN/privkey.pem"
fi
HOOK

chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-traefik.sh
chmod +x /etc/letsencrypt/renewal-hooks/post/start-traefik.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/copy-cert.sh
```

### Containers hebben geen internettoegang

Controleer `daemon.json`:
```bash
cat /etc/docker/daemon.json
# Moet zijn: {"iptables": true}
```

Als `"iptables": false` staat: run `bash setup/harden-server.sh` opnieuw.

### Coolify bereikbaar maar service start niet

Controleer de logs in Coolify: **Project → Service → Logs**

### WordPress admin traag

Controleer of containers internet kunnen bereiken:
```bash
docker exec <wordpress-container> curl -s --max-time 10 https://api.wordpress.org/ -o /dev/null -w '%{time_total}s'
# Moet onder 1 seconde zijn
```

### Odoo addon niet zichtbaar

Herstart de `odoo-addons` container via Coolify — de laatste log moet `Addons gesynchroniseerd` zijn.

### Xibo XMR werkt niet

Controleer dat `signage.<DOMEIN>` zonder Cloudflare proxy staat en poort 9505 open is:
```bash
iptables -L ufw-user-forward -n | grep 9505
```

---

## Gerelateerde documentatie

- [architecture.md](architecture.md) — serverarchitectuur en stack overzicht
- [dns.md](dns.md) — DNS configuratie details
- [reinstallation-guide.md](reinstallation-guide.md) — herinstallatie op bestaande VPS
