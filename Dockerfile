# Accept PostgreSQL version as an argument
ARG POSTGRES_VERSION
FROM postgres:${POSTGRES_VERSION}

# Set the working directory
WORKDIR /scripts

# Copy your scripts into the container
COPY backup.sh .
COPY restore_backup.sh .
COPY incremental_copy.sh .
COPY install-pg-dump.sh .

# Ensure the scripts have execution permissions
RUN chmod +x backup.sh restore_backup.sh incremental_copy.sh install-pg-dump.sh

# Install necessary tools
RUN apt-get update && apt-get install -y awscli

# Set the entrypoint to your backup script
ENTRYPOINT [ "/scripts/backup.sh" ]