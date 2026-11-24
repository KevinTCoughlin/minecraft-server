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
docker compose up -d
```

This uses the popular [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) image with our configuration.

### Building Custom Image

For advanced customization, build from the Dockerfile:

```bash
# Build from repository root (important!)
cd ..  # Go to repository root
docker build -f docker/Dockerfile -t minecraft-server:latest .

# Run the custom image. With --memory, the heap is 75% of that limit.
# With no --memory, the server still starts and picks a safe default heap.
# Do not replace the command: the entrypoint turns SIGTERM into "stop".
docker run -d \
  --name minecraft-server \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 5g --cpus 2 \
  --stop-timeout 90 \
  --tmpfs /tmp:rw,nosuid,size=256m \
  -p 25565:25565 \
  -v minecraft-server-data:/data \
  -v minecraft-server-world:/data/parkour-spiral \
  minecraft-server:latest
```

Build plugins into the image first if you want them baked in: `./gradlew deployToServer` copies the jars to `server/plugins/`, and the image copies those into `/data/plugins` on startup.

**Important**: The Dockerfile must be built from the repository root as the build context, not from the `docker/` directory, because it copies config files from `server/`.

## Configuration

### Docker Compose

Edit `docker-compose.yml` to customize:

- **Memory**: container limit `mem_limit` (default 6G). On the itzg image the heap is 75% of that limit (`INIT_MEMORY` / `MAX_MEMORY`). The custom image uses the same percentage when a limit is set, and accepts `MEMORY` (`2G`, `4G`, `auto`, or `75%`). With no limit it picks a safe default heap instead of refusing to start. See [How much memory?](../README.md#how-much-memory).
- **Configs**: on first start, `prepare-data` copies `server.properties`, `bukkit.yml`, `spigot.yml`, and the Paper world defaults into the data volume. itzg then turns RCON on in that copy so `docker stop` can save the world. Port 25575 is not published. The files in `server/` are not modified.
- **Version**: `VERSION` environment variable (default: 26.3) and `PAPER_BUILD` (default: 258)
- **Server Settings**: Various `SERVER_*` environment variables
- **Ports**: Change port mappings if needed

### Custom Dockerfile

The custom Dockerfile:

1. **Downloads Paper** - Fetches the pinned Paper 26.3 build from Paper's Fill v3 API
2. **Multi-stage build** - Smaller final image
3. **Security hardened** - Non-root user, read-only root, dropped capabilities, digest-pinned base image
4. **Eclipse Temurin** - Uses Eclipse Foundation's OpenJDK

Build arguments:

- `MC_VERSION` - Minecraft version to download (default: 26.3)
- `PAPER_BUILD` - Paper build number (default: 258)

Example:

```bash
docker build -f docker/Dockerfile -t minecraft-server:26.3 \
  --build-arg MC_VERSION=26.3 --build-arg PAPER_BUILD=258 .
```

## Eclipse Temurin

Both configurations use Eclipse Temurin (Eclipse Foundation's OpenJDK distribution):

- Custom Dockerfile: `eclipse-temurin:25-jre-alpine` base image
- Docker Compose: `itzg/minecraft-server:java25` (Temurin 25)

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

The server directory is `/data` (configs, logs, plugins, heap dumps). The world is `/data/parkour-spiral` because that is `level-name` in `server/server.properties`; since Minecraft 26.1 every dimension lives inside that one directory. Mount the world volume at `/data/parkour-spiral` and the rest of the server state at `/data`. `paper.jar` lives in `/opt/minecraft`, so the data volume does not hide it.

```bash
docker run -d \
  --read-only \
  --tmpfs /tmp:rw,nosuid,size=256m \
  --memory 5g \
  -p 25565:25565 \
  -v minecraft-server-data:/data \
  -v minecraft-server-world:/data/parkour-spiral \
  minecraft-server:latest
```

A read-only root needs the `/data` volume and a writable `/tmp`. Without a memory limit the container still starts: the heap is a safe default (about 25% of host memory, clamped between 1G and 4G, or 2G if host memory cannot be read) and the log prints `docker run -m 4g …` and `deploy.resources.limits.memory`. Set a limit when you can. The heap is then 75% of that limit.

## Networking

Default ports:

- **25565** - Minecraft server (TCP/UDP)
- **19132** - Bedrock/Geyser (UDP)

RCON is disabled and not published by default.

## Health Checks

Both configurations include health checks that verify the server is accepting connections. Apple `container` ignores `HEALTHCHECK`.

## Apple container (macOS)

On macOS the root `justfile` drives Apple's [`container`](https://github.com/apple/container) CLI by default; on other systems it uses podman. Set `CONTAINER_ENGINE` to override. Run from the repository root:

```bash
container system start   # once per boot
just image               # build docker/Dockerfile with context .
just run                 # start detached as `minecraft-server`
just logs                # follow logs; wait for "Done"
just rcon list           # RCON from the host (needs python3)
just shell               # shell in the container
just stop                # stop and remove the container; the world volume is kept
```

What `just run` does, and why:

- **Resources**: `container` gives 1 GB of memory by default, too little for a Paper heap. The recipe passes `--memory 5G --cpus 2`; the heap is 75% of that limit. Override with `MC_MEMORY` and `MC_CPUS`. It uses the long flags because podman reads `-c` as CPU shares.
- **Ports**: publishes 25565/tcp+udp and 19132/udp. Change the host ports with `MC_PORT`, `BEDROCK_PORT` and `RCON_PORT`, for example to run next to another server:
  ```bash
  export MC_PORT=25566 RCON_PORT=25576 BEDROCK_PORT=19133
  just run
  just rcon list
  ```
- **RCON**: the image ships with RCON off. `just run` turns it on for this container only and publishes it on host `127.0.0.1` alone. It uses a random password unless you set `RCON_PASSWORD` (letters, digits, `_` and `-` only). `just rcon` reads the password back from the container.
- **Volumes**: the world stays on `minecraft-server-world`, mounted at `/data/parkour-spiral`, so a volume created before the `/data` layout still has `level.dat` at the world root. Configs, logs, plugins, and heap dumps are on `minecraft-server-data` (`MC_DATA_VOLUME`). `container` needs both volumes created first and does not seed them from the image. A new volume is an empty ext4 filesystem with a root-owned `lost+found`. The recipe gives the top level of each volume to the `minecraft` user (uid 1000).
- **Read-only root**: podman runs the container with `--read-only`, `--cap-drop=ALL`, `no-new-privileges`, a tmpfs on `/tmp`, and a 90s stop timeout. Apple `container` does not take those flags; the image still runs as uid 1000 and the entrypoint still handles SIGTERM.
- **No compose, restart policy or health checks**: `docker-compose.yml` does not apply under `container`. After a reboot, run `just run` again; the world is still on the volume. The image `HEALTHCHECK` is ignored by Apple `container`.

To delete the world, run `container volume rm minecraft-server-world`. Configs and logs are on `minecraft-server-data`.

## Management

### Docker Compose

```bash
# Start
docker compose up -d

# Stop
docker compose down

# View logs
docker compose logs -f

# Restart
docker compose restart

# Update image
docker compose pull
docker compose up -d
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

1. Check logs: `docker compose logs`
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
