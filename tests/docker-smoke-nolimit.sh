#!/usr/bin/env bash
# Boot the Paper image with no memory limit. The server must reach "Done"
# and the startup banner must explain the safe default heap and how to set
# docker run -m / Compose deploy.resources.limits.memory.
# tests/docker-smoke.sh still covers a memory-limited boot.
set -euo pipefail

IMAGE="${1:-minecraft-server:smoke}"
NAME="${SMOKE_NOLIMIT_NAME:-mc-smoke-nolimit}"
DATA_DIR="${SMOKE_DATA_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/mc-smoke-nolimit.XXXXXX")}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-300}"
LOG_FILE="${DATA_DIR}/smoke.log"

cleanup() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for the image smoke test" >&2
    exit 1
fi

mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"

cat >"$DATA_DIR/server.properties" <<'EOF'
server-port=25565
online-mode=false
max-players=1
spawn-protection=0
view-distance=4
simulation-distance=4
level-type=flat
level-name=world
generate-structures=false
spawn-monsters=false
spawn-animals=false
enable-command-block=false
enable-rcon=false
motd=smoke
sync-chunk-writes=true
EOF

docker rm -f "$NAME" >/dev/null 2>&1 || true
# No --memory / -m. The entrypoint must choose a safe heap and keep going.
docker run -d \
    --name "$NAME" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --cpus 2 \
    --stop-timeout 90 \
    --tmpfs /tmp:rw,nosuid,size=256m \
    -v "$DATA_DIR:/data" \
    "$IMAGE"

echo "Waiting up to ${STARTUP_TIMEOUT}s for Done (no memory limit)..."
elapsed=0
ready=0
while [[ "$elapsed" -lt "$STARTUP_TIMEOUT" ]]; do
    if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -qx true; then
        docker logs "$NAME" >"$LOG_FILE" 2>&1 || true
        cat "$LOG_FILE" >&2 || true
        echo "Container exited before the server finished starting" >&2
        exit 1
    fi
    docker logs "$NAME" >"$LOG_FILE" 2>&1 || true
    if grep -q 'Done (' "$LOG_FILE"; then
        ready=1
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "Waiting... ${elapsed}s"
done

if [[ "$ready" -ne 1 ]]; then
    cat "$LOG_FILE" >&2 || true
    echo "Server did not reach Done within ${STARTUP_TIMEOUT}s" >&2
    exit 1
fi

require_log() {
    if ! grep -F -q -- "$1" "$LOG_FILE"; then
        cat "$LOG_FILE" >&2 || true
        echo "Missing log line: $1" >&2
        exit 1
    fi
}

require_log "Done ("
require_log "Minecraft memory: no container limit, using a safe default heap."
require_log "Chosen heap:"
require_log "docker run -m 4g …"
require_log "deploy.resources.limits.memory"
require_log "BlackjackPlugin v1.0.0 has been enabled!"

if ! grep -E -q '(^|[[:space:]])-Xmx' "$LOG_FILE"; then
    cat "$LOG_FILE" >&2 || true
    echo "Unlimited container did not set a fixed -Xmx heap" >&2
    exit 1
fi
if grep -F -q 'MaxRAMPercentage' "$LOG_FILE"; then
    cat "$LOG_FILE" >&2 || true
    echo "Unlimited container used MaxRAMPercentage instead of a safe heap" >&2
    exit 1
fi
if grep -F -q 'this container has no memory limit' "$LOG_FILE"; then
    cat "$LOG_FILE" >&2 || true
    echo "Unlimited container still refuses to start" >&2
    exit 1
fi

memory=$(docker inspect -f '{{.HostConfig.Memory}}' "$NAME")
if [[ "$memory" != "0" ]]; then
    echo "Expected no memory limit, docker reports ${memory}" >&2
    exit 1
fi

docker stop -t 30 "$NAME" >/dev/null 2>&1 || true

echo "Docker no-limit smoke test passed"
if [[ -z "${SMOKE_DATA_DIR:-}" ]]; then
    if ! rm -rf "$DATA_DIR" 2>/dev/null; then
        sudo rm -rf "$DATA_DIR"
    fi
fi
