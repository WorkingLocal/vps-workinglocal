#!/usr/bin/env bash
# Blog Convertor — install script voor VPS-WORKINGLOCAL
# Installeert de Node.js webapplicatie als systemd service op poort 3456.
#
# Vereisten:
#   - Node.js geïnstalleerd (apt install nodejs)
#   - Logo-bestand beschikbaar (wordt automatisch aangemaakt via ImageMagick)
#   - AI Engine bereikbaar via Tailscale (100.80.180.55)
#
# Gebruik:
#   bash install.sh

set -euo pipefail

INSTALL_DIR=/opt/blog-ui
SERVICE_NAME=blog-ui
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Blog Convertor installeren in $INSTALL_DIR"

# Maak installatiemap aan
mkdir -p "$INSTALL_DIR"

# Kopieer server.js
cp "$SCRIPT_DIR/server.js" "$INSTALL_DIR/server.js"

# Logo downloaden van WordPress en zwarte tekst wit maken
echo "==> Logo verwerken..."
if ! command -v convert &>/dev/null; then
  apt-get install -y imagemagick
fi
LOGO_URL="https://wordpress.workinglocal.be/wp-content/uploads/2024/08/workinglocal-logo.png"
wget -q "$LOGO_URL" -O "$INSTALL_DIR/logo-original.png"
convert "$INSTALL_DIR/logo-original.png" \
  -channel RGB -fuzz 20% -fill white -opaque black \
  "$INSTALL_DIR/logo-white.png"
echo "    Logo opgeslagen als $INSTALL_DIR/logo-white.png"

# Node.js controleren
if ! command -v node &>/dev/null; then
  echo "==> Node.js installeren..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

echo "==> Node.js versie: $(node --version)"

# Systemd service installeren
cp "$SCRIPT_DIR/blog-convertor.service" /etc/systemd/system/blog-ui.service
systemctl daemon-reload
systemctl enable blog-ui
systemctl restart blog-ui

echo ""
echo "==> Blog Convertor actief op http://$(hostname -I | awk '{print $1}'):3456"
echo "    Status: systemctl status blog-ui"
echo "    Logs:   journalctl -u blog-ui -f"
