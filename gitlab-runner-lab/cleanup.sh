
#!/usr/bin/env bash
set -euo pipefail

RUNNER_NAME="gitlab-runner-lab"
SERVICE="gitlab-runner.service"
STATE_DIR="/var/lib/gitlab-runner-lab"
STATE_FILE="$STATE_DIR/runner.json"
API="https://gitlab.com/api/v4"

echo "Starting GitLab Runner cleanup..."

if sudo test -s "$STATE_FILE"; then
    RUNNER_ID=$(sudo jq -r '.id' "$STATE_FILE")
    RUNNER_TOKEN=$(sudo jq -r '.token' "$STATE_FILE")

    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        echo "Error: GITLAB_TOKEN is required for remote cleanup" >&2
        exit 1
    fi

    echo "Removing GitLab runner ID: $RUNNER_ID"

    # Stop service before unregistering
    sudo systemctl stop "$SERVICE" 2>/dev/null || true

    # Remove local runner manager using its token
    if sudo docker container inspect "$RUNNER_NAME" >/dev/null 2>&1; then
        sudo docker run --rm \
            --volumes-from "$RUNNER_NAME" \
            --entrypoint gitlab-runner \
            gitlab/gitlab-runner:alpine-v18.5.0 \
            unregister \
            --url "https://gitlab.com/" \
            --token "$RUNNER_TOKEN" || true
    fi

    # Delete the remote runner record
    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X DELETE \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$API/runners/$RUNNER_ID")

    if [[ "$HTTP_CODE" != "204" &&
          "$HTTP_CODE" != "404" ]]; then
        echo "Error deleting runner: HTTP $HTTP_CODE" >&2
        exit 1
    fi
fi

# Disable and remove systemd service
sudo systemctl disable --now "$SERVICE" 2>/dev/null || true
sudo rm -f /etc/systemd/system/gitlab-runner.service
sudo systemctl daemon-reload

# Remove dedicated container
if sudo docker container inspect "$RUNNER_NAME" >/dev/null 2>&1; then
    sudo docker rm -f "$RUNNER_NAME"
fi

# Remove only our runner state
sudo rm -rf "$STATE_DIR"

echo "GitLab Runner cleanup completed"
