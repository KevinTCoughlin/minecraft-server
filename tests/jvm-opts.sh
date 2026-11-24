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
