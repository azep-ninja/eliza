#!/bin/bash

# Log startup for debugging
echo "Starting initialization script..."

# Create parent directories first with error checking
echo "Creating directory structure..."
sudo mkdir -p /mnt/stateful_partition || {
    echo "Failed to create stateful_partition directory"
    exit 1
}

# Create qi-agents directory
sudo mkdir -p /mnt/stateful_partition/qi-agents || {
    echo "Failed to create qi-agents directory"
    exit 1
}

# Create data directory
sudo mkdir -p /mnt/stateful_partition/qi-agents/data || {
    echo "Failed to create data directory"
    exit 1
}

# Set permissions
echo "Setting directory permissions..."
sudo chmod -R 777 /mnt/stateful_partition/qi-agents || {
    echo "Failed to set permissions"
    exit 1
}

# Verify directory structure
echo "Verifying directory structure..."
ls -la /mnt/stateful_partition/qi-agents/

# Pull latest image with verification
echo "Pulling latest image..."
if ! docker pull us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version}; then
    echo "Failed to pull image"
    exit 1
fi

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
    -v /mnt/stateful_partition/qi-agents/data:/app/agent/data \
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

# Log success
echo "Startup script completed successfully"