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

# ── 3. Docker UFW bypass blokkeren ────────────────────────────────────────────
echo "→ Docker UFW bypass blokkeren..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "iptables": false
}
EOF

systemctl restart docker
log "Docker iptables bypass uitgeschakeld"

# ── 4. PM2 uitschakelen (overblijfsel van pre-Docker setup) ──────────────────
if systemctl is-active --quiet pm2-root 2>/dev/null; then
    echo "→ PM2 uitschakelen..."
    pm2 kill 2>/dev/null || true
    systemctl disable pm2-root 2>/dev/null || true
    systemctl stop pm2-root 2>/dev/null || true
    log "PM2 gestopt en uitgeschakeld"
else
    log "PM2 niet actief (overgeslagen)"
fi

# ── 5. Verificatie ────────────────────────────────────────────────────────────
echo ""
echo "=== Verificatie ==="
echo ""
echo "Fail2ban gebande IPs:"
fail2ban-client status sshd | grep 'Banned IP' || true
echo ""
echo "SSH config:"
grep -E 'PasswordAuthentication|PubkeyAuthentication|PermitRootLogin' /etc/ssh/sshd_config | grep -v '^#'
echo ""
echo "Docker daemon.json:"
cat /etc/docker/daemon.json
echo ""
log "Hardening voltooid"
