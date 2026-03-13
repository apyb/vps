
#!/bin/bash

# Encerra imediatamente se algum comando falhar
set -e

echo "1/7: Criando diretórios do Pretix e atribuindo o UID correto do Docker (15371)..."
mkdir -p /var/pretix-data
chown -R 15371:15371 /var/pretix-data

mkdir -p /etc/pretix
touch /etc/pretix/pretix.cfg
chown -R 15371:15371 /etc/pretix/
chmod 0700 /etc/pretix/pretix.cfg

echo "2/7: Aplicando configurações do Redis..."
# Adiciona configurações de socket ao redis.conf (apenas se ainda não estiverem lá, para evitar duplicatas em re-execuções)
grep -qF "unixsocket /var/run/redis/redis.sock" /etc/redis/redis.conf || echo "unixsocket /var/run/redis/redis.sock" >> /etc/redis/redis.conf
grep -qF "unixsocketperm 777" /etc/redis/redis.conf || echo "unixsocketperm 777" >> /etc/redis/redis.conf

# Automatiza 'systemctl edit redis-server' criando o arquivo de override diretamente
mkdir -p /etc/systemd/system/redis-server.service.d
cat <<EOF > /etc/systemd/system/redis-server.service.d/override.conf
[Service]
# Mantém o diretório ativo para que o pretix.service no Docker não precise ser
# reiniciado quando o Redis for reiniciado.
RuntimeDirectoryPreserve=yes
EOF

echo "3/7: Recarregando o systemd e reiniciando o Redis..."
systemctl daemon-reload
systemctl restart redis-server

echo "4/7: Configurando o cron job do Pretix..."
# Criar um arquivo de cron dedicado em /etc/cron.d/ é mais organizado do que modificar o crontab do root
cat <<EOF > /etc/cron.d/pretix
15,45 * * * * root /usr/bin/docker exec pretix.service pretix cron
EOF
chmod 0644 /etc/cron.d/pretix

echo "5/7: Baixando a imagem Docker estável do Pretix standalone..."
docker pull pretix/standalone:stable

echo "6/7: Construindo a imagem Docker customizada do Pretix (APyB)..."
if [ -f "/etc/pretix/Dockerfile" ]; then
    cd /etc/pretix
    docker build -t pretix-apyb:latest .
    # Return to previous directory
    cd - > /dev/null
else
    echo "------------------------------------------------------------------"
    echo "AVISO: /etc/pretix/Dockerfile não encontrado! Pulando a construção customizada."
    echo "Coloque seu Dockerfile em /etc/pretix e execute manualmente:"
    echo "cd /etc/pretix && docker build -t pretix-apyb:latest ."
    echo "------------------------------------------------------------------"
fi

echo "=================================================================="
echo "7/7: Configuração do ambiente base do Pretix concluída!"
echo "=================================================================="
