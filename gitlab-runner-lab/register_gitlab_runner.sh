
#!/usr/bin/env bash
set -euo pipefail
umask 077

API="https://gitlab.com/api/v4"
GITLAB_URL="https://gitlab.com"
RUNNER_NAME="gitlab-runner-lab"
RUNNER_TAG="local-devops"
STATE_DIR="/var/lib/gitlab-runner-lab"
STATE_FILE="$STATE_DIR/runner.json"
CONFIG_FILE="$STATE_DIR/config/config.toml"

die() {
    echo "Error: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "Usage: $0 GROUP_URL"
[[ -n "${GITLAB_TOKEN:-}" ]] || die "GITLAB_TOKEN is missing"

for cmd in curl jq docker flock; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Missing dependency: $cmd"
done

GROUP_URL="${1%/}"

[[ "$GROUP_URL" == https://gitlab.com/* ]] ||
    die "Expected a GitLab.com group URL"

GROUP_PATH="${GROUP_URL#https://gitlab.com/}"

[[ -n "$GROUP_PATH" ]] ||
    die "Group path is empty"

GROUP_ENCODED=$(jq -rn \
    --arg path "$GROUP_PATH" '$path | @uri')

sudo mkdir -p "$STATE_DIR/config"
sudo chmod 700 "$STATE_DIR"
sudo chmod 700 "$STATE_DIR/config"

# Prevent simultaneous registration attempts
exec 9>"$HOME/.gitlab-runner-registration.lock"
flock -n 9 || die "Registration already in progress"

# Resolve group ID
GROUP_ID=$(curl -fsS \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$API/groups/$GROUP_ENCODED" |
    jq -er '.id') || die "Cannot resolve GitLab group"

echo "Group ID: $GROUP_ID"

sudo docker container inspect "$RUNNER_NAME" \
    >/dev/null 2>&1 ||
    die "Runner container missing. Run installation first."

# Read existing registration state
if sudo test -s "$STATE_FILE"; then
    SAVED_GROUP=$(sudo cat "$STATE_FILE" |
        jq -r '.group_id')

    [[ "$SAVED_GROUP" == "$GROUP_ID" ]] ||
        die "Existing runner belongs to another group"

    RUNNER_ID=$(sudo cat "$STATE_FILE" |
        jq -er '.id')

    RUNNER_TOKEN=$(sudo cat "$STATE_FILE" |
        jq -er '.token')

    echo "Reusing runner ID: $RUNNER_ID"
else
    echo "Creating GitLab group runner..."

    RESPONSE=$(curl -fsS -X POST \
        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
        --data-urlencode "runner_type=group_type" \
        --data-urlencode "group_id=$GROUP_ID" \
        --data-urlencode "description=$RUNNER_NAME" \
        --data-urlencode "tag_list=$RUNNER_TAG" \
        --data-urlencode "run_untagged=false" \
        "$API/user/runners") ||
        die "Failed to create runner through API"

    RUNNER_ID=$(jq -er '.id' <<< "$RESPONSE")
    RUNNER_TOKEN=$(jq -er '.token' <<< "$RESPONSE")

    # Save state before local registration so retries
    # can reuse the same GitLab runner record.
    jq -n \
        --argjson id "$RUNNER_ID" \
        --argjson group_id "$GROUP_ID" \
        --arg token "$RUNNER_TOKEN" \
        --arg tag "$RUNNER_TAG" \
        '{
            id: $id,
            group_id: $group_id,
            token: $token,
            tag: $tag
        }' | sudo tee "$STATE_FILE" >/dev/null

    sudo chmod 600 "$STATE_FILE"
fi

# Verify that the remote runner still exists
HTTP_CODE=$(curl -sS -o /dev/null \
    -w "%{http_code}" \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    "$API/runners/$RUNNER_ID")

[[ "$HTTP_CODE" == "200" ]] ||
    die "Remote runner verification failed: HTTP $HTTP_CODE"

# Avoid duplicate local configuration entries
if sudo test -f "$CONFIG_FILE" &&
   sudo grep -Fq "$RUNNER_TOKEN" "$CONFIG_FILE"; then
    echo "Local runner configuration already exists"
else
    echo "Registering local Docker executor..."

    sudo docker exec "$RUNNER_NAME" \
        gitlab-runner register \
        --non-interactive \
        --url "$GITLAB_URL/" \
        --token "$RUNNER_TOKEN" \
        --executor "docker" \
        --docker-image "alpine:3.20" \
        --description "$RUNNER_NAME" ||
        die "Local registration failed"
fi

echo "Registration complete"
echo "Runner ID: $RUNNER_ID"
echo "Runner tag: $RUNNER_TAG"
