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
        jq && \
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
    normalize_and_copy_characters() { \
        echo "Debug: Copying and normalizing character files..." && \
        echo "Debug: Looking for files in gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" && \
        bucket_files=$(gsutil ls "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" 2>/dev/null) && \
        if [ -z "$bucket_files" ]; then \
            echo "Debug: No files found in bucket path" && \
            return 1; \
        fi && \
        echo "Debug: Found files in bucket: $bucket_files" && \
        for file in $bucket_files; do \
            filename=$(basename "$file") && \
            lowercase_filename=$(echo "$filename" | tr "[:upper:]" "[:lower:]") && \
            echo "Debug: Found file: $filename" && \
            echo "Debug: Converting to: $lowercase_filename" && \
            if gsutil cp "$file" "/app/characters/$lowercase_filename"; then \
                echo "Debug: Copied file successfully"; \
            else \
                echo "Error: Failed to copy $file"; \
                return 1; \
            fi \
        done && \
        echo "Debug: Normalized character files in directory:" && \
        ls -la /app/characters/ && \
        echo "Debug: Directory contents after copy:" && \
        find /app/characters -type f -name "*.character.json" | while read f; do echo "Found: $f"; done; \
    } && \

    # Initial startup
    echo "Debug: Initial startup at $(date)" && \
    echo "Debug: Environment variables:" && \
    env | grep -E "AGENTS_BUCKET_NAME|DEPLOYMENT_ID" && \
    normalize_and_copy_characters && \

    # Background update checker
    (while true; do \
        current_update=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger") && \
        if [ "$current_update" != "$last_update" ]; then \
            echo "Update triggered at $(date)" && \
            active_characters=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
            echo "Active characters from metadata: $active_characters" && \
            normalize_and_copy_characters && \
            if [ -n "$active_characters" ]; then \
                character_files=$(echo "$active_characters" | jq -r ".[]" | while read char; do \
                    char_lower=$(echo "$char" | tr "[:upper:]" "[:lower:]") && \
                    found_file="/app/characters/${char_lower}.character.json" && \
                    if [ -f "$found_file" ]; then \
                        echo "Found active character file: $found_file" >&2 && \
                        echo "$found_file"; \
                    else \
                        echo "Warning: No file found for active character: $char" >&2; \
                    fi; \
                done | paste -sd "," -) && \
                if [ -n "$character_files" ]; then \
                    echo "Starting with active character files: $character_files" && \
                    pkill -f "pnpm start" || true && \
                    pnpm start --non-interactive --characters="$character_files" & \
                else \
                    echo "Warning: No active character files found to start"; \
                fi; \
            fi && \
            last_update=$current_update; \
        fi && \
        sleep 30; \
    done) & \

    # Initial character start
    active_characters=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
    if [ -n "$active_characters" ]; then \
        character_files=$(echo "$active_characters" | jq -r ".[]" | while read char; do \
            char_lower=$(echo "$char" | tr "[:upper:]" "[:lower:]") && \
            found_file="/app/characters/${char_lower}.character.json" && \
            if [ -f "$found_file" ]; then \
                echo "Found active character file: $found_file" >&2 && \
                echo "$found_file"; \
            else \
                echo "Warning: No file found for active character: $char" >&2; \
            fi; \
        done | paste -sd "," -) && \
        if [ -n "$character_files" ]; then \
            echo "Starting with active character files: $character_files" && \
            exec pnpm start --non-interactive --characters="$character_files"; \
        fi; \
    else \
        character_files=$(find /app/characters -name "*.character.json" | paste -sd "," -) && \
        if [ -n "$character_files" ]; then \
            echo "Starting with all available character files: $character_files" && \
            exec pnpm start --non-interactive --characters="$character_files"; \
        else \
            echo "ERROR: No character files found in /app/characters/" && \
            exit 1; \
        fi; \
    fi'