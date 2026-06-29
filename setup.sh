#!/bin/bash
set -e

# --- CONFIGURATION ---
CT_ID="200"
CT_NAME="adguard-sinkhole-stack"
RAM="1024"
CORES="1"
BRIDGE="vmbr0"
STORAGE="local-lvm"
GITHUB_USER="BK1233"
GITHUB_REPO="proxmox-adguard-sinkhole"
# ---------------------

# Verify container ID doesn't already exist
if pct status $CT_ID >/dev/null 2>&1; then
    echo "ERROR: Container ID $CT_ID already exists! Choose a different ID or destroy the old one."
    exit 1
fi

echo "=== STEP 1: Dynamically Finding Active Debian 12 Template ==="
pveam update

# Extract the exact filename string currently live in the Proxmox catalog
REAL_TEMPLATE=$(pveam available | grep "debian-12-standard" | awk '{print $2}' | head -n 1)

if [ -z "$REAL_TEMPLATE" ]; then
    echo "ERROR: Could not find a valid Debian 12 template string in pveam catalog."
    exit 1
fi

echo "Found active template package: $REAL_TEMPLATE"

echo "=== STEP 2: Downloading Template to Local Storage ==="
pveam download local "$REAL_TEMPLATE"

echo "=== STEP 3: Creating Unprivileged LXC Container ==="
pct create $CT_ID "local:vztmpl/$REAL_TEMPLATE" \
  -cores $CORES \
  -memory $RAM \
  -hostname $CT_NAME \
  -net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  -storage $STORAGE \
  -ostype debian \
  -unprivileged 1 \
  -start 1

echo "=== STEP 4: Injecting Virtualization Features ==="
pct set $CT_ID -features nesting=1,keyctl=1
pct start $CT_ID

echo "Waiting 10 seconds for the container network interface to boot..."
sleep 10

echo "=== STEP 5: Deploying Environment and Docker Stack ==="
pct exec $CT_ID -- bash -c "
  # Install necessary tools
  apt-get update && apt-get install -y curl gnupg2 ca-certificates lsb-release git

  # Clear out internal DNS port blocks if systemd-resolved is managing loops
  if systemctl is-active --quiet systemd-resolved; then
    systemctl disable systemd-resolved && systemctl stop systemd-resolved
    rm -f /etc/resolv.conf && echo 'nameserver 1.1.1.1' > /etc/resolv.conf
  fi

  # Install official engine package configurations for Docker CE
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # Clone your infrastructure files down from GitHub
  git clone https://github.com/BK_1233/proxmox-adguard-sinkhole.git /opt/adguard-stack

  # Run the multi-container environment deployment blueprint
  cd /opt/adguard-stack
  docker compose up -d
"

# Extract assigned DHCP string address for post-deployment printouts
CT_IP=$(pct exec $CT_ID -- ip route get 1.1.1.1 | grep -oP 'src \K\S+')

echo "========================================================="
echo " SUCCESS! Your fully automated stack is running."
echo "========================================================="
echo " Container IP: $CT_IP"
echo " Portainer Dashboard:  https://$CT_IP:9443"
echo " AdGuard Setup Wizard: http://$CT_IP:3000"
echo "========================================================="
