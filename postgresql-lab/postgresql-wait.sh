#!/bin/bash
for i in $(seq 1 60); do
    if timeout 1 docker exec postgresql \
        psql -U postgres -d appdb -tAc "SELECT 1;" \
        2>/dev/null | grep -qx '1'; then
	echo "PostgreSQL is ready"
	exit 0
    fi

    sleep 1
done

echo "PostgreSQL failed to become ready" >&2
exit 1
