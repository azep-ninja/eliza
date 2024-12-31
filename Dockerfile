# Use Node.js 23.3.0 as specified in package.json
FROM node:23.3.0-slim AS builder

# Install pnpm globally and install necessary build tools
RUN npm install -g pnpm@9.4.0 && \
    apt-get update && \
    apt-get install -y git python3 make g++ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set Python 3 as the default python
RUN ln -s /usr/bin/python3 /usr/bin/python

WORKDIR /app

# Copy all workspace files first
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc turbo.json ./
COPY packages ./packages
COPY agent ./agent
COPY scripts ./scripts

# Install dependencies and build the project
RUN pnpm install && \
    pnpm build-docker && \
    pnpm prune --prod

# Final stage
FROM node:23.3.0-slim

# Install runtime dependencies and certificates first
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        python3 \
        curl \
        gnupg \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN npm install -g pnpm@9.4.0

# Install runtime dependencies and Google Cloud SDK
RUN npm install -g pnpm@9.4.0 && \
    apt-get update && \
    apt-get install -y git python3 curl gnupg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && \
    apt-get install -y google-cloud-sdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only necessary files from builder
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/.npmrc ./
COPY --from=builder /app/turbo.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/agent ./agent
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/scripts ./scripts

# Create characters directory
RUN mkdir -p characters

# Add debugging to startup command
CMD sh -c '\
    echo "Debug: Starting container initialization" && \
    last_update="" && \
    while true; do \
        # Check metadata for updates
        current_update=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger") && \
        if [ "$current_update" != "$last_update" ]; then \
            echo "Update triggered" && \
            # Get list of active characters
            active_characters=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
            echo "Active characters: $active_characters" && \
            # Copy all character files (even inactive ones)
            echo "Copying all character files..." && \
            gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ && \
            echo "All character files:" && \
            ls -la /app/characters/ && \
            # Filter for only active characters
            character_files=$(echo "$active_characters" | jq -r ".[]" | while read char; do \
                find /app/characters -name "${char}.character.json"; \
            done | paste -sd "," -) && \
            if [ -n "$character_files" ]; then \
                echo "Restarting with active character files: $character_files" && \
                pkill -f "pnpm start" || true && \
                pnpm start --non-interactive --characters="$character_files" & \
            fi && \
            last_update=$current_update; \
        fi && \
        sleep 30; \
    done & \
    \
    # Initial startup using all available characters
    echo "Debug: Environment variables:" && \
    env | grep -E "AGENTS_BUCKET_NAME|DEPLOYMENT_ID" && \
    echo "Debug: Copying character files..." && \
    gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ && \
    echo "Debug: Character files:" && \
    ls -la /app/characters/ && \
    # Get initial active characters from metadata
    active_characters=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
    if [ -n "$active_characters" ]; then \
        character_files=$(echo "$active_characters" | jq -r ".[]" | while read char; do \
            find /app/characters -name "${char}.character.json"; \
        done | paste -sd "," -) && \
        echo "Starting with active character files: $character_files" && \
        pnpm start --non-interactive --characters="$character_files"; \
    else \
        # If no active characters specified, use all available ones
        character_files=$(find /app/characters -name "*.character.json" | paste -sd "," -) && \
        if [ -n "$character_files" ]; then \
            echo "Starting with all character files: $character_files" && \
            pnpm start --non-interactive --characters="$character_files"; \
        else \
            echo "ERROR: No character files found in /app/characters/" && \
            exit 1; \
        fi; \
    fi'