# Parkour Maps & Rotation

## Map Catalog

All maps sourced from [Hielke Maps](https://hielkemaps.com). Each uses built-in command block systems for checkpoints and timing.

| World | Description | Difficulty |
|-------|-------------|------------|
| `parkour-spiral` | Themed tower climb | Beginner |
| `parkour-spiral-3` | Larger tower, multiple difficulty ranks, easter eggs | Intermediate |
| `parkour-volcano` | Escape an active volcano | Intermediate |
| `parkour-pyramid` | Giant pyramid full of parkour | Mixed |
| `parkour-paradise` | 100 bite-sized parkour levels | Mixed |

## Setup

Install all maps (idempotent — skips existing):

```bash
./scripts/setup-parkour-maps.sh
```

Preview without downloading:

```bash
./scripts/setup-parkour-maps.sh --dry-run
```

The script:
1. Downloads each map zip from hielkemaps.com
2. Extracts the world folder to `server/<name>/`
3. Copies `paper-world.yml` from `server/parkour/` (disables mobs, weather, explosions)
4. Imports into Multiverse via RCON if server is running

## Map Rotation

A LaunchAgent (`com.user.minecraft-parkour-rotation`) runs `mc-server-manager rotate-parkour` every 4 hours.

### How it works

1. Reads the current map index from `~/.local/share/minecraft-server/parkour-rotation-state`
2. Advances to the next map (wraps around)
3. Broadcasts the new featured map to all players via RCON
4. Teleports players in the previous featured world to the new one

### Manual rotation

```bash
mc-server-manager rotate-parkour
```

### Configuration

Set in `~/.config/mc-server/config`:

```bash
PARKOUR_ROTATION_ENABLED="true"
PARKOUR_MAPS="parkour-spiral parkour-spiral-3 parkour-volcano parkour-pyramid parkour-paradise"
```

### Check current state

```bash
mc-server-manager status
```

Shows the current featured map, rotation index, and map list.

## Auto Restart

Server restarts every 6 hours for memory cleanup. The restart LaunchAgent (`com.user.minecraft-server-restart`) fires on a 6-hour interval.

### How it works

- Uses `mc-server-manager restart` with the standard warning sequence (5m, 1m, 30s, 10s, 5s)
- Records restart timestamp to `~/.local/share/minecraft-server/last-restart`
- `mc-server-manager auto-restart` checks elapsed time as a safety net to avoid double-restarts

### Configuration

```bash
AUTO_RESTART_INTERVAL="21600"  # seconds (6 hours), 0 to disable
```

## Adding New Maps

1. Find a map zip (Hielke Maps or other source)
2. Add it to `MAP_NAMES`, `MAP_URLS`, `MAP_ZIP_FOLDERS` arrays in `scripts/setup-parkour-maps.sh`
3. Run the setup script
4. Add the world name to `PARKOUR_MAPS` in your config to include it in rotation

Or manually:

```bash
# Extract to server directory
unzip map.zip -d server/my-map/

# Copy parkour world config
cp server/parkour/paper-world.yml server/my-map/

# Import in-game or via RCON
mv import my-map normal
```

## LaunchAgents

| Agent | Interval | Command |
|-------|----------|---------|
| `com.user.minecraft-parkour-rotation` | 4 hours | `mc-server-manager rotate-parkour` |
| `com.user.minecraft-server-restart` | 6 hours | `mc-server-manager restart` |

### Load/reload agents

```bash
launchctl load ~/Library/LaunchAgents/com.user.minecraft-parkour-rotation.plist
launchctl unload ~/Library/LaunchAgents/com.user.minecraft-server-restart.plist
launchctl load ~/Library/LaunchAgents/com.user.minecraft-server-restart.plist
```
