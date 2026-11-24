#!/usr/bin/env bash
# Contract for scripts/jvm-opts.sh: G1 vs ZGC, fixed vs container heap, OOM dumps.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTS="${ROOT_DIR}/scripts/jvm-opts.sh"

fail() {
    echo "jvm-opts: $*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if ! printf '%s\n' "$haystack" | grep -F -x -q -- "$needle"; then
        printf '%s\n' "$haystack" >&2
        fail "missing flag: $needle"
    fi
}

assert_absent() {
    local haystack="$1"
    local needle="$2"
    if printf '%s\n' "$haystack" | grep -F -q -- "$needle"; then
        printf '%s\n' "$haystack" >&2
        fail "unexpected flag matching: $needle"
    fi
}

container=$(
    HEAP_DUMP_PATH=/dumps MEMORY_MODE=container GC_TYPE=g1gc \
        MC_CGROUP_LIMIT=4294967296 \
        "$OPTS"
)
assert_contains "$container" "-XX:InitialRAMPercentage=75.0"
assert_contains "$container" "-XX:MaxRAMPercentage=75.0"
assert_contains "$container" "-XX:+UseG1GC"
assert_contains "$container" "-XX:+ExitOnOutOfMemoryError"
assert_contains "$container" "-XX:+HeapDumpOnOutOfMemoryError"
assert_contains "$container" "-XX:HeapDumpPath=/dumps"
assert_contains "$container" "-XX:+UnlockExperimentalVMOptions"
assert_absent "$container" "-Xmx"
assert_absent "$container" "-Xms"
assert_absent "$container" "ZGenerational"
assert_absent "$container" "UseCompactObjectHeaders"

custom=$(
    HEAP_DUMP_PATH=/var/dumps MEMORY_MODE=container \
        MAX_RAM_PERCENTAGE=60% GC_TYPE=G1GC \
        MC_CGROUP_LIMIT=4294967296 \
        "$OPTS"
)
assert_contains "$custom" "-XX:InitialRAMPercentage=60"
assert_contains "$custom" "-XX:MaxRAMPercentage=60"

fixed=$(
    HEAP_DUMP_PATH=/tmp/dumps MEMORY_MODE=fixed GC_TYPE=zgc \
        MIN_RAM=1G MAX_RAM=2G \
        "$OPTS"
)
assert_contains "$fixed" "-Xms1G"
assert_contains "$fixed" "-Xmx2G"
assert_contains "$fixed" "-XX:+UseZGC"
assert_contains "$fixed" "-XX:+ExitOnOutOfMemoryError"
assert_contains "$fixed" "-XX:HeapDumpPath=/tmp/dumps"
assert_absent "$fixed" "-XX:+UseG1GC"
assert_absent "$fixed" "MaxRAMPercentage"
assert_absent "$fixed" "ZGenerational"
assert_absent "$fixed" "UseCompactObjectHeaders"
assert_absent "$fixed" "UnlockExperimentalVMOptions"
assert_absent "$fixed" "G1NewSizePercent"

compact_g1=$(
    HEAP_DUMP_PATH=/tmp/dumps COMPACT_OBJECT_HEADERS=true \
        MEMORY_MODE=fixed GC_TYPE=g1gc MIN_RAM=1G MAX_RAM=1G \
        "$OPTS"
)
assert_contains "$compact_g1" "-XX:+UseCompactObjectHeaders"
assert_contains "$compact_g1" "-XX:+UnlockExperimentalVMOptions"
assert_contains "$compact_g1" "-XX:+UseG1GC"
unlock_count=$(printf '%s\n' "$compact_g1" | grep -F -x -c -- '-XX:+UnlockExperimentalVMOptions')
compact_count=$(printf '%s\n' "$compact_g1" | grep -F -x -c -- '-XX:+UseCompactObjectHeaders')
[[ "$unlock_count" -eq 1 ]] || fail "G1 opt-in should not duplicate UnlockExperimentalVMOptions"
[[ "$compact_count" -eq 1 ]] || fail "compact headers flag should appear once"

compact_zgc=$(
    HEAP_DUMP_PATH=/tmp/dumps COMPACT_OBJECT_HEADERS=yes \
        MEMORY_MODE=fixed GC_TYPE=zgc MIN_RAM=1G MAX_RAM=1G \
        "$OPTS"
)
assert_contains "$compact_zgc" "-XX:+UseZGC"
assert_contains "$compact_zgc" "-XX:+UnlockExperimentalVMOptions"
assert_contains "$compact_zgc" "-XX:+UseCompactObjectHeaders"
assert_absent "$compact_zgc" "ZGenerational"

off=$(
    HEAP_DUMP_PATH=/tmp/dumps COMPACT_OBJECT_HEADERS=false \
        MEMORY_MODE=fixed GC_TYPE=g1gc MIN_RAM=1G MAX_RAM=1G \
        "$OPTS"
)
assert_absent "$off" "UseCompactObjectHeaders"

if HEAP_DUMP_PATH=/dumps GC_TYPE=shenandoah "$OPTS" >/dev/null 2>&1; then
    fail "unknown GC_TYPE should fail"
fi
if MEMORY_MODE=container GC_TYPE=g1gc "$OPTS" >/dev/null 2>&1; then
    fail "missing HEAP_DUMP_PATH should fail"
fi
if HEAP_DUMP_PATH=/dumps COMPACT_OBJECT_HEADERS=maybe GC_TYPE=g1gc "$OPTS" >/dev/null 2>&1; then
    fail "unknown COMPACT_OBJECT_HEADERS should fail"
fi

capture() {
    local err_file
    err_file=$(mktemp)
    OPTS_ERR_FILE=$err_file
    OPTS_OUT=$(
        "$@" 2>"$err_file"
    ) || {
        cat "$err_file" >&2 || true
        fail "command failed: $*"
    }
}

assert_err() {
    local needle="$1"
    if ! grep -F -q -- "$needle" "$OPTS_ERR_FILE"; then
        cat "$OPTS_ERR_FILE" >&2 || true
        fail "missing stderr text: $needle"
    fi
}

assert_no_err() {
    local needle="$1"
    if grep -F -q -- "$needle" "$OPTS_ERR_FILE"; then
        cat "$OPTS_ERR_FILE" >&2 || true
        fail "unexpected stderr text: $needle"
    fi
}

# No container limit: safe heap from host RAM, banner on stderr, flags on stdout.
capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container GC_TYPE=g1gc \
        MC_CGROUP_LIMIT=max MC_HOST_MEM_BYTES=8589934592 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xms2G"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_absent "$OPTS_OUT" "MaxRAMPercentage"
assert_absent "$OPTS_OUT" "Chosen heap"
assert_err "Minecraft memory: no container limit, using a safe default heap."
assert_err "Chosen heap: 2G"
assert_err "about 25% of 8G host memory, kept between 1G and 4G."
assert_err "docker run -m 4g …"
assert_err "deploy.resources.limits.memory"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container \
        MC_CGROUP_LIMIT=max MC_HOST_MEM_BYTES=34359738368 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx4G"
assert_err "capped at 4G"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container \
        MC_CGROUP_LIMIT=max MC_HOST_MEM_BYTES=2147483648 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx1G"
assert_err "raised to 1G"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container \
        MC_CGROUP_LIMIT=max MC_HOST_MEM_BYTES=6442450944 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx1536M"
assert_err "Chosen heap: 1536M"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container \
        MC_CGROUP_LIMIT=max MC_HOST_MEM_BYTES=unreadable \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_err "host memory could not be read, so the heap is a fixed 2G."
rm -f "$OPTS_ERR_FILE"

# Real host memory, unlimited cgroup: still a banner and a clamped heap.
capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container MC_CGROUP_LIMIT=max \
        "$OPTS"
xmx=$(printf '%s\n' "$OPTS_OUT" | grep '^-Xmx')
xms=$(printf '%s\n' "$OPTS_OUT" | grep '^-Xms')
if [[ "${xmx#-Xmx}" != "${xms#-Xms}" ]]; then
    fail "safe heap Xms/Xmx differ: $xms vs $xmx"
fi
label=${xmx#-Xmx}
case "$label" in
    1G | 2G | 3G | 4G) ;;
    *M)
        heap_m=${label%M}
        if ((heap_m < 1024 || heap_m > 4096 || heap_m % 256 != 0)); then
            fail "heap ${label} is outside 1G-4G on a 256M step"
        fi
        ;;
    *) fail "unexpected safe heap label: ${label}" ;;
esac
assert_err "docker run -m 4g …"
assert_err "deploy.resources.limits.memory"
assert_absent "$OPTS_OUT" "MaxRAMPercentage"
rm -f "$OPTS_ERR_FILE"

# Fixed host mode ignores an unlimited cgroup and does not print the banner.
capture \
    env HEAP_DUMP_PATH=/tmp/dumps MEMORY_MODE=fixed GC_TYPE=g1gc \
        MIN_RAM=1G MAX_RAM=2G MC_CGROUP_LIMIT=max \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xms1G"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_no_err "Chosen heap"
rm -f "$OPTS_ERR_FILE"

# MEMORY is the one knob and wins over MIN_RAM/MAX_RAM.
capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=2G MEMORY_MODE=fixed \
        MIN_RAM=4G MAX_RAM=8G \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xms2G"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_absent "$OPTS_OUT" "-Xmx8G"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=2g MEMORY_MODE=fixed "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx2G"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=4G MEMORY_MODE=container \
        MC_CGROUP_LIMIT=8589934592 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx4G"
assert_absent "$OPTS_OUT" "MaxRAMPercentage"
assert_no_err "too little headroom"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=75% MEMORY_MODE=container \
        MC_CGROUP_LIMIT=4294967296 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-XX:InitialRAMPercentage=75"
assert_contains "$OPTS_OUT" "-XX:MaxRAMPercentage=75"
assert_absent "$OPTS_OUT" "-Xmx"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=auto MEMORY_MODE=container \
        MC_CGROUP_LIMIT=4294967296 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-XX:MaxRAMPercentage=75.0"
assert_absent "$OPTS_OUT" "-Xmx"
assert_no_err "Chosen heap"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=75% MC_CGROUP_LIMIT=max \
        MC_HOST_MEM_BYTES=8589934592 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_absent "$OPTS_OUT" "MaxRAMPercentage"
assert_err "was not applied as a percentage of the whole machine"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=auto MC_CGROUP_LIMIT=max \
        MC_HOST_MEM_BYTES=8589934592 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx2G"
assert_err "Chosen heap: 2G"
rm -f "$OPTS_ERR_FILE"

# Small limit and tight headroom warn, and the process still prints flags.
capture \
    env HEAP_DUMP_PATH=/dumps MEMORY_MODE=container GC_TYPE=g1gc \
        MC_CGROUP_LIMIT=536870912 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-XX:MaxRAMPercentage=75.0"
assert_absent "$OPTS_OUT" "-Xmx"
assert_err "under 1G"
assert_err "too little headroom"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=3900M MC_CGROUP_LIMIT=4294967296 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx3900M"
assert_err "too little headroom"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=95% \
        MC_CGROUP_LIMIT=21474836480 \
        "$OPTS"
assert_contains "$OPTS_OUT" "-XX:MaxRAMPercentage=95"
assert_err "too little headroom"
assert_err "over 90%"
rm -f "$OPTS_ERR_FILE"

capture \
    env HEAP_DUMP_PATH=/dumps MEMORY=512M MC_CGROUP_LIMIT=max "$OPTS"
assert_contains "$OPTS_OUT" "-Xmx512M"
assert_err "under 1G"
rm -f "$OPTS_ERR_FILE"

expect_memory_error() {
    local value="$1"
    local needle="$2"
    local err_file status
    err_file=$(mktemp)
    set +e
    HEAP_DUMP_PATH=/dumps MEMORY="$value" "$OPTS" >/dev/null 2>"$err_file"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        cat "$err_file" >&2 || true
        fail "MEMORY=${value} should fail"
    fi
    if ! grep -F -q -- "$needle" "$err_file"; then
        cat "$err_file" >&2 || true
        fail "MEMORY=${value} error missing: $needle"
    fi
    if ! grep -F -q -- "75%" "$err_file" || ! grep -F -q -- "auto" "$err_file"; then
        cat "$err_file" >&2 || true
        fail "MEMORY=${value} error should suggest 75% and auto"
    fi
    rm -f "$err_file"
}

expect_memory_error "4GB" "single letter"
expect_memory_error "4096" "no unit"
expect_memory_error "lots" "not a memory setting"
expect_memory_error "1.5G" "decimal"

if command -v java >/dev/null 2>&1; then
    java_major=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d. -f1)
    if [[ "$java_major" =~ ^[0-9]+$ && "$java_major" -ge 17 ]]; then
        for mode in container fixed; do
            for gc in g1gc zgc; do
                flags=()
                # Cap container-percentage heaps so AlwaysPreTouch does not
                # touch a quarter of the machine running this test. Aikar's
                # SurvivorRatio is rejected on a tiny heap, so keep this at 512M.
                if [[ "$mode" == "container" ]]; then
                    flags+=("-XX:MaxRAM=1G")
                fi
                while IFS= read -r flag; do
                    flags+=("$flag")
                done < <(
                    HEAP_DUMP_PATH=/tmp MEMORY_MODE="$mode" GC_TYPE="$gc" \
                        MIN_RAM=512M MAX_RAM=512M MAX_RAM_PERCENTAGE=50 \
                        MC_CGROUP_LIMIT=4294967296 \
                        "$OPTS"
                )
                err=$(java "${flags[@]}" -version 2>&1) || {
                    printf '%s\n' "$err" >&2
                    fail "Java rejected flags for MEMORY_MODE=$mode GC_TYPE=$gc"
                }
                if printf '%s\n' "$err" | grep -Eiq 'unrecognized|ignoring option|error:'; then
                    printf '%s\n' "$err" >&2
                    fail "Java warned about flags for MEMORY_MODE=$mode GC_TYPE=$gc"
                fi
            done
        done
        # Compact headers exist on JDK 25. Older JDKs reject the flag; skip there.
        if [[ "$java_major" -ge 25 ]]; then
            for gc in g1gc zgc; do
                flags=()
                while IFS= read -r flag; do
                    flags+=("$flag")
                done < <(
                    HEAP_DUMP_PATH=/tmp COMPACT_OBJECT_HEADERS=true \
                        MEMORY_MODE=fixed GC_TYPE="$gc" MIN_RAM=512M MAX_RAM=512M \
                        "$OPTS"
                )
                err=$(java "${flags[@]}" -version 2>&1) || {
                    printf '%s\n' "$err" >&2
                    fail "Java rejected compact-header flags for GC_TYPE=$gc"
                }
                if printf '%s\n' "$err" | grep -Eiq 'unrecognized|ignoring option|error:'; then
                    printf '%s\n' "$err" >&2
                    fail "Java warned about compact-header flags for GC_TYPE=$gc"
                fi
            done
        fi
    fi
fi

echo "JVM flag checks passed"
