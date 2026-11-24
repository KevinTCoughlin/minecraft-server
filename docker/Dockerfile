# Multi-stage PaperMC image. The base is pinned by digest so a moved tag
# cannot change what CI and production build. Both stages use the same image.
# eclipse-temurin:25-jre-alpine

# Stage 1: Download and prepare Paper
FROM eclipse-temurin:25-jre-alpine@sha256:69c2a26e9894016e274c880fa542956d005b3755f84db765145185e87405bd89 AS downloader

LABEL description="Custom PaperMC Minecraft Server - Builder Stage"

# Install utilities for download
RUN apk add --no-cache \
    bash \
    curl \
    jq

WORKDIR /download

# Download Paper directly with error handling
# Pin the newest Paper 26.3 build that contains the audited 228/229/233 fixes.
# Build 258 (2026-11-22) is that build. Override PAPER_BUILD only to move forward.
ARG MC_VERSION=26.3
ARG PAPER_BUILD=258
RUN set -e && \
    API_URL="https://fill.papermc.io/v3" && \
    API_ORIGIN="https://fill.papermc.io" && \
    USER_AGENT="minecraft-server-container/1.0 (https://github.com/KevinTCoughlin/minecraft-server)" && \
    echo "Fetching PaperMC ${MC_VERSION} build ${PAPER_BUILD}..." && \
    BUILDS_JSON=$(curl -fsSL --retry 3 --retry-all-errors -H "User-Agent: ${USER_AGENT}" \
        "${API_URL}/projects/paper/versions/${MC_VERSION}/builds") && \
    BUILD_INFO=$(echo "$BUILDS_JSON" | jq -cr --argjson build "$PAPER_BUILD" \
        'map(select(.id == $build and .downloads["server:default"] != null)) | first // empty') && \
    LATEST_BUILD=$(echo "$BUILD_INFO" | jq -r '.id') && \
    if [ -z "$BUILD_INFO" ] || [ -z "$LATEST_BUILD" ] || [ "$LATEST_BUILD" = "null" ]; then \
        echo "Error: Could not find Paper ${MC_VERSION} build ${PAPER_BUILD}"; \
        exit 1; \
    fi && \
    echo "Selected build: ${LATEST_BUILD}" && \
    DOWNLOAD_URL=$(echo "$BUILD_INFO" | jq -r '.downloads["server:default"].url') && \
    DOWNLOAD_SHA256=$(echo "$BUILD_INFO" | jq -r '.downloads["server:default"].checksums.sha256') && \
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ] || \
       [ -z "$DOWNLOAD_SHA256" ] || [ "$DOWNLOAD_SHA256" = "null" ]; then \
        echo "Error: Could not determine download metadata"; \
        exit 1; \
    fi && \
    case "$DOWNLOAD_URL" in http://*|https://*) ;; *) DOWNLOAD_URL="${API_ORIGIN}${DOWNLOAD_URL}" ;; esac && \
    echo "Downloading Paper..." && \
    curl -fsSL --retry 3 --retry-all-errors -H "User-Agent: ${USER_AGENT}" \
        -o /download/paper.jar "$DOWNLOAD_URL" && \
    if [ ! -s /download/paper.jar ] || \
       ! echo "${DOWNLOAD_SHA256}  /download/paper.jar" | sha256sum -c -; then \
        echo "Error: Downloaded file failed checksum validation"; \
        exit 1; \
    fi && \
    echo "Download complete: $(du -h /download/paper.jar | cut -f1)"

# Stage 2: Runtime
FROM eclipse-temurin:25-jre-alpine@sha256:69c2a26e9894016e274c880fa542956d005b3755f84db765145185e87405bd89

LABEL org.opencontainers.image.authors="KevinTCoughlin"
LABEL org.opencontainers.image.source="https://github.com/KevinTCoughlin/minecraft-server"
LABEL org.opencontainers.image.description="PaperMC server built on Eclipse Foundation's OpenJDK"
LABEL org.opencontainers.image.licenses="MIT"

# Security: non-root user. Home is the writable data dir so Java does not
# need to create files under a read-only root.
RUN addgroup -g 1000 -S minecraft && \
    adduser -u 1000 -S -h /data -G minecraft minecraft

# Runtime utilities. curl and jq are only needed to download Paper.
# `apk upgrade` pulls Alpine security fixes the Temurin base image has not
# picked up yet (e.g. libexpat 2.10.0-r0 for CVE-2026-113351/117610/118370).
# busybox-extras provides nc for the healthcheck. tini forwards SIGTERM to
# the entrypoint, which turns it into the console "stop" command.
RUN apk upgrade --no-cache && \
    apk add --no-cache \
    bash \
    tzdata \
    tini \
    busybox-extras && \
    rm -rf /var/cache/apk/*

# MEMORY is the simple knob (2G, 4G, auto, 75%). Unset is auto: a memory
# limit uses MAX_RAM_PERCENTAGE, and no limit uses a safe default heap.
ENV TZ=UTC \
    GC_TYPE=g1gc \
    MEMORY_MODE=container \
    MAX_RAM_PERCENTAGE=75.0 \
    HEAP_DUMP_PATH=/data/dumps

# Immutable server files live outside /data so a volume mounted there does
# not hide the jar. Plugin jars in server/plugins (for example after
# `./gradlew deployToServer`) are copied into the data volume on startup.
RUN mkdir -p /opt/minecraft/defaults/config /opt/minecraft/plugins /data && \
    chown -R minecraft:minecraft /opt/minecraft /data

COPY --from=downloader --chown=minecraft:minecraft /download/paper.jar /opt/minecraft/paper.jar
COPY --chown=minecraft:minecraft scripts/jvm-opts.sh /opt/minecraft/jvm-opts.sh
COPY --chown=minecraft:minecraft docker/entrypoint.sh /opt/minecraft/entrypoint.sh
COPY --chown=minecraft:minecraft server/server.properties /opt/minecraft/defaults/
COPY --chown=minecraft:minecraft server/bukkit.yml /opt/minecraft/defaults/
COPY --chown=minecraft:minecraft server/spigot.yml /opt/minecraft/defaults/
COPY --chown=minecraft:minecraft server/config/ /opt/minecraft/defaults/config/
COPY --chown=minecraft:minecraft server/plugins/ /opt/minecraft/plugins/

RUN chmod 755 /opt/minecraft/entrypoint.sh /opt/minecraft/jvm-opts.sh && \
    chown -R minecraft:minecraft /opt/minecraft /data

WORKDIR /data

USER minecraft

EXPOSE 25565/tcp 25565/udp 19132/udp

# TCP connect, not ICMP, so the check works with every capability dropped.
HEALTHCHECK --interval=15s --timeout=5s --start-period=120s --retries=3 \
    CMD nc -z 127.0.0.1 25565 || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/sbin/tini", "--", "/opt/minecraft/entrypoint.sh"]
