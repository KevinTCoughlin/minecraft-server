#!/usr/bin/env bash
# Start Paper as the container's main process and turn SIGTERM into the
# console "stop" command so the world is saved. Docker's stop grace period is
# the outer bound; this process must be the one that receives SIGTERM (tini
# forwards it here, and Java is a child so it is not killed immediately).

set -euo pipefail

if [[ $# -gt 0 ]]; then
    echo "This image starts Paper from its entrypoint. Pass settings with environment variables, not command arguments." >&2
    exit 1
fi

DATA_DIR=/data
DEFAULTS_DIR=/opt/minecraft/defaults
PLUGINS_DIR=/opt/minecraft/plugins
FIFO=/tmp/minecraft-console

if [[ ! -w /tmp ]]; then
    echo "/tmp is not writable. With a read-only root filesystem, mount a tmpfs on /tmp." >&2
    exit 1
fi

mkdir -p \
    "$DATA_DIR/plugins" \
    "$DATA_DIR/logs" \
    "$DATA_DIR/config" \
    "${HEAP_DUMP_PATH:-$DATA_DIR/dumps}"

copy_if_missing() {
    local source="$1"
    local target="$2"
    if [[ ! -e "$target" ]]; then
        cp -a "$source" "$target"
    fi
}

if [[ -d "$DEFAULTS_DIR" ]]; then
    copy_if_missing "$DEFAULTS_DIR/server.properties" "$DATA_DIR/server.properties"
    copy_if_missing "$DEFAULTS_DIR/bukkit.yml" "$DATA_DIR/bukkit.yml"
    copy_if_missing "$DEFAULTS_DIR/spigot.yml" "$DATA_DIR/spigot.yml"
    if [[ -d "$DEFAULTS_DIR/config" ]]; then
        while IFS= read -r -d '' config; do
            copy_if_missing "$config" "$DATA_DIR/config/$(basename "$config")"
        done < <(find "$DEFAULTS_DIR/config" -maxdepth 1 -type f -print0)
    fi
fi

if [[ ! -f "$DATA_DIR/eula.txt" ]] || ! grep -q 'eula=true' "$DATA_DIR/eula.txt"; then
    printf 'eula=true\n' > "$DATA_DIR/eula.txt"
fi

if [[ -d "$PLUGINS_DIR" ]]; then
    shopt -s nullglob
    for jar in "$PLUGINS_DIR"/*.jar; do
        cp -f "$jar" "$DATA_DIR/plugins/"
    done
    shopt -u nullglob
fi

if [[ -n "${RCON_PASSWORD:-}" ]]; then
    if [[ ! "$RCON_PASSWORD" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "RCON_PASSWORD may only contain letters, digits, _ and -" >&2
        exit 1
    fi
    sed -i \
        -e 's/^enable-rcon=.*/enable-rcon=true/' \
        -e "s/^rcon.password=.*/rcon.password=${RCON_PASSWORD}/" \
        "$DATA_DIR/server.properties"
fi

export MEMORY_MODE="${MEMORY_MODE:-container}"
export HEAP_DUMP_PATH="${HEAP_DUMP_PATH:-$DATA_DIR/dumps}"
export GC_TYPE="${GC_TYPE:-g1gc}"

if [[ "$MEMORY_MODE" == "container" && -r /sys/fs/cgroup/memory.max ]]; then
    cgroup_memory=$(< /sys/fs/cgroup/memory.max)
    if [[ "$cgroup_memory" == "max" ]]; then
        echo "MEMORY_MODE=container sizes the heap as a percentage of the cgroup limit, but this container has no memory limit. Set one (--memory / mem_limit), or set MEMORY_MODE=fixed and MAX_RAM." >&2
        exit 1
    fi
fi

flags=()
while IFS= read -r flag; do
    flags+=("$flag")
done < <(/opt/minecraft/jvm-opts.sh)

if [[ -n "${JVM_OPTS:-}" ]]; then
    # JVM_OPTS is an optional space-separated list of extra flags from the operator.
    # shellcheck disable=SC2206
    extra=($JVM_OPTS)
    flags+=("${extra[@]}")
fi

cd "$DATA_DIR"
echo "JVM flags: ${flags[*]}"

rm -f "$FIFO"
mkfifo "$FIFO"

# Hold the write end open so Java does not see EOF on stdin. The open blocks
# until the read end below is opened, so this must stay in the background.
tail -f /dev/null > "$FIFO" &
HOLDER_PID=$!

JAVA_PID=""
STOP_REQUESTED=0

cleanup_holder() {
    if [[ -n "${HOLDER_PID}" ]]; then
        kill "$HOLDER_PID" 2>/dev/null || true
        wait "$HOLDER_PID" 2>/dev/null || true
        HOLDER_PID=""
    fi
}

# Invoked from the SIGTERM/SIGINT trap. Shellcheck does not see that use.
# shellcheck disable=SC2317,SC2329
request_stop() {
    STOP_REQUESTED=1
    if [[ -n "$JAVA_PID" ]] && kill -0 "$JAVA_PID" 2>/dev/null; then
        # "stop" runs the normal server shutdown, which saves the world.
        printf 'stop\n' > "$FIFO" || true
    fi
}
trap request_stop TERM INT

java "${flags[@]}" -jar /opt/minecraft/paper.jar --nogui < "$FIFO" &
JAVA_PID=$!

# SIGTERM can arrive while stdin is being opened, before JAVA_PID is set.
if [[ "$STOP_REQUESTED" -eq 1 ]]; then
    printf 'stop\n' > "$FIFO" || true
fi

set +e
wait "$JAVA_PID"
status=$?
set -e

# SIGTERM interrupts wait while Java is still saving. Keep waiting so a clean
# exit is what Docker observes inside the stop grace period.
if [[ "$STOP_REQUESTED" -eq 1 ]] && kill -0 "$JAVA_PID" 2>/dev/null; then
    set +e
    wait "$JAVA_PID"
    status=$?
    set -e
fi

cleanup_holder
exit "$status"
