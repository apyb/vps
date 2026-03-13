#!/bin/bash

# Encerra imediatamente se algum comando falhar
set -e

# --- CONFIGURAÇÃO ---
DOMAIN="ingressos.python.org.br"
EMAIL="tecnologia@python.org.br"
REAL_CONF_FILE="/home/apyb/pretix"
# ---------------------

# Verificação de segurança: garante que o arquivo de configuração real existe
if [ ! -f "$REAL_CONF_FILE" ]; then
            echo "ERRO: O arquivo $REAL_CONF_FILE não foi encontrado."
                echo "Coloque seu arquivo de configuração do Nginx lá antes de executar este script."
                    exit 1
fi

echo "1/6: Removendo a configuração padrão do Nginx..."
rm -f /etc/nginx/sites-enabled/default

echo "2/6: Criando configuração temporária HTTP-only do Nginx para evitar conflitos..."
cat <<EOF > /etc/nginx/sites-available/pretix
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root /var/www/html;
}
EOF

echo "3/6: Criando o link simbólico da configuração e iniciando o Nginx..."
ln -sf /etc/nginx/sites-available/pretix /etc/nginx/sites-enabled/
systemctl restart nginx

echo "4/6: Executando o Certbot para gerar os certificados..."
# Executa sem interação, aceita os Termos de Serviço e usa o plugin do Nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

echo "5/6: Certificados obtidos! Copiando sua configuração real do Pretix..."
cp "$REAL_CONF_FILE" /etc/nginx/sites-available/pretix

echo "6/6: Testando a sintaxe e recarregando o Nginx com a configuração segura..."
nginx -t
systemctl reload nginx

echo "Habilitando o timer de renovação automática do Certbot..."
systemctl enable --now certbot.timer
