#!/bin/bash
set -e

# --- CONFIGURATION ---
CT_ID="200"
CT_NAME="adguard-sinkhole-stack"
RAM="1024"
CORES="1"
BRIDGE="vmbr0"
STORAGE="local-lvm"
GITHUB_USER="BK_1233"
GITHUB_REPO="proxmox-adguard-sinkhole"
echo "=== Creating LXC Container ==="
# 1. Update Proxmox package list
pveam update

# 2. Download the template directly from the official Proxmox mirrors using wget
TEMPLATE_URL="http://download.proxmox.com/images/system/debian-12-standard_12.2-1_amd64.tar.zst"
TEMPLATE_FILE="debian-12-standard_12.2-1_amd64.tar.zst"

echo "Downloading template directly..."
mkdir -p /var/lib/vz/template/cache/
wget -N -P /var/lib/vz/template/cache/ "$TEMPLATE_URL"

# 3. Create the container using the explicitly downloaded file
pct create $CT_ID "local:vztmpl/$TEMPLATE_FILE" \
  -cores $CORES -memory $RAM -hostname $CT_NAME \
  -net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  -storage $STORAGE -ostype debian -unprivileged 1 -start 1

# 3. Dynamically find the exact filename Proxmox just downloaded
LATEST_TEMPLATE=$(ls /var/lib/vz/template/cache/ | grep "debian-12-standard" | head -n 1)

# 4. Create the container using that dynamic filename
pct create $CT_ID "local:vztmpl/$LATEST_TEMPLATE" \
  -cores $CORES -memory $RAM -hostname $CT_NAME \
  -net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  -storage $STORAGE -ostype debian -unprivileged 1 -start 1

pct create $CT_ID local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  -cores $CORES -memory $RAM -hostname $CT_NAME \
  -net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  -storage $STORAGE -ostype debian -unprivileged 1 -start 1

pct set $CT_ID -features nesting=1,keyctl=1
pct start $CT_ID
sleep 10

echo "=== Deploying Stack from GitHub ==="
pct exec $CT_ID -- bash -c "
  apt-get update && apt-get install -y curl gnupg2 ca-certificates lsb-release git

  # Clear port 53 if systemd-resolved is active
  if systemctl is-active --quiet systemd-resolved; then
    systemctl disable systemd-resolved && systemctl stop systemd-resolved
    rm -f /etc/resolv.conf && echo 'nameserver 1.1.1.1' > /etc/resolv.conf
  fi

  # Install Docker
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # Clone your exact repository directly into /opt/adguard-stack
  git clone https://github.com/BK_1233/proxmox-adguard-sinkhole.git /opt/adguard-stack

  # Fire it up
  cd /opt/adguard-stack
  docker compose up -d
"

CT_IP=$(pct exec $CT_ID -- ip route get 1.1.1.1 | grep -oP 'src \K\S+')
echo "========================================================="
echo " Done! Portainer: https://$CT_IP:9443 | AdGuard Setup: http://$CT_IP:3000"
echo "========================================================="
