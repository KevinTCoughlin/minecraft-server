#!/usr/bin/env bash
# Boot the Paper image and require a clean "Done", the three plugins, and a
# graceful stop that saves the world. The container is started with the same
# runtime constraints as docker-compose: read-only root, no capabilities,
# no-new-privileges, a memory limit, and a tmpfs on /tmp.
set -euo pipefail

IMAGE="${1:-minecraft-server:smoke}"
NAME="${SMOKE_NAME:-mc-smoke}"
DATA_DIR="${SMOKE_DATA_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/mc-smoke.XXXXXX")}"
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

cat > "$DATA_DIR/server.properties" << 'EOF'
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
docker run -d \
    --name "$NAME" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --memory 4g \
    --cpus 2 \
    --stop-timeout 90 \
    --tmpfs /tmp:rw,nosuid,size=256m \
    -v "$DATA_DIR:/data" \
    -e MAX_RAM_PERCENTAGE=50 \
    -e INITIAL_RAM_PERCENTAGE=50 \
    "$IMAGE"

echo "Waiting up to ${STARTUP_TIMEOUT}s for Done..."
elapsed=0
ready=0
while [[ "$elapsed" -lt "$STARTUP_TIMEOUT" ]]; do
    if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -qx true; then
        docker logs "$NAME" > "$LOG_FILE" 2>&1 || true
        cat "$LOG_FILE" >&2 || true
        echo "Container exited before the server finished starting" >&2
        exit 1
    fi
    docker logs "$NAME" > "$LOG_FILE" 2>&1 || true
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

require_log "BlackjackPlugin v1.0.0 has been enabled!"
require_log "FartPlugin v1.0.0 has been enabled!"
require_log "ExamplePlugin v1.0.0 has been enabled!"
require_log "-XX:MaxRAMPercentage=50"
require_log "-XX:+ExitOnOutOfMemoryError"
require_log "-XX:+HeapDumpOnOutOfMemoryError"
require_log "-XX:HeapDumpPath=/data/dumps"
require_log "-XX:+UseG1GC"

if grep -E -q '(^|[[:space:]])-Xmx' "$LOG_FILE"; then
    echo "Container heap must use MaxRAMPercentage, not -Xmx" >&2
    exit 1
fi
if grep -F -q 'ZGenerational' "$LOG_FILE"; then
    echo "Removed -XX:+ZGenerational is present" >&2
    exit 1
fi
if grep -E -q 'Error occurred while enabling (BlackjackPlugin|FartPlugin|ExamplePlugin)' "$LOG_FILE"; then
    echo "A plugin failed to enable" >&2
    exit 1
fi

uid=$(docker exec "$NAME" id -u)
if [[ "$uid" != "1000" ]]; then
    echo "Server is running as uid ${uid}, expected 1000" >&2
    exit 1
fi

docker exec "$NAME" nc -z 127.0.0.1 25565

read -r rootfs_ro caps security < <(
    docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{json .HostConfig.CapDrop}} {{json .HostConfig.SecurityOpt}}' "$NAME"
)
[[ "$rootfs_ro" == "true" ]] || { echo "Root filesystem is not read-only"; exit 1; }
printf '%s\n' "$caps" | grep -q 'ALL' || { echo "Capabilities were not dropped: $caps"; exit 1; }
printf '%s\n' "$security" | grep -q 'no-new-privileges' || {
    echo "no-new-privileges is not set: $security"
    exit 1
}

echo "Stopping the server and waiting for the world to save..."
docker stop -t 90 "$NAME"

docker logs "$NAME" > "$LOG_FILE" 2>&1 || true
if ! grep -E -q 'Saving worlds|Saving players|All dimensions are saved|ThreadedAnvilChunkStorage' "$LOG_FILE"; then
    cat "$LOG_FILE" >&2 || true
    echo "Graceful stop did not save the world" >&2
    exit 1
fi

exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$NAME")
if [[ "$exit_code" == "137" ]]; then
    echo "Container was SIGKILLed before shutdown finished" >&2
    exit 1
fi

# The world directory is the save. Flat worlds still write level.dat.
if [[ ! -f "$DATA_DIR/world/level.dat" ]]; then
    echo "World was not written to the mounted data volume" >&2
    exit 1
fi

echo "Docker smoke test passed"
# Keep the data dir when the caller set SMOKE_DATA_DIR; otherwise it is a temp
# directory and the trap only removes the container. Remove our temp dir.
if [[ -z "${SMOKE_DATA_DIR:-}" ]]; then
    rm -rf "$DATA_DIR"
fi
