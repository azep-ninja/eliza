#!/bin/bash
set -e
set -x

echo "Starting initialization script..."

# Create data directory
AGENT_DATA_DIR="/var/lib/qi-agents"
echo "Creating data directory in $AGENT_DATA_DIR..."
sudo mkdir -p "$AGENT_DATA_DIR/data" || {
    echo "Failed to create data directory"
    exit 1
}

# Set permissions
echo "Setting directory permissions..."
sudo chmod -R 777 "$AGENT_DATA_DIR" || {
    echo "Failed to set permissions"
    exit 1
}

# Configure Docker daemon
echo "Configuring Docker daemon..."
DOCKER_CONFIG_DIR="/etc/docker"
sudo mkdir -p "$DOCKER_CONFIG_DIR"
cat << 'EOF' | sudo tee "$DOCKER_CONFIG_DIR/daemon.json"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.size=25G"
  ],
  "live-restore": true,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 5
}
EOF

# Get deployment ID from metadata
DEPLOYMENT_ID=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
echo "Deployment ID: ${DEPLOYMENT_ID}"

# Configure gcloud auth
echo "Configuring gcloud auth..."
gcloud auth configure-docker us-east1-docker.pkg.dev --quiet

# Set up periodic cleanup using cron
echo "Setting up periodic image cleanup..."
(crontab -l 2>/dev/null; echo "0 */12 * * * docker image prune -af --filter 'until=48h'") | crontab -

echo "Startup completed successfully"