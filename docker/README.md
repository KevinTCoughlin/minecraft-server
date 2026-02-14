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
docker run -d -p 25565:25565 -v minecraft-data:/server minecraft-server:latest
```

**Important**: The Dockerfile must be built from the repository root as the build context, not from the `docker/` directory, because it needs access to `server/` and `scripts/` directories.

## Configuration

### Docker Compose

Edit `docker-compose.yml` to customize:

- **Memory**: `MEMORY` environment variable (default: 4G)
- **Version**: `VERSION` environment variable (default: 1.21.4)
- **Server Settings**: Various `SERVER_*` environment variables
- **Ports**: Change port mappings if needed

### Custom Dockerfile

The custom Dockerfile:

1. **Downloads Paper** - Uses the update-paper.sh script
2. **Multi-stage build** - Smaller final image
3. **Security hardened** - Non-root user, minimal base image
4. **Eclipse Temurin** - Uses Eclipse Foundation's OpenJDK

Build arguments:

- `MC_VERSION` - Minecraft version to download (default: 1.21.4)

Example:

```bash
docker build -f docker/Dockerfile -t minecraft-server:1.21.4 \
  --build-arg MC_VERSION=1.21.4 .
```

## Eclipse Temurin

Both configurations use Eclipse Temurin (Eclipse Foundation's OpenJDK distribution):

- Custom Dockerfile: `eclipse-temurin:21-jre-alpine` base image
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
  -v minecraft-data:/server \
  minecraft-server:latest
```

## Networking

Default ports:

- **25565** - Minecraft server (TCP/UDP)
- **25575** - RCON (TCP)

## Health Checks

Both configurations include health checks that verify the server is accepting connections.

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
