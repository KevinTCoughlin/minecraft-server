# Fart Plugin

A fun Minecraft plugin that adds a `/fart` command to play fart sound effects in-game.

## Features

- Simple `/fart` command that any player can use
- Plays a funny sound effect using Minecraft's built-in sounds (ENTITY_RAVAGER_STUNNED with low pitch)
- Shows a fun message to the player who used the command
- Broadcasts to nearby players (within 20 blocks) that someone farted
- Default permission allows all players to use the command

## Commands

| Command | Description | Permission |
|---------|-------------|------------|
| `/fart` | Play a fart sound effect | `fart.use` (default: true) |

## Permissions

- `fart.use` - Allows players to use the /fart command (default: true for all players)

## Usage

Simply type `/fart` in chat, and you'll hear a funny sound effect! Nearby players will be notified that you farted.

## Building

```bash
# Build the plugin
./gradlew :plugins:fart-plugin:build

# Build and deploy to server/plugins/
./gradlew :plugins:fart-plugin:deployToServer
```

## Installation

1. Build the plugin using the command above
2. The plugin JAR will be automatically copied to `server/plugins/`
3. Start or restart the server
4. Players can now use `/fart` in-game!

## Technical Details

- Uses Minecraft's ENTITY_RAVAGER_STUNNED sound with a low pitch (0.5) to create a fart-like sound
- Volume is set to 1.0 (normal)
- Nearby player detection radius: 20 blocks in all directions
- Built with Kotlin and PaperMC API 1.21.4

## Credits

Created for fun gameplay! Inspired by Creative Commons sound effects.
