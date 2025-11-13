#!/bin/bash
# ===============================================================
#  Blaz VPS One-Click Installer  (Ubuntu 24.04)
#  Author: Paul Blazevic
#  Repo: https://github.com/paulblazevic/blaz-vps-deploy
# ===============================================================

set -e

# --- CONFIGURATION ---
DOMAIN="vps.blazevic.cc"
EMAIL="paulblazevic@outlook.com"
CLOUDFLARE_API_TOKEN="CFDA71pEULjot2gNH1jGSg9bHbDzZT09jnkK0eMp"
REPO_URL="https://github.com/paulblazevic/blaz-vps-deploy.git"
INSTALL_DIR="$HOME/blaz-vps-deploy"
LOGFILE="/var/log/blaz-setup.log"

echo "[INFO] Starting full Blaz VPS setup..."
echo "[INFO] Log file: $LOGFILE"
echo "[INFO] Using domain: $DOMAIN"

# --- System Update & Packages ---
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl wget git jq unzip socat lsof ufw mailutils postfix \
  apt-transport-https ca-certificates gnupg python3 python3-venv certbot \
  python3-certbot-dns-cloudflare snapd

# --- Install & Configure LXD ---
echo "[INFO] Installing and initializing LXD..."
sudo snap install lxd || true
sudo usermod -aG lxd $USER
newgrp lxd || true
sudo lxd init --auto || true

if ! lxc remote list | grep -q images; then
  sudo lxc remote add images https://images.lxd.canonical.com --protocol=simplestreams
fi

# --- Clone or Update Repository ---
if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "[INFO] Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
else
  echo "[INFO] Pulling latest changes..."
  cd "$INSTALL_DIR"
  git pull origin main || true
fi

# --- Run the Blaz Installer ---
cd "$INSTALL_DIR"
chmod +x install.sh

echo "[INFO] Running main installer..."
sudo env DOMAIN="$DOMAIN" EMAIL="$EMAIL" CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" ./install.sh 2>&1 | tee "$LOGFILE"

echo
echo "=============================================================="
echo "✅  Blaz VPS Deployment Complete"
echo "=============================================================="
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Domain:     $DOMAIN"
echo "Email:      $EMAIL"
echo "Git Repo:   $REPO_URL"
echo "=============================================================="
echo "To access your apps:"
echo "  Plex:               http://<IP>:32400"
echo "  Webmin:             http://<IP>:10000"
echo "  Nextcloud:          http://<IP>:8081"
echo "  CasaOS:             http://<IP>:8181"
echo "  CasaOS (Alt):       http://<IP>:82"
echo "  Syncthing:          http://<IP>:8384"
echo "  CloudPanel:         https://<IP>:8443"
echo "  OpenLiteSpeed:      https://<IP>:7080"
echo "  Nginx Proxy Mgr:    http://<IP>:81"
echo "  WireGuard:          VPN Config Required"
echo "=============================================================="
echo "Admin Login: paulblazevic@outlook.com / password"
echo "=============================================================="
