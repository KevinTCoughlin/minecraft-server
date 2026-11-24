# Container recipes for the custom Paper image (docker/Dockerfile).
#
# Engine: Apple `container` on macOS, podman elsewhere. Override with
#   CONTAINER_ENGINE=podman just run
#
# Host ports are overridable so this can run next to another server, e.g.
#   MC_PORT=25566 RCON_PORT=25576 BEDROCK_PORT=19133 just run
#
# The heap is MAX_RAM_PERCENTAGE (default 75) of MC_MEMORY, not a fixed -Xmx.
# The world volume is mounted at /data/<level-name> so an existing world volume
# (level.dat at its root) still lines up. Configs, logs, plugins, and heap
# dumps live on the data volume.

ENGINE := env("CONTAINER_ENGINE", if os() == "macos" { "container" } else { "podman" })
IMAGE := env("MC_IMAGE", "minecraft-server:latest")
NAME := "minecraft-server"

MC_PORT := env("MC_PORT", "25565")
RCON_PORT := env("RCON_PORT", "25575")
BEDROCK_PORT := env("BEDROCK_PORT", "19132")

MEMORY := env("MC_MEMORY", "5G")
CPUS := env("MC_CPUS", "2")

# level-name in server/server.properties. Since Minecraft 26.1 a world is one
# directory, with every dimension under <world>/dimensions/.
WORLD := "parkour-spiral"
VOLUME := env("MC_VOLUME", "minecraft-server-world")
DATA_VOLUME := env("MC_DATA_VOLUME", "minecraft-server-data")

default:
    @just --list

# Build the Paper image (context is the repo root); extra args go to build,
# e.g. `just image --build-arg PAPER_BUILD=240`
image *args:
    {{ENGINE}} build -f docker/Dockerfile -t {{IMAGE}} {{args}} .

# Run the server detached. Do not replace the image command: the entrypoint
# turns SIGTERM into the console "stop" command so the world is saved.
run:
    #!/usr/bin/env bash
    set -euo pipefail
    # The image ships with RCON off. Turn it on for this container with a
    # one-off password; RCON is published on host loopback only, and
    # `just rcon` reads the password back from the container.
    rcon_password="${RCON_PASSWORD:-$(openssl rand -hex 16)}"
    if [[ ! "$rcon_password" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "RCON_PASSWORD may only contain letters, digits, _ and -" >&2
        exit 1
    fi
    # Apple container needs the volume created up front (podman would auto-create).
    {{ENGINE}} volume inspect {{VOLUME}} >/dev/null 2>&1 || {{ENGINE}} volume create {{VOLUME}} >/dev/null
    {{ENGINE}} volume inspect {{DATA_VOLUME}} >/dev/null 2>&1 || {{ENGINE}} volume create {{DATA_VOLUME}} >/dev/null
    # Apple container volumes are fresh ext4 filesystems: root-owned, not seeded
    # from the image, with a root-only lost+found that Paper trips over. Hand
    # the top level to the image's minecraft user (uid 1000).
    {{ENGINE}} run --rm -u 0 \
        -v {{VOLUME}}:/world -v {{DATA_VOLUME}}:/data \
        --entrypoint sh {{IMAGE}} \
        -c 'for d in /world /data; do find "$d" -maxdepth 1 ! -user 1000 -exec chown 1000:1000 {} +; done'
    # Apple container does not take the docker/podman hardening flags. Podman
    # runs read-only, with no capabilities and a 90s stop grace period.
    # Build one argv so an empty array is never expanded under bash 3.2.
    args=(run -d --name {{NAME}} --memory {{MEMORY}} --cpus {{CPUS}})
    if [[ "{{ENGINE}}" != "container" ]]; then
        args+=(
            --read-only
            --cap-drop=ALL
            --security-opt=no-new-privileges:true
            --tmpfs=/tmp:rw,nosuid,size=256m
            --stop-timeout=90
        )
    fi
    args+=(
        -p {{MC_PORT}}:25565/tcp
        -p {{MC_PORT}}:25565/udp
        -p 127.0.0.1:{{RCON_PORT}}:25575/tcp
        -p {{BEDROCK_PORT}}:19132/udp
        -v {{DATA_VOLUME}}:/data
        -v {{VOLUME}}:/data/{{WORLD}}
        -e RCON_PASSWORD="$rcon_password"
        {{IMAGE}}
    )
    {{ENGINE}} "${args[@]}"
    echo "Started {{NAME}} on :{{MC_PORT}} (RCON 127.0.0.1:{{RCON_PORT}}, Bedrock udp :{{BEDROCK_PORT}})"

# Stop and remove the container (the world and data volumes are kept).
# 90s matches the entrypoint: SIGTERM becomes "stop", then the world saves.
stop:
    #!/usr/bin/env bash
    set +e
    if [[ "{{ENGINE}}" == "container" ]]; then
        {{ENGINE}} stop {{NAME}}
    else
        {{ENGINE}} stop --time 90 {{NAME}}
    fi
    {{ENGINE}} rm {{NAME}}

# Follow server logs
logs:
    {{ENGINE}} logs -f {{NAME}}

# Open a shell in the running container
shell:
    {{ENGINE}} exec -it {{NAME}} bash

# Send an RCON command, e.g. `just rcon list` (needs python3 on the host)
rcon +cmd:
    #!/usr/bin/env python3
    import socket, struct, subprocess, sys

    password = subprocess.run(
        ["{{ENGINE}}", "exec", "{{NAME}}", "printenv", "RCON_PASSWORD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()

    def pkt(rid, kind, body):
        data = struct.pack("<ii", rid, kind) + body.encode() + b"\x00\x00"
        return struct.pack("<i", len(data)) + data

    def recv(s):
        def exact(n):
            buf = b""
            while len(buf) < n:
                chunk = s.recv(n - len(buf))
                if not chunk:
                    sys.exit("rcon: connection closed")
                buf += chunk
            return buf
        (length,) = struct.unpack("<i", exact(4))
        rid, _ = struct.unpack("<ii", exact(8))
        return rid, exact(length - 8)[:-2].decode(errors="replace")

    with socket.create_connection(("127.0.0.1", {{RCON_PORT}}), timeout=10) as s:
        s.sendall(pkt(1, 3, password))
        if recv(s)[0] == -1:
            sys.exit("rcon: authentication failed")
        s.sendall(pkt(2, 2, """{{cmd}}"""))
        print(recv(s)[1])
