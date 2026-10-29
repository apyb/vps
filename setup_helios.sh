#!/bin/bash
# Script 2: Deploy do Helios Voting + SSL + Templates de Email (Idempotente / Safe to Rerun)

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
FROM_EMAIL="comunicacao@python.org.br"
FROM_NAME="Eleições APyB"

INSTALL_DIR="/opt/helios"
# ==========================================

if [ "$SMTP_HOST" = "smtp.seuprovedor.com" ]; then
    echo "ERRO: Configure as variáveis de SMTP no topo do script antes de executar."
    exit 1
fi

echo "1/7: Sincronizando código-fonte base do Helios em $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R apyb:apyb "$INSTALL_DIR"

if [ ! -d "$INSTALL_DIR/.git" ]; then
    git clone https://github.com/benadida/helios-server.git "$INSTALL_DIR"
else
    git -C "$INSTALL_DIR" fetch origin
    git -C "$INSTALL_DIR" reset --hard origin/master
fi

echo "2/7: Aplicando templates de e-mail em Português (mantendo Voter ID / Password)..."
EMAIL_TPL_DIR="$INSTALL_DIR/helios/templates/email"
SERVER_UI_EMAIL_DIR="$INSTALL_DIR/server_ui/templates/email"

mkdir -p "$EMAIL_TPL_DIR" "$SERVER_UI_EMAIL_DIR"

# --- ETAPA 1: Convite para votar e envio de credenciais (vote_subject.txt / vote_body.txt) ---
cat << 'EOF' > "$EMAIL_TPL_DIR/vote_subject.txt"
[APyB] Convite para votação: {{custom_subject|safe}}
EOF

cat << 'EOF' > "$EMAIL_TPL_DIR/vote_body.txt"
Olá, {{voter.name}},

{{custom_message|safe}}

========================
COMO VOTAR
========================

URL da Eleição:
{{election_vote_url}}

Election Fingerprint (Hash de Auditoria):
{{voter.election.hash}}

{% if voter.voter_type == "password" %}Utilize suas credenciais exclusivas abaixo na tela de login da votação:
Voter ID: {{voter.voter_login_id}}
Password: {{voter.voter_password}}

Caso o sistema avise que você está conectado com outra conta, confirme o logout e informe o Voter ID e Password acima.{% else %}Conecte-se utilizando sua conta {{voter.voter_type}}.{% endif %}

{% if voter.vote_hash %}Consta um voto já registrado para o seu usuário nesta eleição com o Ballot Tracker:
{{voter.vote_hash}}

Se desejar, você pode votar novamente até o encerramento da eleição; apenas o último voto enviado será contabilizado.{% endif %}

--
Eleições APyB (Helios Voting)
Dúvidas: diretoria@python.org.br
EOF

# --- ETAPA 2: Avisos gerais / Lembretes durante a eleição (simple_subject.txt / simple_body.txt) ---
cat << 'EOF' > "$EMAIL_TPL_DIR/simple_subject.txt"
[APyB] Comunicado: {{custom_subject|safe}}
EOF

cat << 'EOF' > "$EMAIL_TPL_DIR/simple_body.txt"
Olá, {{voter.name}},

{{custom_message|safe}}

========================
INFORMAÇÕES DE ACESSO
========================

URL da Eleição:
{{election_vote_url}}

{% if voter.voter_type == "password" %}Credenciais para votação:
Voter ID: {{voter.voter_login_id}}
Password: {{voter.voter_password}}{% endif %}

--
Eleições APyB (Helios Voting)
Dúvidas: diretoria@python.org.br
EOF

# --- ETAPA 3: Confirmação de Voto Computado / Recibo (cast_vote_subject.txt / cast_vote_body.txt) ---
cat << 'EOF' > "$SERVER_UI_EMAIL_DIR/cast_vote_subject.txt"
[APyB] Voto registrado ({{custom_subject|safe}})
EOF

cat << 'EOF' > "$SERVER_UI_EMAIL_DIR/cast_vote_body.txt"
Olá, {{voter.name}},

Você registrou seu voto com sucesso na eleição "{{election.name}}".

O seu Ballot Tracker (código rastreador de cédula) é:
{{cast_vote.vote_hash}}

Sua cédula criptografada está arquivada para auditoria pública em:
{{cast_vote_url}}

--
Eleições APyB (Helios Voting)
Dúvidas: diretoria@python.org.br
EOF

# --- ETAPA 4: Divulgação do Resultado Final e Auditoria (result_subject.txt / result_body.txt) ---
cat << 'EOF' > "$EMAIL_TPL_DIR/result_subject.txt"
[APyB] Resultado Oficial: {{custom_subject|safe}}
EOF

cat << 'EOF' > "$EMAIL_TPL_DIR/result_body.txt"
Olá, {{voter.name}},

A apuração da eleição "{{voter.election.name}}" foi concluída e o resultado oficial já está disponível.

{{custom_message|safe}}

========================
RESULTADOS E AUDITORIA
========================

Visualize o resultado e o painel de auditoria em:
{{election_url}}

Election Fingerprint (Hash da Eleição):
{{voter.election.hash}}

{% if voter.vote_hash %}O Ballot Tracker do seu voto computado na urna é:
{{voter.vote_hash}}

Você pode conferir na lista de cédulas apuradas da eleição que o seu Ballot Tracker foi devidamente incluído na contagem.{% else %}Não consta voto registrado para o seu usuário nesta eleição.{% endif %}

--
Eleições APyB (Helios Voting)
Dúvidas: diretoria@python.org.br
EOF

echo "3/7: Criando Dockerfile (Python 3.13 + uv + configurações de Produção)..."
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
COPY pyproject.toml /app/
RUN uv pip install --system -r pyproject.toml "celery[redis]" redis

COPY . /app

# Ajustes de configurações do Django no settings.py
RUN cat << 'PYEOF' >> settings.py

import os
BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://redis:6379/0')
CELERY_BROKER_URL = BROKER_URL
CELERY_RESULT_BACKEND = BROKER_URL
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
CSRF_TRUSTED_ORIGINS = [os.environ.get('URL_HOST', 'https://votacao.python.org.br')]

# Fuso horário e idioma padrão
TIME_ZONE = 'America/Sao_Paulo'
LANGUAGE_CODE = 'pt-br'

# Garante remetente formatado com Nome + Email no Django
DEFAULT_FROM_NAME = os.environ.get('DEFAULT_FROM_NAME', 'Eleicoes APyB')
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'comunicacao@python.org.br')

# Desabilita sslmode obrigatório para o Postgres interno do Compose
if 'OPTIONS' in DATABASES['default']:
    DATABASES['default']['OPTIONS'].pop('sslmode', None)
DATABASES['default']['OPTIONS'] = {'sslmode': 'disable'}
PYEOF

EXPOSE 8000
EOF

echo "4/7: Preservando ou gerando credenciais seguras no .env..."
EXISTING_SECRET=""
EXISTING_DB_PASS=""

if [ -f "$INSTALL_DIR/.env" ]; then
    EXISTING_SECRET=$(grep -E '^SECRET_KEY=' "$INSTALL_DIR/.env" | cut -d= -f2- || true)
    EXISTING_DB_PASS=$(grep -E '^POSTGRES_PASSWORD=' "$INSTALL_DIR/.env" | cut -d= -f2- || true)
fi

if [ -n "$EXISTING_SECRET" ] && [ -n "$EXISTING_DB_PASS" ]; then
    echo " -> Credenciais de banco e SECRET_KEY existentes detectadas no .env; preservando..."
    SECRET_KEY="$EXISTING_SECRET"
    DB_PASS="$EXISTING_DB_PASS"
else
    echo " -> Gerando novas credenciais para SECRET_KEY e PostgreSQL..."
    SECRET_KEY=$(openssl rand -hex 32)
    DB_PASS=$(openssl rand -hex 16)
fi

cat << EOF > "$INSTALL_DIR/.env"
DEBUG=0
SECRET_KEY=${SECRET_KEY}
ALLOWED_HOSTS=${HELIOS_DOMAIN}
URL_HOST=https://${HELIOS_DOMAIN}
SECURE_URL_HOST=https://${HELIOS_DOMAIN}
SECURE_SSL_REDIRECT=1

POSTGRES_PASSWORD=${DB_PASS}
DATABASE_URL=postgres://helios:${DB_PASS}@db:5432/helios
CELERY_BROKER_URL=redis://redis:6379/0

HELIOS_ADMIN_ONLY=1
SITE_TITLE=Eleições APyB
WELCOME_MESSAGE=Sistema de Votação da Associação Python Brasil
HELP_EMAIL_ADDRESS=${ADMIN_EMAIL}

AUTH_ENABLED_SYSTEMS=password

EMAIL_HOST=${SMTP_HOST}
EMAIL_PORT=${SMTP_PORT}
EMAIL_HOST_USER=${SMTP_USER}
EMAIL_HOST_PASSWORD=${SMTP_PASS}
EMAIL_USE_TLS=1
DEFAULT_FROM_EMAIL=${FROM_EMAIL}
DEFAULT_FROM_NAME=${FROM_NAME}
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
    build: .
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

echo "5/7: Compilando imagem atualizada e recriando containers web e worker..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" build
docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d --force-recreate web worker

echo "Aguardando inicialização do container web e verificando migrações..."
for i in {1..15}; do
    if docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T web python manage.py migrate --noinput &>/dev/null; then
        break
    fi
    sleep 2
done
docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T web python manage.py migrate --noinput

echo "6/7: Verificando usuário administrador (${ADMIN_USER})..."
NEW_ADMIN_PASS=$(openssl rand -base64 12)
ADMIN_STATUS=$(docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T web python manage.py shell << PYEOF
from helios_auth.models import User
user, created = User.objects.get_or_create(
    user_type='password',
    user_id='${ADMIN_USER}',
    defaults={
        'name': 'APyB Admin',
        'info': {'password': '${NEW_ADMIN_PASS}'},
        'admin_p': True
    }
)
if created:
    print("CREATED:${NEW_ADMIN_PASS}")
else:
    print("EXISTING:" + user.info.get('password', 'definida-anteriormente'))
PYEOF
)

if echo "$ADMIN_STATUS" | grep -q "CREATED:"; then
    FINAL_ADMIN_PASS=$(echo "$ADMIN_STATUS" | grep -o "CREATED:.*" | cut -d: -f2-)
else
    FINAL_ADMIN_PASS=$(echo "$ADMIN_STATUS" | grep -o "EXISTING:.*" | cut -d: -f2-)
fi

echo "7/7: Verificando Virtual Host no Nginx e Certificado SSL..."
if ! grep -q "listen 443 ssl" "/etc/nginx/sites-available/${HELIOS_DOMAIN}.conf" 2>/dev/null; then
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
else
    sudo nginx -t
    sudo systemctl reload nginx
    echo " -> Nginx já configurado com HTTPS (443); configuração preservada."
fi

echo "=================================================================="
echo "Helios Voting ativo em: https://${HELIOS_DOMAIN}"
echo "Usuário Admin:          ${ADMIN_USER}"
echo "Senha Admin:            ${FINAL_ADMIN_PASS}"
echo "Remetente configurado:  ${FROM_NAME} <${FROM_EMAIL}>"
echo "Templates atualizados:  vote, simple, cast_vote e result"
echo "=================================================================="
