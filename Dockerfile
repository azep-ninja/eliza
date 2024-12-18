# Use a specific Node.js version for better reproducibility
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

# Copy package.json and other configuration files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc turbo.json ./

# Copy the rest of the application code
COPY agent ./agent
COPY packages ./packages
COPY scripts ./scripts
# Don't copy characters folder as we'll get it from GCS

# Install dependencies and build the project
RUN pnpm install --frozen-lockfile \
    && pnpm build-docker \
    && pnpm prune --prod

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

# Set default environment variables
ENV PORT=8080
ENV SERVER_PORT=8080

# Expose the port
EXPOSE 8080

# Modified command to fetch character file from GCS before starting
CMD sh -c "gsutil cp gs://${AGENTS_BUCKET_NAME}/${CHARACTER_FILE} characters/${CHARACTER_FILE} && pnpm start --non-interactive --characters=characters/$CHARACTER_FI${CHARACTER_FILE}"