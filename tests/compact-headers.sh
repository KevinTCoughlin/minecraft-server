#!/usr/bin/env bash
# Safety, parsing, and a stubbed before/after run for measure-compact-headers.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MEASURE="${ROOT_DIR}/scripts/measure-compact-headers.sh"
TMP="$(mktemp -d)"
LIVE_PID=""
WORK=""

cleanup() {
    if [[ -n "$LIVE_PID" ]]; then
        kill "$LIVE_PID" 2>/dev/null || true
        wait "$LIVE_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
    echo "compact-headers: $*" >&2
    if [[ -n "$WORK" && -d "$WORK" ]]; then
        echo "---- summary ----" >&2
        cat "$WORK/summary.md" >&2 2>/dev/null || true
        echo "---- baseline stdout ----" >&2
        cat "$WORK/baseline/stdout.log" >&2 2>/dev/null || true
        echo "---- baseline stderr ----" >&2
        cat "$WORK/baseline/stderr.log" >&2 2>/dev/null || true
        echo "---- compact stdout ----" >&2
        cat "$WORK/compact/stdout.log" >&2 2>/dev/null || true
        echo "---- compact stderr ----" >&2
        cat "$WORK/compact/stderr.log" >&2 2>/dev/null || true
    fi
    exit 1
}

assert_refused() {
    local err_file="$1"
    local out_file="$2"
    if ! grep -q 'refusing to use the original world' "$err_file" "$out_file"; then
        cat "$out_file" "$err_file" >&2
        fail "expected a refusal that names the original world"
    fi
}

make_world() {
    local dir="$1"
    mkdir -p "$dir/region"
    printf 'level-v1\n' > "$dir/level.dat"
    printf 'chunk\n' > "$dir/region/r.0.0.mca"
    printf 'keep\n' > "$dir/marker"
}

run_refused() {
    local out="$TMP/refuse.out"
    local err="$TMP/refuse.err"
    local status=0
    set +e
    "$@" >"$out" 2>"$err"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
        cat "$out" "$err" >&2
        fail "command should have refused: $*"
    fi
    assert_refused "$err" "$out"
}

# --- check-copy -----------------------------------------------------------

make_world "$TMP/src"

run_refused "$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/src"

ln -s "$TMP/src" "$TMP/link-dest"
run_refused "$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/link-dest"

mkdir -p "$TMP/hard"
ln "$TMP/src/level.dat" "$TMP/hard/level.dat"
run_refused "$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/hard"

mkdir -p "$TMP/src/nested"
printf 'level-v1\n' > "$TMP/src/nested/level.dat"
run_refused "$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/src/nested"
rm -rf "$TMP/src/nested"

mkdir -p "$TMP/good-copy"
cp -a "$TMP/src/." "$TMP/good-copy/"
"$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/good-copy" >/dev/null

mkdir -p "$TMP/linked-region"
cp -a "$TMP/src/." "$TMP/linked-region/"
rm -rf "$TMP/linked-region/region"
ln -s "$TMP/src/region" "$TMP/linked-region/region"
run_refused "$MEASURE" check-copy --source "$TMP/src" --dest "$TMP/linked-region"

# --- parsers --------------------------------------------------------------

heap_kb=$(printf ' garbage-first heap   total 131072K, used 2364K [0x0, 0x1)\n Metaspace       used 85K, committed 320K, reserved 1114112K\n' | "$MEASURE" parse-heap)
[[ "$heap_kb" == "2364" ]] || fail "jcmd heap parser returned ${heap_kb}"

heap_mb=$(printf ' ZHeap used 2M, capacity 64M, max capacity 64M\n' | "$MEASURE" parse-heap)
[[ "$heap_mb" == "2048" ]] || fail "megabyte heap parser returned ${heap_mb}"

jstat_kb=$(printf 'S0U S1U EU OU\n1.5 2.5 4 8\n' | "$MEASURE" parse-heap)
[[ "$jstat_kb" == "16" ]] || fail "jstat parser returned ${jstat_kb}"

write_fixture_run() {
    local dir="$1"
    local heap_a="$2"
    local heap_b="$3"
    local soak_pause_ms="$4"
    local tps_line="$5"
    local mspt_body="$6"
    mkdir -p "$dir/logs"
    printf '%s\n%s\n' "$heap_a" "$heap_b" > "$dir/heap-samples.txt"
    printf '100\n' > "$dir/warmup-uptime.txt"
    cat > "$dir/gc.log" <<EOF
[1.000s][info][gc          ] GC(0) Pause Young (Normal) (G1 Evacuation Pause) 10M->9M(64M) 999.000ms
[150.000s][info][gc,phases   ] GC(1)   Evacuate Collection Set: 1.000ms
[150.000s][info][gc,start    ] GC(1) Pause Young (Normal) (G1 Evacuation Pause)
[160.000s][info][gc          ] GC(1) Pause Young (Normal) (G1 Evacuation Pause) 800M->700M(4096M) ${soak_pause_ms}ms
EOF
    cat > "$dir/logs/latest.log" <<EOF
[00:00:00] [Server thread/INFO]: Done (1.000s)! For help, type "help"
[00:00:02] [Server thread/INFO]: TPS from last 1m, 5m, 15m: ${tps_line}
[00:00:03] [Server thread/INFO]: Server tick times (avg/min/max) from last 5s, 10s, 1m:
${mspt_body}
EOF
    printf '%s\n' '-XX:+UseG1GC' > "$dir/flags.txt"
}

write_run_env() {
    local work="$1"
    cat > "$work/run.env" <<'EOF'
WORLD_NAME=parkour-spiral
WORLD_SIZE_KB=1234
JAVA_VERSION=openjdk version "25.0.1"
WARMUP_SECONDS=120
SOAK_SECONDS=180
MIN_RAM=4G
MAX_RAM=4G
GC_TYPE=g1gc
VIEW_DISTANCE=10
SIMULATION_DISTANCE=10
SERVER_PORT=25566
SOURCE_PATH=/worlds/parkour-spiral
EOF
}

expect_verdict() {
    local work="$1"
    local expected="$2"
    local got=""
    "$MEASURE" summarize --work "$work" --output "$work/summary.md" >/dev/null
    got=$(tr -d '[:space:]' < "$work/verdict.txt")
    [[ "$got" == "$expected" ]] || fail "verdict ${got}, expected ${expected} (${work})"
    grep -q 'smaller heap' "$work/summary.md" || fail "summary missing acceptance text"
    grep -q 'parkour-spiral' "$work/summary.md" || fail "summary missing world name"
    grep -q '1234 KB' "$work/summary.md" || fail "summary missing world size"
}

accept_work="$TMP/sum-accept"
mkdir -p "$accept_work"
write_run_env "$accept_work"
write_fixture_run "$accept_work/baseline" 900000 950000 10.000 '20.0, 20.0, *' '[00:00:03] [Server thread/INFO]: 5s 1.00/0.50/2.00
[00:00:03] [Server thread/INFO]: 10s 1.00/0.50/2.00
[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
write_fixture_run "$accept_work/compact" 700000 720000 8.000 '§a20.0§r, §a20.0§r, §a*' '[00:00:03] [Server thread/INFO]: 1m 4.00/1.00/8.00'
expect_verdict "$accept_work" ACCEPT
grep -q '999' "$accept_work/summary.md" && fail "warmup pause of 999ms leaked into the summary"
grep -q '| GC pause max (ms) | 10.000 | 8.000 |' "$accept_work/summary.md" || fail "soak pause max was not the compared value"

pause_work="$TMP/sum-pause"
mkdir -p "$pause_work"
write_run_env "$pause_work"
write_fixture_run "$pause_work/baseline" 900000 950000 10.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
write_fixture_run "$pause_work/compact" 700000 720000 12.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
expect_verdict "$pause_work" REJECT

heap_work="$TMP/sum-heap"
mkdir -p "$heap_work"
write_run_env "$heap_work"
write_fixture_run "$heap_work/baseline" 700000 720000 10.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
write_fixture_run "$heap_work/compact" 900000 950000 8.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 4.00/1.00/8.00'
expect_verdict "$heap_work" REJECT

tps_work="$TMP/sum-tps"
mkdir -p "$tps_work"
write_run_env "$tps_work"
write_fixture_run "$tps_work/baseline" 900000 950000 10.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
write_fixture_run "$tps_work/compact" 700000 720000 10.000 '19.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
expect_verdict "$tps_work" REJECT

mspt_work="$TMP/sum-mspt"
mkdir -p "$mspt_work"
write_run_env "$mspt_work"
write_fixture_run "$mspt_work/baseline" 900000 950000 10.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 18.2/8.1/95.6, 15.5/7.4/95.6, 12.2/5.6/95.6'
write_fixture_run "$mspt_work/compact" 700000 720000 10.000 '20,0, *, *' '[00:00:03] [Server thread/INFO]: 1m 4,50/1,00/8,00'
expect_verdict "$mspt_work" ACCEPT
grep -q '| MSPT 1m avg | 12.2 | 4.50 |' "$mspt_work/summary.md" || fail "MSPT parser did not take the 1m average"

missing_work="$TMP/sum-missing"
mkdir -p "$missing_work"
write_run_env "$missing_work"
write_fixture_run "$missing_work/baseline" 900000 950000 10.000 '*, *, *' '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00'
write_fixture_run "$missing_work/compact" 700000 720000 8.000 '20.0, *, *' '[00:00:03] [Server thread/INFO]: 1m 4.00/1.00/8.00'
expect_verdict "$missing_work" INCONCLUSIVE

p99_work="$TMP/sum-p99"
mkdir -p "$p99_work/baseline/logs" "$p99_work/compact/logs"
write_run_env "$p99_work"
printf '900000\n' > "$p99_work/baseline/heap-samples.txt"
printf '700000\n' > "$p99_work/compact/heap-samples.txt"
printf '100\n' > "$p99_work/baseline/warmup-uptime.txt"
printf '100\n' > "$p99_work/compact/warmup-uptime.txt"
{
    echo '[1.000s][info][gc] GC(0) Pause Young (Normal) (G1 Evacuation Pause) 10M->9M(64M) 999.000ms'
    i=0
    while [[ "$i" -lt 100 ]]; do
        echo "[$((101 + i)).000s][info][gc] GC(${i}) Pause Young (Normal) (G1 Evacuation Pause) 10M->9M(64M) 1.000ms"
        i=$((i + 1))
    done
    echo '[250.000s][info][gc] GC(100) Pause Young (Normal) (G1 Evacuation Pause) 10M->9M(64M) 50.000ms'
} > "$p99_work/baseline/gc.log"
cp "$p99_work/baseline/gc.log" "$p99_work/compact/gc.log"
for side in baseline compact; do
    cat > "$p99_work/$side/logs/latest.log" <<'EOF'
[00:00:02] [Server thread/INFO]: TPS from last 1m, 5m, 15m: 20.0, *, *
[00:00:03] [Server thread/INFO]: Server tick times (avg/min/max) from last 5s, 10s, 1m:
[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00
EOF
    printf '%s\n' '-XX:+UseG1GC' > "$p99_work/$side/flags.txt"
done
expect_verdict "$p99_work" ACCEPT
grep -q '| GC pause p99 (ms) | 1.000 | 1.000 |' "$p99_work/summary.md" || fail "p99 should ignore the single 50ms outlier at this sample size"
grep -q '| GC pause max (ms) | 50.000 | 50.000 |' "$p99_work/summary.md" || fail "max pause should keep the 50ms outlier"

# --- measure refusals -----------------------------------------------------

JAR="$TMP/paper.jar"
printf 'jar\n' > "$JAR"
SERVER_EMPTY="$TMP/empty-server"
mkdir -p "$SERVER_EMPTY"

run_refused env SERVER_DIR="$SERVER_EMPTY" "$MEASURE" measure \
    --world "$TMP/src" \
    --work-dir "$TMP/src" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1
[[ ! -d "$TMP/src/baseline" ]] || fail "refusal created a server directory inside the original world"

run_refused env SERVER_DIR="$SERVER_EMPTY" "$MEASURE" measure \
    --world "$TMP/src" \
    --work-dir "$TMP/src/inside" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1
[[ ! -e "$TMP/src/inside" ]] || fail "refusal created a directory inside the original world"

ln -s "$TMP/src" "$TMP/alias"
run_refused env SERVER_DIR="$SERVER_EMPTY" "$MEASURE" measure \
    --world "$TMP/src" \
    --work-dir "$TMP/alias/child" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1
[[ ! -e "$TMP/src/child" ]] || fail "refusal followed a symlink into the original world"

LIVE_SERVER="$TMP/live-server"
mkdir -p "$LIVE_SERVER/parkour/region"
printf 'level-v1\n' > "$LIVE_SERVER/parkour/level.dat"
printf 'keep\n' > "$LIVE_SERVER/parkour/marker"
bash -c 'exec -a "java -jar paper.jar --nogui" sleep 120' &
LIVE_PID=$!
printf '%s\n' "$LIVE_PID" > "$LIVE_SERVER/server.pid"
if ! ps -p "$LIVE_PID" -o args= | grep -q 'paper.jar'; then
    fail "could not mark the fake server process as paper.jar"
fi
run_refused env SERVER_DIR="$LIVE_SERVER" "$MEASURE" measure \
    --world "$LIVE_SERVER/parkour" \
    --work-dir "$TMP/live-work" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1
[[ ! -d "$TMP/live-work" ]] || fail "live-server refusal still created a work directory"
grep -q 'keep' "$LIVE_SERVER/parkour/marker" || fail "live world marker changed"
kill "$LIVE_PID" 2>/dev/null || true
wait "$LIVE_PID" 2>/dev/null || true
LIVE_PID=""

# --- stubbed before/after run --------------------------------------------

STUB_JAVA="$TMP/java-stub"
STUB_JCMD="$TMP/jcmd-stub"
STUB_HOOK="$TMP/hook"
RECORD="$TMP/record"
mkdir -p "$RECORD"

cat > "$STUB_JAVA" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-version" ]]; then
    echo 'openjdk version "25.0.0" test' >&2
    exit 0
fi
record="${STUB_RECORD:?}"
cwd=$(pwd -P)
variant=baseline
case "$cwd" in
    */compact) variant=compact ;;
esac
printf '%s\n' "$cwd" >> "$record/cwds"
{
    echo "--- ${variant}"
    for arg in "$@"; do
        # printf treats a leading dash as an option, and the java argv includes --nogui.
        echo "$arg"
    done
} >> "$record/args"
mkdir -p logs
if [[ -n "${SOURCE_PHYS:-}" && -d world ]]; then
    world_phys=$(cd world && pwd -P)
    if [[ "$world_phys" == "$SOURCE_PHYS" ]]; then
        printf '%s\n' "$world_phys" >> "$record/violations"
        exit 2
    fi
    printf 'stub\n' >> world/stub-wrote
fi
gc_log=""
for arg in "$@"; do
    case "$arg" in
        -Xlog:*)
            gc_log=$(printf '%s\n' "$arg" | sed -n 's/.*file=\([^:]*\).*/\1/p')
            ;;
    esac
done
if [[ -n "$gc_log" ]]; then
    printf '[0.100s][info][gc] GC(0) Pause Young (Normal) (G1 Evacuation Pause) 10M->9M(64M) 1.000ms\n' >> "$gc_log"
fi
printf '[00:00:00] [Server thread/INFO]: Done (0.100s)! For help, type "help"\n' > logs/latest.log
while IFS= read -r line; do
    case "$line" in
        tps)
            if [[ "$variant" == compact ]]; then
                pause=8.000
                before=600M
            else
                pause=12.000
                before=800M
            fi
            if [[ -n "$gc_log" ]]; then
                printf '[1000.000s][info][gc] GC(1) Pause Young (Normal) (G1 Evacuation Pause) %s->500M(4096M) %sms\n' \
                    "$before" "$pause" >> "$gc_log"
            fi
            printf '[00:00:02] [Server thread/INFO]: TPS from last 1m, 5m, 15m: 20.0, *, *\n' >> logs/latest.log
            ;;
        mspt)
            printf '[00:00:03] [Server thread/INFO]: Server tick times (avg/min/max) from last 5s, 10s, 1m:\n' >> logs/latest.log
            if [[ "$variant" == compact ]]; then
                printf '[00:00:03] [Server thread/INFO]: 1m 4.00/1.00/8.00\n' >> logs/latest.log
            else
                printf '[00:00:03] [Server thread/INFO]: 1m 5.00/1.00/12.00\n' >> logs/latest.log
            fi
            ;;
        stop)
            exit 0
            ;;
    esac
done
exit 0
EOF

cat > "$STUB_JCMD" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MEASURE_VARIANT:-}" == compact ]]; then
    echo " garbage-first heap   total 4194304K, used 700000K [0x0, 0x1)"
else
    echo " garbage-first heap   total 4194304K, used 900000K [0x0, 0x1)"
fi
EOF

cat > "$STUB_HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest="$1"
source="$2"
rm -rf "$dest"
ln -s "$source" "$dest"
EOF

chmod +x "$STUB_JAVA" "$STUB_JCMD" "$STUB_HOOK"

if command -v shasum >/dev/null 2>&1; then
    checksum_before=$(shasum -a 256 "$TMP/src/level.dat")
else
    checksum_before=$(sha256sum "$TMP/src/level.dat")
fi

HOOK_RECORD="$TMP/hook-record"
mkdir -p "$HOOK_RECORD"
run_refused env \
    SERVER_DIR="$SERVER_EMPTY" \
    JAVA_CMD="$STUB_JAVA" \
    JCMD_CMD="$STUB_JCMD" \
    STUB_RECORD="$HOOK_RECORD" \
    SOURCE_PHYS="$TMP/src" \
    MEASURE_AFTER_COPY_HOOK="$STUB_HOOK" \
    "$MEASURE" measure \
    --world "$TMP/src" \
    --work-dir "$TMP/hook-work" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1 --sample-interval 30 \
    --startup-timeout 15 --shutdown-timeout 10
[[ ! -s "$HOOK_RECORD/cwds" ]] || fail "hooked copy still started Java"
if command -v shasum >/dev/null 2>&1; then
    checksum_after=$(shasum -a 256 "$TMP/src/level.dat")
else
    checksum_after=$(sha256sum "$TMP/src/level.dat")
fi
[[ "$checksum_before" == "$checksum_after" ]] || fail "hook refusal changed the original level.dat"

WORK="$TMP/run-work"
env \
    SERVER_DIR="$SERVER_EMPTY" \
    JAVA_CMD="$STUB_JAVA" \
    JCMD_CMD="$STUB_JCMD" \
    STUB_RECORD="$RECORD" \
    SOURCE_PHYS="$TMP/src" \
    COMPACT_OBJECT_HEADERS=true \
    "$MEASURE" measure \
    --world "$TMP/src" \
    --work-dir "$WORK" \
    --paper-jar "$JAR" \
    --warmup 1 --soak 1 --sample-interval 30 \
    --startup-timeout 15 --shutdown-timeout 10 \
    --min-ram 512M --max-ram 512M --port 25567 \
    >"$TMP/measure.out" 2>"$TMP/measure.err"

verdict=$(tr -d '[:space:]' < "$WORK/verdict.txt")
[[ "$verdict" == "ACCEPT" ]] || fail "stubbed measurement verdict was ${verdict}"
[[ -s "$RECORD/violations" ]] && fail "server was pointed at the original world"
cwd_count=$(wc -l < "$RECORD/cwds" | tr -d ' ')
[[ "$cwd_count" == "2" ]] || fail "expected two server starts, saw ${cwd_count}"
while IFS= read -r cwd; do
    [[ "$cwd" != "$TMP/src" ]] || fail "server cwd was the original world"
    [[ -d "$cwd/world" && ! -L "$cwd/world" ]] || fail "server world is not a real directory"
    "$MEASURE" check-copy --source "$TMP/src" --dest "$cwd/world" >/dev/null
    grep -q '^level-name=world$' "$cwd/server.properties" || fail "level-name was not world"
done < "$RECORD/cwds"
[[ ! -e "$TMP/src/stub-wrote" ]] || fail "stub write landed in the original world"
[[ -f "$WORK/baseline/world/stub-wrote" && -f "$WORK/compact/world/stub-wrote" ]] || fail "copies were not what the server wrote"
grep -q 'UseCompactObjectHeaders' "$WORK/baseline/flags.txt" && fail "baseline flags include compact headers"
grep -q '^-XX:+UseCompactObjectHeaders$' "$WORK/compact/flags.txt" || fail "compact flags omit the opt-in"
grep -q 'UseCompactObjectHeaders' "$WORK/baseline/command.txt" && fail "baseline command includes compact headers"
grep -q 'UseCompactObjectHeaders' "$WORK/compact/command.txt" || fail "compact command omits the flag"
flag_hits=$(grep -c 'UseCompactObjectHeaders' "$RECORD/args" || true)
[[ "$flag_hits" == "1" ]] || fail "expected the flag on exactly one java invocation, saw ${flag_hits}"
if command -v shasum >/dev/null 2>&1; then
    checksum_after=$(shasum -a 256 "$TMP/src/level.dat")
else
    checksum_after=$(sha256sum "$TMP/src/level.dat")
fi
[[ "$checksum_before" == "$checksum_after" ]] || fail "original level.dat changed"
grep -q '^keep$' "$TMP/src/marker" || fail "original marker changed"
grep -q 'Verdict: ACCEPT' "$TMP/measure.out" || fail "stdout did not include the verdict"

"$MEASURE" --help >/dev/null

echo "Compact object header harness checks passed"
