# PaperMC Minecraft Server

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/ci.yml/badge.svg)](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/ci.yml)
[![CodeQL](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/codeql.yml/badge.svg)](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/codeql.yml)
[![Docker](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/docker.yml/badge.svg)](https://github.com/KevinTCoughlin/minecraft-server/actions/workflows/docker.yml)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/KevinTCoughlin)](https://github.com/sponsors/KevinTCoughlin)

A config-driven PaperMC server setup with Kotlin/Java plugin development capability, manageable via shell scripts and Docker. **Built on Eclipse Temurin (Eclipse Foundation's OpenJDK) with experimental JVM optimizations and Minecraft datapacks for enhanced performance and gameplay.**

## Features

✨ **Modern DevOps**
- Automated CI/CD with GitHub Actions
- Security scanning with CodeQL and Trivy
- Dependency management with Dependabot
- Docker container builds with SBOM generation
- Automated unit-test reporting

🚀 **Eclipse Foundation & Microsoft OpenJDK**
- Built on Eclipse Temurin (Eclipse Foundation's distribution)
- Java 25 with advanced JVM optimizations
- Aikar's flags for optimal Minecraft performance
- Full support for Microsoft-adopted OpenJDK runtimes

⚡ **Experimental Features Enabled**
- Advanced JVM optimizations with experimental VM options
- Bundle datapack for improved inventory management
- See [Experimental Features Guide](docs/experimental-features.md) for details

## Prerequisites

This release requires **Java 25** and **Paper 26.3**. Java 21 and Minecraft 1.21.x users should stay on the previous release.

- **Java 25** (Eclipse Temurin). Paper 26.3 does not start on Java 21.
- **Gradle 9.8** via the wrapper (`./gradlew`). Gradle 8 cannot run on Java 25.
- **Docker & Docker Compose** (optional, for containerized deployment)
- **Minecraft Java Edition** client (to connect)

## Quick Start

```bash
git clone https://github.com/KevinTCoughlin/minecraft-server.git
cd minecraft-server
./setup.sh           # one-click setup
./scripts/start.sh   # start server
# Connect to localhost:25565
```

Requires Java 25 and Paper 26.3 (`brew install --cask temurin@25`). Java 21 / 1.21.x servers should stay on the previous release.

The management scripts support the Bash and BSD userland included with macOS;
`update-paper.sh` uses macOS `shasum` when GNU `sha256sum` is unavailable.

### Manual Setup

```bash
./scripts/update-paper.sh   # download PaperMC
./scripts/start.sh          # start server
./scripts/stop.sh           # graceful stop
```

### Containers (just)

```bash
just image   # build docker/Dockerfile (Apple `container` on macOS, podman elsewhere)
just run     # start detached; the world is on a named volume
just logs    # follow logs
just stop
```

See [docker/README.md](docker/README.md#apple-container-macos) for ports, RCON, volumes and overrides.

### Docker Compose

```bash
cd docker
docker-compose up -d

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

## Project Structure

```
minecraft-server/
├── server/                    # Server runtime
│   ├── paper.jar             # PaperMC JAR (gitignored)
│   ├── server.properties     # Server configuration
│   ├── config/               # Paper global and world-default settings
│   ├── bukkit.yml            # Bukkit configuration
│   ├── spigot.yml            # Spigot configuration
│   └── plugins/              # Compiled plugins
├── plugins/                   # Plugin source code
│   ├── blackjack-plugin/     # Blackjack minigame (LiteCommands)
│   └── example-plugin/       # Sample Kotlin plugin
├── scripts/                   # Management scripts
├── docker/                    # Docker configuration
├── docs/                      # Documentation
├── build.gradle.kts          # Root Gradle config
└── settings.gradle.kts       # Multi-project setup
```

## Scripts

| Script | Description |
|--------|-------------|
| `start.sh` | Start server with optimized JVM flags (Aikar's flags + experimental features) |
| `stop.sh` | Graceful shutdown via RCON |
| `update-paper.sh` | Download/update to latest PaperMC build |
| `backup.sh` | Archive world folders with timestamp |
| `deploy.sh` | Rsync to remote host |
| `measure-compact-headers.sh` | Compare heap, GC pauses, and TPS with compact object headers on a copy of a world |

### JVM Experimental Features

This server uses optimized JVM flags including experimental features for maximum performance:
- **G1 Garbage Collector** with advanced tuning
- **Experimental VM Options** enabled for cutting-edge optimizations
- **Aikar's Flags** - Industry-standard Minecraft server JVM configuration

**📖 See [Experimental Features Guide](docs/experimental-features.md) for complete details, configuration options, and troubleshooting.**

`-XX:+UseCompactObjectHeaders` stays off unless `COMPACT_OBJECT_HEADERS=true`. Compare it on a copy of a real world with [the measurement harness](docs/compact-object-headers.md) before turning that opt-in on for a server anyone plays.

### Minecraft Experimental Features

Experimental Minecraft features are enabled via datapacks:
- **Bundle** datapack - Enables bundle items for inventory management
- Configured in `server.properties` via `initial-enabled-packs=vanilla,bundle`
- ⚠️ **Warning**: Experimental features may change between updates. Always backup worlds!

**📖 See [Experimental Features Guide](docs/experimental-features.md) for usage instructions and how to enable additional features.**

### Environment Variables

```bash
# start.sh and the container image
MEMORY=auto         # auto, a size (2G, 4G, 512M), or a percent of the container limit (75%)
MIN_RAM=2G          # Fixed heap when MEMORY is unset (host start)
MAX_RAM=4G          # Fixed heap when MEMORY is unset (host start)
MAX_RAM_PERCENTAGE=75.0  # Heap share of the container limit when MEMORY is unset

# update-paper.sh
MC_VERSION=26.3  # Minecraft version (defaults to server/.paper-version)

# stop.sh
RCON_HOST=localhost
RCON_PORT=25575
RCON_PASSWORD=...   # Optional; RCON is disabled by default

# backup.sh
BACKUP_DIR=./backups
MAX_BACKUPS=10

# deploy.sh
DEPLOY_HOST=your-server.com
DEPLOY_USER=minecraft
DEPLOY_PATH=~/minecraft-server
DEPLOY_PORT=22

# scripts/jvm-opts.sh — off unless set to true
COMPACT_OBJECT_HEADERS=true

# measure-compact-headers.sh
WARMUP_SECONDS=120
SOAK_SECONDS=180
```

## How much memory?

`MEMORY` is the one knob: `2G`, `4G`, `auto`, or `75%`. A container limit is still the better way to size the server. With a limit, the heap stays a percentage of that limit (75% unless you set another percentage), so the rest can hold metaspace, threads, and native memory. With no limit, the server does not refuse to start and does not take a percentage of the whole machine. It picks a safe heap, about 25% of host memory, rounded to the nearest 256M and kept between 1G and 4G, or a fixed 2G if host memory cannot be read, and it prints the `docker run -m` and Compose settings below.

These are general starting points for the **container limit** (`docker run -m` or Compose `deploy.resources.limits.memory`), not benchmarks. This repository has not measured them on a production world. View distance moves the numbers as much as player count does.

| Players | Vanilla | Small | Modded |
|---------|---------|-------|--------|
| 1–5 | 2G | 2G | 4G |
| 6–20 | 4G | 4G–6G | 6G–8G |
| More than 20 | 6G and up | 6G–8G | 8G and up |

- **Vanilla** is one world and few plugins. A handful of players keep a modest set of chunks loaded, so 2G is enough to boot and play.
- **Small** is a compact world or a light plugin set, such as the parkour maps in this repo. Extra worlds and plugins sit on top of the same heap, so a busier small server wants the same limit as vanilla or one step higher.
- **Modded** means a modpack or many plugins. Those load more classes and keep more of the world in memory, so start higher and raise the limit if the server pauses or restarts on an out-of-memory error.
- A 4G limit is about a 3G heap plus the rest for the JVM. That is why the limit is larger than the heap you want.

```bash
docker run -m 4g …
```

```yaml
deploy:
  resources:
    limits:
      memory: 4G
```

For a before-and-after check of heap use, pauses, and TPS on a copy of a real world, follow [minecraft-server#129](https://github.com/KevinTCoughlin/minecraft-server/issues/129).

## Plugin Development

### Available Plugins

#### Blackjack Plugin
A fully-featured Blackjack minigame with:
- Chat-based gameplay
- Player statistics tracking
- Configurable house rules
- Modern command framework using [LiteCommands](https://github.com/Rollczi/LiteCommands)

**Commands**: `/bj [start|hit|stand|double|split|surrender|insurance|stats|rules]`

See [docs/litecommands-refactor.md](docs/litecommands-refactor.md) for implementation details.

#### Example Plugin
A simple example plugin demonstrating basic Bukkit/Paper API usage.

#### Fart Plugin
A fun plugin that adds a `/fart` command:
- Plays a humorous sound effect using Minecraft's built-in sounds
- Broadcasts to nearby players
- Available to all players by default

**Commands**: `/fart`

See [plugins/fart-plugin/README.md](plugins/fart-plugin/README.md) for details.

### Building Plugins

```bash
# Build the blackjack plugin
./gradlew :plugins:blackjack-plugin:build

# Build and copy to server/plugins/
./gradlew :plugins:blackjack-plugin:deployToServer

# Build the example plugin
./gradlew :plugins:example-plugin:build

# Build and copy to server/plugins/
./gradlew :plugins:example-plugin:deployToServer

# Build the fart plugin
./gradlew :plugins:fart-plugin:build

# Build and copy to server/plugins/
./gradlew :plugins:fart-plugin:deployToServer
```

### Creating a New Plugin

1. Create a new directory under `plugins/`:
   ```bash
   mkdir -p plugins/my-plugin/src/main/kotlin/com/example/myplugin
   ```

2. Add to `settings.gradle.kts`:
   ```kotlin
   include("plugins:my-plugin")
   ```

3. Create `plugins/my-plugin/build.gradle.kts` (copy from example-plugin)

4. Create your main plugin class extending `JavaPlugin`

5. Create `src/main/resources/plugin.yml` with plugin metadata

### Plugin Structure

```kotlin
// Main plugin class
class MyPlugin : JavaPlugin() {
    override fun onEnable() {
        saveDefaultConfig()
        // Register commands and listeners
    }

    override fun onDisable() {
        // Cleanup
    }
}
```

### Paper API Resources

- [Paper API Documentation](https://docs.papermc.io/paper)
- [Paper API Javadocs](https://jd.papermc.io/paper/26.3/)
- [Paper Development Guide](https://docs.papermc.io/paper/dev)

## Server Configuration

### Important Files

- **server.properties**: Core Minecraft server settings
- **config/paper-global.yml**: PaperMC global configuration
- **config/paper-world-defaults.yml**: Default world settings
- **bukkit.yml**: Bukkit-level settings
- **spigot.yml**: Spigot performance tuning

Paper 26.3 build 258 is the pinned server and plugin API. What that build changes, which plugins were checked, and what to retest before a future 26.4 move are in [Paper 26.4 prep](docs/paper-26.4-prep.md).

### Optional RCON (Disabled by Default)

1. Enable RCON and set a strong unique password in `server/server.properties`:
   ```properties
   rcon.password=your-secure-password
   ```

2. Restrict port 25575 to trusted hosts and set the script environment variable:
   ```bash
   export RCON_PASSWORD=your-secure-password
   ```

## Deployment

### To Remote Host

1. Create `.env` file:
   ```bash
   DEPLOY_HOST=your-server.com
   DEPLOY_USER=minecraft
   DEPLOY_PATH=minecraft-server
   ```

2. Run deploy script:
   ```bash
   ./scripts/deploy.sh
   ```

3. On remote host:
   ```bash
   cd ~/minecraft-server
   ./scripts/update-paper.sh
   ./scripts/start.sh
   ```

### Using Docker in Production

```bash
# On remote host
cd docker
docker-compose up -d
```

## Uptime alerts

`.github/workflows/server-health.yml` checks the dev server every 15 minutes from GitHub-hosted runners. Java Edition must answer a server-list status handshake on TCP `25565` (`enable-status=true`, the default in `server/server.properties`). Bedrock must answer a RakNet unconnected ping on UDP `19132` (Geyser). A port is reported down only after a retry, so one lost packet does not open an issue.

The check opens one issue titled "Server down", comments when the set of down ports changes (and at most every 6 hours while it stays down), and comments and closes that issue when both ports answer again.

Set the repository variable `MC_HEALTH_HOST` to the server's public hostname or IPv4 address (Settings > Secrets and variables > Actions > Variables). A secret of the same name is used when the variable is empty. The issue text includes that address. Until one of them is set, the workflow prints a notice and skips, and it does not open an issue.

Optional variables `MC_HEALTH_JAVA_PORT` (default `25565`) and `MC_HEALTH_BEDROCK_PORT` (default `19132`) override the ports.

## Backups

```bash
# Create backup
./scripts/backup.sh

# Backups are stored in ./backups/ by default
# Format: minecraft-backup-YYYYMMDD-HHMMSS.tar.gz
```

## Troubleshooting

### Server won't start

1. Check Java version: `java -version` (requires 21+)
2. Check if port 25565 is available: `lsof -i :25565`
3. Check server logs: `tail -f server/logs/latest.log`

### Can't connect to server

1. Verify server is running
2. Check firewall rules
3. Verify `online-mode` setting matches your needs

### Plugin won't load

1. Check `plugins/example-plugin/build/libs/` for JAR
2. Verify plugin is in `server/plugins/`
3. Check server logs for errors

## Git Strategy

**Tracked:**
- Configuration files (server.properties, yml configs)
- Scripts
- Plugin source code
- Docker configuration

**Gitignored:**
- paper.jar and server binaries
- World folders (world/, world_nether/, world_the_end/)
- Player data, logs, cache
- ops.json, whitelist.json
- Build outputs

## License

MIT
