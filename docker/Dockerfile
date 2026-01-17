# Custom PaperMC Dockerfile (optional - for advanced customization)
# The docker-compose.yml uses itzg/minecraft-server by default,
# but this Dockerfile can be used for custom builds.

FROM eclipse-temurin:21-jre-alpine

LABEL maintainer="your-email@example.com"
LABEL description="Custom PaperMC Minecraft Server"

# Create minecraft user
RUN addgroup -S minecraft && adduser -S minecraft -G minecraft

# Install utilities
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tzdata

# Set timezone
ENV TZ=UTC

# Create directories
RUN mkdir -p /server/plugins && \
    chown -R minecraft:minecraft /server

WORKDIR /server

# Copy configuration files
COPY --chown=minecraft:minecraft ../server/server.properties /server/
COPY --chown=minecraft:minecraft ../server/paper-global.yml /server/config/
COPY --chown=minecraft:minecraft ../server/paper-world-defaults.yml /server/config/
COPY --chown=minecraft:minecraft ../server/bukkit.yml /server/
COPY --chown=minecraft:minecraft ../server/spigot.yml /server/

# Copy scripts
COPY --chown=minecraft:minecraft ../scripts/update-paper.sh /server/

# Download Paper
RUN chmod +x /server/update-paper.sh && \
    MC_VERSION=1.21.4 /server/update-paper.sh

# Accept EULA
RUN echo "eula=true" > /server/eula.txt

USER minecraft

# Expose ports
EXPOSE 25565/tcp
EXPOSE 25565/udp
EXPOSE 25575/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD nc -z localhost 25565 || exit 1

# JVM arguments
ENV JVM_OPTS="-Xms2G -Xmx4G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"

# Start server
ENTRYPOINT ["sh", "-c", "java $JVM_OPTS -jar paper.jar --nogui"]
