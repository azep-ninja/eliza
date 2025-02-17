# Use Node.js 23.3.0 as specified in package.json
FROM node:23.3.0-slim AS builder

# Playwright environment variables
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium \
    PLAYWRIGHT_BROWSER_ARGS="--no-sandbox,--disable-setuid-sandbox,--headless=new,--disable-gpu,--disable-software-rasterizer,--disable-dev-shm-usage,--disable-dbus" \
    PLAYWRIGHT_SKIP_BROWSER_VALIDATION=1
    DISPLAY= \
    XAUTHORITY=

# Install pnpm globally and install necessary build tools
RUN npm install -g pnpm@9.4.0 && \
    apt-get update && \
    apt-get install -y git python3 make g++ curl \
        chromium \
        libglib2.0-0 \
        libnss3 \
        libnspr4 \
        libdbus-1-3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
        libatspi2.0-0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set Python 3 as the default python
RUN ln -s /usr/bin/python3 /usr/bin/python

WORKDIR /app

# Copy all files
COPY . .

# Install dependencies with improved error handling and debugging
RUN pnpm install --frozen-lockfile || \
    (echo "Frozen lockfile install failed, trying without..." && \
    pnpm install --no-frozen-lockfile) && \
    pnpm list && \
    echo "Dependencies installed successfully" && \
    # Debug workspace packages
    pnpm list -r | grep "@elizaos" || echo "No workspace packages found!"

# Build with detailed logging
RUN set -ex && \
    for i in 1 2 3; do \
        echo "Build attempt $i" && \
        (PNPM_DEBUG=1 DEBUG=* TURBO_LOG_VERBOSITY=verbose pnpm build-docker 2>&1 | tee build_attempt_${i}.log) && exit 0 || \
        (echo "=== Build Failure Details for Attempt ${i} ===" && \
        cat build_attempt_${i}.log && \
        echo "=== End of Build Failure Details ===" && \
        echo "Build failed, retrying..." && \
        sleep 5) \
    done && \
    echo "All build attempts failed" && \
    echo "=== All Build Logs ===" && \
    cat build_attempt_*.log && \
    exit 1

# Prune for production
RUN pnpm prune --prod && \
    echo "Production pruning completed"

# Final stage
FROM node:23.3.0-slim

# Playwright environment variables
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium \
    PLAYWRIGHT_BROWSER_ARGS="--no-sandbox,--disable-setuid-sandbox,--headless=new,--disable-gpu,--disable-software-rasterizer,--disable-dev-shm-usage,--disable-dbus" \
    PLAYWRIGHT_SKIP_BROWSER_VALIDATION=1
    DISPLAY= \
    XAUTHORITY=

# Install runtime dependencies and certificates first
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        git \
        python3 \
        python3-pip \
        curl \
        node-gyp \
        ffmpeg \
        libtool-bin \
        autoconf \
        automake \
        libopus-dev \
        make \
        g++ \
        logrotate \
        cron \
        build-essential \
        libcairo2-dev \
        libjpeg-dev \
        libpango1.0-dev \
        libgif-dev \
        openssl \
        gnupg \
        ca-certificates \
        jq \
        libssl-dev \
        procps \
        chromium \
        libglib2.0-0 \
        libnss3 \
        libnspr4 \
        libdbus-1-3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libdrm2 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
        libatspi2.0-0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install pnpm, PM2, and Google Cloud SDK
RUN npm install -g pnpm@9.4.0 pm2@latest && \
    apt-get update && \
    apt-get install -y git python3 curl gnupg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && \
    apt-get install -y google-cloud-sdk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/logs && \
    chmod 755 /app/logs

WORKDIR /app

# Copy necessary files from builder
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/.npmrc ./
COPY --from=builder /app/turbo.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/agent ./agent
COPY --from=builder /app/client ./client
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/scripts ./scripts

# Create necessary directories
RUN mkdir -p characters && \
    mkdir -p characters/knowledge

RUN service cron start

# Expose necessary ports
EXPOSE 3000 5173

# CMD that fetches and runs the entrypoint script
CMD sh -c 'echo "Fetching latest container entrypoint script..." && \
    gsutil cp "gs://${AGENTS_BUCKET_NAME}/_project-files/container-entrypoint.sh" /app/container-entrypoint.sh && \
    chmod +x /app/container-entrypoint.sh && \
    /app/container-entrypoint.sh'