FROM debian:bookworm

# Avoid interactive prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone (default: UTC)
ENV TZ=UTC
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
