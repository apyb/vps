#!/bin/bash
# Ubuntu 22.04 Baseline Setup & Hardening Script

# Exit immediately if a command fails
set -e

# ==========================================
# CONFIGURATION - MUST FILL THIS OUT
# ==========================================
# Paste your public SSH key inside the quotes below:
PUBKEY="YOUR_PUBKEY_HERE"
SSH_PORT="22022"
# ==========================================

if [ "$PUBKEY" = "YOUR_PUBKEY_HERE" ]; then
    echo "ERROR: You must edit this script and add your public SSH key to the PUBKEY variable before running."
    exit 1
fi

echo "1/8: Updating and upgrading system packages..."
apt update && apt upgrade -y

echo "2/8: Installing core tools, terminal utilities, database clients, and editors..."
apt install -y ufw fail2ban unattended-upgrades curl tmux ca-certificates gnupg lsb-release postgresql-client redis-server nginx certbot python3-certbot-nginx vim

echo "Configuring unattended-upgrades to run automatically..."
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

echo "3/8: Setting up the official Docker repository and installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "4/8: Creating the 'apyb' user with sudo privileges..."
useradd -m -s /bin/bash apyb
usermod -aG sudo apyb

echo "5/8: Configuring SSH keys for 'apyb'..."
mkdir -p /home/apyb/.ssh
echo "$PUBKEY" > /home/apyb/.ssh/authorized_keys
chmod 700 /home/apyb/.ssh
chmod 600 /home/apyb/.ssh/authorized_keys
chown -R apyb:apyb /home/apyb/.ssh

echo "6/8: Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat <<EOF > /etc/ssh/sshd_config
# Hardened SSH Configuration
Port $SSH_PORT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
UseDNS no
EOF

echo "7/8: Configuring and enabling UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw allow http
ufw allow https
ufw --force enable

echo "8/8: Enabling services and applying configurations..."
systemctl enable --now docker nginx redis-server fail2ban
systemctl restart ssh

echo "=================================================================="
echo "Setup complete! Password authentication is now disabled."
echo "Please update the apyb password with: passwd apyb"
echo "You can now log in using: ssh -p $SSH_PORT apyb@your_server_ip"
echo "=================================================================="
