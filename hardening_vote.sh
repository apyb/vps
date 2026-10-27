#!/bin/bash
# Script 1: Hardening Ubuntu 26.04 LTS + Docker + Nginx + Swap (Idempotente / Safe to Rerun)
# Execute como root ou via: sudo ./01_hardening.sh

set -euo pipefail

ADMIN_USER="apyb"
SWAP_SIZE="2G"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: Execute este script como root (sudo ./01_hardening.sh)."
    exit 1
fi

echo "1/8: Atualizando pacotes do sistema e configurando fuso horário..."
export DEBIAN_FRONTEND=noninteractive
timedatectl set-timezone America/Sao_Paulo
apt-get update && apt-get upgrade -y

echo "2/8: Instalando dependências base, Nginx, Certbot, UFW e Fail2Ban..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    git \
    ufw \
    fail2ban \
    python3-systemd \
    unattended-upgrades \
    nginx \
    certbot \
    python3-certbot-nginx \
    openssl

echo "3/8: Verificando arquivo de Swap (${SWAP_SIZE})..."
if ! swapon --show | grep -q '/swapfile'; then
    if [ ! -f /swapfile ]; then
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile
fi
if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
sysctl -w vm.swappiness=10 >/dev/null
echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf

echo "4/8: Verificando usuário administrativo '${ADMIN_USER}' e chaves SSH..."
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
fi

echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-${ADMIN_USER}"
chmod 440 "/etc/sudoers.d/90-${ADMIN_USER}"

mkdir -p "/home/${ADMIN_USER}/.ssh"
# Só copia chaves SSH se o authorized_keys do apyb ainda estiver vazio
if [ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]; then
    if [ -s /home/ubuntu/.ssh/authorized_keys ]; then
        cp /home/ubuntu/.ssh/authorized_keys "/home/${ADMIN_USER}/.ssh/authorized_keys"
    elif [ -n "${SUDO_USER:-}" ] && [ -s "/home/${SUDO_USER}/.ssh/authorized_keys" ]; then
        cp "/home/${SUDO_USER}/.ssh/authorized_keys" "/home/${ADMIN_USER}/.ssh/authorized_keys"
    elif [ -s /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys "/home/${ADMIN_USER}/.ssh/authorized_keys"
    fi
fi

chmod 700 "/home/${ADMIN_USER}/.ssh"
if [ -f "/home/${ADMIN_USER}/.ssh/authorized_keys" ]; then
    chmod 600 "/home/${ADMIN_USER}/.ssh/authorized_keys"
fi
chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.ssh"

if [ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]; then
    echo "ERRO CRÍTICO: Nenhuma chave SSH encontrada para ${ADMIN_USER}. Abortando antes de bloquear o SSH."
    exit 1
fi

echo "5/8: Verificando Docker Engine e Docker Compose (Ubuntu 26.04 DEB822)..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    rm -f /etc/apt/sources.list.d/docker.list

    CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    if ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release" &>/dev/null; then
        echo "Aviso: Repositório Docker para '${CODENAME}' não encontrado; usando pacote estável 'noble'."
        CODENAME="noble"
    fi

    cat << EOF > /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

usermod -aG docker "$ADMIN_USER"

mkdir -p /etc/docker
DAEMON_JSON_TMP=$(mktemp)
cat << 'EOF' > "$DAEMON_JSON_TMP"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Só reinicia o Docker se o daemon.json tiver mudado ou se o Docker estiver parado
if ! cmp -s "$DAEMON_JSON_TMP" /etc/docker/daemon.json; then
    mv "$DAEMON_JSON_TMP" /etc/docker/daemon.json
    chmod 644 /etc/docker/daemon.json
    systemctl enable --now docker
    systemctl restart docker
else
    rm -f "$DAEMON_JSON_TMP"
    systemctl enable --now docker
fi

echo "6/8: Configurando Firewall (UFW) e Fail2Ban..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

cat << 'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
EOF
systemctl enable --now fail2ban
systemctl reload-or-restart fail2ban

echo "7/8: Aplicando Hardening no OpenSSH..."
cat << EOF > /etc/ssh/sshd_config.d/99-apyb-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
AllowUsers ${ADMIN_USER} ubuntu
EOF

mkdir -p /run/sshd
chmod 0755 /run/sshd
sshd -t
systemctl daemon-reload
systemctl reload-or-restart ssh

echo "8/8: Ativando atualizações automáticas de segurança..."
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "=================================================================="
echo "Hardening do Ubuntu 26.04 LTS concluído com sucesso (Idempotente)!"
echo "Conecte-se com: ssh ${ADMIN_USER}@$(curl -s4 ifconfig.me)"
echo "=================================================================="
