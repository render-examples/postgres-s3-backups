#!/usr/bin/env bash

set -o errexit -o pipefail -o nounset


if [[ -z "$POSTGRES_VERSION" ]]; then
  echo "POSTGRES_VERSION must be set"
  exit 1
fi

if [[ "$POSTGRES_VERSION" != @(11|12|13|14|15|16) ]]; then
  echo "POSTGRES_VERSION must be one of 11, 12, 13, 14, 15, 16"
  exit 1
fi

# if POSTGRES_VERSION is 16:
if [[ "$POSTGRES_VERSION" == 16 ]]; then
  dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
  dnf install -y postgresql16
  exit 0
fi

cat <<EOF > /etc/yum.repos.d/pgdg.repo
[pgdg$POSTGRES_VERSION]
name=PostgreSQL $POSTGRES_VERSION for RHEL/CentOS 7 - x86_64
baseurl=http://download.postgresql.org/pub/repos/yum/$POSTGRES_VERSION/redhat/rhel-7-x86_64
enabled=1
gpgcheck=0
EOF

yum install postgresql$POSTGRES_VERSION-server -y
