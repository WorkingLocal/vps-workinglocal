# Stappenplan — Nieuwe server uitrollen

Dit document beschrijft het volledige proces om een Working Local platform op te zetten voor een nieuwe klant, van lege VPS tot volledig operationeel systeem.

---

## Overzicht

| Fase | Wat | Tijd (schatting) |
|---|---|---|
| 1 | VPS bestellen en toegang | 5 min |
| 2 | Server basisinstallatie | 10 min |
| 3 | Coolify installeren en configureren | 10 min |
| 4 | DNS instellen | 5 min |
| 5 | Services uitrollen via script | 10 min |
| 6 | Services configureren (Odoo, Xibo) | 15 min |
| 7 | Verificatie | 5 min |

**Totaal: ±1 uur** (excl. DNS propagatie)

---

## Vereisten

- Ubuntu 24.04 LTS VPS met minimaal **4 GB RAM**, **50 GB opslag**
- Root SSH toegang
- Domein beheerd in Cloudflare
- Lokaal: `bash`, `curl`, `jq`, `openssl` beschikbaar (standaard op macOS/Linux)
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

Verwachte output: `Time zone: Europe/Brussels (CEST, +0200)`

### 2.2 — Docker installeren

```bash
bash setup/install-docker.sh
```

Verwachte output: `Docker version 27.x.x` en `Docker Compose version v2.x.x`

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
Poorten 8000, 8080, 19999, 6001, 6002 worden expliciet geblokkeerd.

> **Verificatie:**
> ```bash
> ufw status verbose
> ```

### 2.4 — Security hardening

```bash
bash setup/harden-server.sh
```

Dit script voert automatisch uit:
- **Fail2ban** installeren — blokkeert IP's na herhaalde mislukte SSH pogingen
- **SSH** hardening — wachtwoord-login uit, root enkel via key (`prohibit-password`)
- **Docker UFW bypass** blokkeren — Docker omzeilt anders de firewall voor intern-only poorten
- **PM2** uitschakelen — overblijfsel van pre-Docker setup

> **Verificatie:**
> ```bash
> fail2ban-client status sshd
> grep -E 'PasswordAuthentication|PermitRootLogin' /etc/ssh/sshd_config
> ```

---

## Fase 3 — Coolify installeren en configureren

### 3.1 — Coolify installeren

```bash
bash setup/install-coolify.sh
```

Coolify installeert automatisch en start op poort 8000.

### 3.2 — Coolify dashboard openen

Coolify is **niet publiek bereikbaar** (poort 8000 is geblokkeerd door UFW).
Open een SSH tunnel vanuit je lokale machine:

```bash
ssh -L 8000:localhost:8000 root@<VPS-IP>
```

Ga dan naar: **http://localhost:8000**

> Laat deze terminal open zolang je Coolify gebruikt.

### 3.3 — Admin account aanmaken

1. Ga naar **http://localhost:8000/register**
2. Vul een e-mailadres en wachtwoord in
3. Log in

### 3.4 — Localhost server toevoegen

1. Ga naar **Servers → Add New Server**
2. Kies **Localhost**
3. Klik **Validate Server**

Als er een fout verschijnt over poort 80:
```bash
# Op de VPS:
systemctl stop caddy
systemctl disable caddy
```
Klik daarna opnieuw op **Validate Server**.

### 3.5 — API token aanmaken

Dit token is nodig voor het uitrolscript.

1. Ga naar **Keys & Tokens → API Tokens**
2. Klik **+ New Token**
3. Naam: `deployment-script`
4. Klik **Create** en kopieer het token — **je ziet het maar één keer**

---

## Fase 4 — DNS instellen

Doe dit in Cloudflare (of de DNS provider van de klant).

Voeg voor elk subdomein een **A-record** toe:

| Type | Naam | Waarde | Proxy |
|---|---|---|---|
| A | `odoo` | `<VPS-IP>` | DNS only (grijs wolkje) |
| A | `signage` | `<VPS-IP>` | DNS only (grijs wolkje) |
| A | `metrics` | `<VPS-IP>` | DNS only (grijs wolkje) |
| A | `focus` | `<VPS-IP>` | DNS only (grijs wolkje) |

> **Belangrijk:** Proxy moet **UIT** (grijs wolkje) voor alle vier. Cloudflare proxy blokkeert de Xibo XMR-poort 9505.

DNS propagatie via Cloudflare duurt doorgaans minder dan 5 minuten.

> **Verificatie** (wacht tot propagatie klaar is):
> ```bash
> dig odoo.<DOMEIN> +short
> # Moet het VPS-IP teruggeven
> ```

---

## Fase 5 — Services uitrollen via script

Het script `setup/new-customer.sh` regelt alle Coolify API-calls automatisch.

### 5.1 — Script uitvoeren

Voer het script uit **vanuit de `vps-workinglocal` map op je lokale machine** (met SSH tunnel actief op poort 8000):

```bash
bash setup/new-customer.sh
```

Het script vraagt interactief:

| Vraag | Voorbeeld |
|---|---|
| Klantnaam | `acme` |
| Hoofddomein | `acme.be` |
| VPS IP-adres | `1.2.3.4` |
| Coolify API token | *(token uit stap 3.5)* |
| Welke services | `alles` |

### 5.2 — Wat het script doet

1. Verbinding testen met Coolify API
2. Server UUID ophalen
3. Nieuw project aanmaken: `Working Local — acme`
4. Vier services deployen via Coolify API:
   - **Odoo** (Docker Compose uit `odoo-workinglocal`)
   - **Xibo CMS** (Docker Compose uit `signage-workinglocal`)
   - **Netdata** (Docker Compose uit `metrics-workinglocal`)
   - **Focus App** (GitHub repo `focus-workinglocal`, Dockerfile build)
5. Willekeurige wachtwoorden genereren en instellen als environment variabelen
6. Alle services starten
7. Klantconfig opslaan in `customers/acme/config.env`
8. DNS instructies opslaan in `customers/acme/DNS.md`

### 5.3 — Output controleren

Het script toont groene vinkjes per stap. Eventuele waarschuwingen (geel) betekenen dat je die stap manueel moet afwerken in Coolify.

Aan het einde zie je een samenvatting:

```
Services gedeployd voor acme:
  ● Odoo CE       → https://odoo.acme.be
  ● Xibo CMS      → https://signage.acme.be
  ● Netdata       → https://metrics.acme.be
  ● Focus App     → https://focus.acme.be

Config opgeslagen in: customers/acme/config.env
```

> **Bewaar `customers/acme/config.env` veilig.** Dit bestand bevat alle wachtwoorden.
> Het staat in `.gitignore` en wordt nooit gecommit.

---

## Fase 6 — Services configureren

Wacht tot alle containers groen zijn in Coolify (doorgaans 2–5 minuten na het starten).

### 6.1 — Odoo: eerste database aanmaken

1. Ga naar `https://odoo.<DOMEIN>/web/database/manager`
2. Klik **Create Database**
3. Vul in:
   - **Master Password:** *(zie `customers/<naam>/config.env` → `ODOO_MASTER_PASSWORD`)*
   - **Database Name:** `workinglocal` (of naam naar keuze)
   - **Language:** Nederlands
   - **Country:** Belgium
4. Klik **Create**
5. Log in als admin

### 6.2 — Odoo: custom addon installeren

1. Ga naar **Apps** (raster-icoon linksboven)
2. Klik **Update Apps List** (developer mode vereist — ga eerst naar `https://odoo.<DOMEIN>/web?debug=1`)
3. Zoek op `coworking` of `Working Local`
4. Klik **Installeer** op **Working Local — Coworking Reservaties**

De installatie duurt 1–2 minuten. Na installatie verschijnt het **Working Local** menu in de navigatie.

### 6.3 — Xibo: eerste login en wachtwoord wijzigen

1. Ga naar `https://signage.<DOMEIN>`
2. Log in met:
   - Gebruiker: `xibo_admin`
   - Wachtwoord: `password`
3. **Wijzig het wachtwoord onmiddellijk** via het gebruikersmenu rechtsboven

### 6.4 — Xibo: Odoo integratie instellen

1. Ga in Xibo naar **DataSets → + Add DataSet**
2. Kies **Remote DataSet**
3. Vul in:
   - URL: `https://odoo.<DOMEIN>/api/workspaces/availability`
   - Refresh interval: `60` seconden
   - Data path: `workspaces`
4. Definieer kolommen: `name`, `type`, `available`, `capacity`, `is_occupied`

Zie [odoo-workinglocal/docs/xibo-integration.md](https://github.com/WorkingLocal/odoo-workinglocal/blob/main/docs/xibo-integration.md) voor de volledige integratie setup.

### 6.5 — Focus App: operator URL

De Focus App is direct bruikbaar. De operator-URL (met geheim):

```
https://focus.<DOMEIN>/?key=<FOCUS_OPERATOR_SECRET>
```

Het `FOCUS_OPERATOR_SECRET` staat in `customers/<naam>/config.env`.

---

## Fase 7 — Verificatie

### 7.1 — Containers controleren

```bash
# Op de VPS:
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
```

Alle relevante containers moeten `Up` tonen.

### 7.2 — Services bereikbaar

```bash
# Vervang DOMEIN door het klantdomein
DOMEIN="acme.be"
for sub in odoo signage metrics focus; do
    CODE=$(curl -sk "https://${sub}.${DOMEIN}" -o /dev/null -w "%{http_code}")
    echo "${sub}.${DOMEIN} → HTTP ${CODE}"
done
```

Verwachte output: alle vier `200` of `302` (redirect naar login).

### 7.3 — Xibo endpoint

```bash
curl -s "https://odoo.<DOMEIN>/api/workspaces/availability" | jq '.workspaces | length'
# Moet 5 teruggeven (de 5 demo werkplekken)
```

### 7.4 — Firewall

```bash
ufw status verbose
```

Controleer dat poort 8000 **niet** in de lijst staat als ALLOW.

---

## Problemen oplossen

### Coolify bereikbaar maar service start niet

Controleer de logs van de specifieke container in Coolify:
**Project → Service → Logs**

### Odoo addon niet zichtbaar na installatie

De `odoo-addons` container moet de addon van GitHub hebben gekloond. Controleer de logs van de `odoo-addons` container — de laatste regel moet `Addons gesynchroniseerd` zijn.

Als dat niet zo is: herstart de `odoo-addons` container via Coolify.

### Xibo XMR werkt niet op displays

Controleer dat DNS voor `signage.<DOMEIN>` **zonder** Cloudflare proxy staat (grijs wolkje). Controleer ook dat poort 9505 open staat:

```bash
ufw status | grep 9505
```

### DNS propageert niet

```bash
# Lokaal cache leegmaken
# Windows:
ipconfig /flushdns
# macOS:
sudo dscacheutil -flushcache
```

---

## Gerelateerde documentatie

- [architecture.md](architecture.md) — serverarchitectuur en stack overzicht
- [dns.md](dns.md) — DNS configuratie details
- [reinstallation-guide.md](reinstallation-guide.md) — herinstallatie op bestaande Working Local VPS
- [odoo-workinglocal/docs/setup.md](https://github.com/WorkingLocal/odoo-workinglocal/blob/main/docs/setup.md) — Odoo deployment details
- [signage-workinglocal/docs/setup.md](https://github.com/WorkingLocal/signage-workinglocal/blob/main/docs/setup.md) — Xibo deployment details
