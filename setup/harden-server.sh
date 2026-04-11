#!/bin/bash
# Security hardening voor een Working Local VPS
# Gebruik: bash harden-server.sh
# Vereist: uitgevoerd als root, Docker al geïnstalleerd

set -e

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}✓${NC} $1"; }

echo "=== Security hardening ==="
echo ""

# ── 1. Fail2ban ──────────────────────────────────────────────────────────────
echo "→ Fail2ban installeren..."
apt-get install -y fail2ban > /dev/null 2>&1

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 24h
EOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
log "Fail2ban actief (SSH brute force bescherming)"

# ── 2. SSH hardening ──────────────────────────────────────────────────────────
echo "→ SSH hardening..."
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

systemctl reload ssh
log "SSH: wachtwoord-login uitgeschakeld, root enkel via key"

# ── 3. Docker iptables — containers hebben internettoegang nodig ───────────────
# Docker iptables MOET aan staan zodat containers externe diensten kunnen bereiken
# (WordPress admin, Odoo updates, etc.). We beveiligen de poorten via DOCKER-USER.
echo "→ Docker iptables configureren..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": true
}
EOF

systemctl restart docker
log "Docker iptables actief (containers hebben internettoegang)"

# ── 4. UFW after.rules — DOCKER-USER chain voor poortbeveiliging ──────────────
echo "→ DOCKER-USER firewall regels instellen..."

# Verwijder bestaande DOCKER-USER blok als die al bestaat
sed -i '/# BEGIN UFW AND DOCKER/,/# END UFW AND DOCKER/d' /etc/ufw/after.rules

cat >> /etc/ufw/after.rules << 'EOF'

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN

-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j RETURN
COMMIT
# END UFW AND DOCKER
EOF

ufw reload
log "UFW DOCKER-USER chain geconfigureerd"

# ── 5. iptables-persistent installeren ────────────────────────────────────────
echo "→ iptables-persistent installeren..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1
log "iptables-persistent geïnstalleerd"

# ── 6. PM2 uitschakelen (overblijfsel van pre-Docker setup) ──────────────────
if systemctl is-active --quiet pm2-root 2>/dev/null; then
    echo "→ PM2 uitschakelen..."
    pm2 kill 2>/dev/null || true
    systemctl disable pm2-root 2>/dev/null || true
    systemctl stop pm2-root 2>/dev/null || true
    log "PM2 gestopt en uitgeschakeld"
else
    log "PM2 niet actief (overgeslagen)"
fi

# ── 7. iptables regels opslaan ────────────────────────────────────────────────
iptables-save > /etc/iptables/rules.v4
log "iptables regels persistent opgeslagen"

# ── 8. Verificatie ────────────────────────────────────────────────────────────
echo ""
echo "=== Verificatie ==="
echo ""
echo "Fail2ban status:"
fail2ban-client status sshd | grep 'Banned IP' || true
echo ""
echo "SSH config:"
grep -E 'PasswordAuthentication|PubkeyAuthentication|PermitRootLogin' /etc/ssh/sshd_config | grep -v '^#'
echo ""
echo "Docker daemon.json:"
cat /etc/docker/daemon.json
echo ""
log "Hardening voltooid"
