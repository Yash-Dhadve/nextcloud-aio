#!/usr/bin/env bash
# ==============================================================================
# Automated Production Installer: Nextcloud AIO + Tailscale Funnel on Debian
# ==============================================================================
# Designed for bare-metal Debian 12 (Bookworm) or Debian 13 (Trixie) hosts.
# Sets up Docker, UFW, Tailscale, and Nextcloud AIO.
# ==============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Text styling
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}   Nextcloud AIO Production Automated Installer for Debian       ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"

# Check for root / sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] This script must be run as root or with sudo.${NC}"
    exit 1
fi

# Detect Debian release
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[ERROR] Cannot detect operating system. /etc/os-release missing.${NC}"
    exit 1
fi
. /etc/os-release
if [ "$ID" != "debian" ] && [ "$ID_LIKE" != *"debian"* ]; then
    echo -e "${YELLOW}[WARNING] This script is optimized for Debian. Detected: $ID. Proceeding anyway...${NC}"
fi

# 1. Update and base packages
echo -e "\n${GREEN}[1/6] Updating package repositories and installing prerequisites...${NC}"
apt-get update
apt-get upgrade -y
apt-get install -y curl ufw jq apt-transport-https ca-certificates gnupg lsb-release iptables

# 2. Install Official Docker Engine
echo -e "\n${GREEN}[2/6] Installing official Docker Engine & Docker Compose...${NC}"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker daemon DNS
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF

systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

# 3. Configure Debian UFW Firewall
echo -e "\n${GREEN}[3/6] Configuring UFW Firewall...${NC}"
ufw allow 22/tcp comment 'SSH Access' || true
ufw allow 8080/tcp comment 'Nextcloud AIO Setup UI' || true
ufw allow 11000/tcp comment 'Nextcloud Internal Web Proxy' || true
echo "y" | ufw enable || true

# 4. Install Tailscale
echo -e "\n${GREEN}[4/6] Installing official Tailscale package...${NC}"
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

# 5. Launch Nextcloud AIO Mastercontainer
echo -e "\n${GREEN}[5/6] Deploying Nextcloud AIO Mastercontainer...${NC}"
# Stop any existing container if present
docker stop nextcloud-aio-mastercontainer 2>/dev/null || true
docker rm nextcloud-aio-mastercontainer 2>/dev/null || true

docker run -d \
  --init \
  --sig-proxy=false \
  --name nextcloud-aio-mastercontainer \
  --restart always \
  --publish 8080:8080 \
  --env APACHE_PORT=11000 \
  --env APACHE_IP_BINDING=127.0.0.1 \
  --env SKIP_DOMAIN_VALIDATION=true \
  --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
  --volume /var/run/docker.sock:/var/run/docker.sock:ro \
  ghcr.io/nextcloud-releases/all-in-one:latest

# 6. Final Instructions
HOST_IP="$(hostname -I | awk '{print $1}')"

echo -e "\n${BLUE}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD} Nextcloud AIO Installation Succeeded!${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "Next quick steps to finish configuration:\n"
echo -e "1. ${BOLD}Authenticate Tailscale:${NC}"
echo -e "   Run: ${YELLOW}sudo tailscale up${NC}"
echo -e "   (Ensure 'MagicDNS' & 'HTTPS Certificates' are enabled in https://login.tailscale.com/admin/dns)\n"
echo -e "2. ${BOLD}Open the AIO Setup Panel:${NC}"
echo -e "   URL: ${YELLOW}https://${HOST_IP}:8080${NC}"
echo -e "   Enter your Tailscale FQDN (from 'tailscale status') in the domain box.\n"
echo -e "3. ${BOLD}Activate Public Funnel (No Tailscale App needed for Friends):${NC}"
echo -e "   Run: ${YELLOW}sudo tailscale funnel --bg 11000${NC}\n"
echo -e "4. ${BOLD}Enable Registration with Admin Approval:${NC}"
echo -e "   Run: ${YELLOW}sudo bash enable-registration.sh${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"
