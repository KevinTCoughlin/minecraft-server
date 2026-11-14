# Multi-stage Custom PaperMC Dockerfile with security hardening
# Built on Eclipse Temurin (Eclipse Foundation's OpenJDK)

# Stage 1: Download and prepare Paper
FROM eclipse-temurin:25-jre-alpine AS downloader

LABEL description="Custom PaperMC Minecraft Server - Builder Stage"

# Install utilities for download
RUN apk add --no-cache \
    bash \
    curl \
    jq

WORKDIR /tmp

# Download Paper from the Fill v3 API (the v2 API now returns 410 Gone)
ARG MC_VERSION=1.21.11
RUN set -e && \
    API_URL="https://fill.papermc.io/v3/projects/paper" && \
    UA="minecraft-server-docker-build (https://github.com/KevinTCoughlin/minecraft-server)" && \
    echo "Fetching latest PaperMC build for Minecraft ${MC_VERSION}..." && \
    BUILD_INFO=$(curl -fsSL -A "$UA" "${API_URL}/versions/${MC_VERSION}/builds/latest") && \
    BUILD_ID=$(echo "$BUILD_INFO" | jq -r '.id') && \
    DOWNLOAD_URL=$(echo "$BUILD_INFO" | jq -r '.downloads."server:default".url') && \
    SHA256=$(echo "$BUILD_INFO" | jq -r '.downloads."server:default".checksums.sha256') && \
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then \
        echo "Error: Could not find a build for version ${MC_VERSION}"; \
        exit 1; \
    fi && \
    echo "Downloading Paper ${MC_VERSION} build ${BUILD_ID}..." && \
    curl -fsSL -A "$UA" -o /tmp/paper.jar "$DOWNLOAD_URL" && \
    echo "${SHA256}  /tmp/paper.jar" | sha256sum -c - && \
    echo "Download complete: $(du -h /tmp/paper.jar | cut -f1)"

# Stage 2: Runtime
FROM eclipse-temurin:25-jre-alpine

LABEL org.opencontainers.image.authors="KevinTCoughlin"
LABEL org.opencontainers.image.source="https://github.com/KevinTCoughlin/minecraft-server"
LABEL org.opencontainers.image.description="PaperMC server built on Eclipse Foundation's OpenJDK"
LABEL org.opencontainers.image.licenses="MIT"

# Security: Create non-root user
RUN addgroup -g 1000 -S minecraft && \
    adduser -u 1000 -S minecraft -G minecraft

# Install runtime utilities (including busybox-extras for nc in healthcheck)
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tzdata \
    tini \
    busybox-extras && \
    rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC

# Create directories with proper permissions
RUN mkdir -p /server/plugins /server/config /server/logs && \
    chown -R minecraft:minecraft /server

WORKDIR /server

# Copy Paper from downloader stage
COPY --from=downloader --chown=minecraft:minecraft /tmp/paper.jar /server/paper.jar

# Copy configuration files (build context should be repository root)
COPY --chown=minecraft:minecraft server/server.properties /server/
COPY --chown=minecraft:minecraft server/paper-global.yml /server/config/
COPY --chown=minecraft:minecraft server/paper-world-defaults.yml /server/config/
COPY --chown=minecraft:minecraft server/bukkit.yml /server/
COPY --chown=minecraft:minecraft server/spigot.yml /server/

# Accept EULA
RUN echo "eula=true" > /server/eula.txt && \
    chown minecraft:minecraft /server/eula.txt

# Switch to non-root user
USER minecraft

# Expose ports
EXPOSE 25565/tcp 25565/udp 25575/tcp 19132/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD nc -z localhost 25565 || exit 1

# JVM arguments - Optimized with Aikar's flags
# Using Eclipse Temurin OpenJDK for best performance
ENV JVM_OPTS="-Xms2G -Xmx4G \
    -XX:+UseG1GC \
    -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch \
    -XX:G1NewSizePercent=30 \
    -XX:G1MaxNewSizePercent=40 \
    -XX:G1HeapRegionSize=8M \
    -XX:G1ReservePercent=20 \
    -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 \
    -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem \
    -XX:MaxTenuringThreshold=1 \
    -Dusing.aikars.flags=https://mcflags.emc.gs \
    -Daikars.new.flags=true"

# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start server
CMD ["sh", "-c", "java $JVM_OPTS -jar paper.jar --nogui"]
