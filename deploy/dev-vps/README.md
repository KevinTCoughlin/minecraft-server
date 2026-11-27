# dev-vps: Minecraft dev world on a rootless-Podman VPS

Operations kit for a small Debian VPS that runs this repo's container image
(`ghcr.io/kevintcoughlin/minecraft-server`) as a rootless Podman Quadlet under the system user `mc`.
It adds the pieces the image does not have: auto-update with rollback, daily backups with a monthly
restore test, idle-only Chunky pre-generation, idle-only reboots, and a small `mc` admin command.

Nothing here runs in CI or in the container image. It is copied to the host by hand (see below).
CI only lints the scripts (`bash -n` and `shellcheck` on ubuntu).

Safety rules baked into every job: nothing restarts or reboots the server unless `mc-players` reports
`humans=0` (an unreadable count counts as busy), and the update, backup and plugin jobs share one `flock`.

## What is in this directory

| Path | Install to | What |
|---|---|---|
| `quadlet/minecraft-dev.container` | `~mc/.config/containers/systemd/` | Quadlet unit for the server container |
| `systemd/*.service`, `*.timer` | `~mc/.config/systemd/user/` | server update, plugin update, backup, restore test, Chunky idle |
| `bin/*` | `~mc/.local/bin/` | `mc-rcon`, `mc-players`, `mc-lib.sh`, `mc-server-update`, `mc-plugin-update`, `mc-backup`, `mc-restore-test`, `mc-chunky-idle` |
| `env/*.example` | `~mc/.config/minecraft-dev/` | templates for `rcon.env` (secret) and `update.env` (optional) |
| `host/mc` | `/usr/local/bin/mc` | root admin kit: `mc status\|logs\|players\|rcon\|backup\|restore-test\|update\|plugin-update\|reboot-check\|motd` |
| `host/sbin/as-mc` | `/usr/local/sbin/as-mc` | run a command as `mc` with its user-session environment |
| `host/sbin/mc-reboot-if-idle` | `/usr/local/sbin/` | reboot for pending updates only when idle |
| `host/systemd/mc-reboot-if-idle.*` | `/etc/systemd/system/` | its service and timer (02:15 to 03:15 PT) |
| `host/50-mc-dev` | `/etc/update-motd.d/50-mc-dev` | login banner (players, reboot pending, last backup) |
| `host/52unattended-upgrades-local` | `/etc/apt/apt.conf.d/` | unattended-upgrades never reboots by itself |

## Secrets and host-specific values

- `rcon.env` holds `RCON_PASSWORD` and is never committed. Use `env/rcon.env.example` as the template.
- Nothing in this directory contains passwords, keys, tokens or device codes. Xbox broadcast tokens live
  under the server data dir on the host and are covered by 0600 backups.
- The host IP, SSH keys and player identifiers are intentionally not recorded here.

---

Reference host: a small VPS named `mc-dev` (Debian 13, 4 vCPU, 3.8 GiB RAM, 2 GiB swap). Replace
`<host-ip>` below with your own address.
Server: `ghcr.io/kevintcoughlin/minecraft-server` (Paper 26.3) as a rootless Podman Quadlet under
the system user `mc` (nologin, lingering on). This directory is the copy of
`~mc/deploy/` from that host, kept in the repo so the box can be rebuilt from scratch.

## Layout on the host (all owned by mc)

| Path | What |
|---|---|
| `~/deploy/quadlet/minecraft-dev.container` | Quadlet source (installed to `~/.config/containers/systemd/`) |
| `~/deploy/systemd/*.service, *.timer` | updater, plugin updater, backup, restore test, Chunky idle-only units (installed to `~/.config/systemd/user/`) |
| `~/deploy/bin/` | `mc-rcon`, `mc-players`, `mc-lib.sh`, `mc-server-update`, `mc-plugin-update`, `mc-backup`, `mc-restore-test`, `mc-chunky-idle` (installed to `~/.local/bin/`) |
| `~/.config/minecraft-dev/rcon.env` | `RCON_PASSWORD=...`, mode 0600. Never print or commit. Template: `env/rcon.env.example` |
| `~/minecraft-dev/data/` | bind-mounted at `/data`: world, plugins, configs, whitelist/ops, logs |
| `~/backups/minecraft/` | `daily-*`, `pre-update-*`, `pre-plugin-*` `.tar.zst` (7 kept per prefix), mode 0700 |
| `~/.local/state/mc-server-update/`, `mc-plugin-update/` | history, previous Quadlet, downloads, stashed jars |

Root helper: `/usr/local/sbin/as-mc <cmd>` runs a command as mc with its user-session env
(XDG_RUNTIME_DIR, DBUS). Example: `as-mc systemctl --user status minecraft-dev`.

## Rebuild from scratch (as root)

1. Base host (back up the old configs under `/root/` first):
   apt full-upgrade; `unattended-upgrades` (no auto reboot); fail2ban sshd jail with growing bans
   (`/etc/fail2ban/jail.d/50-bantime.conf`); `/etc/ssh/sshd_config.d/50-hardening.conf`;
   `/etc/sysctl.d/90-hardening.conf`; nftables `inet filter` in `/etc/nftables.conf` (default drop;
   22/tcp, 25565/tcp, 19132/udp); timezone America/Los_Angeles; hostname mc-dev.
   Apply firewall changes only with a revert timer:
   `systemd-run --unit=fw-revert --on-active=5min /usr/sbin/nft -f /root/<previous>.conf`,
   then `nft -f` the new file, open a FRESH ssh session, then `systemctl stop fw-revert.timer`.
2. Podman: `apt install podman uidmap passt slirp4netns fuse-overlayfs dbus-user-session jq zstd curl`.
3. User: `useradd --system --create-home --home-dir /home/mc --shell /usr/sbin/nologin mc`;
   `usermod --add-subuids 100000-165535 --add-subgids 100000-165535 mc`; `loginctl enable-linger mc`.
4. Copy this directory to `/home/mc/deploy` (chown mc), then as mc:
   ```
   mkdir -p ~/.local/bin ~/.config/systemd/user ~/.config/containers/systemd ~/.config/minecraft-dev \
            ~/minecraft-dev/data/plugins ~/backups/minecraft
   install -m 0755 ~/deploy/bin/* ~/.local/bin/ && chmod 644 ~/.local/bin/mc-lib.sh
   cp ~/deploy/systemd/* ~/.config/systemd/user/
   cp ~/deploy/quadlet/minecraft-dev.container ~/.config/containers/systemd/
   (umask 077; printf 'RCON_PASSWORD=%s\n' "$(head -c 32 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32)" \
       > ~/.config/minecraft-dev/rcon.env)
   ```
5. Seed `server.properties` BEFORE first start (the entrypoint only copies defaults when missing):
   `podman run --rm --entrypoint cat <Image> /opt/minecraft/defaults/server.properties > ~/minecraft-dev/data/server.properties`
   then set: `motd=<your motd>`, `white-list=true`, `enforce-whitelist=true`, `view-distance=8`,
   `simulation-distance=6`, `difficulty=normal`, `online-mode=true`, `level-name=world`, `enable-rcon=true`; chmod 600.
   The entrypoint writes `rcon.password` from `RCON_PASSWORD`.
6. Bedrock (Geyser + Floodgate, not in the image): download Spigot builds into `~/minecraft-dev/data/plugins/`
   from `https://download.geysermc.org/v2/projects/{geyser,floodgate}/versions/latest/builds/latest`
   (verify `.downloads.spigot.sha256`). Installed 2026-11-26: Geyser 2.12.1 b1312, Floodgate 2.2.5 b141.
   After first start, in `plugins/Geyser-Spigot/config.yml` set
   `auth-type: floodgate` (default was `online`) and restart.
   Geyser 2.12 uses the NetherNet transport: built-in signaling on **19132/tcp** plus WebRTC on
   **19132/udp**. Both must be open in nftables for Bedrock joins.
7. Start: `systemctl --user daemon-reload && systemctl --user start minecraft-dev`
   (the Quadlet's `[Install] WantedBy=default.target` starts it at boot via lingering).
8. DeathBanPro: `mc-plugin-update --now`.
9. Timers: `systemctl --user enable --now mc-server-update.timer mc-plugin-update.timer mc-backup.timer mc-restore-test.timer mc-chunky-idle.timer`.
10. Host pieces, as root (sources in `host/`): `install -m 0755 host/mc /usr/local/bin/mc`;
    `install -m 0755 host/sbin/as-mc host/sbin/mc-reboot-if-idle /usr/local/sbin/`;
    `install -m 0755 host/50-mc-dev /etc/update-motd.d/50-mc-dev`;
    `install -m 0644 host/52unattended-upgrades-local /etc/apt/apt.conf.d/`;
    `install -m 0644 host/systemd/* /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now mc-reboot-if-idle.timer`.

## Players

Whitelist and op are by UUID. Bedrock players through Floodgate get the name `.<Gamertag>` with spaces
as `_`, and UUID `00000000-0000-0000-XXXX-XXXXXXXXXXXX` built from the hex XUID
(`curl https://api.geysermc.org/v2/xbox/xuid/<gamertag>`).
- Example Bedrock player: gamertag `Some Gamer`, Floodgate name `.Some_Gamer`, UUID
  `00000000-0000-0000-<hex XUID, 16 digits split 4-12>`. Whitelist it with `mc-rcon fwhitelist add <uuid>`
  (the gamertag form can fail with "Unable to find user in our cache") and op it by writing `ops.json`
  while the server is stopped, since `op <name>` needs a profile lookup that fails for an unseen Bedrock player.
- Java players: `mc-rcon whitelist add <name>`, `mc-rcon op <name>`.
- Ops have `deathban.bypass` (DeathBanPro default), so ops are never death-banned.

## Operations

- Status: `as-mc systemctl --user status minecraft-dev`; logs: `journalctl _UID=988 -u ...` as root
  (mc cannot read its own journal as a system user) or `~/minecraft-dev/data/logs/latest.log`.
- Players: `mc-players` prints `humans=N` (exit 1 = unknown, treated as busy).
- Console: `mc-rcon <command>` (RCON on 127.0.0.1:25575 only; not in the firewall).
- Image updates: `mc-server-update [--dry-run|--now]`. Timer 04:15-07:55 PT every 20 min.
  Pulls `:main`, needs `org.opencontainers.image.revision` with all check runs green, skips
  `[skip deploy]`/`[manual]`, needs humans=0, takes a `pre-update` backup, rewrites `Image=repo:sha-<7>@digest`,
  restarts, health = unit active + RCON + "Done (...)! For help" in a fresh latest.log; failure restores the
  previous Quadlet (`~/.local/state/mc-server-update/minecraft-dev.container.prev`) and restarts.
- DeathBanPro updates: `mc-plugin-update [--dry-run|--now]`. Timer 04:05-07:45 PT every 20 min. Newest
  non-draft release incl. prereleases; sha256 from the release asset digest (or a checksums asset);
  skip when installed sha256 matches; humans=0; plugins dir backup; old jar stashed; restart; needs
  "Enabling DeathBanPro v<version>" and no enable error, else restores the old jar.
- The image copies its baked jars (blackjack, example, fart) into `/data/plugins` with `cp -f` on every
  start. Other jars (DeathBanPro, Geyser, Floodgate) are untouched. Deleting a baked jar does not stick.
- Backups: `mc-backup [--tag NAME]`. Timer daily 03:30 PT (Persistent). Pauses Chunky, then
  save-off, save-all flush, tar.zst of `/data` minus cache/libraries/versions/logs/dumps, save-on,
  verify level.dat, keep 7. Pregen stays paused until `mc-chunky-idle` sees the lock dropped and
  humans=0. Restore: stop the unit, move `~/minecraft-dev/data` aside, `mkdir` it,
  `tar --zstd -xf <archive> -C ~/minecraft-dev/data`, then start (Paper re-downloads its caches).
- One flock (`~/.local/state/minecraft-dev/maintenance.lock`) is shared by the update and backup
  jobs. `mc-chunky-idle` checks it (does not hold it) so it will not resume pregen mid-backup.


## Chunk pre-generation (Chunky)

Chunky 1.5.66 (Hangar `pop4959/Chunky`, Paper 26.1-26.3 jar `Chunky-Paper-1.5.66.jar`,
sha256 `a2c7877eaacf52605f5d2b08000656fbc43f7bec1eaf6ef9e71b6b9103a9c14f`) lives in
`~/minecraft-dev/data/plugins/` and is not touched by the image entrypoint or `mc-plugin-update`.
`continue-on-restart: true` (and `update-interval: 30`) so a backup, image/plugin update, or
`mc-reboot-if-idle` cycle does not lose the task.

Target: overworld (`minecraft:overworld`), circle, radius 3000 blocks, centered at world spawn
(currently 32, 640). After that task finishes, `mc-chunky-idle` starts the nether
(`minecraft:the_nether`) at radius 1000, also a circle at nether spawn. The two never run at
the same time. A 3000-block overworld ring is a few GB; the box has ~54 GB free.

Completion is detected from Chunky's durable `~/minecraft-dev/data/plugins/Chunky/tasks.log`
(`completed world=minecraft:overworld ...`), with a fallback to `Task finished for ...` in
`latest.log`, and then recorded in `~/.local/state/mc-chunky-idle/overworld-done`. Live
`chunky progress` says "No tasks" both before any work and after a task ends, so it is not
used as the handoff signal. After the nether task completes, the script writes `pregen-done`
once and stays quiet (no start/continue/pause). Markers also include `nether-started` and
`nether-done`.

Idle-only: user timer `mc-chunky-idle.timer` (every minute, plus 30s after boot) runs
`mc-chunky-idle`, which issues `chunky pause` when `humans>0` or the maintenance lock is held,
and `chunky continue` when idle (unless pregen is already done). Both commands are idempotent.
`mc-reboot-if-idle` only looks at players and SSH, not chunk generation; continue-on-restart
covers a mid-pregen reboot.

Manual: `mc rcon chunky progress`, `mc rcon chunky pause`, `mc rcon chunky continue`.

## Gotchas

- The provider configures eth0 twice (ifupdown and netplan). `networking.service` fails at boot
  ("Address already assigned") and the system `network-online.target` is never reached. The Quadlet sets
  `[Quadlet] DefaultDependencies=false` so it does not wait 90 s on `podman-user-wait-network-online`.
- `broadcast-rcon-to-ops=true` (image default): ops see `[Rcon: ...]` lines in chat when the jobs run.
- Paper in the image is 26.3 build 258; Paper says it is 5 builds behind (latest stable 263). That moves
  with the image, not here.

## Host hardening (mirrors cs-server)

- SSH: key-only. Regenerate host keys if the provider template baked them in.
  `/etc/ssh/sshd_config.d/00-mc-dev.conf`: `PermitRootLogin prohibit-password`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `MaxAuthTries 3`. `00-` wins over the
  provider's `99-ctrl.conf`. Before touching sshd or the firewall, open a second session and keep a revert
  timer running. Recovery without a key: the provider's VNC console.
- `/etc/systemd/system/ssh.service.d/oom.conf`: `OOMScoreAdjust=-900`.
  The Minecraft container runs with `--oom-score-adj=500`.
- `/etc/systemd/journald.conf.d/50-mc-dev.conf`: persistent, 200M, 1 month.
- `/etc/sysctl.d/60-game-host.conf` (same as cs-server) plus `90-hardening.conf`.
- `/usr/local/sbin/mc-reboot-if-idle` + `mc-reboot-if-idle.timer` (02:15-03:15 PT every 20 min): reboots only
  with `/var/run/reboot-required`, humans=0, and no logged-in session. unattended-upgrades never reboots.
- `mc-restore-test` user timer, monthly on the 1st at 03:50 PT.
- `/usr/local/bin/mc` admin kit (`mc status|logs|players|rcon|backup|restore-test|update|plugin-update|reboot-check`)
  and `/etc/update-motd.d/50-mc-dev` login banner.
- Host-side sources for the pieces above: `host/` (install paths in the table below).

## Xbox / console joins (MCXboxBroadcast)

Consoles cannot add servers. `plugins/Geyser-Spigot/extensions/MCXboxBroadcastExtension.jar`
(MCXboxBroadcast build 165, sha256 `f8e55766…bb788`, supports Bedrock 1.26.60 / NetherNet) broadcasts the
server as a joinable session from a bot Xbox account. Sign in once with a DEDICATED ALT Microsoft account
(never the main one; the project warns the account could be banned): the device code is in
`mc logs` (`[Auth] To sign in, use ... https://www.microsoft.com/link and enter the code ...`).
Tokens are cached in `plugins/Geyser-Spigot/extensions/mcxboxbroadcast/` (mode 700; included in backups,
which are 0600). Then on the Xbox: add the alt's gamertag as a friend, Minecraft > Play > Friends tab,
join the server under Joinable Friends. Whitelist still applies.
