#!/bin/bash
# setup-blaz.sh — Blaz VPS Full Installer v2.1 (Docker fixed)
# Usage: curl -fsSL https://raw.githubusercontent.com/paulblazevic/blaz-vps-deploy/main/setup-blaz.sh | sudo bash

set -euo pipefail

# ============================
#  CONFIGURATION VARIABLES
# ============================
DOMAIN="vps.blazevic.cc"
EMAIL="paulblazevic@outlook.com"
CLOUDFLARE_API_TOKEN="CFDA71pEULjot2gNH1jGSg9bHbDzZT09jnkK0eMp"
MONITOR_EMAIL="paulblazevic@outlook.com"  # optional
GITHUB_USER="paulblazevic"
GITHUB_TOKEN="${GITHUB_TOKEN:-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}"
GITHUB_REPO="blaz-vps-deploy"

# ============================
#  UTILITY FUNCTIONS
# ============================
log() { echo -e "\e[34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
ok() { echo -e "\e[32m[OK]\e[0m $*"; }

# ============================
#  SYSTEM UPDATE
# ============================
log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl wget git lsb-release apt-transport-https ca-certificates gnupg software-properties-common \
    unzip socat lsof ufw mailutils postfix python3-certbot-dns-cloudflare certbot jq

# Configure Postfix non-interactively
log "Configuring Postfix (Internet Site mode)..."
echo "postfix postfix/mailname string $DOMAIN" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
dpkg-reconfigure -f noninteractive postfix || warn "Postfix reconfigure failed, continuing..."

# ============================
#  DOCKER INSTALL (FIXED)
# ============================
log "Installing Docker CE from official Docker repository..."
# Remove old conflicting packages
apt remove -y docker docker.io docker-ce docker-ce-cli containerd containerd.io || true
apt autoremove -y || true

# Add Docker GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable Docker
systemctl enable docker
systemctl start docker
ok "Docker installed successfully"

# ============================
#  FIREWALL SETUP
# ============================
log "Configuring UFW firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80,443/tcp
ufw allow 51820/udp
ufw allow 81/tcp    # Nginx Proxy Manager
ufw allow 32400/tcp # Plex
ufw allow 10000/tcp # Webmin
ufw allow 8081/tcp  # Nextcloud
ufw allow 8181/tcp  # CasaOS
ufw allow 82/tcp    # CasaOS Alt
ufw allow 8384/tcp  # Syncthing
ufw allow 8443/tcp  # CloudPanel
ufw allow 7080/tcp  # OLS
ufw --force enable
ok "Firewall configured"

# ============================
#  CLOUDLFARE DNS & SSL
# ============================
log "Setting up Cloudflare DNS and SSL..."
IP=$(curl -s ifconfig.me)

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
  warn "Cloudflare zone not found. Skipping DNS."
else
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$IP\",\"ttl\":120,\"proxied\":true}" \
    || warn "Failed to create DNS record"
fi

# Certbot Cloudflare credentials
CF_CRED_FILE=$(mktemp)
echo "dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN" > $CF_CRED_FILE
certbot certonly --dns-cloudflare --dns-cloudflare-credentials $CF_CRED_FILE -d $DOMAIN --non-interactive --agree-tos --email $EMAIL || warn "Certbot failed"
rm -f $CF_CRED_FILE
ok "Cloudflare DNS & SSL setup complete"

# ============================
#  DOCKER CONTAINERS
# ============================
log "Deploying Docker containers..."

declare -A CONTAINERS=(
  [plex]="plexinc/pms-docker:latest -p 32400:32400"
  [webmin]="webmin/webmin:latest -p 10000:10000"
  [nextcloud]="nextcloud:latest -p 8081:80"
  [casaos]="blazevic/casaos:latest -p 8181:80"
  [casaos-alt]="blazevic/casaos:latest -p 82:80"
  [syncthing]="linuxserver/syncthing:latest -p 8384:8384"
  [cloudpanel]="cloudpanel/cloudpanel:latest -p 8443:8443"
  [ols]="litespeedtech/openlitespeed:latest -p 7080:7080"
  [nginxproxymanager]="jc21/nginx-proxy-manager:latest -p 81:81"
  [wireguard]="linuxserver/wireguard:latest -p 51820:51820/udp"
)

for name in "${!CONTAINERS[@]}"; do
  image_ports=(${CONTAINERS[$name]})
  image=${image_ports[0]}
  ports=${image_ports[@]:1}
  if ! docker ps -a --format '{{.Names}}' | grep -qw "$name"; then
    log "Running container $name ($image)..."
    docker run -d --name "$name" $ports "$image" || warn "Failed to run $name"
  else
    ok "Container $name already exists. Skipping."
  fi
done

# ============================
#  FINAL SUMMARY
# ============================
echo "========================================================="
echo "✅ BLAZ VPS DEPLOYMENT SUMMARY"
echo "========================================================="
printf "%-20s %-30s\n" "Application" "Access URL"
echo "---------------------------------------------------------"
printf "%-20s %-30s\n" "Plex" "http://$IP:32400"
printf "%-20s %-30s\n" "Webmin" "http://$IP:10000"
printf "%-20s %-30s\n" "Nextcloud" "http://$IP:8081"
printf "%-20s %-30s\n" "CasaOS" "http://$IP:8181"
printf "%-20s %-30s\n" "CasaOS (Alt)" "http://$IP:82"
printf "%-20s %-30s\n" "Syncthing" "http://$IP:8384"
printf "%-20s %-30s\n" "CloudPanel" "https://$IP:8443"
printf "%-20s %-30s\n" "OLS (LiteSpeed)" "https://$IP:7080"
printf "%-20s %-30s\n" "Nginx Proxy Mgr" "http://$IP:81"
printf "%-20s %-30s\n" "WireGuard VPN" "Config required"
echo "========================================================="
echo "Admin Login: $EMAIL / password"
echo "========================================================="

# ============================
#  AUTO-GITHUB SYNC
# ============================
if [ -d ".git" ]; then
  log "Syncing latest version to GitHub..."
  git config user.email "$EMAIL"
  git config user.name "$GITHUB_USER"
  git add setup-blaz.sh
  git commit -m "Auto-sync: updated setup-blaz.sh on $(date)" || true
  git push https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$GITHUB_REPO.git main || warn "GitHub sync failed"
  ok "GitHub sync complete ✅"
else
  warn "Git repo not found. Skipping GitHub sync."
fi
