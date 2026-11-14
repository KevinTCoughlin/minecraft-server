# Docker Configuration

This directory contains Docker configuration for running the Minecraft server in containers.

## Files

- **Dockerfile** - Multi-stage Dockerfile for custom PaperMC builds
- **docker-compose.yml** - Docker Compose configuration using itzg/minecraft-server

## Quick Start

### Using Docker Compose (Recommended)

The easiest way to run the server:

```bash
cd docker
docker-compose up -d
```

This uses the popular [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) image with our configuration.

### Building Custom Image

For advanced customization, build from the Dockerfile:

```bash
# Build from repository root (important!)
cd ..  # Go to repository root
docker build -f docker/Dockerfile -t minecraft-server:latest .

# Run the custom image
docker run -d -p 25565:25565 -v minecraft-world:/server/parkour-spiral minecraft-server:latest
```

Mount volumes on the world directories only. `/server` holds `paper.jar` and the configs baked into the image; a volume over it would hide (or, under Apple `container`, replace) them.

**Important**: The Dockerfile must be built from the repository root as the build context, not from the `docker/` directory, because it copies config files from `server/`.

## Configuration

### Docker Compose

Edit `docker-compose.yml` to customize:

- **Memory**: `MEMORY` environment variable (default: 4G)
- **Version**: `VERSION` environment variable (default: 1.21.11)
- **Server Settings**: Various `SERVER_*` environment variables
- **Ports**: Change port mappings if needed

### Custom Dockerfile

The custom Dockerfile:

1. **Downloads Paper** - Fetches the latest build for `MC_VERSION` from the PaperMC API
2. **Multi-stage build** - Smaller final image
3. **Security hardened** - Non-root user, minimal base image
4. **Eclipse Temurin** - Uses Eclipse Foundation's OpenJDK

Build arguments:

- `MC_VERSION` - Minecraft version to download (default: 1.21.11)

Example:

```bash
docker build -f docker/Dockerfile -t minecraft-server:1.21.11 \
  --build-arg MC_VERSION=1.21.11 .
```

## Eclipse Temurin

Both configurations use Eclipse Temurin (Eclipse Foundation's OpenJDK distribution):

- Custom Dockerfile: `eclipse-temurin:25-jre-alpine` base image
- Docker Compose: itzg image uses Temurin internally

## Volumes

### Docker Compose

Persistent data is stored in the `minecraft-data` volume:

```bash
# Backup volume
docker run --rm -v minecraft-data:/data -v $(pwd):/backup alpine tar czf /backup/minecraft-backup.tar.gz /data

# Restore volume
docker run --rm -v minecraft-data:/data -v $(pwd):/backup alpine tar xzf /backup/minecraft-backup.tar.gz -C /
```

### Custom Dockerfile

Mount volumes for persistence:

```bash
docker run -d \
  -p 25565:25565 \
  -v minecraft-world:/server/parkour-spiral \
  -v minecraft-world_nether:/server/parkour-spiral_nether \
  -v minecraft-world_the_end:/server/parkour-spiral_the_end \
  minecraft-server:latest
```

(`parkour-spiral` is `level-name` in `server/server.properties`.)

## Networking

Default ports:

- **25565** - Minecraft server (TCP/UDP)
- **25575** - RCON (TCP)
- **19132** - Bedrock via Geyser (UDP), when the Geyser plugin is installed

## Health Checks

Both configurations include health checks that verify the server is accepting connections. (Apple `container` ignores `HEALTHCHECK`.)

## Apple container (macOS)

On macOS the root `justfile` drives Apple's [`container`](https://github.com/apple/container) CLI by default (podman elsewhere; override with `CONTAINER_ENGINE`). Run from the repository root:

```bash
container system start   # once per boot
just image               # build docker/Dockerfile with context .
just run                 # start detached as `minecraft-server`
just logs                # follow logs, wait for "Done"
just rcon list           # RCON from the host (needs python3)
just shell               # shell in the container
just stop                # stop and remove the container; volumes are kept
```

What `just run` does and why:

- **Resources**: `container` defaults to 1 GB of memory, too little for `-Xmx4G`, so it passes `--memory 5G --cpus 2` (override with `MC_MEMORY` / `MC_CPUS`). The long flags are deliberate: podman reads `-c` as CPU shares.
- **Ports**: publishes 25565/tcp+udp, 19132/udp and RCON 25575 on `127.0.0.1` only. Override host ports with `MC_PORT`, `BEDROCK_PORT` and `RCON_PORT`, e.g. to run beside another server:
  ```bash
  MC_PORT=25566 RCON_PORT=25576 BEDROCK_PORT=19133 just run
  MC_PORT=25566 RCON_PORT=25576 BEDROCK_PORT=19133 just rcon list
  ```
- **Volumes**: the three world dirs live on named volumes `minecraft-server-world`, `-world_nether` and `-world_the_end` (prefix: `MC_VOLUME_PREFIX`). `container` needs them created first and does not seed them from the image, so they start empty and root-owned; the recipe creates them and chowns them to the `minecraft` user (uid 1000).
- **No compose, restart policy or health checks**: `docker-compose.yml` does not apply. Run `just run` again after a reboot; the world survives on the volumes.

Remove the worlds with `container volume rm minecraft-server-world minecraft-server-world_nether minecraft-server-world_the_end`.

## Management

### Docker Compose

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# View logs
docker-compose logs -f

# Restart
docker-compose restart

# Update image
docker-compose pull
docker-compose up -d
```

### Custom Image

```bash
# View logs
docker logs -f <container-id>

# Execute commands
docker exec -it <container-id> bash

# Stop gracefully
docker stop <container-id>
```

## Production Deployment

For production:

1. Use Docker Compose for easier management
2. Set up regular backups (see Volumes section)
3. Monitor resource usage
4. Use proper firewall rules
5. Consider using Docker networks for isolation
6. Set up log aggregation
7. Monitor with health checks

## Troubleshooting

### Container won't start

1. Check logs: `docker-compose logs`
2. Verify port availability: `lsof -i :25565`
3. Check resource limits

### Permission errors

The custom Dockerfile runs as user `minecraft` (UID 1000). Ensure volume permissions match.

### Connection issues

1. Verify ports are exposed: `docker ps`
2. Check firewall rules
3. Verify `online-mode` setting matches your needs

## Resources

- [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [PaperMC](https://papermc.io/)
- [Eclipse Temurin](https://adoptium.net/)
- [Docker Documentation](https://docs.docker.com/)

---

**Built with Eclipse Temurin OpenJDK** ☕
