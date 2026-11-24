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
# MEMORY is the simple knob: 2G, 4G, auto, or 75%.
#   - A size sets -Xms and -Xmx to that size.
#   - A percentage sets InitialRAMPercentage and MaxRAMPercentage, and is only
#     applied when a container memory limit is set.
#   - auto (or an empty MEMORY) keeps the older behavior: MEMORY_MODE=fixed
#     uses MIN_RAM and MAX_RAM; MEMORY_MODE=container uses
#     INITIAL_RAM_PERCENTAGE and MAX_RAM_PERCENTAGE when a limit is set.
# With no cgroup limit, container mode does not fail and does not take a
# percentage of the whole machine. It picks a safe heap: about 25% of host
# memory, rounded to the nearest 256M, clamped between 1G and 4G. If host
# memory cannot be read, the heap is a fixed 2G. A banner on stderr explains
# the choice and how to set a limit.
#
# A limit under 1G, or a heap that leaves less than 512M outside the limit
# (or more than 90% of the limit), prints a warning and still starts.
#
# MC_CGROUP_LIMIT and MC_HOST_MEM_BYTES override detection. Tests set them.
# Operators should use MEMORY, or the container limit, instead.
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
MEMORY="${MEMORY:-}"

GIB=$((1024 * 1024 * 1024))
MIB=$((1024 * 1024))
MIN_DEFAULT_HEAP=$GIB
MAX_DEFAULT_HEAP=$((4 * GIB))
FALLBACK_HEAP=$((2 * GIB))
HEAP_ROUND_STEP=$((256 * MIB))
MIN_LIMIT_BYTES=$GIB
MIN_HEADROOM_BYTES=$((512 * MIB))

if [[ -z "$HEAP_DUMP_PATH" ]]; then
    echo "HEAP_DUMP_PATH is required (directory for -XX:HeapDumpPath)" >&2
    exit 1
fi

case "$MEMORY_MODE" in
    fixed | container) ;;
    *)
        echo "Unknown MEMORY_MODE: ${MEMORY_MODE} (expected fixed or container)" >&2
        exit 1
        ;;
esac

die_memory() {
    printf '%s\n' "$1" >&2
    exit 1
}

bytes_to_label() {
    local bytes="$1"
    if ((bytes % GIB == 0)); then
        printf '%sG\n' "$((bytes / GIB))"
    elif ((bytes % MIB == 0)); then
        printf '%sM\n' "$((bytes / MIB))"
    elif ((bytes % 1024 == 0)); then
        printf '%sK\n' "$((bytes / 1024))"
    else
        printf '%s\n' "$bytes"
    fi
}

round_to_step() {
    local bytes="$1"
    local step="$2"
    printf '%s\n' "$((((bytes + step / 2) / step) * step))"
}

normalize_percent() {
    local value="${1%\%}"
    if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "Invalid memory percentage: $1" >&2
        exit 1
    fi
    printf '%s\n' "$value"
}

# Basis points: 75 -> 7500, 75.5 -> 7550. Avoids awk for headroom math.
percent_to_basis() {
    local pct="${1%\%}"
    local whole frac
    if [[ "$pct" == *.* ]]; then
        whole="${pct%%.*}"
        frac="${pct#*.}"
        frac="${frac}00"
        frac="${frac:0:2}"
        printf '%s\n' "$((10#$whole * 100 + 10#$frac))"
    else
        printf '%s\n' "$((10#$pct * 100))"
    fi
}

heap_bytes_from_basis() {
    local limit="$1"
    local basis="$2"
    printf '%s\n' "$(((limit / 10000) * basis + (limit % 10000) * basis / 10000))"
}

# CGROUP_HAS_LIMIT=1 and CGROUP_LIMIT_BYTES when a real positive limit exists.
detect_cgroup_limit() {
    CGROUP_HAS_LIMIT=0
    CGROUP_LIMIT_BYTES=""
    local raw=""
    if [[ -n "${MC_CGROUP_LIMIT+x}" ]]; then
        raw="$MC_CGROUP_LIMIT"
    elif [[ -r /sys/fs/cgroup/memory.max ]]; then
        raw=$(tr -d '[:space:]' </sys/fs/cgroup/memory.max)
    elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        raw=$(tr -d '[:space:]' </sys/fs/cgroup/memory/memory.limit_in_bytes)
    else
        return 0
    fi
    if [[ -z "$raw" || "$raw" == "max" || "$raw" == "unlimited" ]]; then
        return 0
    fi
    if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    # cgroup v1 reports "unlimited" as a sentinel with 16 or more digits.
    if ((${#raw} >= 16)); then
        return 0
    fi
    if [[ "$raw" -eq 0 ]]; then
        return 0
    fi
    CGROUP_HAS_LIMIT=1
    CGROUP_LIMIT_BYTES=$raw
}

read_host_bytes() {
    local kb="" bytes="" key value _
    if [[ -n "${MC_HOST_MEM_BYTES+x}" ]]; then
        if [[ "$MC_HOST_MEM_BYTES" =~ ^[0-9]+$ && "$MC_HOST_MEM_BYTES" -gt 0 ]]; then
            printf '%s\n' "$MC_HOST_MEM_BYTES"
        fi
        return 0
    fi
    if [[ -r /proc/meminfo ]]; then
        while read -r key value _; do
            if [[ "$key" == "MemTotal:" && "$value" =~ ^[0-9]+$ ]]; then
                kb=$value
                break
            fi
        done </proc/meminfo
        if [[ -n "$kb" && "$kb" -gt 0 ]]; then
            printf '%s\n' "$((kb * 1024))"
            return 0
        fi
    fi
    if command -v sysctl >/dev/null 2>&1; then
        bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
        if [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 ]]; then
            printf '%s\n' "$bytes"
        fi
    fi
}

# SAFE_HEAP_BYTES and SAFE_HEAP_WHY.
choose_safe_heap() {
    local host quarter host_label chosen
    host=$(read_host_bytes)
    if [[ -z "$host" ]]; then
        SAFE_HEAP_BYTES=$FALLBACK_HEAP
        SAFE_HEAP_WHY="host memory could not be read, so the heap is a fixed 2G."
        return 0
    fi
    quarter=$((host / 4))
    host_label=$(bytes_to_label "$host")
    if ((quarter < MIN_DEFAULT_HEAP)); then
        SAFE_HEAP_BYTES=$MIN_DEFAULT_HEAP
        SAFE_HEAP_WHY="about 25% of ${host_label} host memory is under 1G, so the heap is raised to 1G."
    elif ((quarter > MAX_DEFAULT_HEAP)); then
        SAFE_HEAP_BYTES=$MAX_DEFAULT_HEAP
        SAFE_HEAP_WHY="about 25% of ${host_label} host memory is above 4G, so the heap is capped at 4G."
    else
        chosen=$(round_to_step "$quarter" "$HEAP_ROUND_STEP")
        if ((chosen < MIN_DEFAULT_HEAP)); then
            chosen=$MIN_DEFAULT_HEAP
        elif ((chosen > MAX_DEFAULT_HEAP)); then
            chosen=$MAX_DEFAULT_HEAP
        fi
        SAFE_HEAP_BYTES=$chosen
        SAFE_HEAP_WHY="about 25% of ${host_label} host memory, kept between 1G and 4G."
    fi
}

print_banner() {
    local heap_label="$1"
    local why="$2"
    local extra="${3:-}"
    {
        printf '%s\n' "----------------------------------------------------------------"
        printf '%s\n' "Minecraft memory: no container limit, using a safe default heap."
        printf '%s\n' "Chosen heap: ${heap_label}"
        printf '%s\n' "Why: ${why}"
        if [[ -n "$extra" ]]; then
            printf '%s\n' "$extra"
        fi
        printf '%s\n' "A container limit is the better knob. Set one with:"
        printf '%s\n' "  docker run -m 4g …"
        printf '%s\n' "In Compose, set deploy.resources.limits.memory (for example, 4G)."
        printf '%s\n' "With a limit, the heap is 75% of that limit. You can also set MEMORY=2G, MEMORY=4G, MEMORY=auto, or MEMORY=75%."
        printf '%s\n' "----------------------------------------------------------------"
    } >&2
}

warn_about_limit() {
    local limit_bytes="$1"
    local heap_bytes="$2"
    local percent="${3:-}"
    local limit_label headroom head_label whole=""
    limit_label=$(bytes_to_label "$limit_bytes")
    if ((limit_bytes < MIN_LIMIT_BYTES)); then
        printf 'Warning: the container memory limit is %s, which is under 1G. Paper often fails to keep up in a limit that small. The server will still start. Raise it, for example: docker run -m 2g …\n' \
            "$limit_label" >&2
    fi
    headroom=$((limit_bytes - heap_bytes))
    local reasons=""
    if ((headroom < MIN_HEADROOM_BYTES)); then
        if ((headroom <= 0)); then
            reasons="the heap is larger than the limit"
        else
            head_label=$(bytes_to_label "$headroom")
            reasons="only ${head_label} is left outside the heap"
        fi
    fi
    if [[ -n "$percent" ]]; then
        percent="${percent%\%}"
        whole="${percent%%.*}"
        if [[ "$whole" =~ ^[0-9]+$ ]] && ((whole > 90)); then
            if [[ -n "$reasons" ]]; then
                reasons="${reasons}; the heap is over 90% of the limit"
            else
                reasons="the heap is over 90% of the limit"
            fi
        fi
    fi
    if [[ -n "$reasons" ]]; then
        printf 'Warning: the heap leaves too little headroom (%s). The server will still start. Leave about a quarter of the limit outside the heap, or raise the limit.\n' \
            "$reasons" >&2
    fi
}

classify_memory() {
    local value lower
    value=$(printf '%s' "$MEMORY" | tr -d '[:space:]')
    MEMORY_KIND=empty
    MEMORY_PERCENT=""
    MEMORY_SIZE_BYTES=""
    if [[ -z "$value" ]]; then
        return 0
    fi
    lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" == "auto" ]]; then
        MEMORY_KIND=auto
        return 0
    fi
    if [[ "$lower" =~ ^[0-9]+%$ || "$lower" =~ ^[0-9]+\.[0-9]+%$ ]]; then
        local pct="${lower%\%}"
        local basis
        basis=$(percent_to_basis "$pct")
        if ((basis > 10000)); then
            die_memory "MEMORY=${value} is over 100%. Use a percentage from 1% to 100% (for example 75%), a size such as 4G, or auto."
        fi
        if ((basis <= 0)); then
            die_memory "MEMORY=${value} is not a usable percentage. Use a percentage from 1% to 100% (for example 75%), a size such as 4G, or auto."
        fi
        MEMORY_KIND=percent
        MEMORY_PERCENT=$pct
        return 0
    fi
    if [[ "$lower" =~ ^[0-9]+[kmg]$ ]]; then
        local num="${lower%[kmg]}"
        local unit
        unit=$(printf '%s' "${lower#"${lower%?}"}" | tr '[:lower:]' '[:upper:]')
        if ((${#num} > 6)); then
            die_memory "MEMORY=${value} is too large. Use a size such as 2G or 4G, a percentage such as 75%, or auto."
        fi
        if ((num == 0)); then
            die_memory "MEMORY=${value} is zero. Use a size such as 2G or 4G, a percentage such as 75%, or auto."
        fi
        case "$unit" in
            K) MEMORY_SIZE_BYTES=$((num * 1024)) ;;
            M) MEMORY_SIZE_BYTES=$((num * 1024 * 1024)) ;;
            G) MEMORY_SIZE_BYTES=$((num * 1024 * 1024 * 1024)) ;;
            *)
                die_memory "MEMORY=${value} is not a memory setting. Use a size such as 2G or 4G, a percentage such as 75%, or auto."
                ;;
        esac
        MEMORY_KIND=size
        return 0
    fi
    if [[ "$lower" =~ ^[0-9]+(\.[0-9]+)?(gib|mib|kib|gb|mb|kb|tb)$ ]]; then
        die_memory "MEMORY=${value} uses a long unit. Use a number and a single letter, such as 4G or 512M, not ${value}. You can also use 75% or auto."
    fi
    if [[ "$lower" =~ ^[0-9]+\.[0-9]+[kmg]$ ]]; then
        die_memory "MEMORY=${value} has a decimal. Use a whole number such as 4G or 1536M, a percentage such as 75%, or auto."
    fi
    if [[ "$lower" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        die_memory "MEMORY=${value} has no unit. Use 4G or 4096M, a percentage such as 75%, or auto."
    fi
    die_memory "MEMORY=${value} is not a memory setting. Use a size such as 2G or 4G, a percentage such as 75%, or auto."
}

use_fixed_heap() {
    local label
    label=$(bytes_to_label "$1")
    flags+=("-Xms${label}" "-Xmx${label}")
}

use_percent_heap() {
    local initial="$1"
    local max="$2"
    flags+=(
        "-XX:InitialRAMPercentage=$(normalize_percent "$initial")"
        "-XX:MaxRAMPercentage=$(normalize_percent "$max")"
    )
}

use_safe_default() {
    local extra="${1:-}"
    local label
    choose_safe_heap
    label=$(bytes_to_label "$SAFE_HEAP_BYTES")
    print_banner "$label" "$SAFE_HEAP_WHY" "$extra"
    use_fixed_heap "$SAFE_HEAP_BYTES"
}

warn_percent_limit() {
    local percent="$1"
    local basis heap_bytes
    basis=$(percent_to_basis "$percent")
    heap_bytes=$(heap_bytes_from_basis "$CGROUP_LIMIT_BYTES" "$basis")
    warn_about_limit "$CGROUP_LIMIT_BYTES" "$heap_bytes" "$percent"
}

detect_cgroup_limit
classify_memory

flags=()

case "$MEMORY_KIND" in
    size)
        use_fixed_heap "$MEMORY_SIZE_BYTES"
        if ((CGROUP_HAS_LIMIT == 1)); then
            warn_about_limit "$CGROUP_LIMIT_BYTES" "$MEMORY_SIZE_BYTES" ""
        elif ((MEMORY_SIZE_BYTES < MIN_LIMIT_BYTES)); then
            printf 'Warning: MEMORY=%s is under 1G. Paper often needs more than that. The server will still start. A size such as 2G or 4G is a safer start.\n' \
                "$(bytes_to_label "$MEMORY_SIZE_BYTES")" >&2
        fi
        ;;
    percent)
        if ((CGROUP_HAS_LIMIT == 1)); then
            use_percent_heap "$MEMORY_PERCENT" "$MEMORY_PERCENT"
            warn_percent_limit "$MEMORY_PERCENT"
        else
            use_safe_default "MEMORY=${MEMORY_PERCENT}% needs a container memory limit, so it was not applied as a percentage of the whole machine."
        fi
        ;;
    auto)
        if ((CGROUP_HAS_LIMIT == 1)); then
            use_percent_heap "$INITIAL_RAM_PERCENTAGE" "$MAX_RAM_PERCENTAGE"
            warn_percent_limit "$MAX_RAM_PERCENTAGE"
        else
            use_safe_default
        fi
        ;;
    empty)
        if [[ "$MEMORY_MODE" == "container" ]]; then
            if ((CGROUP_HAS_LIMIT == 1)); then
                use_percent_heap "$INITIAL_RAM_PERCENTAGE" "$MAX_RAM_PERCENTAGE"
                warn_percent_limit "$MAX_RAM_PERCENTAGE"
            else
                use_safe_default
            fi
        else
            flags+=(
                "-Xms${MIN_RAM}"
                "-Xmx${MAX_RAM}"
            )
        fi
        ;;
    *)
        echo "Unknown memory choice: ${MEMORY_KIND}" >&2
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
