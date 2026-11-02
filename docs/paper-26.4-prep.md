# Paper 26.3 build 237 and a future 26.4 login change

This server runs **Paper 26.3 build 237** (published 2026-11-01, channel `STABLE`) on **Java 25**. Build 237 is the newest 26.3 build as of 2026-11-02 and includes the three fixes below. Its own commit is "Sync latest Moonrise changes (#14452)" and does not touch damage, potions, or respawn. Minecraft 26.4 is preview-only: Paper's Fill API has no 26.4 version, and this repository does not migrate to it.

Checked against `https://fill.papermc.io/v3/projects/paper/versions/26.3/builds` on 2026-11-02.

## Upstream changes

### Build 228 — fire damage is a block-damage event

Commit `2e549d6` ("Call EntityDamageByBlockEvent for fire damage", #12235), 2026-10-29. This is the only commit in build 228.

Standing in fire now goes through `DamageSource.eventBlockDamager`, so the Bukkit event is `EntityDamageByBlockEvent` (cause `FIRE`, damager is the fire block). That event still extends `EntityDamageEvent`. The same commit removes the early `DamageTypes.IN_FIRE` → `DamageCause.FIRE` mapping that used to run before the block-damager branch. Burning damage (`FIRE_TICK`) is unchanged and is not a block event.

`DamageCause.DRAGON_BREATH` was **not** deprecated by this commit. On current Paper `main` it is already `@Deprecated(since = "1.21.5")`, with javadoc that vanilla reports dragon breath as `ENTITY_ATTACK` unless a command or plugin forces the old cause. `CraftEventFactory` still assigns `DRAGON_BREATH` when the damage type is dragon breath and an entity damager is present. No commit in 26.3 builds 228–237 mentions dragon breath.

### Build 229 — a cancelled splash no longer puts fires out

Commit `ff31a2c` ("Fix cancelled PotionSplashEvent putting out fires", #12194), 2026-10-29. Cancelling `PotionSplashEvent` now stops a water splash or lingering potion from extinguishing fire. This matches the long-standing report in PaperMC/Paper#11981.

### Build 233 — respawn search covers the whole square

Commit `f728a12` ("Fix respawn radius only covering part of the square", #14390), 2026-10-31. `PlayerSpawnFinder` used the attempt cap as the modular area, so some radii (the comment calls out 51×51, where 17 is not coprime) never sampled the full `(2r+1)²` square around the world spawn. The area and the attempt cap are now separate (`MC-302446`). This is the vanilla no-bed / no-respawn-anchor search. A plugin that sets the respawn location on `PlayerRespawnEvent` does not go through this search.

## First-party plugins

`example-plugin`, `blackjack-plugin`, and `fart-plugin` were read in full.

| Concern | Result |
| --- | --- |
| `EntityDamageEvent` / `EntityDamageByBlockEvent` listeners | None. Fire contact cannot be handled twice. |
| Admin or permission immunity | None. Creative, spectator, and invulnerability stay vanilla. |
| Life or death counters | None. Nothing can increment twice on one fatal fire hit. |
| `DamageCause.DRAGON_BREATH` | No references. |
| `PotionSplashEvent` | No listeners, so nothing cancels a splash. No region or arena plugin is in this repo. Parkour course invincibility is the Parkour plugin and the `fire_damage` gamerule, not a splash-cancel. |
| Respawn | No `PlayerRespawnEvent` listener and no plugin-chosen spawn. Bed and respawn-anchor handling stay vanilla. The build 233 fix applies to the world-spawn square. |

DeathBan Pro is named in `CLAUDE.md` and has no source here, so it was not audited. If that jar is still deployed, retest it: a fatal fire hit now arrives as `EntityDamageByBlockEvent`.

## Config migrated by booting 26.3.237

A first boot of build 237 rewrote three files in place. `_version` stayed 31. The values below are what that boot wrote; behavior that was already set is unchanged.

- `server/config/paper-global.yml`: `commands.time-command-affects-all-worlds` moved to `time.affects-all-worlds` (still false). Dropped `logging.deobfuscate-stacktraces`, `misc.fix-far-end-terrain-generation`, `misc.send-full-pos-for-item-entities`, and `unsupported-settings.compression-format`. Added `misc.catchup-ticks`, `misc.max-tracking-combat-entries`, `unsupported-settings.oversized-item-component-sanitizer`, and `update-checker.enabled`.
- `server/config/paper-world-defaults.yml`: new chunk-unload, tree-snow, and command-block time-format keys, plus `unsupported-settings.ticking`.
- `server/spigot.yml`: `config-version` 12 → 13, and a `seed-abandonedcamp` salt.

Paper still tries to save these files on later startups. Compose mounts them read-only, which logs a save error and still reaches `Done`. The custom image copies them into a writable layer.

## Why there is no MockBukkit test for these cases

The existing tests are plain JUnit (blackjack rules). MockBukkit `org.mockbukkit.mockbukkit:mockbukkit-v26.3:4.119.0` (2026-10-29) is built against `paper-api` **26.3.build.200-stable**, which is older than builds 228, 229, and 233. It cannot reproduce the server patches, and there is no plugin listener for it to call. Those three fixes are in `paper-server`, not in code this repo can unit-test. The manual checklist below is the coverage for them.

## 26.4 Snapshot 5 login change (do not migrate yet)

[Minecraft 26.4 Snapshot 5](https://www.minecraft.net/en-us/article/minecraft-26-4-snapshot-5) (2026-10-20) is a preview. Wiki protocol id for that snapshot is `1073742167` (`0x40000157`); later snapshots can change it. Data pack `125.0`, resource pack `100.2`, Java 25.

Encryption and compression are no longer applied the moment both sides see the old packet. The server sends connection options on one of:

| Server → client | Client → server |
| --- | --- |
| `minecraft:login_finished` | `minecraft:login_acknowledged` |
| `minecraft:apply_options` | `minecraft:options_applied` |

Packets after the acknowledgement use the new settings. The old immediate switch could desynchronize compression (fixed as `MC-308621`).

### What this repo actually uses

| Piece | In this repo | 26.3 target | 26.4 note |
| --- | --- | --- | --- |
| Paper | Docker, `server/.paper-version`, Gradle `paper-api` `26.3.build.237-stable` | 26.3 build 237 | No 26.4 Paper build exists. Stay here. |
| First-party plugins | Bukkit/Paper API and LiteCommands 3.11.0 (commands only) | Compile against 26.3 build 237 | No NMS (`net.minecraft`), ProtocolLib, PacketEvents, ViaVersion, or Netty pipeline code. |
| Velocity | `server/config/paper-global.yml` has `proxies.velocity.enabled: false`. The Compose service is commented out. | Not deployed. Released line is **4.3.1** (2026-10-27), a packet-validation fix, not a protocol bump. | [Velocity#1913](https://github.com/PaperMC/Velocity/pull/1913) (draft, open) is the 26.4 work. A `Minecraft 26.4-snapshot-5` commit landed on 2026-10-23 and was **reverted the same day** (`77274a8`). 4.3.1 does not speak `apply_options` / `options_applied`. Do not enable the proxy on a 26.4 server until that work is in a release. |
| BungeeCord | `server/spigot.yml` `settings.bungeecord: false` | Not deployed | Same login change. No BungeeCord jar is pinned here. |
| Geyser-Spigot | Not vendored (`server/plugins/` is empty in git). `CLAUDE.md` expects it. | **2.12.1 build 1280** (Geyser download API, 2026-10-31) for Java 26.3 | Needs a build whose notes name the 26.4 acknowledgement packets before Bedrock players can join a 26.4 backend. |
| Floodgate | Not vendored | **2.2.5 build 141** (2026-09-17), still the newest build, the one that moved to 26.3 | Auth plugin; retest with Geyser after any 26.4 Geyser bump. No newer build as of 2026-11-01. |
| WorldEdit | Not vendored. Docs say 7.4.0. | **7.4.6** (Hangar, Paper 1.21.4–26.3, 2026-10-15) | Block API only. Recheck the Hangar page when moving to 26.4. |
| Multiverse-Core | Not vendored. Docs say 5.5.2. | **5.8.2** (Hangar, 1.18.2–26.3, 2026-10-26) | World manager, not a packet library. 5.5.2 does not list 26.3. |
| Parkour (A5H73Y) | Not vendored. Docs say 7.2.5. | Newest release is **7.2.8** (2026-06-24). CurseForge lists it through **26.2**, not 26.3. | Course deaths are this plugin's counter. Confirm on a 26.3 server before trusting it. It does not implement the login protocol. |
| DeathBan Pro | Named in `CLAUDE.md` only | Unknown; no jar in git | Retest fatal fire and respawn if it is still installed. |
| ViaVersion / ViaBackwards / ProtocolLib / PacketEvents | Not referenced in Gradle or `server/plugins` | Do not add them for 26.3 | Any future protocol bridge must understand the acknowledgement packets. ViaVersion lets newer clients talk to an older server; it is not a substitute for Paper 26.4. |

`network-compression-threshold=256` in `server.properties` means login compression is on. That is the setting the 26.4 acknowledgement change is meant to make safe. Leave it for 26.3.

## Manual checklist

Live server only. Run against Paper 26.3 build 237 with the three first-party jars, then again with Geyser 2.12.1-b1280, Floodgate 2.2.5-b141, WorldEdit 7.4.6, and Multiverse-Core 5.8.2 if those are deployed.

1. **Boot.** `./setup.sh` then `./scripts/start.sh` on Java 25. Log contains `Done` and `26.3-237`. No crash report. `Done` alone is not a pass: an older jar and a server still passing `-XX:+ZGenerational` both reach `Done`.
   - **Stale jar.** Leave `.paper-version` at `26.3-237`, replace `paper.jar` with any other file, and run `./scripts/update-paper.sh`. It must refuse to stay on that file and download build 237. A script that prints "Already at latest version" here is still broken.
   - **ZGC.** Stop the server, then `GC_TYPE=zgc ./scripts/start.sh`. The process command line includes `-XX:+UseZGC` and does not include `ZGenerational`. The log does not contain `Ignoring option ZGenerational`.
   - **Docker.** `docker compose up` from `docker/` with `VERSION=26.3` and `PAPER_BUILD=237`, and the health check goes green.
2. **Direct fire, once.** Survival player, no resistance or fire protection, standing in fire until death. One death message. If a death-ban or parkour death counter is installed, it increments by one. An operator in creative, and a player with vanilla invulnerability, takes no damage.
3. **Burn tick.** Light a player, then leave the fire block. Further damage is `FIRE_TICK` only. Still one death when health reaches zero.
4. **Dragon breath.** Stand in dragon's breath. Confirm the server does not require a plugin to translate `DRAGON_BREATH`; no first-party plugin branches on that cause.
5. **Cancelled splash.** On a throwaway world, place fire, cancel `PotionSplashEvent` from a temporary test plugin (none of the shipped plugins do this), and throw a water splash potion. The fire stays. Without the cancel, the same potion puts the fire out.
6. **Respawn square.** World spawn set. The gamerule is `minecraft:respawn_radius` (`/gamerule minecraft:respawn_radius 25`). `spawnRadius` is the old name and is not the key Paper 26.3 reads. Radius 25 is the 51×51 square called out in the fix: 17 divides 51×51, and that area is larger than the old 1024-attempt cap. The default radius 10 is only 21×21, which the unpatched search already covered, so a test at 10 can pass on a server that still has the bug. No bed and no respawn anchor. Die repeatedly and record X/Z. Positions should be able to land on the full square, including corners, not only a band. Then set a bed, die, and confirm respawn is the bed. Break the bed, die, and confirm the search is used again.
7. **Plugin respawn.** Nothing in this repo sets a respawn location. If DeathBan or Parkour is installed, die on a course and confirm it still sends the player to that plugin's spawn exactly once.
8. **26.4 login, later.** Do this only after Paper publishes 26.4 and the proxy/Geyser builds above have released the acknowledgement support. Do not point this repo at a 26.4 snapshot for it.
   - Java client on that same version: fresh login, disconnect, reconnect, then a second account while the first stays online. Chat and move after each.
   - Repeat with `network-compression-threshold=256` (the value in `server.properties`) and once with compression disabled (`-1`). Failure looks like an instant disconnect or a malformed-packet / bad packet id error after login success.
   - Online-mode (encryption) and, if you use it, offline-mode.
   - If Velocity is turned on: the same Java cases through the proxy, using a Velocity release that contains the 26.4 work (not 4.3.1).
   - Bedrock through Geyser on UDP 19132: join, disconnect, reconnect, with Floodgate on. Then, only if you run Geyser on the proxy, the same through Geyser-Velocity.
