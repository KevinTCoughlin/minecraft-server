#!/usr/bin/env bash
# Print JVM flags, one per line, for the Paper server.
#
# GC_TYPE=g1gc (default) uses Aikar's G1 flags. They are still accepted on
# Java 25; JDK 25 did not remove or deprecate any of them. Three
# (G1NewSizePercent, G1MaxNewSizePercent, G1MixedGCLiveThresholdPercent) are
# experimental, so UnlockExperimentalVMOptions stays.
# GC_TYPE=zgc selects generational ZGC. JDK 24 made that the only ZGC mode and
# removed -XX:+ZGenerational; passing it makes Java 25 warn and a later JDK
# will refuse to start.
#
# MEMORY_MODE=fixed (default) sets -Xms/-Xmx from MIN_RAM and MAX_RAM. That is
# the right choice on a host, where there is no cgroup limit.
# MEMORY_MODE=container sets InitialRAMPercentage and MaxRAMPercentage instead
# of a hardcoded heap. Both default to 75 so the heap does not resize (the
# container equivalent of Aikar's Xms=Xmx) and about a quarter of the limit
# remains for metaspace, threads, and native memory. The container must have a
# memory limit; otherwise the percentage is of the whole machine.
#
# Every mode exits on the first OutOfMemoryError and writes a heap dump under
# HEAP_DUMP_PATH, which must be a directory on a mounted volume in containers.
#
# -XX:+UseCompactObjectHeaders is off unless COMPACT_OBJECT_HEADERS is true
# (also: 1, yes, on). On JDK 25 it is still experimental, so the opt-in also
# passes UnlockExperimentalVMOptions when the selected GC set does not already
# (G1 already does; ZGC does not). It is not part of Aikar's flags. Leave it
# off until scripts/measure-compact-headers.sh shows a smaller heap with
# pauses and TPS no worse, on a copy of a real world. See
# docs/compact-object-headers.md.

set -euo pipefail

GC_TYPE="${GC_TYPE:-g1gc}"
MEMORY_MODE="${MEMORY_MODE:-fixed}"
MIN_RAM="${MIN_RAM:-4G}"
MAX_RAM="${MAX_RAM:-4G}"
MAX_RAM_PERCENTAGE="${MAX_RAM_PERCENTAGE:-75.0}"
INITIAL_RAM_PERCENTAGE="${INITIAL_RAM_PERCENTAGE:-${MAX_RAM_PERCENTAGE}}"
HEAP_DUMP_PATH="${HEAP_DUMP_PATH:-}"

if [[ -z "$HEAP_DUMP_PATH" ]]; then
    echo "HEAP_DUMP_PATH is required (directory for -XX:HeapDumpPath)" >&2
    exit 1
fi

normalize_percent() {
    local value="${1%\%}"
    if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Invalid memory percentage: $1" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

flags=()

case "$MEMORY_MODE" in
    container)
        flags+=(
            "-XX:InitialRAMPercentage=$(normalize_percent "$INITIAL_RAM_PERCENTAGE")"
            "-XX:MaxRAMPercentage=$(normalize_percent "$MAX_RAM_PERCENTAGE")"
        )
        ;;
    fixed)
        flags+=(
            "-Xms${MIN_RAM}"
            "-Xmx${MAX_RAM}"
        )
        ;;
    *)
        echo "Unknown MEMORY_MODE: ${MEMORY_MODE} (expected fixed or container)" >&2
        exit 1
        ;;
esac

flags+=(
    "-XX:+ExitOnOutOfMemoryError"
    "-XX:+HeapDumpOnOutOfMemoryError"
    "-XX:HeapDumpPath=${HEAP_DUMP_PATH}"
)

# Lowercase without bash 4 ${var,,} so macOS /bin/bash can run the flag tests.
gc=$(printf '%s' "$GC_TYPE" | tr '[:upper:]' '[:lower:]')

case "$gc" in
    zgc)
        # Generational ZGC is the only mode on Java 25. Do not pass ZGenerational.
        flags+=(
            "-XX:+UseZGC"
            "-XX:+AlwaysPreTouch"
            "-XX:+DisableExplicitGC"
            "-XX:+PerfDisableSharedMem"
        )
        ;;
    g1gc | g1)
        # https://docs.papermc.io/paper/aikars-flags
        flags+=(
            "-XX:+UseG1GC"
            "-XX:+ParallelRefProcEnabled"
            "-XX:MaxGCPauseMillis=200"
            "-XX:+UnlockExperimentalVMOptions"
            "-XX:+DisableExplicitGC"
            "-XX:+AlwaysPreTouch"
            "-XX:G1NewSizePercent=30"
            "-XX:G1MaxNewSizePercent=40"
            "-XX:G1HeapRegionSize=8M"
            "-XX:G1ReservePercent=20"
            "-XX:G1HeapWastePercent=5"
            "-XX:G1MixedGCCountTarget=4"
            "-XX:InitiatingHeapOccupancyPercent=15"
            "-XX:G1MixedGCLiveThresholdPercent=90"
            "-XX:G1RSetUpdatingPauseTimePercent=5"
            "-XX:SurvivorRatio=32"
            "-XX:+PerfDisableSharedMem"
            "-XX:MaxTenuringThreshold=1"
            "-Dusing.aikars.flags=https://mcflags.emc.gs"
            "-Daikars.new.flags=true"
        )
        ;;
    *)
        echo "Unknown GC_TYPE: ${GC_TYPE} (expected g1gc or zgc)" >&2
        exit 1
        ;;
esac

# Opt-in only. Empty and the usual false values leave the flag off.
compact_headers=$(printf '%s' "${COMPACT_OBJECT_HEADERS:-}" | tr '[:upper:]' '[:lower:]')
case "$compact_headers" in
    ""|0|false|no|off)
        ;;
    1|true|yes|on)
        if ! printf '%s\n' "${flags[@]}" | grep -F -x -q -- '-XX:+UnlockExperimentalVMOptions'; then
            flags+=("-XX:+UnlockExperimentalVMOptions")
        fi
        flags+=("-XX:+UseCompactObjectHeaders")
        ;;
    *)
        echo "Unknown COMPACT_OBJECT_HEADERS: ${COMPACT_OBJECT_HEADERS} (expected true or false)" >&2
        exit 1
        ;;
esac

printf '%s\n' "${flags[@]}"
