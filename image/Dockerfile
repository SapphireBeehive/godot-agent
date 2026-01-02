# Dockerfile for Claude-Godot Sandbox Agent
# Provides: Godot 4.x headless + Claude Code CLI
# Target: Linux arm64 (Apple Silicon via Docker)

# Build arguments for version pinning
ARG GODOT_VERSION=4.3
ARG GODOT_RELEASE_TYPE=stable
ARG GODOT_SHA256

# TODO: When Godot 4.6 is released, update GODOT_VERSION
# TODO: Native arm64 Godot builds may require building from source

# --- Stage 1: Build/Download dependencies ---
FROM debian:bookworm-slim AS builder

ARG GODOT_VERSION
ARG GODOT_RELEASE_TYPE
ARG GODOT_SHA256

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy and run Godot installer
COPY install/fetch_godot.sh /tmp/fetch_godot.sh
RUN chmod +x /tmp/fetch_godot.sh && \
    GODOT_VERSION=${GODOT_VERSION} \
    GODOT_RELEASE_TYPE=${GODOT_RELEASE_TYPE} \
    GODOT_SHA256=${GODOT_SHA256} \
    /tmp/fetch_godot.sh

# --- Stage 2: Runtime image ---
FROM debian:bookworm-slim AS runtime

# Labels for image metadata
LABEL org.opencontainers.image.title="Claude-Godot Sandbox Agent"
LABEL org.opencontainers.image.description="Sandboxed environment for Claude Code + Godot development"
LABEL org.opencontainers.image.source="https://github.com/your-org/claude-godot-sandbox"

# Install minimal runtime dependencies
# - bash: for scripts
# - git: for version control operations
# - ca-certificates: for HTTPS
# - nodejs + npm: required for Claude Code CLI (npm package)
# Note: Node.js is required because Claude Code is distributed as npm package
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    ca-certificates \
    nodejs \
    npm \
    # Godot runtime dependencies
    libfontconfig1 \
    libgl1 \
    libxi6 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && rm -rf /var/cache/apt/archives/*

# Copy Godot binary from builder
COPY --from=builder /opt/godot /opt/godot
COPY --from=builder /usr/local/bin/godot /usr/local/bin/godot

# Create non-root user 'claude' with uid 1000
RUN groupadd -g 1000 claude && \
    useradd -m -u 1000 -g claude -s /bin/bash claude

# Install Claude Code CLI
# This happens after user creation so npm global packages are accessible
COPY install/install_claude_code.sh /tmp/install_claude_code.sh
RUN chmod +x /tmp/install_claude_code.sh && \
    /tmp/install_claude_code.sh || \
    echo "WARNING: Claude Code installation incomplete - see logs above"

# Create project directory
RUN mkdir -p /project && chown claude:claude /project

# Set up minimal home directory structure
RUN mkdir -p /home/claude/.config && \
    chown -R claude:claude /home/claude

# Security: Remove package managers and unnecessary tools from runtime path
# Note: We keep npm for Claude Code but could remove it post-install if needed
# RUN rm -rf /usr/bin/apt* /usr/bin/dpkg* || true

# Set environment
ENV HOME=/home/claude
ENV USER=claude
ENV GODOT_PATH=/opt/godot/godot

# Switch to non-root user
USER claude
WORKDIR /project

# Default command - can be overridden
CMD ["bash"]

# Health check - verify core tools are available
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD godot --headless --version || exit 1

