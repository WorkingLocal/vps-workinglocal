# DNS Configuratie — Cloudflare

Alle domeinen staan in Cloudflare voor `workinglocal.be`.

## A-Records

| Naam | Type | Waarde | Proxy | Reden |
|---|---|---|---|---|
| `focus` | A | `23.94.220.181` | DNS only | Direct naar VPS |
| `signage` | A | `23.94.220.181` | DNS only | XMR poort 9505 vereist directe verbinding |
| `metrics` | A | `23.94.220.181` | DNS only | Direct naar VPS |
| `odoo` | A | `23.94.220.181` | DNS only | Direct naar VPS |

> **Proxy UIT (grijs wolkje)** voor alle VPS subdomeinen.
> Cloudflare proxy blokkeert niet-standaard poorten zoals 9505 (Xibo XMR).

## Bestaande records

| Naam | Type | Proxy | Opmerking |
|---|---|---|---|
| `www` | CNAME / A | Cloudflare CDN | WordPress site op aparte hosting |
| `workinglocal.be` | A | Cloudflare CDN | WordPress hoofddomein |

## Bij herinstallatie op nieuw IP

Pas het IP-adres aan in alle 4 A-records in Cloudflare.
Propagatie via Cloudflare gaat snel (< 5 min), maar lokale DNS cache kan langer duren:

```bash
# Windows — cache leegmaken
ipconfig /flushdns
```
