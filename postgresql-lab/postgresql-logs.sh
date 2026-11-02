#!/bin/bash

LOG_DIR=/var/log/postgresql-container
mkdir -p "$LOG_DIR"

while true; do
    if ! docker inspect postgresql >/dev/null 2>&1; then
        sleep 2
	continue 
    fi

    docker logs --follow --since 2s --timestamps postgresql \
        >> "$LOG_DIR/output.log" \
        2>> "$LOG_DIR/error.log"
    sleep 2
done
