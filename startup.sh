#!/bin/bash

# Log startup for debugging
echo "Starting initialization script..."

# Create the directory for SQLite database
mkdir -p /agent/data
chmod 777 /agent/data

# Setting up restart policy
# Always try to restart the container if it exits
RESTART_POLICY="--restart=always"

# Check if old container exists and remove it
if [ "$(docker ps -aq -f name=${FULL_NAME})" ]; then
    echo "Removing old container..."
    docker rm -f ${FULL_NAME}
fi

# Pull latest image
echo "Pulling latest image..."
docker pull gcr.io/${PROJECT_ID}/${FULL_NAME}

# Run container with persistent storage and restart policy
echo "Starting container..."
docker run -d \
    --name ${FULL_NAME} \
    ${RESTART_POLICY} \
    -v /agent/data:/app/agent/data \
    -e AGENTS_BUCKET_NAME="$AGENTS_BUCKET_NAME" \
    -e CHARACTER_FILE="$CHARACTER_FILE" \
    -e SMALL_GOOGLE_MODEL="$SMALL_GOOGLE_MODEL" \
    -e MEDIUM_GOOGLE_MODEL="$MEDIUM_GOOGLE_MODEL" \
    -e GOOGLE_GENERATIVE_AI_API_KEY="$GOOGLE_GENERATIVE_AI_API_KEY" \
    gcr.io/${PROJECT_ID}/${FULL_NAME}

# Log container status
echo "Container started. Checking status..."
docker ps | grep ${FULL_NAME}