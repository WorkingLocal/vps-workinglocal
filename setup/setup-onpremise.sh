#!/bin/bash
# On-Premise setup — Working Local
# Gebruik: bash setup/setup-onpremise.sh
# Vereist: uitgevoerd als root, Docker + Coolify al geïnstalleerd
#
# Dit script configureert de On-Premise specifieke componenten:
#   - Cloudflared tunnel (vervangt open poorten + vaste DNS)
#   - Urbackup server (backup target voor andere toestellen)
#   - iDrive Linux agent (offsite backup naar iDrive cloud)
#
# Voer eerst uit: bash setup/install-docker.sh && bash setup/harden-server.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== On-Premise setup — Working Local ==="
echo ""

# ── Vereisten controleren ──────────────────────────────────────────────────────
[[ -f "$SCRIPT_DIR/.env" ]] || {
    echo "Geen .env bestand gevonden."
    echo "Kopieer .env.onpremise.template naar .env en vul de waarden in:"
    echo "  cp .env.onpremise.template .env"
    exit 1
}

source "$SCRIPT_DIR/.env"

[[ -n "$CLOUDFLARE_TUNNEL_TOKEN" && "$CLOUDFLARE_TUNNEL_TOKEN" != "VERVANG_MET_TUNNEL_TOKEN" ]] || {
    echo "CLOUDFLARE_TUNNEL_TOKEN niet ingesteld in .env"
    echo "Maak een tunnel aan in Cloudflare Zero Trust → Networks → Tunnels"
    exit 1
}

# ── 1. Cloudflared + Urbackup starten ─────────────────────────────────────────
echo "→ Cloudflared en Urbackup starten..."
cd "$SCRIPT_DIR"
docker compose -f docker-compose.onpremise.yml --env-file .env up -d

log "Cloudflared gestart (tunnel actief)"
log "Urbackup server gestart"

# ── 2. Urbackup firewall poorten openen ───────────────────────────────────────
echo "→ Urbackup poorten openen in firewall..."
ufw allow 55413/tcp comment 'Urbackup client protocol'
ufw allow 55414/tcp comment 'Urbackup client protocol'
ufw allow 55415/tcp comment 'Urbackup internet protocol'
ufw reload
log "Urbackup poorten open (55413-55415)"

# ── 3. iDrive Linux agent installeren ─────────────────────────────────────────
echo "→ iDrive Linux agent installeren..."
if ! command -v idrive &>/dev/null; then
    # Installeer iDrive agent
    apt-get install -y perl libwww-perl > /dev/null 2>&1
    cd /tmp
    curl -s -O https://www.idrive.com/downloads/linux/download-for-linux/IDriveForLinux.zip 2>/dev/null || {
        warn "iDrive download mislukt — installeer manueel via https://www.idrive.com/linux-backup-agent"
    }
    if [[ -f IDriveForLinux.zip ]]; then
        unzip -q IDriveForLinux.zip
        cd IDriveForLinux
        bash install.sh
        log "iDrive agent geïnstalleerd"
        warn "Configureer iDrive via: idrivem"
    fi
else
    log "iDrive agent al geïnstalleerd"
fi
cd "$SCRIPT_DIR"

# ── 4. Verificatie ────────────────────────────────────────────────────────────
echo ""
echo "=== Status ==="
docker compose -f docker-compose.onpremise.yml ps
echo ""
echo "=== Volgende stappen ==="
echo ""
echo "1. Cloudflare Zero Trust dashboard:"
echo "   → Controleer of de tunnel 'Healthy' is"
echo "   → Voeg public hostnames toe voor elke service (zie docs/onpremise.md)"
echo ""
echo "2. Urbackup web UI:"
echo "   → Toegankelijk via de Cloudflare tunnel URL voor Urbackup"
echo "   → Of tijdelijk via http://localhost:55414"
echo "   → Installeer Urbackup clients op andere toestellen"
echo ""
echo "3. iDrive configureren:"
echo "   → idrivem (interactieve configuratie)"
echo "   → Stel backup schema in voor /var/urbackup en Docker volumes"
echo ""
warn "Zie docs/onpremise.md voor de volledige configuratiegids"
