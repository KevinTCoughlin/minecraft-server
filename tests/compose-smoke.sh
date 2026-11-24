#!/usr/bin/env bash
# Boot the hardened itzg Compose service and require a clean "Done", the three
# plugins, and a graceful stop that saves the world. This is the Compose
# counterpart of tests/docker-smoke.sh: same success bar, the real
# docker/docker-compose.yml constraints (read-only root, no capabilities,
# no-new-privileges, uid 1000, 6G limit, percentage heap).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker/docker-compose.yml"
COMPOSE=(docker compose -f "$COMPOSE_FILE")
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-600}"
LOG_DIR="${COMPOSE_SMOKE_LOG_DIR:-/tmp/mc-smoke-compose}"
LOG_FILE="${LOG_DIR}/smoke.log"
CONTAINER=minecraft-server

mkdir -p "$LOG_DIR"

cleanup() {
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for the Compose smoke test" >&2
    exit 1
fi

require_jar() {
    local pattern="$1"
    local jar
    local found=0
    for jar in "${ROOT_DIR}/server/plugins/"${pattern}; do
        if [[ -f "$jar" ]]; then
            found=1
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "Missing server/plugins/${pattern}. Stage the plugin jars before this smoke test." >&2
        exit 1
    fi
}

require_jar 'blackjack-plugin-*.jar'
require_jar 'fart-plugin-*.jar'
require_jar 'example-plugin-*.jar'

save_logs() {
    "${COMPOSE[@]}" logs > "$LOG_FILE" 2>&1 || true
}

"${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
if ! "${COMPOSE[@]}" up -d; then
    save_logs
    cat "$LOG_FILE" >&2 || true
    echo "docker compose up failed" >&2
    exit 1
fi

echo "Waiting up to ${STARTUP_TIMEOUT}s for Done..."
elapsed=0
ready=0
while [[ "$elapsed" -lt "$STARTUP_TIMEOUT" ]]; do
    if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true; then
        save_logs
        cat "$LOG_FILE" >&2 || true
        echo "Container exited before the server finished starting" >&2
        exit 1
    fi
    save_logs
    if grep -q 'Failed to update server.properties' "$LOG_FILE"; then
        cat "$LOG_FILE" >&2 || true
        echo "itzg could not write server.properties" >&2
        exit 1
    fi
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

if grep -E -q 'Error occurred while enabling (BlackjackPlugin|FartPlugin|ExamplePlugin)' "$LOG_FILE"; then
    echo "A plugin failed to enable" >&2
    exit 1
fi

# itzg does not print the java command. Read it from the live process.
cmdlines="$(docker exec "$CONTAINER" sh -c 'for f in /proc/[0-9]*/cmdline; do tr "\0" " " < "$f"; echo; done')"
printf '%s\n' "$cmdlines" >> "$LOG_FILE"

require_cmdline() {
    if ! grep -F -q -- "$1" <<< "$cmdlines"; then
        printf '%s\n' "$cmdlines" >&2
        echo "Missing JVM flag: $1" >&2
        exit 1
    fi
}

require_cmdline "-XX:+UseG1GC"
require_cmdline "-XX:+ExitOnOutOfMemoryError"
require_cmdline "-XX:+HeapDumpOnOutOfMemoryError"
require_cmdline "-XX:HeapDumpPath=/data"
require_cmdline "-XX:MaxRAMPercentage=75"
require_cmdline "-XX:InitialRAMPercentage=75"

if grep -E -q '(^|[[:space:]])-Xmx' <<< "$cmdlines"; then
    echo "itzg heap must use MaxRAMPercentage, not -Xmx" >&2
    exit 1
fi
if grep -F -q 'ZGenerational' <<< "$cmdlines"; then
    echo "Removed -XX:+ZGenerational is present" >&2
    exit 1
fi

uid="$(docker exec "$CONTAINER" id -u)"
if [[ "$uid" != "1000" ]]; then
    echo "Server is running as uid ${uid}, expected 1000" >&2
    exit 1
fi

health_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if docker exec "$CONTAINER" mc-health; then
        health_ok=1
        break
    fi
    sleep 5
done
if [[ "$health_ok" -ne 1 ]]; then
    echo "mc-health did not succeed" >&2
    exit 1
fi

read -r rootfs_ro caps security memory < <(
    docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{json .HostConfig.CapDrop}} {{json .HostConfig.SecurityOpt}} {{.HostConfig.Memory}}' "$CONTAINER"
)
[[ "$rootfs_ro" == "true" ]] || { echo "Root filesystem is not read-only"; exit 1; }
printf '%s\n' "$caps" | grep -q 'ALL' || { echo "Capabilities were not dropped: $caps"; exit 1; }
printf '%s\n' "$security" | grep -q 'no-new-privileges' || {
    echo "no-new-privileges is not set: $security"
    exit 1
}
# mem_limit: 6g
if [[ "$memory" != "6442450944" ]]; then
    echo "Memory limit is ${memory}, expected 6442450944 (6g)" >&2
    exit 1
fi

echo "Stopping the server and waiting for the world to save..."
docker stop -t 90 "$CONTAINER"

save_logs
if ! grep -E -q 'Saving worlds|Saving players|All dimensions are saved|ThreadedAnvilChunkStorage' "$LOG_FILE"; then
    cat "$LOG_FILE" >&2 || true
    echo "Graceful stop did not save the world" >&2
    exit 1
fi

exit_code="$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER")"
if [[ "$exit_code" == "137" ]]; then
    echo "Container was SIGKILLed before shutdown finished" >&2
    exit 1
fi

image="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
docker run --rm --network none \
    -v minecraft-server-data:/data:ro \
    --entrypoint sh \
    "$image" \
    -c 'test -f /data/parkour-spiral/level.dat'

echo "itzg Compose smoke test passed"
