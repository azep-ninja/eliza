#!/bin/bash

# Enable error checking and debugging
set -e  # Exit on any error
set -x  # Print each command before executing

# Log startup for debugging
echo "Starting initialization script..."

# Check if directory exists first and show current permissions
echo "Checking current state..."
ls -la /mnt || true
ls -la /mnt/stateful_partition || true

# Try creating base directory first
echo "Creating base directory..."
if ! sudo mkdir -p /mnt/stateful_partition; then
    echo "Failed to create /mnt/stateful_partition"
    # Try to identify the issue
    df -h
    mount | grep /mnt
    ls -la /mnt
    exit 1
fi

# Try alternative locations if stateful_partition isn't working
if [ ! -d "/mnt/stateful_partition" ]; then
    echo "Using alternative directory /var/lib/qi-agents"
    sudo mkdir -p /var/lib/qi-agents || {
        echo "Failed to create alternative directory"
        exit 1
    }
    AGENT_DATA_DIR="/var/lib/qi-agents"
else
    AGENT_DATA_DIR="/mnt/stateful_partition/qi-agents"
    # Create qi-agents directory
    sudo mkdir -p "$AGENT_DATA_DIR" || {
        echo "Failed to create qi-agents directory"
        exit 1
    }
fi

# Create data directory
echo "Creating data directory in $AGENT_DATA_DIR..."
sudo mkdir -p "$AGENT_DATA_DIR/data" || {
    echo "Failed to create data directory"
    exit 1
}

# Set permissions with verbose output
echo "Setting directory permissions..."
sudo chmod -Rv 777 "$AGENT_DATA_DIR" || {
    echo "Failed to set permissions"
    exit 1
}

# Verify directory structure and permissions
echo "Verifying directory structure..."
ls -la "$AGENT_DATA_DIR"
ls -la "$AGENT_DATA_DIR/data"

# Pull latest image with verification
echo "Pulling latest image..."
docker pull us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version} 2>&1 | tee /tmp/docker-pull.log || {
    echo "Failed to pull image, logs:"
    cat /tmp/docker-pull.log
    exit 1
}

# Get secrets from Secret Manager
echo "Fetching secrets..."
AGENTS_BUCKET_NAME=$(gcloud secrets versions access latest --secret="agents-bucket-name")
SMALL_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="small-google-model")
MEDIUM_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="medium-google-model")
GOOGLE_GENERATIVE_AI_API_KEY=$(gcloud secrets versions access latest --secret="google-generative-ai-key")

# Run container with persistent storage and restart policy
echo "Starting container..."
docker run -d \
    --name ${FULL_NAME} \
    --restart=always \
    -v "$AGENT_DATA_DIR/data":/app/agent/data \
    -e AGENTS_BUCKET_NAME="${AGENTS_BUCKET_NAME}" \
    -e CHARACTER_FILE="${CHARACTER_FILE}" \
    -e SMALL_GOOGLE_MODEL="${SMALL_GOOGLE_MODEL}" \
    -e MEDIUM_GOOGLE_MODEL="${MEDIUM_GOOGLE_MODEL}" \
    -e GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY}" \
    -e PORT="8080" \
    -e SERVER_PORT="8080" \
    us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version}

# Verify container is running
echo "Container started. Checking status..."
if ! docker ps | grep ${FULL_NAME}; then
    echo "Container failed to start. Checking logs:"
    docker logs ${FULL_NAME}
    exit 1
fi

# Final verification
echo "Verifying final state..."
df -h
mount
docker ps
ls -la "$AGENT_DATA_DIR"

echo "Startup script completed successfully"