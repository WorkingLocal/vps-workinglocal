# Hoe gebruik ik deze repo? — VPS-WORKINGLOCAL

## Wat is dit?

Deze repo bevat alle scripts en documentatie om een Working Local VPS op te zetten en te beheren. De VPS draait alle diensten van Working Local: Odoo, Xibo, WordPress, Netdata, Focus App en Urbackup.

---

## Hoe zet ik een nieuwe VPS op?

### Wat heb je nodig?

- Een VPS bij een provider (Hetzner, OVH, Hostinger, ...) met Ubuntu 24.04 LTS
- SSH toegang als root
- Een domein beheerd in Cloudflare
- Deze repo gecloned op je laptop

### Stap 1 — Verbinding maken

```bash
ssh root@<VPS-IP>
```

Clone de repo op de VPS:

```bash
git clone https://github.com/WorkingLocal/vps-workinglocal.git
cd vps-workinglocal
```

### Stap 2 — Docker installeren

```bash
bash setup/install-docker.sh
```

Controleer daarna:
```bash
docker --version
```

### Stap 3 — Firewall instellen

```bash
bash setup/configure-firewall.sh
```

Dit opent de juiste poorten en blokkeert de rest.

### Stap 4 — Beveiliging instellen

```bash
bash setup/harden-server.sh
```

Dit doet automatisch:
- Fail2ban installeren (beschermt SSH tegen brute force aanvallen)
- SSH beveiligen (wachtwoord-login uitschakelen)
- Docker correct configureren

> **Let op:** Zorg dat je SSH-sleutel al toegevoegd is vóór je dit uitvoert. Na dit script werkt inloggen met wachtwoord niet meer.

### Stap 5 — Coolify installeren

```bash
bash setup/install-coolify.sh
```

Coolify is het beheerpaneel voor alle containers. Na installatie draait het op poort 8000.

### Stap 6 — Coolify toegankelijk maken

Voeg eerst een DNS-record toe in Cloudflare:
- **Type:** A
- **Naam:** coolify
- **Waarde:** jouw VPS-IP
- **Proxy:** UIT (grijs wolkje)

Wacht tot het record actief is, voer dan uit op de VPS:

```bash
bash setup/configure-coolify-domain.sh workinglocal.be
```

Coolify is nu bereikbaar via **https://coolify.workinglocal.be**.

> Als je een beveiligingswaarschuwing ziet in de browser, wacht dan 1-2 minuten. Het SSL-certificaat wordt automatisch aangevraagd.

### Stap 7 — DNS instellen voor alle services

Voeg A-records toe in Cloudflare voor elke service (proxy UIT):

| Naam | Waarde |
|---|---|
| odoo | jouw VPS-IP |
| signage | jouw VPS-IP |
| metrics | jouw VPS-IP |
| focus | jouw VPS-IP |
| wordpress | jouw VPS-IP |
| backup | jouw VPS-IP |

### Stap 8 — Services deployen

Elke service heeft zijn eigen repo. Deploy ze via Coolify:

1. Ga naar **https://coolify.workinglocal.be**
2. **New Resource → Docker Compose**
3. Plak de `docker-compose.yml` uit de bijbehorende repo
4. Stel het domein en environment variables in
5. Deploy

Zie de individuele repos voor details.

### Stap 9 — Eerste klant uitrollen

```bash
bash setup/new-customer.sh
```

Het script vraagt naar klantnaam, domein en Coolify API token, en regelt de rest automatisch.

---

## Hoe herstel ik een SSL-certificaat?

Als een website een beveiligingsfout toont (ongeldig certificaat), was het DNS-record waarschijnlijk nog niet actief toen het certificaat aangevraagd werd.

Oplossing:

```bash
bash setup/reset-acme.sh
```

Wacht daarna 2 minuten en herlaad de pagina.

---

## Hoe log ik in op Coolify?

Ga naar **https://coolify.workinglocal.be** en log in met je beheerdersaccount.

Als Coolify niet bereikbaar is, gebruik dan een tijdelijke SSH tunnel:

```bash
ssh -L 8000:localhost:8000 root@23.94.220.181 -N
```

Ga dan naar **http://localhost:8000**.

---

## Hoe controleer ik of alles draait?

```bash
ssh root@23.94.220.181
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

Alle containers moeten `Up` tonen.

---

## Hoe voeg ik een SSH-sleutel toe?

```bash
ssh root@<VPS-IP> "echo '<jouw-publieke-sleutel>' >> ~/.ssh/authorized_keys"
```

Je publieke sleutel vind je in `~/.ssh/id_ed25519.pub` op je laptop.

---

## Problemen oplossen

| Probleem | Oplossing |
|---|---|
| Coolify niet bereikbaar | Check DNS: `dig coolify.workinglocal.be +short` |
| SSL-fout | Run `bash setup/reset-acme.sh` |
| Container start niet | Check logs in Coolify → Project → Service → Logs |
| WordPress admin traag | `docker exec <container> curl -s https://api.wordpress.org` — moet snel reageren |
| SSH login mislukt | Controleer of je SSH-sleutel correct is toegevoegd |
