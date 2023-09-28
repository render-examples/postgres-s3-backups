#!/bin/bash

set -o errexit -o nounset -o pipefail

auth_gcloud() {
    gcloud auth login --cred-file=$GCS_AUTH_KEY_FILE
}

pg_dump_database() {
    pg_dump --no-owner --no-privileges --clean --if-exists --quote-all-identifiers --no-password "$DATABASE_URL"
}

upload_to_bucket() {
    # See https://cloud.google.com/sdk/gcloud/reference/storage/cp
    gcloud storage cp - "gs://$GCS_BUCKET_NAME/$(date +%Y-%m-%dT%H-%MZ.sql.gz)"
}

main() {
    auth_gcloud

    echo "Taking backup and uploading it to GCS..."
    pg_dump_database | gzip | upload_to_bucket
    echo "Done."
}

main
