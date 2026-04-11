#!/bin/bash
# Coolify dashboard achter eigen subdomein zetten
# Gebruik: bash configure-coolify-domain.sh <DOMEIN>
# Voorbeeld: bash configure-coolify-domain.sh workinglocal.be
# Vereist: uitgevoerd als root op de VPS, Coolify draait al
#
# Na dit script is Coolify bereikbaar via https://coolify.<DOMEIN>
# Voeg eerst een DNS A-record toe: coolify.<DOMEIN> → <VPS-IP> (proxy UIT)

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

DOMEIN="${1}"
[[ -z "$DOMEIN" ]] && { echo "Gebruik: bash configure-coolify-domain.sh <DOMEIN>"; exit 1; }

FQDN="https://coolify.${DOMEIN}"

echo "=== Coolify subdomein instellen: ${FQDN} ==="

# Controleer of Coolify draait
docker ps --filter name=coolify --format '{{.Names}}' | grep -q '^coolify$' || {
    echo "Coolify container niet gevonden. Is Coolify geïnstalleerd?"
    exit 1
}

# FQDN en API instellen in de database
echo "→ FQDN instellen in Coolify database..."
docker exec coolify php artisan tinker --execute \
    "DB::table('instance_settings')->where('id',0)->update(['fqdn'=>'${FQDN}','is_api_enabled'=>true]); echo 'done';" \
    > /dev/null

log "FQDN ingesteld: ${FQDN}"

# Coolify herstarten zodat Traefik-config bijgewerkt wordt
echo "→ Coolify herstarten..."
docker restart coolify > /dev/null
sleep 5
docker inspect coolify --format '{{.State.Status}}' | grep -q running || {
    echo "Coolify hervat niet correct — controleer: docker logs coolify"
    exit 1
}
log "Coolify herstart"

# Controleer of Traefik-config aangemaakt is
DYNAMIC_CONFIG="/data/coolify/proxy/dynamic/coolify.yaml"
if [[ -f "$DYNAMIC_CONFIG" ]]; then
    log "Traefik config aangemaakt: ${DYNAMIC_CONFIG}"
else
    warn "Traefik config niet gevonden — wacht 30 seconden en controleer opnieuw"
fi

echo ""
echo "=== Volgende stappen ==="
echo ""
echo "1. Voeg een DNS A-record toe in Cloudflare:"
echo "   Type: A | Naam: coolify | Waarde: $(curl -s ifconfig.me) | Proxy: UIT (grijs wolkje)"
echo ""
echo "2. Wacht tot DNS propageert:"
echo "   dig coolify.${DOMEIN} +short"
echo ""
echo "3. Als het certificaat niet automatisch aangevraagd wordt:"
echo "   bash setup/reset-acme.sh"
echo ""
echo "4. Coolify bereikbaar via: ${FQDN}"
echo ""
warn "Proxy (Cloudflare oranje wolk) moet UIT staan — Coolify gebruikt WebSockets"
