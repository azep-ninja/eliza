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
CMD sh -c 'echo "Debug: Starting container initialization" && \
env | grep -E "AGENTS_BUCKET_NAME|DEPLOYMENT_ID" && \
gsutil ls "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/" && \
gsutil ls "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge" && \
gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ || true && \
ls -la /app/characters/ && \
gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge/*" /app/characters/knowledge || true && \
ls -la /app/characters/knowledge && \
active_characters_raw=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
active_characters=$(echo "$active_characters_raw" | sed "s/;/,/g") && \
if [ -n "$active_characters" ]; then \
    echo "Active characters from metadata: $active_characters" && \
    chars_temp="" && \
    for char in $(echo "$active_characters" | sed "s/[][\"]//g" | tr "," " "); do \
        [ -n "$chars_temp" ] && chars_temp="${chars_temp}," ; \
        character_file="/app/characters/${char}.character.json" && \
        if secret_ref=$(jq -r ".settings.secrets._secretRef" "$character_file") && [ "$secret_ref" != "null" ]; then \
            echo "Processing secrets for character: $char" && \
            key_name=$(jq -r ".settings.secrets._keyName" "$character_file") && \
            temp_cipher=$(mktemp) && \
            temp_plain=$(mktemp) && \
            gcloud secrets versions access latest --secret="$secret_ref" --out-file="$temp_cipher" && \
            if gcloud kms decrypt \
                --key="$key_name" \
                --location=global \
                --ciphertext-file="$temp_cipher" \
                --plaintext-file="$temp_plain"; then \
                temp_file=$(mktemp) && \
                chmod 600 "$temp_file" && \
                jq --arg secrets "$(cat $temp_plain)" \
                   ".settings.secrets = (\$secrets | fromjson)" \
                   "$character_file" > "$temp_file" && \
                mv "$temp_file" "$character_file" && \
                echo "Successfully decrypted secrets for: $char" ; \
            else \
                echo "Failed to decrypt secrets for: $char" ; \
            fi && \
            rm -f "$temp_cipher" "$temp_plain" ; \
        fi; \
        chars_temp="${chars_temp}${character_file}" ; \
    done && \
    character_files="$chars_temp" && \
    if [ -n "$character_files" ]; then \
        echo "Using character files: $character_files" && \
        initial_update=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger" || echo "0") && \
        last_update="$initial_update" && \
        backup_trigger=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/backup-trigger" || echo "0") && \
        last_backup="$backup_trigger" && \
        storage_check=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/storage-check-trigger" || echo "0") && \
        last_storage_check="$storage_check" && \
        while true; do \
            echo "Starting agent with characters..." && \
            PNPM_NO_LIFECYCLE_ERRORS=true pnpm start --non-interactive --characters="$character_files" & \
            main_pid=$! && \
            update_lock="/tmp/update.lock" && \
            rm -f "$update_lock" && \
            while kill -0 $main_pid 2>/dev/null; do \
                if [ ! -f "$update_lock" ]; then \
                    # Check for configuration updates
                    current_update=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/character-update-trigger" || echo "$last_update") && \
                    if [ "$current_update" != "$last_update" ]; then \
                        touch "$update_lock" && \
                        echo "Configuration update started at $(date)" && \
                        gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/*.character.json" /app/characters/ || true && \
                        gsutil -m cp "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/knowledge/*" /app/characters/knowledge || true && \
                        new_chars_raw=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/active-characters") && \
                        new_chars_temp="" && \
                        for c in $(echo "$new_chars_raw" | sed "s/[][\"]//g;s/;/,/g" | tr "," " "); do \
                            if [ -f "/app/characters/${c}.character.json" ]; then \
                                [ -n "$new_chars_temp" ] && new_chars_temp="${new_chars_temp}," ; \
                                character_file="/app/characters/${c}.character.json" && \
                                if secret_ref=$(jq -r ".settings.secrets._secretRef" "$character_file") && [ "$secret_ref" != "null" ]; then \
                                    echo "Processing secrets for character update: $c" && \
                                    key_name=$(jq -r ".settings.secrets._keyName" "$character_file") && \
                                    temp_cipher=$(mktemp) && \
                                    temp_plain=$(mktemp) && \
                                    gcloud secrets versions access latest --secret="$secret_ref" --out-file="$temp_cipher" && \
                                    if gcloud kms decrypt \
                                        --key="$key_name" \
                                        --location=global \
                                        --ciphertext-file="$temp_cipher" \
                                        --plaintext-file="$temp_plain"; then \
                                        temp_file=$(mktemp) && \
                                        chmod 600 "$temp_file" && \
                                        jq --arg secrets "$(cat $temp_plain)" \
                                           ".settings.secrets = (\$secrets | fromjson)" \
                                           "$character_file" > "$temp_file" && \
                                        mv "$temp_file" "$character_file" && \
                                        echo "Successfully decrypted secrets for update: $c" ; \
                                    else \
                                        echo "Failed to decrypt secrets for update: $c" ; \
                                    fi && \
                                    rm -f "$temp_cipher" "$temp_plain" ; \
                                fi; \
                                new_chars_temp="${new_chars_temp}${character_file}" ; \
                            fi; \
                        done && \
                        if [ -n "$new_chars_temp" ]; then \
                            character_files="$new_chars_temp" && \
                            last_update="$current_update" && \
                            echo "Updated character list: $character_files" && \
                            kill $main_pid && \
                            break; \
                        fi && \
                        rm -f "$update_lock"; \
                    fi && \

                    # Check for backup trigger
                    current_backup=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/backup-trigger" || echo "$last_backup") && \
                    if [ "$current_backup" != "$last_backup" ]; then \
                        echo "Database backup triggered at $(date)" && \
                        if [ -f "/app/agent/data/db.sqlite" ]; then \
                            node -e '\
                            const Database = require("better-sqlite3");\
                            const fs = require("fs");\
                            const { execSync } = require("child_process");\
                            const db = new Database("/app/agent/data/db.sqlite");\
                            const backupPath = "/tmp/backup.sqlite";\
                            db.backup(backupPath)\
                              .then(() => {\
                                console.log("Backup created successfully");\
                                execSync(`gsutil cp ${backupPath} gs://${process.env.AGENTS_BUCKET_NAME}/${process.env.DEPLOYMENT_ID}/backups/db-${Date.now()}.sqlite`);\
                                fs.unlinkSync(backupPath);\
                                console.log("Backup uploaded and cleaned up");\
                              })\
                              .catch(console.error)\
                              .finally(() => db.close());\
                            ' && \
                            echo "Database backup completed successfully" && \
                            last_backup="$current_backup" \
                        else \
                            echo "Database file not found" \
                        fi \
                    fi && \

                    # Check storage usage
                    current_storage_check=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/storage-check-trigger" || echo "$last_storage_check") && \
                    if [ "$current_storage_check" != "$last_storage_check" ]; then \
                        echo "Checking storage usage at $(date)" && \
                        if [ -f "/app/agent/data/db.sqlite" ]; then \
                            db_size=$(stat -c %s /app/agent/data/db.sqlite 2>/dev/null) && \
                            total_space=$(df -B1 --output=size /app/agent/data | tail -1) && \
                            used_space=$(df -B1 --output=used /app/agent/data | tail -1) && \
                            avail_space=$(df -B1 --output=avail /app/agent/data | tail -1) && \
                            # Function to format bytes
                            format_size() {
                                local bytes=$1
                                if [ $bytes -lt 1000 ]; then
                                    echo "${bytes} B"
                                elif [ $bytes -lt 1000000 ]; then
                                    echo "$(( (bytes + 500) / 1000 )) KB"
                                elif [ $bytes -lt 1000000000 ]; then
                                    echo "$(( (bytes + 500000) / 1000000 )) MB"
                                else
                                    echo "$(( (bytes + 500000000) / 1000000000 )) GB"
                                fi
                            } && \
                            echo "{\
                            \"raw\": {\
                                \"dbSize\": $db_size,\
                                \"totalSpace\": $total_space,\
                                \"usedSpace\": $used_space,\
                                \"availableSpace\": $avail_space\
                            },\
                            \"readable\": {\
                                \"dbSize\": \"$(format_size $db_size)\",\
                                \"totalSpace\": \"$(format_size $total_space)\",\
                                \"usedSpace\": \"$(format_size $used_space)\",\
                                \"availableSpace\": \"$(format_size $avail_space)\"\
                            },\
                            \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"\
                            }" > /tmp/storage-info.json && \
                            gsutil cp /tmp/storage-info.json "gs://${AGENTS_BUCKET_NAME}/${DEPLOYMENT_ID}/storage-info.json" && \
                            rm /tmp/storage-info.json && \
                            echo "Storage info updated successfully" && \
                            last_storage_check="$current_storage_check" \
                        else \
                            echo "Database file not found for storage check" \
                        fi \
                    fi \
                fi && \
                sleep 30; \
            done && \
            wait $main_pid; \
            exit_code=$? && \
            if [ $exit_code -ne 0 ]; then exit $exit_code; fi && \
            echo "Clean exit, waiting before restart..." && \
            sleep 2; \
        done; \
    else \
        sleep infinity; \
    fi; \
else \
    sleep infinity; \
fi'