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
if ! docker pull us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version}; then
    echo "Failed to pull image"
    exit 1
fi

# Get secrets from Secret Manager
echo "Fetching secrets..."
AGENTS_BUCKET_NAME=$(gcloud secrets versions access latest --secret="agents-bucket-name") || {
    echo "Failed to fetch agents-bucket-name secret"
    exit 1
}
SMALL_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="small-google-model") || {
    echo "Failed to fetch small-google-model secret"
    exit 1
}
MEDIUM_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="medium-google-model") || {
    echo "Failed to fetch medium-google-model secret"
    exit 1
}
GOOGLE_GENERATIVE_AI_API_KEY=$(gcloud secrets versions access latest --secret="google-generative-ai-key") || {
    echo "Failed to fetch google-generative-ai-key secret"
    exit 1
}

# Debug existing environment variables
echo "Debug: Checking existing environment variables:"
echo "AGENTS_BUCKET_NAME from environment: ${AGENTS_BUCKET_NAME}"
echo "CHARACTER_FILE from environment: ${CHARACTER_FILE}"

# Run container with persistent storage and restart policy
echo "Starting container with environment variables..."
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

# Verify container is running and check logs
echo "Checking container status and logs..."
sleep 5  # Give container a moment to start
if ! docker ps | grep ${FULL_NAME}; then
    echo "Container failed to start. Checking logs:"
    docker logs ${FULL_NAME}
    exit 1
fi

# Show container logs and verify environment variables
echo "Container environment variables:"
docker exec ${FULL_NAME} env | grep -E 'AGENTS_BUCKET_NAME|CHARACTER_FILE'

echo "Initial container logs:"
docker logs ${FULL_NAME}

echo "Startup script completed successfully"