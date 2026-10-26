#!/bin/bash
# Script 1: Configuração Base e Hardening para Ubuntu 24.04 / 26.04 (Instância Efêmera Helios)

set -e

# ==========================================
# CONFIGURAÇÃO - PREENCHA ANTES DE EXECUTAR
# ==========================================
PUBKEY="YOUR_PUBKEY_HERE"
SSH_PORT="22022"
# ==========================================

if [ "$PUBKEY" = "YOUR_PUBKEY_HERE" ]; then
    echo "ERRO: Edite este script e adicione sua chave SSH pública na variável PUBKEY antes de executar."
    exit 1
fi

echo "1/8: Atualizando e fazendo upgrade dos pacotes do sistema..."
apt update && apt upgrade -y

echo "2/8: Instalando ferramentas essenciais..."
apt install -y ufw fail2ban unattended-upgrades curl git openssl tmux ca-certificates gnupg lsb-release nginx certbot python3-certbot-nginx vim

echo "Configurando unattended-upgrades para execução automática..."
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

echo "3/8: Configurando o repositório oficial do Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "4/8: Criando o usuário 'apyb' com privilégios de sudo e docker..."
if ! id "apyb" &>/dev/null; then
    useradd -m -s /bin/bash apyb
else
    echo "Usuário 'apyb' já existe, pulando criação..."
fi
usermod -aG sudo,docker apyb

echo "5/8: Configurando chaves SSH para o usuário 'apyb'..."
mkdir -p /home/apyb/.ssh
if ! grep -q "$PUBKEY" /home/apyb/.ssh/authorized_keys 2>/dev/null; then
    echo "$PUBKEY" >> /home/apyb/.ssh/authorized_keys
fi
chmod 755 /home/apyb
chmod 700 /home/apyb/.ssh
chmod 600 /home/apyb/.ssh/authorized_keys
chown -R apyb:apyb /home/apyb/.ssh

echo "6/8: Endurecendo a configuração do SSH e Fail2ban..."
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-custom-hardening.conf
Port $SSH_PORT
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
UseDNS no
EOF

cat <<EOF > /etc/fail2ban/jail.d/sshd-custom.conf
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 5
bantime = 1h
EOF

echo "7/8: Configurando e habilitando o UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT/tcp
ufw allow http
ufw allow https
ufw --force enable

echo "8/8: Habilitando serviços e aplicando configurações..."
systemctl enable --now docker nginx fail2ban

systemctl stop ssh.socket || true
systemctl disable ssh.socket || true
systemctl mask ssh.socket || true
systemctl enable ssh.service
systemctl restart ssh.service
systemctl restart fail2ban

echo "=================================================================="
echo "Setup base concluído com sucesso!"
echo "ATENÇÃO: Defina a senha do usuário 'apyb' AGORA rodando:"
echo "passwd apyb"
echo ""
echo "Não se esqueça de liberar a porta $SSH_PORT, 80 e 443 no Firewall da Cloud!"
echo "Nova conexão: ssh -p $SSH_PORT apyb@ip_do_servidor"
echo "=================================================================="
