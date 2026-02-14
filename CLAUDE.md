# CLAUDE.md - Minecraft Server

## Server Overview

PaperMC 1.21.4 server on port 25565 with Bedrock cross-play via Geyser (port 19132) + Floodgate.

### Management

```bash
mc-server-manager start    # start server
mc-server-manager stop     # stop server
./scripts/start.sh         # alt: start with Aikar's flags
./scripts/stop.sh          # alt: graceful RCON stop
```

### Server Paths

- Server root: `server/`
- Plugins: `server/plugins/`
- Logs: `server/logs/latest.log`
- Worlds: `server/world/`, `server/parkour/`, `server/parkour-spiral/`, `server/parkour-spiral-3/`, `server/parkour-volcano/`, `server/parkour-pyramid/`, `server/parkour-paradise/`

## Installed Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| Geyser-Spigot | - | Bedrock Edition cross-play |
| Floodgate | - | Bedrock auth (no Java account needed) |
| Parkour (A5H73Y) | 7.2.5 | Parkour courses, checkpoints, leaderboards |
| WorldEdit | 7.4.0 | Fast course building (`//set`, `//stack`, `//copy`) |
| Multiverse-Core | 5.5.2 | Multi-world management |
| Blackjack | 1.0.0 | `/bj` minigame |
| Fart | 1.0.0 | `/fart` sound effect |
| DeathBan Pro | 1.0.0-beta | Death ban mechanic |

## Build System

Kotlin + Gradle with version catalog and convention plugin.

### Quick Reference

```bash
./gradlew build                              # build all plugins
./gradlew :plugins:blackjack-plugin:test     # run blackjack tests (70 tests)
./gradlew :plugins:fart-plugin:deployToServer  # build + copy JAR to server/plugins/
```

### Structure

- `gradle/libs.versions.toml` -- all dependency versions (Kotlin, Paper API, Shadow, LiteCommands, JUnit, kotlinx-serialization, kaml)
- `buildSrc/src/main/kotlin/paper-plugin.gradle.kts` -- convention plugin applied by all 3 plugins (JVM 21 toolchain, shadow JAR, deployToServer task, plugin.yml template expansion)
- `gradle.properties` -- project group/version, `minecraftVersion` (used by convention plugin for plugin.yml `apiVersion`)

### Plugin Build Files

Each plugin applies `id("paper-plugin")` and only declares its own dependencies. Blackjack additionally applies `kotlin("plugin.serialization")` and configures relocations + `-parameters` for LiteCommands.

### Key Libraries (blackjack-plugin)

| Library | Purpose |
|---------|---------|
| LiteCommands | Annotation-based command framework |
| kotlinx.serialization + kaml | Type-safe YAML config deserialization |

## Parkour Setup

### First-Time Setup (after server start)

1. Start the server and confirm plugins load in `logs/latest.log`
2. Create the parkour world (already done):
   ```
   mv create parkour normal --world-type flat --no-structures
   ```
3. Configure the parkour world (already done):
   ```
   mv modify parkour set gamemode adventure
   mv modify parkour set difficulty peaceful
   mv gamerule set minecraft:spawn_mobs false parkour
   mv gamerule set minecraft:advance_weather false parkour
   mv gamerule set minecraft:advance_time false parkour
   mv gamerule set minecraft:fire_damage false parkour
   mv gamerule set minecraft:spawn_monsters false parkour
   mv gamerule set minecraft:spawn_phantoms false parkour
   mv gamerule set minecraft:mob_griefing false parkour
   ```
4. Set parkour lobby (in-game as op):
   ```
   /mv tp parkour                        # teleport to parkour world
   /pa setlobby                          # set lobby at current location
   ```

### Creating a Course

```
/mv tp parkour                   # go to parkour world
/pa create <name>                # create course at current position (start point)
```

Walk to each checkpoint location:
```
/pa checkpoint                   # add checkpoint at current position
```

Walk to the finish:
```
/pa finish                       # set finish point
/pa ready <name>                 # mark course as playable
```

### Playing a Course

```
/pa join <name>                  # join a course
/pa leave                        # leave current course
/pa restart                      # restart current course
```

### Leaderboards & Stats

```
/pa leaderboard <name>           # view course leaderboard
/pa stats <player>               # view player stats
/pa times <name>                 # view all times for a course
```

### Course Management

```
/pa list                         # list all courses
/pa info <name>                  # course details
/pa delete <name>                # delete a course
/pa reset <name>                 # reset course times/stats
/pa setcreator <name> <player>   # set course creator
/pa prize <name>                 # configure course prize
/pa setmaxdeaths <name> <n>      # set max deaths (0 = unlimited)
/pa setmaxtime <name> <seconds>  # set time limit
```

### WorldEdit Quick Reference (for building courses)

```
//wand                           # get selection wand
//pos1 //pos2                    # set corners
//set <block>                    # fill selection
//replace <from> <to>            # replace blocks
//stack <count> [direction]      # repeat selection
//copy //paste                   # clipboard ops
//undo //redo                    # history
```

### Parkour Config

Config: `server/plugins/Parkour/config.yml`

Key customizations from defaults:
- `Scoreboard.Enabled: true` - live scoreboard during courses
- `Sounds.Enabled: true` - audio feedback for checkpoints/finish
- `OnDie.SetXPBarToDeathCount: true` - XP bar shows death count
- `DisplayLiveTime.Enabled: true` - show elapsed time
- `DisplayNewRecords: true` - announce new records globally
- `DisableFallDamage: true` - no fall damage during courses
- `DisablePlayerDamage: true` - invincible during courses
- `DieInLava: true` / `DieInVoid: true` - reset on lava/void
- `OnLeaveServer.LeaveCourse: true` - clean state on disconnect

### Parkour World Config

World-specific settings in `server/parkour/paper-world.yml`:
- All mob spawning disabled (spawn limits set to 0)
- Thunder/ice/snow disabled
- Explosion knockback disabled

### Pre-built Parkour Maps

Maps from [Hielke Maps](https://hielkemaps.com), installed via `scripts/setup-parkour-maps.sh`:

| World | Command | Description |
|-------|---------|-------------|
| `parkour-spiral` | `/mv tp parkour-spiral` | Original Parkour Spiral - themed tower climb, great for beginners |
| `parkour-spiral-3` | `/mv tp parkour-spiral-3` | Parkour Spiral 3 - bigger tower, multiple difficulty ranks, easter eggs |
| `parkour-volcano` | `/mv tp parkour-volcano` | Escape an active volcano through parkour |
| `parkour-pyramid` | `/mv tp parkour-pyramid` | One giant pyramid full of parkour |
| `parkour-paradise` | `/mv tp parkour-paradise` | 100 bite-sized parkour levels |

These maps use their own command block systems for checkpoints/timing — no Parkour plugin setup needed.

To add more maps: download a map zip, extract to `server/<name>/` (no spaces), then `mv import <name> normal`.

### Map Rotation

Maps rotate automatically every 4 hours via `mc-server-manager rotate-parkour` (LaunchAgent). On rotation:
1. Featured map advances (round-robin through `PARKOUR_MAPS`)
2. Server broadcasts the new featured map
3. Players in the previous featured map are teleported to the new one

```bash
mc-server-manager rotate-parkour   # manual rotation
mc-server-manager status           # see current featured map
```

Config in `~/.config/mc-server/config`:
- `PARKOUR_ROTATION_ENABLED` — enable/disable (default: true)
- `PARKOUR_MAPS` — space-separated world names to rotate through

### Auto Restart

Server restarts every 6 hours for memory cleanup via `mc-server-manager auto-restart` (LaunchAgent). Uses the standard restart flow with player warnings.

Config: `AUTO_RESTART_INTERVAL` (seconds, default: 21600 = 6h, 0 to disable).

### Notes

- `allow-flight=true` is set in `server.properties` (required for parkour plugin)
- Bedrock players connect via Geyser on port 19132
- Parkour plugin works with Bedrock players through Geyser
- Courses are stored in `server/plugins/Parkour/courses/`
