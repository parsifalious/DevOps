#!/usr/bin/env bash
set -euo pipefail

RUNNER_NAME="gitlab-runner-lab"
RUNNER_IMAGE="gitlab/gitlab-runner:alpine-v18.5.0"
CONFIG_DIR="/var/lib/gitlab-runner-lab/config"
SERVICE="gitlab-runner.service"

command -v docker >/dev/null || {
    echo "Error: Docker is not installed" >&2
    exit 1
}

sudo systemctl is-active --quiet docker || {
    echo "Error: Docker is not running" >&2
    exit 1
}

sudo mkdir -p "$CONFIG_DIR"
sudo chmod 700 "$CONFIG_DIR"

if ! sudo docker container inspect "$RUNNER_NAME" \
    >/dev/null 2>&1; then

    sudo docker create \
        --name "$RUNNER_NAME" \
        --restart=no \
        -v "$CONFIG_DIR:/etc/gitlab-runner:Z" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        "$RUNNER_IMAGE"
else
    echo "Existing runner container preserved"
fi

sudo docker update --restart=no "$RUNNER_NAME" >/dev/null

sudo tee /etc/systemd/system/"$SERVICE" >/dev/null <<'EOF'
[Unit]
Description=GitLab Runner Docker Container
Requires=docker.service
After=docker.service
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/bin/docker start -a gitlab-runner-lab
ExecStop=/usr/bin/docker stop -t 30 gitlab-runner-lab
Restart=on-failure
RestartSec=10
TimeoutStopSec=45

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
sudo systemctl start "$SERVICE"

echo "GitLab Runner installation completed"
