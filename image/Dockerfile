# Dockerfile for Claude-Godot Sandbox Agent
# Provides: Godot 4.x headless + Claude Code CLI
# Target: Linux arm64 (Apple Silicon via Docker)
#
# Optimized for build cache efficiency and faster rebuilds

# Build arguments for version pinning
ARG GODOT_VERSION=4.6
ARG GODOT_RELEASE_TYPE=beta2

# NOTE: Native arm64 Godot builds may require building from source

# --- Stage 1: Build/Download dependencies ---
FROM debian:bookworm-slim AS builder

ARG GODOT_VERSION
ARG GODOT_RELEASE_TYPE

# Install build tools and fetch Godot in a single layer for better caching
# Copy script first (separate layer) so script changes don't invalidate apt cache
COPY install/fetch_godot.sh /tmp/fetch_godot.sh
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    unzip \
    && chmod +x /tmp/fetch_godot.sh \
    && GODOT_VERSION=${GODOT_VERSION} \
    GODOT_RELEASE_TYPE=${GODOT_RELEASE_TYPE} \
    /tmp/fetch_godot.sh \
    && rm -rf /var/lib/apt/lists/*

# --- Stage 2: Runtime image ---
FROM debian:bookworm-slim AS runtime

# Labels for image metadata
LABEL org.opencontainers.image.title="Claude-Godot Sandbox Agent"
LABEL org.opencontainers.image.description="Sandboxed environment for Claude Code + Godot development"
LABEL org.opencontainers.image.source="https://github.com/SapphireBeehiveStudios/godot-agent"

# Use bash with pipefail for proper error handling in piped commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install all runtime dependencies in a single layer
# This layer will be cached unless dependencies change
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    ca-certificates \
    nodejs \
    npm \
    # Workflow tools
    curl \
    jq \
    zip \
    unzip \
    file \
    make \
    # Python for GitHub App token generation
    python3 \
    # Godot runtime dependencies
    libfontconfig1 \
    libgl1 \
    libxi6 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# Install uv for Python package management (faster than pip)
# hadolint ignore=DL3013
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
    && uv pip install --system --break-system-packages PyJWT cryptography requests

# Install GitHub CLI (gh) for repo management (issues, PRs, etc.)
# hadolint ignore=DL3008
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI as root before user creation
# This ensures npm packages are installed globally and accessible
# Copy script first (separate layer) for better cacheability
COPY install/install_claude_code.sh /tmp/install_claude_code.sh
RUN chmod +x /tmp/install_claude_code.sh && \
    /tmp/install_claude_code.sh || \
    echo "WARNING: Claude Code installation incomplete - see logs above"

# Create user and directories in a single layer
# This layer is stable and rarely changes
RUN groupadd -g 1000 claude && \
    useradd -m -u 1000 -g claude -s /bin/bash claude && \
    mkdir -p /project /home/claude/.config /etc/claude && \
    chown -R claude:claude /project /home/claude

# Copy Godot binary from builder (after user creation for proper ownership)
# This is version-dependent, so it changes when Godot version changes
COPY --from=builder /opt/godot /opt/godot
COPY --from=builder /usr/local/bin/godot /usr/local/bin/godot

# Copy entrypoint script and set permissions in one layer
# Scripts change more frequently, so they're copied later
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/setup-git-pat.sh /opt/scripts/setup-git-pat.sh
COPY scripts/setup-github-app.sh /opt/scripts/setup-github-app.sh
COPY scripts/clone-repo.sh /opt/scripts/clone-repo.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /opt/scripts/setup-git-pat.sh \
    /opt/scripts/setup-github-app.sh /opt/scripts/clone-repo.sh

# Copy config files last (they change most frequently)
# This minimizes cache invalidation when only config changes
COPY config/claude-settings.json /etc/claude/settings.json
COPY config/sandbox-context.md /etc/claude/sandbox-context.md

# Set environment variables (stable, rarely changes)
ENV HOME=/home/claude
ENV USER=claude
ENV GODOT_PATH=/opt/godot/godot

# Switch to non-root user
USER claude
WORKDIR /project

# Entrypoint sets up Claude config on each container start
# (required because /home/claude is a tmpfs mount)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command - can be overridden
CMD ["bash"]

# Health check - verify core tools are available
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD godot --headless --version || exit 1
