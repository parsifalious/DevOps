#!/bin/bash

set -o pipefail

STATE_FILE=/run/postgresql-healthcheck.failures

if ! systemctl is-active --quiet postgresql.service; then
    rm -f "$STATE_FILE"
    exit 0
fi

if timeout 4 docker exec postgresql \
    psql -U postgres -d appdb -tAc "SELECT 1;" \
    | grep -qx '1'; then
    rm -f "$STATE_FILE"
    exit 0
fi
count=0
if [[ -f "$STATE_FILE" ]]; then
    read -r count< "$STATE_FILE"
fi

count=$((count+1))
echo "$count" > "$STATE_FILE"

logger -t postgresql-healthcheck \
    "PostgreSQL healthcheck failed ($count/3)"

if (( count >=3 )); then
    logger -t postgresql-healthcheck \
        "Three consecutive failures. Restarting PostgreSQL."

    rm -f "$STATE_FILE"
    systemctl restart --no-block postgresql.service
fi

exit 1
