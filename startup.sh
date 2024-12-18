#!/bin/bash

# Extract agent name from CHARACTER_FILE
AGENT_NAME=$(echo $CHARACTER_FILE | sed 's/\.character\.json//' | sed 's/_/-/g')

# Add suffix if provided
if [ ! -z "$SUFFIX" ]; then
  FULL_NAME="$AGENT_NAME-$SUFFIX"
else
  FULL_NAME="$AGENT_NAME"
fi

# Create the directory for SQLite database
mkdir -p /agent/data
chmod 777 /agent/data

# Pull and run the container
docker pull gcr.io/$PROJECT_ID/$FULL_NAME
docker run -d \
  --name $FULL_NAME \
  --restart always \
  -v /agent/data:/app/agent/data \
  -e AGENTS_BUCKET_NAME="$AGENTS_BUCKET_NAME" \
  -e CHARACTER_FILE="$CHARACTER_FILE" \
  -e SMALL_GOOGLE_MODEL="$SMALL_GOOGLE_MODEL" \
  -e MEDIUM_GOOGLE_MODEL="$MEDIUM_GOOGLE_MODEL" \
  -e GOOGLE_GENERATIVE_AI_API_KEY="$GOOGLE_GENERATIVE_AI_API_KEY" \
  gcr.io/$PROJECT_ID/$FULL_NAME