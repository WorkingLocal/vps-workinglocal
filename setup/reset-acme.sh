#!/bin/bash
# Reset Let's Encrypt certificaten (acme.json)
# Gebruik: bash reset-acme.sh
# Vereist: uitgevoerd als root op de VPS
#
# Gebruik dit als SSL-certificaten niet aangevraagd worden omdat
# Let's Encrypt een mislukte poging gecached heeft (DNS was nog niet actief).

set -e

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}✓${NC} $1"; }

echo "=== Let's Encrypt certificaten resetten ==="

ACME_FILE="/data/coolify/proxy/acme.json"

[[ -f "$ACME_FILE" ]] || { echo "acme.json niet gevonden op ${ACME_FILE}"; exit 1; }

echo "→ Huidige certificaten:"
cat "$ACME_FILE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
certs=d.get('letsencrypt',{}).get('Certificates',[])
print(f'  {len(certs)} certificaten aanwezig:')
for c in certs:
    print(f'  - {c[\"domain\"][\"main\"]}')
" 2>/dev/null || echo "  (leeg of ongeldig JSON)"

echo ""
echo "→ acme.json resetten..."
docker stop coolify-proxy
echo '{}' > "$ACME_FILE"
chmod 600 "$ACME_FILE"
docker start coolify-proxy
sleep 3
docker inspect coolify-proxy --format '{{.State.Status}}' | grep -q running
log "coolify-proxy herstart"

echo ""
echo "Traefik vraagt nu nieuwe certificaten aan voor alle geconfigureerde domeinen."
echo "Dit duurt 1-2 minuten. Controleer nadien:"
echo "  cat ${ACME_FILE} | python3 -c \"import json,sys; d=json.load(sys.stdin); [print(c['domain']['main']) for c in d.get('letsencrypt',{}).get('Certificates',[])]\" "
