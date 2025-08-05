#!/bin/bash
set -e

# Environment Variables
DB_HOST=${DB_HOST:-postgres-db}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:?DB_USER not set}
DB_PASSWORD=${DB_PASSWORD:?DB_PASSWORD not set}
DB_NAME=${DB_NAME:?DB_NAME not set}
BACKUP_DIR=${BACKUP_DIR:-/mnt/backups}
RETENTION_DAYS=${RETENTION_DAYS:-7}
ENCRYPT=${ENCRYPT:-false}
ENCRYPT_PASS=${ENCRYPT_PASS:-""}

export PGPASSWORD="$DB_PASSWORD"

TIMESTAMP=$(date +"%Y-%m-%d_%H%M")
CURRENT_TIME=$(date +%H%M)
BACKUP_FILE="$BACKUP_DIR/bica-backup-${TIMESTAMP}.tar.gz"

echo "Now is $(date +"%H:%M"), creating backup..."

#  Clean up at 03:00 
if [[ "$CURRENT_TIME" == "0300" ]]; then
    echo "[$TIMESTAMP] Clean backups with more than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -mmin +$RETENTION_DAYS -exec rm {} \;
fi                              #mmin test  mtime  

# Waiting for postgres
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"; do
    echo "Waiting for PostgreSQL in $DB_HOST:$DB_PORT..."
    sleep 3
done

# Dump creating
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" > /tmp/db_backup.sql

# Compress
tar -czf "$BACKUP_FILE" -C /tmp db_backup.sql
rm /tmp/db_backup.sql

# Encrypt 
if [ "$ENCRYPT" = "true" ] && [ -n "$ENCRYPT_PASS" ]; then
    openssl enc -aes-256-cbc -pbkdf2 -salt -in "$BACKUP_FILE" -out "${BACKUP_FILE}.enc" -k "$ENCRYPT_PASS"
    rm "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.enc"
fi

echo "Backup created: $BACKUP_FILE"
