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

# Install dependencies with fallback
RUN pnpm install --frozen-lockfile || \
    (echo "Frozen lockfile install failed, trying without..." && \
    pnpm install --no-frozen-lockfile) && \
    pnpm list && \
    echo "Dependencies installed successfully"

# Build with detailed logging
RUN set -e && \
    for i in 1 2 3; do \
        echo "Build attempt $i" && \
        PNPM_DEBUG=1 pnpm build-docker && exit 0 || \
        echo "Build failed, retrying..." && \
        sleep 5; \
    done && \
    echo "All build attempts failed" && \
    find . -name "*.log" -type f -exec cat {} + && \
    exit 1

# Prune for production
RUN pnpm prune --prod && \
    echo "Production pruning completed"

# Final stage
FROM node:23.3.0-slim

# Install runtime dependencies and certificates first
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        python3 \
        curl \
        gnupg \
        ca-certificates \
        jq \
        procps && \
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

# Create characters and knowledge directory
RUN mkdir -p characters && \
    mkdir -p characters/knowledge

# Debugging and character monitoring to startup command
CMD sh -c '\
    # Initial setup \
    echo "Debug: Starting container initialization" && \
    env | grep -E "AGENTS_BUCKET_NAME|DEPLOYMENT_ID" && \
    gsutil ls "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/" && \
    gsutil ls "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge" && \
    gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ || true && \
    ls -la /app/characters/ && \
    gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge/*" /app/characters/knowledge || true && \
    ls -la /app/characters/knowledge && \
    \
    active_characters_raw=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
    active_characters=$(echo "$active_characters_raw" | sed "s/;/,/g") && \
    if [ -n "$active_characters" ]; then \
        echo "Active characters from metadata: $active_characters" && \
        chars_temp="" && \
        for char in $(echo "$active_characters" | sed "s/[][\"]//g" | tr "," " "); do \
            if [ -n "$chars_temp" ]; then chars_temp="$chars_temp,"; fi && \
            chars_temp="${chars_temp}/app/characters/${char}.character.json"; \
        done && \
        character_files="$chars_temp" && \
        \
        if [ -n "$character_files" ]; then \
            echo "Using character files: $character_files" && \
            initial_update=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger" || echo "0") && \
            last_update="$initial_update" && \
            \
            while true; do \
                echo "Starting agent with characters..." && \
                PNPM_NO_LIFECYCLE_ERRORS=true pnpm start --non-interactive --characters="$character_files" & \
                main_pid=$! && \
                update_lock="/tmp/update.lock" && \
                rm -f "$update_lock" && \
                \
                { \
                    while kill -0 $main_pid 2>/dev/null; do \
                        current_update=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger" || echo "$last_update") && \
                        if [ "$current_update" != "$last_update" ]; then \
                            touch "$update_lock" && \
                            echo "Configuration update at $(date)" && \
                            gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ || true && \
                            gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge/*" /app/characters/knowledge || true && \
                            \
                            new_chars_raw=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
                            new_chars=$(echo "$new_chars_raw" | sed "s/;/,/g") && \
                            chars_temp="" && \
                            for char in $(echo "$new_chars" | sed "s/[][\"]//g" | tr "," " "); do \
                                if [ -n "$chars_temp" ]; then chars_temp="$chars_temp,"; fi && \
                                chars_temp="${chars_temp}/app/characters/${char}.character.json"; \
                            done && \
                            character_files="$chars_temp" && \
                            last_update="$current_update" && \
                            kill $main_pid && \
                            break; \
                        fi; \
                        sleep 30; \
                    done; \
                } & \
                watch_pid=$! && \
                wait $main_pid; \
                exit_code=$? && \
                kill $watch_pid 2>/dev/null || true && \
                rm -f "$update_lock" && \
                if [ $exit_code -ne 0 ]; then exit $exit_code; fi && \
                sleep 2; \
            done; \
        else \
            sleep infinity; \
        fi; \
    else \
        sleep infinity; \
    fi'