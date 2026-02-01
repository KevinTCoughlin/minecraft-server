# Fart Plugin Usage Guide

## Quick Start

Once the plugin is built and deployed, players can immediately start using the `/fart` command!

## How to Use

### Basic Usage
Simply type in the chat:
```
/fart
```

### What Happens
1. You'll hear a funny fart sound effect (using Minecraft's ENTITY_RAVAGER_STUNNED sound with low pitch)
2. You'll see a message: `💨 *Fart noise* 💨`
3. All players within 20 blocks will see: `[YourName] farted! 💨`

## Building & Deploying

### Step 1: Build the Plugin
```bash
./gradlew :plugins:fart-plugin:build
```

This will compile the plugin and create a JAR file.

### Step 2: Deploy to Server
```bash
./gradlew :plugins:fart-plugin:deployToServer
```

This will copy the plugin JAR to the `server/plugins/` directory.

### Step 3: Restart the Server
Stop and start your Minecraft server to load the new plugin:
```bash
./scripts/stop.sh
./scripts/start.sh
```

## Permissions

By default, all players can use the `/fart` command. If you want to restrict it, you can modify the permission in your server's permission plugin:

- Permission node: `fart.use`
- Default: `true` (everyone can use it)

## Customization

If you want to customize the plugin, you can modify:

### Sound Effect
In `FartCommand.kt`, line 22, change the sound:
```kotlin
Sound.ENTITY_RAVAGER_STUNNED  // Current sound
```

Available alternatives:
- `Sound.ENTITY_GHAST_HURT` - Longer, deeper sound
- `Sound.ENTITY_RAVAGER_ROAR` - Louder, more dramatic
- `Sound.BLOCK_BREWING_STAND_BREW` - Bubbly sound

### Volume & Pitch
In `FartCommand.kt`, line 23-24:
```kotlin
1.0f,  // volume (0.0 to 2.0)
0.5f   // pitch (0.5 to 2.0, lower = deeper)
```

### Detection Radius
In `FartCommand.kt`, line 33-35, change the radius (currently 20 blocks):
```kotlin
20.0,  // X radius
20.0,  // Y radius  
20.0   // Z radius
```

## Troubleshooting

### Plugin Not Loading
1. Check server logs: `tail -f server/logs/latest.log`
2. Verify the plugin JAR is in `server/plugins/`
3. Ensure you restarted the server after copying the plugin

### Command Not Working
1. Check you have permission: `fart.use`
2. Make sure you're typing `/fart` (not just `fart`)
3. Only players can use the command (not console)

### No Sound Playing
1. Make sure your Minecraft client sound is enabled
2. Check your game sound settings (Master Volume, Hostile Creatures volume)
3. The sound plays at your location, so you should be able to hear it

## Fun Facts

- The fart sound uses Minecraft's ENTITY_RAVAGER_STUNNED sound effect with a pitch of 0.5
- Nearby players within 20 blocks get notified
- The plugin is lightweight and won't affect server performance
- Sound is client-side, so each player hears it from their own perspective

## For Your Son

Tell your son that the `/fart` command is now available! He can use it anytime in the game to make his character fart with a funny sound. All his friends nearby will see the message too! 💨😄

Enjoy!
