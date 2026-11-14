# Container recipes for the custom Paper image (docker/Dockerfile).
#
# Engine: Apple `container` on macOS, podman elsewhere. Override with
#   CONTAINER_ENGINE=podman just run
#
# Host ports are overridable so this can run next to another server, e.g.
#   MC_PORT=25566 RCON_PORT=25576 BEDROCK_PORT=19133 just run

ENGINE := env("CONTAINER_ENGINE", if os() == "macos" { "container" } else { "podman" })
IMAGE := env("MC_IMAGE", "minecraft-server:latest")
NAME := "minecraft-server"
MC_VERSION := env("MC_VERSION", "1.21.11")

MC_PORT := env("MC_PORT", "25565")
RCON_PORT := env("RCON_PORT", "25575")
BEDROCK_PORT := env("BEDROCK_PORT", "19132")
RCON_PASSWORD := env("RCON_PASSWORD", "changeme")

MEMORY := env("MC_MEMORY", "5G")
CPUS := env("MC_CPUS", "2")

# level-name in server/server.properties; Paper stores each dimension in its own dir.
WORLD := "parkour-spiral"
VOLUME_PREFIX := env("MC_VOLUME_PREFIX", "minecraft-server")

default:
    @just --list

# Build the Paper image (context is the repo root)
image:
    {{ENGINE}} build -f docker/Dockerfile --build-arg MC_VERSION={{MC_VERSION}} -t {{IMAGE}} .

# Run the server detached with world dirs on named volumes
run:
    #!/usr/bin/env bash
    set -euo pipefail
    for dim in "" _nether _the_end; do
        vol="{{VOLUME_PREFIX}}-world${dim}"
        # Apple container needs volumes created up front (podman would auto-create).
        {{ENGINE}} volume inspect "$vol" >/dev/null 2>&1 || {{ENGINE}} volume create "$vol" >/dev/null
    done
    # Apple container volumes are fresh ext4 filesystems: root-owned, not seeded
    # from the image, with a root-only lost+found that Paper trips over. Hand
    # the top level to the image's minecraft user (uid 1000).
    {{ENGINE}} run --rm -u 0 \
        -v {{VOLUME_PREFIX}}-world:/w/a \
        -v {{VOLUME_PREFIX}}-world_nether:/w/b \
        -v {{VOLUME_PREFIX}}-world_the_end:/w/c \
        --entrypoint sh {{IMAGE}} -c 'find /w -mindepth 1 -maxdepth 2 ! -user 1000 -exec chown 1000:1000 {} +'
    {{ENGINE}} run -d --name {{NAME}} \
        --memory {{MEMORY}} --cpus {{CPUS}} \
        -p {{MC_PORT}}:25565/tcp \
        -p {{MC_PORT}}:25565/udp \
        -p 127.0.0.1:{{RCON_PORT}}:25575/tcp \
        -p {{BEDROCK_PORT}}:19132/udp \
        -v {{VOLUME_PREFIX}}-world:/server/{{WORLD}} \
        -v {{VOLUME_PREFIX}}-world_nether:/server/{{WORLD}}_nether \
        -v {{VOLUME_PREFIX}}-world_the_end:/server/{{WORLD}}_the_end \
        {{IMAGE}}
    echo "Started {{NAME}} on :{{MC_PORT}} (RCON 127.0.0.1:{{RCON_PORT}}, Bedrock udp :{{BEDROCK_PORT}})"

# Stop and remove the container (volumes are kept)
stop:
    -{{ENGINE}} stop {{NAME}}
    -{{ENGINE}} rm {{NAME}}

# Follow server logs
logs:
    {{ENGINE}} logs -f {{NAME}}

# Open a shell in the running container
shell:
    {{ENGINE}} exec -it {{NAME}} bash

# Send an RCON command, e.g. `just rcon list` (needs python3 on the host)
rcon +cmd:
    #!/usr/bin/env python3
    import socket, struct, sys

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
        s.sendall(pkt(1, 3, "{{RCON_PASSWORD}}"))
        if recv(s)[0] == -1:
            sys.exit("rcon: authentication failed")
        s.sendall(pkt(2, 2, """{{cmd}}"""))
        print(recv(s)[1])
