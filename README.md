# PaperMC Minecraft Server

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/KevinTCoughlin)](https://github.com/sponsors/KevinTCoughlin)

A config-driven PaperMC server setup with Kotlin/Java plugin development capability, manageable via shell scripts and Docker. **Features experimental JVM optimizations and Minecraft datapacks for enhanced performance and gameplay.**

## Features

✨ **Experimental Features Enabled**
- Advanced JVM optimizations with Aikar's flags
- Bundle datapack for improved inventory management
- See [Experimental Features Guide](docs/experimental-features.md) for details

## Prerequisites

- **Java 21** or later (for local development)
- **Gradle 8.x** (uses wrapper, auto-downloads)
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

Requires Java 21+ (`brew install openjdk@21`)

### Manual Setup

```bash
./scripts/update-paper.sh   # download PaperMC
./scripts/start.sh          # start server
./scripts/stop.sh           # graceful stop
```

### Docker

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
│   ├── paper-global.yml      # Paper-specific settings
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

### JVM Experimental Features

This server uses optimized JVM flags including experimental features for maximum performance:
- **G1 Garbage Collector** with advanced tuning
- **Experimental VM Options** enabled for cutting-edge optimizations
- **Aikar's Flags** - Industry-standard Minecraft server JVM configuration

**📖 See [Experimental Features Guide](docs/experimental-features.md) for complete details, configuration options, and troubleshooting.**

### Minecraft Experimental Features

Experimental Minecraft features are enabled via datapacks:
- **Bundle** datapack - Enables bundle items for inventory management
- Configured in `server.properties` via `initial-enabled-packs=vanilla,bundle`
- ⚠️ **Warning**: Experimental features may change between updates. Always backup worlds!

**📖 See [Experimental Features Guide](docs/experimental-features.md) for usage instructions and how to enable additional features.**

### Environment Variables

```bash
# start.sh
MIN_RAM=2G          # Minimum RAM allocation
MAX_RAM=4G          # Maximum RAM allocation

# update-paper.sh
MC_VERSION=1.21.4   # Minecraft version

# stop.sh
RCON_HOST=localhost
RCON_PORT=25575
RCON_PASSWORD=changeme

# backup.sh
BACKUP_DIR=./backups
MAX_BACKUPS=10

# deploy.sh
DEPLOY_HOST=your-server.com
DEPLOY_USER=minecraft
DEPLOY_PATH=~/minecraft-server
DEPLOY_PORT=22
```

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
- [Paper API Javadocs](https://jd.papermc.io/paper/1.21/)
- [Paper Development Guide](https://docs.papermc.io/paper/dev)

## Server Configuration

### Important Files

- **server.properties**: Core Minecraft server settings
- **paper-global.yml**: PaperMC global configuration
- **paper-world-defaults.yml**: Default world settings
- **bukkit.yml**: Bukkit-level settings
- **spigot.yml**: Spigot performance tuning

### Changing RCON Password

1. Edit `server/server.properties`:
   ```properties
   rcon.password=your-secure-password
   ```

2. Update scripts or set environment variable:
   ```bash
   export RCON_PASSWORD=your-secure-password
   ```

## Deployment

### To Remote Host

1. Create `.env` file:
   ```bash
   DEPLOY_HOST=your-server.com
   DEPLOY_USER=minecraft
   DEPLOY_PATH=~/minecraft-server
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

# With custom settings
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

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
