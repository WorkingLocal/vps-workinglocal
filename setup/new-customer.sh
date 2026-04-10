#!/bin/bash
# =============================================================================
# Working Local — Nieuwe klant uitrollen
# =============================================================================
# Gebruik: bash new-customer.sh
#
# Wat dit script doet:
#   1. Vraagt klantgegevens op (naam, domein, VPS IP, Coolify token)
#   2. Genereert sterke willekeurige wachtwoorden
#   3. Maakt een Coolify project aan via API
#   4. Deployt alle services: Odoo, Xibo CMS, Netdata, Focus App
#   5. Voegt alle environment variabelen toe via API
#   6. Slaat een klantconfig op in ./customers/<klantnaam>/
# =============================================================================

set -e

# ── Kleuren ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}✓${NC} $1"; }
info()    { echo -e "${BLUE}→${NC} $1"; }
warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; exit 1; }
header()  { echo -e "\n${BOLD}$1${NC}\n$(printf '─%.0s' {1..60})"; }

# ── Vereisten controleren ────────────────────────────────────────────────────
header "Vereisten controleren"
for cmd in curl jq openssl; do
    command -v "$cmd" &>/dev/null || error "$cmd is niet geïnstalleerd. Installeer het eerst."
    log "$cmd beschikbaar"
done

# ── Klantgegevens ophalen ────────────────────────────────────────────────────
header "Klantgegevens"

read -p "Klantnaam (bv. acme): " CUSTOMER_NAME
CUSTOMER_NAME=$(echo "$CUSTOMER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
[[ -z "$CUSTOMER_NAME" ]] && error "Klantnaam is verplicht."

read -p "Hoofddomein (bv. acme.be): " BASE_DOMAIN
[[ -z "$BASE_DOMAIN" ]] && error "Domein is verplicht."

read -p "VPS IP-adres: " VPS_IP
[[ -z "$VPS_IP" ]] && error "VPS IP is verplicht."

read -p "Coolify API token (uit Coolify → Keys & Tokens): " COOLIFY_TOKEN
[[ -z "$COOLIFY_TOKEN" ]] && error "Coolify API token is verplicht."

COOLIFY_URL="http://${VPS_IP}:8000"

echo ""
read -p "Welke services wil je installeren? (alles/odoo/xibo/netdata/focus) [alles]: " SERVICES_INPUT
SERVICES_INPUT=${SERVICES_INPUT:-alles}

INSTALL_ODOO=false
INSTALL_XIBO=false
INSTALL_NETDATA=false
INSTALL_FOCUS=false

if [[ "$SERVICES_INPUT" == "alles" ]]; then
    INSTALL_ODOO=true; INSTALL_XIBO=true; INSTALL_NETDATA=true; INSTALL_FOCUS=true
else
    IFS='/' read -ra SELECTED <<< "$SERVICES_INPUT"
    for s in "${SELECTED[@]}"; do
        case "$s" in
            odoo)    INSTALL_ODOO=true ;;
            xibo)    INSTALL_XIBO=true ;;
            netdata) INSTALL_NETDATA=true ;;
            focus)   INSTALL_FOCUS=true ;;
        esac
    done
fi

# ── Subdomeinen ──────────────────────────────────────────────────────────────
ODOO_DOMAIN="odoo.${BASE_DOMAIN}"
XIBO_DOMAIN="signage.${BASE_DOMAIN}"
NETDATA_DOMAIN="metrics.${BASE_DOMAIN}"
FOCUS_DOMAIN="focus.${BASE_DOMAIN}"

# ── Wachtwoorden genereren ───────────────────────────────────────────────────
header "Wachtwoorden genereren"

gen_password() { openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32; }

ODOO_DB_USER="odoo"
ODOO_DB_PASSWORD=$(gen_password)
ODOO_MASTER_PASSWORD=$(gen_password)
MYSQL_USER="xibo"
MYSQL_PASSWORD=$(gen_password)
MYSQL_ROOT_PASSWORD=$(gen_password)
FOCUS_OPERATOR_SECRET=$(gen_password)

log "Wachtwoorden gegenereerd"

# ── Output map aanmaken ──────────────────────────────────────────────────────
CUSTOMER_DIR="$(dirname "$0")/../customers/${CUSTOMER_NAME}"
mkdir -p "$CUSTOMER_DIR"

# ── Coolify API helper ───────────────────────────────────────────────────────
coolify_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(-s -X "$method" \
        -H "Authorization: Bearer ${COOLIFY_TOKEN}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json")

    [[ -n "$data" ]] && args+=(-d "$data")

    curl "${args[@]}" "${COOLIFY_URL}/api/v1${endpoint}"
}

# ── Coolify verbinding testen ────────────────────────────────────────────────
header "Coolify verbinding testen"

HEALTH=$(coolify_api GET "/health" 2>/dev/null) || error "Kan Coolify niet bereiken op ${COOLIFY_URL}. Controleer IP en token."
log "Coolify bereikbaar"

# ── Server UUID ophalen ──────────────────────────────────────────────────────
header "Server ophalen"

SERVERS=$(coolify_api GET "/servers")
SERVER_UUID=$(echo "$SERVERS" | jq -r '.[0].uuid // empty')
[[ -z "$SERVER_UUID" ]] && error "Geen server gevonden in Coolify. Voeg eerst een server toe."
SERVER_NAME=$(echo "$SERVERS" | jq -r '.[0].name')
log "Server gevonden: ${SERVER_NAME} (${SERVER_UUID})"

# ── Project aanmaken ─────────────────────────────────────────────────────────
header "Project aanmaken"

PROJECT_PAYLOAD=$(jq -n \
    --arg name "Working Local — ${CUSTOMER_NAME}" \
    --arg desc "Coworking platform voor ${BASE_DOMAIN}" \
    '{"name": $name, "description": $desc}')

PROJECT_RESPONSE=$(coolify_api POST "/projects" "$PROJECT_PAYLOAD")
PROJECT_UUID=$(echo "$PROJECT_RESPONSE" | jq -r '.uuid // empty')
[[ -z "$PROJECT_UUID" ]] && error "Project aanmaken mislukt: ${PROJECT_RESPONSE}"
log "Project aangemaakt (${PROJECT_UUID})"

# ── Environment UUID ophalen ─────────────────────────────────────────────────
sleep 1
ENVS=$(coolify_api GET "/projects/${PROJECT_UUID}/environments")
ENVIRONMENT_UUID=$(echo "$ENVS" | jq -r '.[0].uuid // .[0].name // empty')

# Sommige Coolify versies returnen name ipv uuid voor environments
if [[ -z "$ENVIRONMENT_UUID" ]]; then
    ENVIRONMENT_UUID="production"
    warn "Geen environment UUID gevonden, gebruik 'production' als environment_name"
fi
log "Environment: ${ENVIRONMENT_UUID}"

# ── Docker Compose bestanden inladen ─────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Service deployen via Coolify API ─────────────────────────────────────────
deploy_service() {
    local service_name="$1"
    local compose_file="$2"
    local fqdn="$3"
    local description="$4"

    info "Service deployen: ${service_name}..."

    local compose_raw
    compose_raw=$(cat "$compose_file")

    local payload
    payload=$(jq -n \
        --arg name "$service_name" \
        --arg desc "$description" \
        --arg project_uuid "$PROJECT_UUID" \
        --arg server_uuid "$SERVER_UUID" \
        --arg environment_uuid "$ENVIRONMENT_UUID" \
        --arg fqdn "https://${fqdn}" \
        --arg compose "$compose_raw" \
        '{
            "type": "docker-compose",
            "name": $name,
            "description": $desc,
            "project_uuid": $project_uuid,
            "server_uuid": $server_uuid,
            "environment_name": "production",
            "docker_compose_raw": $compose,
            "instant_deploy": false
        }')

    local response
    response=$(coolify_api POST "/services" "$payload")
    local uuid
    uuid=$(echo "$response" | jq -r '.uuid // empty')

    if [[ -z "$uuid" ]]; then
        warn "Service ${service_name} aanmaken mogelijk mislukt: ${response}"
        echo ""
        return 1
    fi

    log "Service aangemaakt: ${service_name} (${uuid})"
    echo "$uuid"
}

set_env_vars() {
    local service_uuid="$1"
    shift
    local envs=("$@")

    local payload="["
    local first=true
    for env in "${envs[@]}"; do
        local key="${env%%=*}"
        local val="${env#*=}"
        [[ "$first" == true ]] || payload+=","
        payload+=$(jq -n --arg k "$key" --arg v "$val" '{"key":$k,"value":$v,"is_preview":false}')
        first=false
    done
    payload+="]"

    coolify_api POST "/services/${service_uuid}/envs/bulk" \
        "{\"data\": ${payload}}" > /dev/null 2>&1 || true
}

start_service() {
    local service_uuid="$1"
    local name="$2"
    coolify_api GET "/services/${service_uuid}/start" > /dev/null 2>&1 \
        && log "${name} gestart" \
        || warn "${name} starten mislukt — start manueel in Coolify"
}

# ── Odoo deployen ─────────────────────────────────────────────────────────────
ODOO_UUID=""
if [[ "$INSTALL_ODOO" == true ]]; then
    header "Odoo deployen"
    ODOO_COMPOSE="${REPO_ROOT}/odoo-workinglocal/docker-compose.yml"
    [[ -f "$ODOO_COMPOSE" ]] || error "Odoo docker-compose.yml niet gevonden op ${ODOO_COMPOSE}"

    ODOO_UUID=$(deploy_service \
        "odoo-${CUSTOMER_NAME}" \
        "$ODOO_COMPOSE" \
        "$ODOO_DOMAIN" \
        "Odoo CE voor ${BASE_DOMAIN}")

    if [[ -n "$ODOO_UUID" ]]; then
        set_env_vars "$ODOO_UUID" \
            "ODOO_DB_USER=${ODOO_DB_USER}" \
            "ODOO_DB_PASSWORD=${ODOO_DB_PASSWORD}" \
            "ODOO_MASTER_PASSWORD=${ODOO_MASTER_PASSWORD}"
        log "Odoo environment variabelen ingesteld"
        start_service "$ODOO_UUID" "Odoo"
    fi
fi

# ── Xibo deployen ─────────────────────────────────────────────────────────────
XIBO_UUID=""
if [[ "$INSTALL_XIBO" == true ]]; then
    header "Xibo CMS deployen"
    XIBO_COMPOSE="${REPO_ROOT}/signage-workinglocal/docker-compose.yml"
    [[ -f "$XIBO_COMPOSE" ]] || error "Xibo docker-compose.yml niet gevonden op ${XIBO_COMPOSE}"

    XIBO_UUID=$(deploy_service \
        "xibo-${CUSTOMER_NAME}" \
        "$XIBO_COMPOSE" \
        "$XIBO_DOMAIN" \
        "Xibo CMS voor ${BASE_DOMAIN}")

    if [[ -n "$XIBO_UUID" ]]; then
        set_env_vars "$XIBO_UUID" \
            "XIBO_SERVER_NAME=${XIBO_DOMAIN}" \
            "MYSQL_USER=${MYSQL_USER}" \
            "MYSQL_PASSWORD=${MYSQL_PASSWORD}" \
            "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}"
        log "Xibo environment variabelen ingesteld"
        start_service "$XIBO_UUID" "Xibo"
    fi
fi

# ── Netdata deployen ──────────────────────────────────────────────────────────
NETDATA_UUID=""
if [[ "$INSTALL_NETDATA" == true ]]; then
    header "Netdata deployen"
    NETDATA_COMPOSE="${REPO_ROOT}/metrics-workinglocal/docker-compose.yml"
    [[ -f "$NETDATA_COMPOSE" ]] || error "Netdata docker-compose.yml niet gevonden op ${NETDATA_COMPOSE}"

    NETDATA_UUID=$(deploy_service \
        "netdata-${CUSTOMER_NAME}" \
        "$NETDATA_COMPOSE" \
        "$NETDATA_DOMAIN" \
        "Netdata monitoring voor ${BASE_DOMAIN}")

    if [[ -n "$NETDATA_UUID" ]]; then
        start_service "$NETDATA_UUID" "Netdata"
    fi
fi

# ── Focus App deployen ────────────────────────────────────────────────────────
FOCUS_UUID=""
if [[ "$INSTALL_FOCUS" == true ]]; then
    header "Focus App deployen"

    FOCUS_PAYLOAD=$(jq -n \
        --arg name "focus-${CUSTOMER_NAME}" \
        --arg desc "Focus Kiosk app voor ${BASE_DOMAIN}" \
        --arg project_uuid "$PROJECT_UUID" \
        --arg server_uuid "$SERVER_UUID" \
        --arg git_repo "https://github.com/WorkingLocal/focus-workinglocal" \
        --arg git_branch "master" \
        --arg fqdn "https://${FOCUS_DOMAIN}" \
        --arg ports "3000" \
        '{
            "name": $name,
            "description": $desc,
            "project_uuid": $project_uuid,
            "server_uuid": $server_uuid,
            "environment_name": "production",
            "git_repository": $git_repo,
            "git_branch": $git_branch,
            "build_pack": "dockerfile",
            "ports_exposes": $ports,
            "domains": $fqdn,
            "instant_deploy": false
        }')

    FOCUS_RESPONSE=$(coolify_api POST "/applications/public" "$FOCUS_PAYLOAD")
    FOCUS_UUID=$(echo "$FOCUS_RESPONSE" | jq -r '.uuid // empty')

    if [[ -z "$FOCUS_UUID" ]]; then
        warn "Focus App aanmaken mogelijk mislukt: ${FOCUS_RESPONSE}"
    else
        log "Focus App aangemaakt (${FOCUS_UUID})"

        # Env vars via applications endpoint
        coolify_api PATCH "/applications/${FOCUS_UUID}" \
            "$(jq -n \
                --arg url "https://${FOCUS_DOMAIN}" \
                --arg secret "$FOCUS_OPERATOR_SECRET" \
                '{"environment_variables": {"PUBLIC_URL": $url, "OPERATOR_SECRET": $secret}}')" \
            > /dev/null 2>&1 || true
        log "Focus environment variabelen ingesteld"

        coolify_api GET "/applications/${FOCUS_UUID}/start" > /dev/null 2>&1 \
            && log "Focus App gestart" \
            || warn "Focus App starten mislukt — start manueel in Coolify"
    fi
fi

# ── Klantconfig opslaan ───────────────────────────────────────────────────────
header "Klantconfig opslaan"

cat > "${CUSTOMER_DIR}/config.env" << EOF
# Working Local — ${CUSTOMER_NAME}
# Aangemaakt op: $(date '+%Y-%m-%d %H:%M')
# BEWAAR DIT BESTAND VEILIG — NOOIT COMMITTEN

CUSTOMER_NAME=${CUSTOMER_NAME}
BASE_DOMAIN=${BASE_DOMAIN}
VPS_IP=${VPS_IP}
COOLIFY_PROJECT_UUID=${PROJECT_UUID}
COOLIFY_SERVER_UUID=${SERVER_UUID}

# Odoo
ODOO_URL=https://${ODOO_DOMAIN}
ODOO_DB_USER=${ODOO_DB_USER}
ODOO_DB_PASSWORD=${ODOO_DB_PASSWORD}
ODOO_MASTER_PASSWORD=${ODOO_MASTER_PASSWORD}
ODOO_COOLIFY_UUID=${ODOO_UUID}

# Xibo CMS
XIBO_URL=https://${XIBO_DOMAIN}
XIBO_SERVER_NAME=${XIBO_DOMAIN}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
XIBO_COOLIFY_UUID=${XIBO_UUID}

# Netdata
NETDATA_URL=https://${NETDATA_DOMAIN}
NETDATA_COOLIFY_UUID=${NETDATA_UUID}

# Focus App
FOCUS_URL=https://${FOCUS_DOMAIN}
FOCUS_OPERATOR_SECRET=${FOCUS_OPERATOR_SECRET}
FOCUS_COOLIFY_UUID=${FOCUS_UUID}
EOF

log "Config opgeslagen in ${CUSTOMER_DIR}/config.env"

# DNS instructies genereren
cat > "${CUSTOMER_DIR}/DNS.md" << EOF
# DNS instellingen voor ${BASE_DOMAIN}

Voeg volgende A-records toe in Cloudflare (of andere DNS provider):

| Type | Naam | Waarde | Proxy |
|---|---|---|---|
| A | odoo | ${VPS_IP} | DNS only (grijs) |
| A | signage | ${VPS_IP} | DNS only (grijs) |
| A | metrics | ${VPS_IP} | DNS only (grijs) |
| A | focus | ${VPS_IP} | DNS only (grijs) |

> Proxy moet UIT (grijs wolkje) voor signage vanwege XMR poort 9505.
EOF

log "DNS instructies opgeslagen in ${CUSTOMER_DIR}/DNS.md"

# ── Samenvatting ─────────────────────────────────────────────────────────────
header "Klaar"

echo ""
echo -e "${BOLD}Services gedeployd voor ${CUSTOMER_NAME}:${NC}"
echo ""
[[ "$INSTALL_ODOO"    == true ]] && echo -e "  ${GREEN}●${NC} Odoo CE       → https://${ODOO_DOMAIN}"
[[ "$INSTALL_XIBO"    == true ]] && echo -e "  ${GREEN}●${NC} Xibo CMS      → https://${XIBO_DOMAIN}"
[[ "$INSTALL_NETDATA" == true ]] && echo -e "  ${GREEN}●${NC} Netdata       → https://${NETDATA_DOMAIN}"
[[ "$INSTALL_FOCUS"   == true ]] && echo -e "  ${GREEN}●${NC} Focus App     → https://${FOCUS_DOMAIN}"
echo ""
echo -e "${BOLD}Volgende stappen:${NC}"
echo ""
echo "  1. DNS instellen — zie ${CUSTOMER_DIR}/DNS.md"
echo "  2. Wacht tot services opstarten in Coolify"
[[ "$INSTALL_ODOO" == true ]] && \
echo "  3. Odoo database aanmaken via https://${ODOO_DOMAIN}/web/database/manager"
[[ "$INSTALL_ODOO" == true ]] && \
echo "     Master password: ${ODOO_MASTER_PASSWORD}"
[[ "$INSTALL_XIBO" == true ]] && \
echo "  4. Xibo eerste login: gebruiker=xibo_admin / wachtwoord=password (direct wijzigen)"
echo ""
echo -e "${YELLOW}Config opgeslagen in: ${CUSTOMER_DIR}/config.env${NC}"
echo -e "${YELLOW}Bewaar dit bestand veilig — nooit committen!${NC}"
