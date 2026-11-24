# Experimental Features Guide

This document explains the experimental features enabled in this Minecraft server and how to manage them.

## Overview

This server has been configured with experimental features at two levels:
1. **JVM Level** - Advanced Java Virtual Machine optimizations
2. **Minecraft Level** - Experimental game features via datapacks

**Note**: This server runs Paper 26.3, which requires Java 25+. The start script still offers both G1GC (Aikar's flags, the default) and ZGC.

## JVM Experimental Features

### What's Enabled

The server uses comprehensive JVM optimization flags including experimental features for maximum performance:

```bash
-XX:+UnlockExperimentalVMOptions
-XX:+UseG1GC
-XX:+ParallelRefProcEnabled
-XX:MaxGCPauseMillis=200
-XX:+DisableExplicitGC
-XX:+AlwaysPreTouch
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1HeapRegionSize=8M
-XX:G1ReservePercent=20
-XX:G1HeapWastePercent=5
-XX:G1MixedGCCountTarget=4
-XX:InitiatingHeapOccupancyPercent=15
-XX:G1MixedGCLiveThresholdPercent=90
-XX:G1RSetUpdatingPauseTimePercent=5
-XX:SurvivorRatio=32
-XX:+PerfDisableSharedMem
-XX:MaxTenuringThreshold=1
-XX:+ExitOnOutOfMemoryError
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/path/to/dumps

# Marker flags for tracking and identification
-Dusing.aikars.flags=https://mcflags.emc.gs
-Daikars.new.flags=true
```

`scripts/jvm-opts.sh` is the single flag list. On a host (`MEMORY_MODE=fixed`, the `start.sh` default) the heap is `-Xms`/`-Xmx` from `MIN_RAM` and `MAX_RAM`. In the container image (`MEMORY_MODE=container`) a memory limit selects `-XX:InitialRAMPercentage` and `-XX:MaxRAMPercentage` (both 75 by default) so the heap tracks the cgroup limit and does not resize. With no limit, the image does not refuse to start and does not take a percentage of the whole machine. It uses a safe default heap, about 25% of host memory clamped between 1G and 4G, or 2G if host memory cannot be read, and prints how to set a limit. `MEMORY` overrides that choice (`2G`, `4G`, `auto`, or `75%`). `G1NewSizePercent`, `G1MaxNewSizePercent`, and `G1MixedGCLiveThresholdPercent` are still experimental on Java 25, which is why `UnlockExperimentalVMOptions` stays. The other Aikar flags are accepted on Java 25 with no warning.

### How much memory?

`MEMORY` is the one knob. A container limit is still the better way to size the server: the heap is then 75% of that limit unless you set another percentage. With no limit, the safe default above is a boot choice, not a sizing recommendation.

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

In Compose, set `deploy.resources.limits.memory` (for example `4G`).

For a before-and-after check of heap use, pauses, and TPS on a copy of a real world, follow [minecraft-server#129](https://github.com/KevinTCoughlin/minecraft-server/issues/129).

`-XX:+ExitOnOutOfMemoryError` ends the process on the first out-of-memory error so a supervisor can restart it. The heap dump is written under `HEAP_DUMP_PATH` (`server/dumps` for `start.sh`, `/data/dumps` in the image).

**Note**: The `-Dusing.aikars.flags` and `-Daikars.new.flags` properties are marker flags that identify the server as using Aikar's optimized configuration. They don't affect runtime behavior but may be used by plugins and monitoring tools for detection and troubleshooting.

### Compact object headers (off unless opted in)

JDK 25 can shrink object headers with `-XX:+UseCompactObjectHeaders` (Project Lilliput). `scripts/jvm-opts.sh` leaves the flag off unless `COMPACT_OBJECT_HEADERS` is `true` (`1`, `yes`, and `on` do the same). The Compose `JVM_XX_OPTS` block does not set it. The flag is outside Aikar's set, and on a Minecraft heap it can change memory use and pause times. The G1 set already passes `-XX:+UnlockExperimentalVMOptions`, which this flag also requires. The ZGC set does not, so the opt-in adds that unlock only when the flag is requested.

Measure a **copy** of a real world before using the opt-in on a server anyone plays:

```bash
./scripts/stop.sh
./scripts/measure-compact-headers.sh --world server/parkour-spiral
```

The harness refuses to start Paper on the original world path. Acceptance is a smaller heap with GC pauses and TPS no worse. MSPT is part of that TPS check because TPS is capped at 20. A passing summary is evidence for a follow-up that would change the default. The harness itself leaves the default off. Full steps and the decision rule are in [Compact object headers](compact-object-headers.md). The measurement is tracked in https://github.com/KevinTCoughlin/minecraft-server/issues/129.

### ZGC (Alternative - MC 26.1+ Default)

For Minecraft 26.1+, ZGC (Z Garbage Collector) is the new default. Set `GC_TYPE=zgc` to enable:

```bash
-XX:+UseZGC
-XX:+AlwaysPreTouch
-XX:+DisableExplicitGC
-XX:+PerfDisableSharedMem
-XX:+ExitOnOutOfMemoryError
-XX:+HeapDumpOnOutOfMemoryError
```

JDK 24 removed `-XX:+ZGenerational`. Generational ZGC is the only mode, and passing the old flag makes Java 25 print a warning.

**ZGC Benefits**:
- Sub-millisecond pause times (vs G1GC's ~200ms target)
- Better suited for large heaps (8GB+)
- Generational mode improves throughput

**When to use ZGC**:
- Minecraft 26.1+ (default)
- Large servers with 8GB+ RAM
- When minimizing lag spikes is critical

**When to use G1GC**:
- This repository's default, including Paper 26.3
- Smaller servers (2-4GB RAM)
- Maximum compatibility with existing setups

### Benefits

- **Lower GC Pause Times**: Reduced lag spikes from garbage collection
- **Better Memory Management**: More efficient heap utilization
- **Improved Performance**: Smoother gameplay, especially with many players
- **Aikar's Flags**: Industry-tested configuration used by thousands of servers

### Where It's Applied

These flags are applied in:
- `scripts/start.sh` - For local server startup
- `docker/Dockerfile` - For custom Docker builds
- `docker/docker-compose.yml` - For Docker Compose deployments

### Resources

- [PaperMC Aikar's Flags Documentation](https://docs.papermc.io/paper/aikars-flags)
- [Minecraft Performance Flags Benchmarks](https://github.com/brucethemoose/Minecraft-Performance-Flags-Benchmarks)

## Minecraft Experimental Features

### What's Enabled

The server enables experimental Minecraft features through datapacks:

**Bundle Datapack**
- Enables bundle items for inventory management
- Allows storing multiple item types in a single inventory slot
- Available since Minecraft 1.21 experiments

### Configuration

Experimental features are enabled via `server.properties`:

```properties
initial-enabled-packs=vanilla,bundle
```

Or in Docker via `docker-compose.yml`:

```yaml
environment:
  INITIAL_ENABLED_PACKS: "vanilla,bundle"
```

### How to Add More Experimental Features

To enable additional experimental datapacks:

1. **For Local Server**: Edit `server/server.properties`
   ```properties
   initial-enabled-packs=vanilla,bundle,other_experimental_pack
   ```

2. **For Docker**: Edit `docker/docker-compose.yml`
   ```yaml
   environment:
     INITIAL_ENABLED_PACKS: "vanilla,bundle,other_experimental_pack"
   ```

3. **Available Experimental Packs** (varies by Minecraft version):
   - `bundle` - Bundle items (enabled by default in this server)
   - Check [Minecraft Wiki - Experiments](https://minecraft.wiki/w/Experiments) for version-specific experimental features

### Important Warnings

⚠️ **Before enabling experimental features:**

1. **Backup Your World**: Experimental features may cause issues or change behavior
2. **Cannot Be Disabled**: Once a world is created with experimental features, they cannot be removed
3. **May Change**: Experimental features can change significantly between updates
4. **Not for Realms**: Worlds with experimental features cannot be uploaded to Minecraft Realms
5. **Plugin Compatibility**: Some plugins may not work correctly with experimental features

### How to Use Bundles

Once the bundle datapack is enabled:

1. **Crafting**: Bundles are crafted with 6 String and 1 Rabbit Hide in a crafting table (Minecraft 1.21+):
2. **Using**: Right-click to place items in, right-click while sneaking to take items out
3. **Capacity**: Bundles can hold up to 64 item units (one full stack = 64 units)
4. **Dyeing**: Bundles can be dyed using 1 Bundle + 1 Dye

## Troubleshooting

### JVM Flags Issues

**Problem**: Server won't start with experimental flags
- **Solution**: This release requires Java 25 and Paper 26.3. Java 21 and Minecraft 1.21.x should stay on the previous release. Check with `java -version`.
  - On Ubuntu/Debian: install Eclipse Temurin 25 from [Adoptium](https://adoptium.net/installation/linux/). `openjdk-21-jre` cannot run Paper 26.3.
  - On macOS with Homebrew: `brew install --cask temurin@25`
  - On Windows: Download from [Adoptium](https://adoptium.net/)
  - Set `JAVA_HOME` to use a specific Java version
- **Solution**: Check for typos in flag configuration
- **Solution**: Try disabling specific flags one at a time

**Problem**: High memory usage
- **Solution**: On a host, adjust `MIN_RAM` and `MAX_RAM`, or set `MEMORY` (`2G`, `4G`, `auto`, or `75%`). In a container, set a memory limit (the heap is 75% of it unless `MEMORY` says otherwise). See [How much memory?](#how-much-memory) for starting points. A limit under 1G, or a heap that leaves very little room outside itself, prints a warning and still starts.
- **Solution**: Monitor with `/spark profiler` if using Spark plugin

### Minecraft Experimental Features Issues

**Problem**: Bundle datapack not working
- **Solution**: Verify `initial-enabled-packs` is set correctly
- **Solution**: Delete the world and create a new one (experimental packs apply at world creation)
- **Solution**: Check Minecraft version compatibility

**Problem**: World won't load after enabling experimental features
- **Solution**: Restore from backup
- **Solution**: Check server logs: `tail -f server/logs/latest.log`

**Problem**: Plugins breaking with experimental features
- **Solution**: Update plugins to latest versions
- **Solution**: Report compatibility issues to plugin authors
- **Solution**: Consider disabling experimental features if critical plugins fail

## Performance Monitoring

To verify experimental features are working:

1. **JVM Monitoring**:
   ```bash
   # Check if experimental flags are active
   jps -v | grep paper.jar
   ```

2. **Enable JMX** (in server.properties):
   ```properties
   enable-jmx-monitoring=true
   ```

3. **Use Spark Plugin**:
   - Download from [SparkMC](https://spark.lucko.me/)
   - Monitor GC performance: `/spark gc monitor`
   - Profile CPU: `/spark profiler start`

## Further Reading

- [PaperMC Configuration Documentation](https://docs.papermc.io/paper/reference/configuration/)
- [Minecraft Wiki - Experiments](https://minecraft.wiki/w/Experiments)
- [Java Performance Tuning Guide](https://docs.oracle.com/en/java/javase/25/gctuning/)
- [ZGC Documentation](https://wiki.openjdk.org/display/zgc)
- [Aikar's Flags Explained](https://mcflags.emc.gs/)

## Support

If you encounter issues with experimental features:
1. Check this documentation first
2. Review server logs for error messages
3. Test without experimental features to isolate the issue
4. Consult the PaperMC Discord or forums
5. Report bugs to the appropriate project (Paper, Mojang, or plugin authors)
