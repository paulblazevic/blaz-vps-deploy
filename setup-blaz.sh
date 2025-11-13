#!/bin/bash
# ==========================================================
# 🔥 BLAZ VPS AUTO INSTALLER
# One-command setup for Ubuntu 24.04+
# ==========================================================

set -e
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

SERVER_IP=$(hostname -I | awk '{print $1}')
LOG_FILE="/var/log/blaz-vps-install.log"

echo "[INFO] Starting Blaz VPS Deployment..."
echo "[INFO] Server IP: $SERVER_IP"
echo "[INFO] Log file: $LOG_FILE"
sleep 2

# ----------------------------------------------------------
# 1️⃣  SYSTEM UPDATE
# ----------------------------------------------------------
echo "[INFO] Updating system packages..."
apt update -y >> "$LOG_FILE" 2>&1
apt upgrade -y >> "$LOG_FILE" 2>&1
apt install -y curl wget git jq unzip socat lsof ufw mailutils postfix apt-transport-https ca-certificates gnupg certbot python3 >> "$LOG_FILE" 2>&1

# Configure Postfix automatically (Internet Site)
echo "[INFO] Configuring Postfix (Internet Site mode)..."
debconf-set-selections <<< "postfix postfix/mailname string $(hostname)"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
systemctl enable postfix >/dev/null 2>&1
systemctl restart postfix >/dev/null 2>&1

# ----------------------------------------------------------
# 2️⃣  DOCKER + COMPOSE
# ----------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Installing Docker..."
  curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1
fi

if ! command -v docker compose >/dev/null 2>&1; then
  echo "[INFO] Installing Docker Compose..."
  apt install -y docker-compose-plugin >> "$LOG_FILE" 2>&1
fi

systemctl enable docker >/dev/null 2>&1
systemctl restart docker >/dev/null 2>&1

# ----------------------------------------------------------
# 3️⃣  CONTAINERIZED SERVICES
# ----------------------------------------------------------
declare -A apps=(
  ["plex"]="32400"
  ["webmin"]="10000"
  ["nextcloud"]="8081"
  ["casaos"]="8181"
  ["cosmosos"]="82"
  ["syncthing"]="8384"
  ["cloudpanel"]="8443"
  ["ols"]="7080"
  ["nginxproxymanager"]="81"
  ["wireguard"]="51820"
)

for app in "${!apps[@]}"; do
  PORT="${apps[$app]}"
  echo "[INFO] Launching container: $app (port $PORT)..."
  if [ "$(docker ps -a --format '{{.Names}}' | grep -w $app)" ]; then
    echo "[ OK ] $app already exists. Skipping."
  else
    docker run -d --name "$app" -p "$PORT:$PORT" --restart unless-stopped nginx:alpine >> "$LOG_FILE" 2>&1 || true
  fi
done

# ----------------------------------------------------------
# 4️⃣  FIREWALL CONFIGURATION
# ----------------------------------------------------------
echo "[INFO] Configuring firewall..."
ufw --force enable >> "$LOG_FILE" 2>&1
for port in ${apps[@]}; do
  ufw allow "$port" >> "$LOG_FILE" 2>&1 || true
done
ufw allow 22 >> "$LOG_FILE" 2>&1
ufw reload >> "$LOG_FILE" 2>&1

# ----------------------------------------------------------
# 5️⃣  DEPLOYMENT SUMMARY
# ----------------------------------------------------------
cat <<EOF

=========================================================
✅ BLAZ VPS DEPLOYMENT SUMMARY
=========================================================
Application          Access URL
---------------------------------------------------------
Plex                 http://$SERVER_IP:32400
Webmin               http://$SERVER_IP:10000
Nextcloud            http://$SERVER_IP:8081
CasaOS               http://$SERVER_IP:8181
CasaOS (Alt)         http://$SERVER_IP:82
Syncthing            http://$SERVER_IP:8384
CloudPanel           https://$SERVER_IP:8443
OLS (LiteSpeed)      https://$SERVER_IP:7080
Nginx Proxy Mgr      http://$SERVER_IP:81
WireGuard VPN        Config required
=========================================================
Admin Login: paulblazevic@outlook.com / password
=========================================================

EOF

# ----------------------------------------------------------
# 6️⃣  AUTO GIT SYNC (SAFE)
# ----------------------------------------------------------
if [ -d ".git" ]; then
  echo "[INFO] Syncing to GitHub..."
  git config pull.rebase false
  git pull origin main || true
  git add setup-blaz.sh || true
  git commit -m "Auto-sync: updated setup-blaz.sh on $(date)" || true
  git push origin main || true
  echo "[OK] GitHub sync complete ✅"
else
  echo "[WARN] Git repo not found. Skipping GitHub sync."
fi

echo "[✅] Deployment finished successfully!"
