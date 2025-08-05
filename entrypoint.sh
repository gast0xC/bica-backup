#!/bin/bash

# Export container environment variables for cron
printenv | grep -E '^(DB_HOST|DB_PORT|DB_USER|DB_PASSWORD|DB_NAME|BACKUP_DIR|RETENTION_DAYS|ENCRYPT|ENCRYPT_PASS)' > /etc/environment

# Create log file if it does not exist
touch /var/log/backup.log

# Start cron in foreground to keep the container running
exec cron -f
