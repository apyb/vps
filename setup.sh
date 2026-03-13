#!/bin/bash
# Script de Configuração Base e Hardening para Ubuntu 22.04

# Encerra imediatamente se algum comando falhar
set -e

# ==========================================
# CONFIGURAÇÃO - PREENCHA ANTES DE EXECUTAR
# ==========================================
# Cole sua chave SSH pública entre as aspas abaixo:
PUBKEY="YOUR_PUBKEY_HERE"
SSH_PORT="22022"
# ==========================================

if [ "$PUBKEY" = "YOUR_PUBKEY_HERE" ]; then
    echo "ERRO: Edite este script e adicione sua chave SSH pública na variável PUBKEY antes de executar."
    exit 1
fi

echo "1/8: Atualizando e fazendo upgrade dos pacotes do sistema..."
apt update && apt upgrade -y

echo "2/8: Instalando ferramentas essenciais, utilitários de terminal, clientes de banco de dados e editores..."
apt install -y ufw fail2ban unattended-upgrades curl tmux ca-certificates gnupg lsb-release postgresql-client redis-server nginx certbot python3-certbot-nginx vim

echo "Configurando unattended-upgrades para execução automática..."
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

echo "3/8: Configurando o repositório oficial do Docker e instalando o Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "4/8: Criando o usuário 'apyb' com privilégios de sudo..."
useradd -m -s /bin/bash apyb
usermod -aG sudo apyb

echo "5/8: Configurando chaves SSH para o usuário 'apyb'..."
mkdir -p /home/apyb/.ssh
echo "$PUBKEY" > /home/apyb/.ssh/authorized_keys
chmod 700 /home/apyb/.ssh
chmod 600 /home/apyb/.ssh/authorized_keys
chown -R apyb:apyb /home/apyb/.ssh

echo "6/8: Endurecendo a configuração do SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cat <<EOF > /etc/ssh/sshd_config
# Configuração SSH Endurecida
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

echo "7/8: Configurando e habilitando o UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw allow http
ufw allow https
ufw --force enable

echo "8/8: Habilitando serviços e aplicando configurações..."
systemctl enable --now docker nginx redis-server fail2ban
systemctl restart ssh

echo "=================================================================="
echo "Setup concluído! Autenticação por senha foi desabilitada."
echo "Atualize a senha do usuário apyb com: passwd apyb"
echo "Agora você pode conectar usando: ssh -p $SSH_PORT apyb@ip_do_servidor"
echo "=================================================================="
