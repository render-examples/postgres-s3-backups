#!/bin/bash

set -o errexit -o pipefail

s3() {
    aws s3 --region "$AWS_REGION" "$@"
}

s3api() {
    aws s3api "$1" --region "$AWS_REGION" --bucket "$S3_BUCKET_NAME" "${@:2}"
}

get_last_backup_full_key() {
    s3api list-objects-v2 \
        --prefix "db_backups/" \
        --query "reverse(sort_by(Contents, &Key))[0].Key" \
        --output text
}

get_last_backup() {
    local full_key=$(get_last_backup_full_key)
    echo "${full_key#db_backups/}"
}

download_backup() {
    formatted_key="$1"
    echo "Downloading $formatted_key..."
    s3 cp "s3://$S3_BUCKET_NAME/db_backups/$formatted_key" ./downloaded_dump.sql.gz
}

download_last_backup() {
    echo "Finding last backup..."
    local last_backup=$(get_last_backup)
    download_backup "$last_backup"
}

restore_backup() {
    local pg_conn_url="$1"
    gunzip -c ./downloaded_dump.sql.gz | psql "$pg_conn_url"

    if [ $? -eq 0 ]; then
        echo "Backup restored successfully."
    else
        echo "Error: Backup restoration failed."
        exit 1
    fi
}

main() {
    if [[ $# -lt 1 || $# -gt 3 ]]; then
        echo "Usage: $0 [-y] <restoration_url> [backup_key]"
        exit 1
    fi

    local confirm=false
    local restoration_url
    local backup_key

    if [[ $1 == "-y" ]]; then
        confirm=true
        shift
    fi

    if [[ -z $1 ]]; then
        echo "Error: Restoration URL is required."
        echo "Usage: $0 [-y] <restoration_url> [backup_key]"
    else
        restoration_url=$1
        shift
    fi

    if [[ -n $1 ]]; then
        backup_key=$1
    fi

    if [[ $confirm != true ]]; then
        read -p "Are you sure you want to proceed with the backup restoration? (y/n) " confirmation
        if [[ $confirmation != "y" && $confirmation != "Y" ]]; then
            echo "Operation cancelled."
            exit 1
        fi
    fi

    if [[ -n $backup_key ]]; then
        download_backup "$backup_key"
    else
        download_last_backup
    fi

    restore_backup "$restoration_url"
}

main "$@"
