#!/bin/bash
# Script 3: Backup final da eleição antes de destruir a VPS

set -euo pipefail

INSTALL_DIR="/opt/helios"
BACKUP_DIR="$HOME/helios-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="helios_apyb_backup_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "1/3: Exportando dump do PostgreSQL..."
docker compose -f "$INSTALL_DIR/docker-compose.yml" exec -T db \
    pg_dump -U helios helios > "$BACKUP_DIR/helios_db_${TIMESTAMP}.sql"

echo "2/3: Copiando arquivo .env..."
cp "$INSTALL_DIR/.env" "$BACKUP_DIR/helios_env_${TIMESTAMP}.bak"

echo "3/3: Compactando pacote final..."
tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" \
    "helios_db_${TIMESTAMP}.sql" \
    "helios_env_${TIMESTAMP}.bak"

rm -f "$BACKUP_DIR/helios_db_${TIMESTAMP}.sql" "$BACKUP_DIR/helios_env_${TIMESTAMP}.bak"

echo "=================================================================="
echo "Backup concluído: $BACKUP_DIR/$ARCHIVE_NAME"
echo "Baixe para sua máquina local rodando (no seu computador):"
echo "scp -P 22022 apyb@$(hostname -I | awk '{print $1}'):$BACKUP_DIR/$ARCHIVE_NAME ."
echo "=================================================================="
