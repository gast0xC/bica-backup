
# Bica Backup - Documentation

This repository contains a Docker-based system to perform **automatic backups of a PostgreSQL database** for the BICA application, with support for **backup retention** and **optional encryption**.

The solution is designed to:

Create compressed and optionally encrypted backups of a PostgreSQL database.

Store backups locally in **/mnt/backups** on the host machine.

Run automatically twice per day at **03:00 AM and 14:00 PM (UTC)**.

Automatically delete old backups according to a **configurable retention period**.

Run entirely in a Docker container, ensuring it can **restart and continue backups after server reboots**.


---

## File Structure

.
├── backup.sh # Main backup script
├── crontab.txt # Scheduled tasks (cron)
├── docker-compose.yml # Docker services
├── Dockerfile # Backup container image
├── entrypoint.sh # Cron initialization script
├── README.md # Official documentation
├── backups/ # Folder where backups are stored
└── pgdata/  # Folder where pgdata is stored


---

## 1- `backup.sh` - Backup Script

```bash
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
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -exec rm {} \;
fi                              #mmin test  

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

```


Bash script to:

1. Wait for PostgreSQL to be ready.  
2. Create a `pg_dump` of the database.  
3. Compress and optionally encrypt the backup.  
4. Clean old backups according to the configured retention.  
5. **Store backups in the `backups/` folder.**

---

### Environment Variables

| Variable          | Default         | Description                                        |
|-------------------|----------------|----------------------------------------------------|
| `DB_HOST`         | `postgres-db`  | PostgreSQL host                                    |
| `DB_PORT`         | `5432`         | PostgreSQL port                                    |
| `DB_USER`         | **Required**   | Database user                                      |
| `DB_PASSWORD`     | **Required**   | Database password                                  |
| `DB_NAME`         | **Required**   | Database name                                      |
| `BACKUP_DIR`      | `/mnt/backups` | Directory to store backups                         |
| `RETENTION_DAYS`  | `7`            | Number of days to retain backups                   |
| `ENCRYPT`         | `false`        | Enable encryption (`true`/`false`)                 |
| `ENCRYPT_PASS`    | `""`           | Encryption password (if `ENCRYPT=true`)            |

---

### Backup Naming Convention

Backups are generated as single archive files named like:

```
bica-backup-YYYY-MM-DD_HHMM.tar.gz
bica-backup-YYYY-MM-DD_HHMM.tar.gz.enc  # if encrypted
```


---

### Retention Policy

- Old backups are **deleted** only during the **03:00 AM** run (±1 minute).  
- `find` is used to remove backups older than the value of `RETENTION_DAYS`.  


```bash
find /mnt/backups -type f -mtime +$RETENTION_DAYS -exec rm {} \;
```

### PostgreSQL Connection Handling
The script waits until the PostgreSQL server is ready using:

```bash
pg_isready -h $DB_HOST -p $DB_PORT -U $DB_USER
```
Retries every 3 seconds until the database is available.

### Temporary Files
Database dump is first created in **/tmp/db_backup.sql**.

Then compressed into .tar.gz and the temporary SQL file is deleted.

### Encryption (Optional)
```bash
If ENCRYPT=true and ENCRYPT_PASS is set:
```

### Logging & Exit Behavior
Script outputs timestamped messages with status.

set -e ensures the script stops on any error, preventing incomplete backups

## 2- `crontab.txt` - Scheduling

`cron` automatically executes backups:

```cron
# Production
0 3  * * * . /etc/environment; /backup.sh >> /var/log/backup.log 2>&1
0 14 * * * . /etc/environment; /backup.sh >> /var/log/backup.log 2>&1

# Test every 1 minute
#* * * * * . /etc/environment; /backup.sh >> /var/log/backup.log 2>&1

```

#### Schedule Details
- 03:00 UTC → Nightly backup (includes retention cleanup)

- 14:00 UTC → Additional backup (without cleanup)

- Test mode → Every minute if the last line is uncommented

#### How It Works
- **Environment Loading**

**./etc/environment** makes all container environment variables (**DB_HOST**, **DB_USER**, **ENCRYPT**, etc.) available to the script when executed by **cron**.

Without this step, cron would run with a limited environment, and the script would fail to connect to the database.

- **Logging**
All script output is appended to **/var/log/backup.log** with:
```bash
>> /var/log/backup.log 2>&1
```
**stdout** and **stderr** are combined in the same file.

Logs can be viewed live with:
```bash
docker exec -it bica-backup tail -f /var/log/backup.log
```
- **Cron Behavior in Docker**

The cron configuration file /etc/cron.d/backup-cron is loaded into the container using:

```bash
crontab /etc/cron.d/backup-cron
```
Cron runs in the **foreground** (cron -f) via `entrypoint.sh` to keep the container alive.

If the container or server restarts, cron will **automatically resume scheduled backups**.

---

## 3- `docker-compose.yml` - Services

The `docker-compose.yml` defines **two services**:

1. **`postgres-db`** → PostgreSQL database container  
2. **`bica-backup`** → Backup container that runs `backup.sh` and cron jobs  

---

### Docker Compose File

```yaml
services:
  postgres-db:                    # PostgreSQL Service
    image: postgres:15
    container_name: postgres-db
    environment:
      POSTGRES_USER: myuser        # Database username
      POSTGRES_PASSWORD: mypass    # Database password
      POSTGRES_DB: mydatabase      # Database name
    ports:
      - "5432:5432"                # Expose DB to host
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    networks:
      - bica-net                   # Use the same network for both services

  bica-backup:                     # Backup Service
    build: .                       # Build image from local Dockerfile
    container_name: bica-backup
    restart: unless-stopped        # Auto-restart after reboot
    environment:
      DB_HOST: postgres-db         # Connects to the postgres-db service
      DB_PORT: 5432
      DB_USER: myuser              # DB username
      DB_PASSWORD: mypass          # DB password
      DB_NAME: mydatabase          # Target database
      BACKUP_DIR: /mnt/backups     # Backup folder inside the container
      RETENTION_DAYS: 7            # Number of days to retain backups
      ENCRYPT: "true"             # Set to "true" to enable encryption
      ENCRYPT_PASS: "MySecretKey"  # encryp pw

    volumes:
      - ./backups:/mnt/backups     # Map host folder for persistent backups
    depends_on:
      - postgres-db                # Start database before backup service
    networks:
      - bica-net

networks:
  bica-net:
    driver: bridge                 # Simple Docker bridge network

```

### `postgres-db` service

-   Runs a PostgreSQL 15 database

-   Credentials defined via environment variables

-   Exposes port `5432` to the host

-   Connected to the `bica-net` network

### `bica-backup` service

-   Builds a custom image from the Dockerfile

-   Runs `backup.sh` automatically via cron

-   Shares the same network to access the DB using the service name `postgres-db`

-   Stores backups in the mapped `./backups` folder on the host

-   Retention and optional encryption are configurable through environment variables

### Networking & Volumes
-   Both services share the `bica-net` bridge network

-   Backups are stored persistently in the `backups/` folder on the host:
```bash
backups/
├── bica-backup-YYYY-MM-DD_HHMM.tar.gz
└── bica-backup-YYYY-MM-DD_HHMM.tar.gz.enc  # if encrypted
```

### Deployment
-   Build and start containers:

```bash
docker compose up -d --build
```

Once running, backups are automatically created in **./backups**.

- Stop and remove containers (without deleting volumes):
```bash
docker compose down
```
---

## 4- `Dockerfile` - Backup Image

The backup image is based on **Debian Bookworm** and includes everything required to run scheduled PostgreSQL backups.

---

### Dockerfile

```dockerfile
FROM debian:bookworm

# Avoid interactive prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone (default: UTC)
ENV TZ=Europe/Lisbon 
    #Europe/Lisbon  UTC
# Install required packages
RUN apt-get update && apt-get install -y \
    tzdata \
    postgresql-client-15 \
    cron \
    bash \
    coreutils \
    tar \
    gzip \
    openssl \
 && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
 && echo $TZ > /etc/timezone \
 && rm -rf /var/lib/apt/lists/*

# Copy scripts and cron configuration
COPY backup.sh /backup.sh
COPY entrypoint.sh /entrypoint.sh
COPY crontab.txt /etc/cron.d/backup-cron

# Set correct permissions
RUN chmod +x /backup.sh /entrypoint.sh \
    && chmod 0644 /etc/cron.d/backup-cron \
    && crontab /etc/cron.d/backup-cron

# Run cron in foreground to keep the container alive
ENTRYPOINT ["/entrypoint.sh"]

```


**Base Image**: Uses **debian:bookworm** as a lightweight OS.

**Packages Installed**:

   -   `postgresql-client-15` → Provides `pg_dump` and `pg_isready`

   -   `cron` → Runs scheduled backups

   -   `tar`, `gzip`, `openssl` → Compression & optional encryption

   -   `bash`, `coreutils` → Required for script execution

**Timezone**: Defaults to `UTC` but can be changed if needed.

#### Scripts

-   `backup.sh` → Handles the backup process

-   `entrypoint.sh` → Starts cron in foreground

-   `crontab.txt` → Defines the backup schedule

#### Permissions:

-   `backup.sh` and `entrypoint.sh` are executable

-   Cron file is loaded into the container automatically

    -   The entrypoint runs `cron -f` to keep the container running continuously

---

## 5- `entrypoint.sh` - Cron Initialization

The `entrypoint.sh` script is responsible for preparing the environment for cron jobs and ensuring that scheduled backups run correctly inside the container.

---

### Script Code

```bash
#!/bin/bash

# Export container environment variables for cron
printenv | grep -E '^(DB_HOST|DB_PORT|DB_USER|DB_PASSWORD|DB_NAME|BACKUP_DIR|RETENTION_DAYS|ENCRYPT)' > /etc/environment

# Create log file if it does not exist
touch /var/log/backup.log

# Start cron in foreground to keep the container running
exec cron -f

```

**Exports Environment Variables**

-   Cron runs in a minimal environment and does not automatically **inherit Docker environment variables**.

-   `printenv | grep ... > /etc/environment` ensures that the backup script has access to:
    - `DB_HOST`
    - `DB_PORT`
    - `DB_USER`
    - `DB_PASSWORD`
    - `DB_NAME`
    - `BACKUP_DIR`
    - `RETENTION_DAYS`
    - `ENCRYPT`

**Ensures Logging**

Creates `/var/log/backup.log` if it does not exist.

All cron job outputs (`stdout` and `stderr`) are appended to this file.

**Runs Cron in Foreground**

-   `exec cron -f` starts cron in foreground mode:
    -   Keeps the container alive
    -   Allows Docker to manage logs and lifecycle
    -   Ensures that cron jobs continue to run on schedule
    -   Foreground mode (`-f`) ensures the container keeps running and supervises the cron jobs.
---
#teste amaral