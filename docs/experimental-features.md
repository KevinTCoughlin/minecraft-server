# Experimental Features Guide

This document explains the experimental features enabled in this Minecraft server and how to manage them.

## Overview

This server has been configured with experimental features at two levels:
1. **JVM Level** - Advanced Java Virtual Machine optimizations
2. **Minecraft Level** - Experimental game features via datapacks

**Note**: PaperMC 1.21.4 requires Java 21 or later. While many of the JVM flags work with earlier versions, Java 21+ is required for the Minecraft server itself.

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

# Marker flags for tracking and identification
-Dusing.aikars.flags=https://mcflags.emc.gs
-Daikars.new.flags=true
```

**Note**: The `-Dusing.aikars.flags` and `-Daikars.new.flags` properties are marker flags that identify the server as using Aikar's optimized configuration. They don't affect runtime behavior but may be used by plugins and monitoring tools for detection and troubleshooting.

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
   - For Minecraft 1.21.4, the Bundle feature is the primary experimental datapack
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

1. **Crafting**: Bundles are crafted with 1 String and 1 Leather in a crafting table:
   ```
   [ ]  [S]  [ ]     S = String
   [ ]  [ ]  [ ]     L = Leather
   [ ]  [L]  [ ]
   ```
   (String in top-center, Leather in bottom-center)
2. **Using**: Right-click to place items in, right-click while sneaking to take items out
3. **Capacity**: Bundles can hold up to 64 item units (one full stack = 64 units)
4. **Dyeing**: Bundles can be dyed using 1 Bundle + 1 Dye

## Troubleshooting

### JVM Flags Issues

**Problem**: Server won't start with experimental flags
- **Solution**: Check Java version (requires Java 21+): `java -version`
  - On Ubuntu/Debian: `sudo apt install openjdk-21-jre-headless`
  - On macOS with Homebrew: `brew install openjdk@21`
  - On Windows: Download from [Adoptium](https://adoptium.net/)
- **Solution**: Check for typos in flag configuration
- **Solution**: Try disabling specific flags one at a time

**Problem**: High memory usage
- **Solution**: Adjust `-Xms` and `-Xmx` values in scripts or Docker config
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
- [Java Performance Tuning Guide](https://docs.oracle.com/en/java/javase/21/gctuning/)
- [Aikar's Flags Explained](https://mcflags.emc.gs/)

## Support

If you encounter issues with experimental features:
1. Check this documentation first
2. Review server logs for error messages
3. Test without experimental features to isolate the issue
4. Consult the PaperMC Discord or forums
5. Report bugs to the appropriate project (Paper, Mojang, or plugin authors)
