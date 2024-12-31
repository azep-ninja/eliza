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

# Get deployment ID from metadata
DEPLOYMENT_ID=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
echo "Deployment ID: ${DEPLOYMENT_ID}"

# Configure gcloud auth
echo "Configuring gcloud auth..."
gcloud auth configure-docker us-east1-docker.pkg.dev --quiet

echo "Startup completed successfully"