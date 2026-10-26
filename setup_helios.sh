#!/bin/bash
# Script 2: Deploy do Helios Voting + SSL (Executar após o 01_hardening.sh)

set -euo pipefail

# ==========================================
# CONFIGURAÇÃO - PREENCHA ANTES DE EXECUTAR
# ==========================================
HELIOS_DOMAIN="votacao.python.org.br"
ADMIN_EMAIL="diretoria@python.org.br"
ADMIN_USER="admin"

SMTP_HOST="smtp.seuprovedor.com"
SMTP_PORT="587"
SMTP_USER="seu_usuario_smtp"
SMTP_PASS="sua_senha_smtp"
FROM_EMAIL="eleicoes@python.org.br"

INSTALL_DIR="/opt/helios"
# ==========================================

if [ "$SMTP_HOST" = "smtp.seuprovedor.com" ]; then
    echo "ERRO: Configure as variáveis de SMTP no topo do script antes de executar."
    exit 1
fi

echo "1/6: Clonando benadida/helios-server em $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R apyb:apyb "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR/.git" ]; then
    git clone https://github.com/benadida/helios-server.git "$INSTALL_DIR"
else
    git -C "$INSTALL_DIR" pull origin master
fi

echo "2/6: Criando Dockerfile para o Helios (Python 3.13 + uv)..."
cat << 'EOF' > "$INSTALL_DIR/Dockerfile"
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libldap2-dev \
    libsasl2-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY . /app

# Instala as dependências do pyproject.toml do Helios + suporte ao Redis no Celery
RUN uv pip install --system -r pyproject.toml "celery[redis]" redis

# Garante que o Celery use Redis via variável de ambiente e que o Django confie no HTTPS do Nginx
RUN cat << 'PYEOF' >> settings.py

import os
BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://redis:6379/0')
CELERY_BROKER_URL = BROKER_URL
CELERY_RESULT_BACKEND = BROKER_URL
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
CSRF_TRUSTED_ORIGINS = [os.environ.get('URL_HOST', 'https://votacao.python.org.br')]
PYEOF

EXPOSE 8000
EOF

echo "3/6: Gerando arquivo .env e docker-compose.yml..."
SECRET_KEY=$(openssl rand -base64 32)
DB_PASS=$(openssl rand -hex 16)
ADMIN_PASS=$(openssl rand -base64 12)

cat << EOF > "$INSTALL_DIR/.env"
DEBUG=0
SECRET_KEY=${SECRET_KEY}
ALLOWED_HOSTS=${HELIOS_DOMAIN}
URL_HOST=https://${HELIOS_DOMAIN}
SECURE_SSL_REDIRECT=1

POSTGRES_PASSWORD=${DB_PASS}
DATABASE_URL=postgres://helios:${DB_PASS}@db:5432/helios
CELERY_BROKER_URL=redis://redis:6379/0

HELIOS_ADMIN_ONLY=1
SITE_TITLE=Eleicoes APyB
WELCOME_MESSAGE=Sistema de Votacao da Associacao Python Brasil
HELP_EMAIL_ADDRESS=${ADMIN_EMAIL}

AUTH_ENABLED_SYSTEMS=password

EMAIL_HOST=${SMTP_HOST}
EMAIL_PORT=${SMTP_PORT}
EMAIL_HOST_USER=${SMTP_USER}
EMAIL_HOST_PASSWORD=${SMTP_PASS}
EMAIL_USE_TLS=1
DEFAULT_FROM_EMAIL=${FROM_EMAIL}
EOF
chmod 600 "$INSTALL_DIR/.env"

cat << 'EOF' > "$INSTALL_DIR/docker-compose.yml"
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: helios
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: helios
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U helios"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped

  web:
    build: .
    image: helios-apyb:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    env_file: .env
    ports:
      - "127.0.0.1:8000:8000"
    command: >
      sh -c "python manage.py migrate --noinput &&
             gunicorn wsgi:application --bind 0.0.0.0:8000 --workers 3 --timeout 120"

  worker:
    image: helios-apyb:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    env_file: .env
    command: celery -A helios worker --loglevel=INFO --concurrency=2

volumes:
  pgdata:
EOF

echo "4/6: Subindo os containers via Docker Compose..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d --build

echo "Aguardando migrações do banco de dados..."
sleep 10

echo "5/6: Criando usuário administrador ($ADMIN_USER) no Helios..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T web python manage.py shell << PYEOF
from helios_auth.models import User
user, created = User.objects.get_or_create(
    user_type='password',
    user_id='${ADMIN_USER}',
    defaults={
        'name': 'APyB Admin',
        'info': {'password': '${ADMIN_PASS}'},
        'admin_p': True
    }
)
if not created:
    user.info = {'password': '${ADMIN_PASS}'}
    user.admin_p = True
    user.save()
PYEOF

echo "6/6: Configurando Nginx e gerando certificado HTTPS via Certbot..."
sudo tee "/etc/nginx/sites-available/${HELIOS_DOMAIN}.conf" > /dev/null << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${HELIOS_DOMAIN};

    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/${HELIOS_DOMAIN}.conf" "/etc/nginx/sites-enabled/${HELIOS_DOMAIN}.conf"
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

sudo certbot --nginx \
    -d "${HELIOS_DOMAIN}" \
    --non-interactive \
    --agree-tos \
    -m "${ADMIN_EMAIL}" \
    --redirect

echo "=================================================================="
echo "Helios Voting ativo em: https://${HELIOS_DOMAIN}"
echo "Usuário Admin:          ${ADMIN_USER}"
echo "Senha Admin:            ${ADMIN_PASS}"
echo "Arquivo .env:           ${INSTALL_DIR}/.env"
echo "=================================================================="
