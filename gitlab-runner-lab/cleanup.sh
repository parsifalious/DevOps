
#!/usr/bin/env bash
set -euo pipefail

RUNNER_NAME="gitlab-runner-lab"
SERVICE="gitlab-runner.service"
STATE_DIR="/var/lib/gitlab-runner-lab"
STATE_FILE="$STATE_DIR/runner.json"
API="https://gitlab.com/api/v4"

echo "Starting GitLab Runner cleanup..."

if sudo test -s "$STATE_FILE"; then
    [[ -n "${GITLAB_TOKEN:-}" ]] || {
        echo "Error: GITLAB_TOKEN is required" >&2
        exit 1
    }

    RUNNER_ID=$(sudo jq -er '.id' "$STATE_FILE")

    echo "Deleting remote runner ID: $RUNNER_ID"

    HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
        --retry 2 \
        -X DELETE \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        "$API/runners/$RUNNER_ID")

    case "$HTTP_CODE" in
        204|404)
            echo "Remote runner removed or already absent"
            ;;
        *)
            echo "Error: GitLab API returned HTTP $HTTP_CODE" >&2
            exit 1
            ;;
    esac
fi

# Stop and disable the dedicated systemd service
if sudo systemctl cat "$SERVICE" >/dev/null 2>&1; then
    sudo systemctl disable --now "$SERVICE"
fi

# Remove only our service unit
sudo rm -f "/etc/systemd/system/$SERVICE"
sudo systemctl daemon-reload

# Remove only our dedicated Docker container
if sudo docker container inspect "$RUNNER_NAME" >/dev/null 2>&1; then
    sudo docker rm -f "$RUNNER_NAME"
fi

# Remove dedicated configuration and saved state
sudo rm -rf -- "$STATE_DIR"

echo "GitLab Runner cleanup completed"
