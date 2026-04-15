#!/bin/bash
# UFW Firewall configuratie
# Gebruik: bash configure-firewall.sh
# Vereist: uitgevoerd als root

set -e

echo "=== UFW Firewall instellen ==="

ufw default deny incoming
ufw default allow outgoing

# ── Publiek bereikbaar — INPUT (host zelf) ────────────────────────────────────
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP → Traefik (redirect naar HTTPS)'
ufw allow 443/tcp   comment 'HTTPS → Traefik'
ufw allow 443/udp   comment 'HTTPS QUIC → Traefik'
ufw allow 9505/tcp  comment 'Xibo XMR push (geen Cloudflare proxy)'

# ── Publiek bereikbaar — FORWARD (Docker containers via Traefik) ───────────────
# BELANGRIJK: ufw allow opent alleen INPUT (host). Docker-containers zitten achter
# FORWARD/NAT. Zonder ufw route allow blijft ufw-user-forward leeg en blokkeert
# DOCKER-USER al het externe verkeer naar containers.
ufw route allow 80/tcp    comment 'HTTP forward → Traefik container'
ufw route allow 443/tcp   comment 'HTTPS forward → Traefik container'
ufw route allow 443/udp   comment 'HTTPS QUIC forward → Traefik container'
ufw route allow 9505/tcp  comment 'Xibo XMR forward → Xibo container'

# ── Expliciete DENY voor intern-only poorten (Docker bypass bescherming) ───────
ufw deny 8000/tcp   comment 'Coolify dashboard — alleen via SSH tunnel'
ufw deny 8080/tcp   comment 'Intern gebruik — niet publiek'
ufw deny 19999/tcp  comment 'Netdata — via Traefik reverse proxy'
ufw deny 6001/tcp   comment 'Intern Docker'
ufw deny 6002/tcp   comment 'Intern Docker'

ufw --force enable

echo ""
echo "=== Firewall status ==="
ufw status verbose

echo ""
echo "Intern bereikbaar (niet publiek):"
echo "  - Poort 8000: Coolify dashboard (bereik via SSH tunnel: ssh -L 8000:localhost:8000 root@<VPS-IP>)"
echo "  - Poort 19999: Netdata (via Traefik: https://metrics.<domein>)"
