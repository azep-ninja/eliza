#!/bin/bash

# Log startup for debugging
echo "Starting initialization script..."

# Use /mnt/stateful_partition which is writable in GCE
mkdir -p /mnt/stateful_partition/agent/data
chmod 777 /mnt/stateful_partition/agent/data

# Verify directory creation
ls -la /mnt/stateful_partition/qi-agents/

# Pull latest image
echo "Pulling latest image..."
docker pull us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version}

# Run container with persistent storage and restart policy
echo "Starting container..."
docker run -d \
    --name ${FULL_NAME} \
    --restart=always \
    -v /mnt/stateful_partition/agent/data:/app/agent/data \
    -e AGENTS_BUCKET_NAME="gs://$AGENTS_BUCKET_NAME" \
    -e CHARACTER_FILE="$CHARACTER_FILE" \
    -e SMALL_GOOGLE_MODEL="$SMALL_GOOGLE_MODEL" \
    -e MEDIUM_GOOGLE_MODEL="$MEDIUM_GOOGLE_MODEL" \
    -e GOOGLE_GENERATIVE_AI_API_KEY="$GOOGLE_GENERATIVE_AI_API_KEY" \
    us-central1-docker.pkg.dev/${PROJECT_ID}/${FULL_NAME}:${version}

# Log container status
echo "Container started. Checking status..."
docker ps | grep ${FULL_NAME}