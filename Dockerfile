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

# Set the working directory
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

# Create a new stage for the final image
FROM node:23.3.0-slim

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

# Copy built artifacts and production dependencies from the builder stage
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

# Add debugging and error handling to startup command
CMD sh -c '\
    echo "Debug: Starting container" && \
    echo "Debug: AGENTS_BUCKET_NAME=${AGENTS_BUCKET_NAME}" && \
    echo "Debug: CHARACTER_FILE=${CHARACTER_FILE}" && \
    echo "Debug: Full GCS path=gs://${AGENTS_BUCKET_NAME}/${CHARACTER_FILE}" && \
    if [ -z "${AGENTS_BUCKET_NAME}" ]; then \
        echo "Error: AGENTS_BUCKET_NAME is empty" && exit 1; \
    fi && \
    if [ -z "${CHARACTER_FILE}" ]; then \
        echo "Error: CHARACTER_FILE is empty" && exit 1; \
    fi && \
    echo "Debug: Attempting to copy character file..." && \
    gsutil cp gs://${AGENTS_BUCKET_NAME}/${CHARACTER_FILE} characters/${CHARACTER_FILE} && \
    # Get secrets directly when starting the application
    export SMALL_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="small-google-model") && \
    export MEDIUM_GOOGLE_MODEL=$(gcloud secrets versions access latest --secret="medium-google-model") && \
    export GOOGLE_GENERATIVE_AI_API_KEY=$(gcloud secrets versions access latest --secret="google-generative-ai-key") && \
    echo "Debug: Environment variables:" && \
    echo "SMALL_GOOGLE_MODEL=${SMALL_GOOGLE_MODEL}" && \
    echo "MEDIUM_GOOGLE_MODEL=${MEDIUM_GOOGLE_MODEL}" && \
    echo "Debug: Starting application..." && \
    pnpm start --non-interactive --characters=characters/${CHARACTER_FILE}'