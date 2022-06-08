FROM amazon/aws-cli:latest
ARG POSTGRES_VERSION

RUN yum update -y \
    && yum install -y gzip

WORKDIR /scripts
COPY install-pg_dump.sh .
RUN "/scripts/install-pg_dump.sh"

COPY backup.sh .
ENTRYPOINT [ "/scripts/backup.sh" ]
