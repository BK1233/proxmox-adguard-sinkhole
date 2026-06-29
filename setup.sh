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
# ---------------------

echo "=== Creating LXC Container ==="
pveam update
pveam download local debian-12-standard_12.2-1_amd64.tar.zst || true

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
