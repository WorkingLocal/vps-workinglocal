#!/bin/bash
# UFW Firewall configuratie voor VPS-WORKINGLOCAL
# Gebruik: bash configure-firewall.sh
# Vereist: uitgevoerd als root

set -e

echo "=== UFW Firewall instellen ==="

ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP (Caddy redirect naar HTTPS)'
ufw allow 443/tcp   comment 'HTTPS (Caddy)'
ufw allow 443/udp   comment 'HTTPS QUIC'
ufw allow 9505/tcp  comment 'Xibo XMR push (geen Cloudflare proxy)'

ufw --force enable

echo ""
echo "=== Firewall status ==="
ufw status verbose

echo ""
echo "Geblokkeerd (niet meer publiek bereikbaar):"
echo "  - Poort 8000: Coolify dashboard (bereik via SSH tunnel)"
echo "  - Poort 19999: Netdata (bereik via https://metrics.workinglocal.be)"
