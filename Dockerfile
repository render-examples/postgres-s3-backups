FROM amazon/aws-cli:latest
ARG POSTGRES_VERSION

RUN yum update -y \
    && yum install -y gzip

WORKDIR /scripts
COPY install-pg-dump.sh .
RUN "/scripts/install-pg-dump.sh"

COPY backup.sh .
COPY restore_backup.sh .
COPY incremental_copy.sh .
ENTRYPOINT [ "/scripts/backup.sh" ]
