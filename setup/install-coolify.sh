#!/bin/bash
# Coolify installatie op Ubuntu 24.04
# Vereist: Docker al geinstalleerd (run install-docker.sh eerst)
# Gebruik: bash install-coolify.sh

set -e

echo "=== Docker controleren ==="
docker --version || { echo "Docker niet gevonden. Run install-docker.sh eerst."; exit 1; }

echo "=== Coolify installeren ==="
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

echo ""
echo "=== Coolify geinstalleerd ==="
echo "Dashboard bereikbaar op: http://$(curl -s ifconfig.me):8000"
echo "Of via SSH tunnel: ssh -L 8000:localhost:8000 root@<VPS-IP>"
