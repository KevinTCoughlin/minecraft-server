#!/usr/bin/env bash
# Before/after measurement of -XX:+UseCompactObjectHeaders on a COPY of a world.
#
# The original world directory is never the server's level. The script copies
# it twice, runs the same heap and the same flags except the compact-header
# opt-in, and writes a comparison. There is no switch that points the server
# at the original path.
#
#   ./scripts/measure-compact-headers.sh --world server/parkour-spiral
#
# See docs/compact-object-headers.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
JVM_OPTS_SH="${SCRIPT_DIR}/jvm-opts.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ -t 1 ]]; then
    log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
    log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
else
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

die() {
    log_error "$*"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: measure-compact-headers.sh [measure] --world PATH [options]
       measure-compact-headers.sh check-copy --source PATH --dest PATH
       measure-compact-headers.sh summarize --work DIR [--output FILE]
       measure-compact-headers.sh parse-heap < heap-tool-output

Runs Paper twice on independent copies of a world: once with the current
flags, once with COMPACT_OBJECT_HEADERS=true. The flag stays off in
scripts/jvm-opts.sh unless that variable is set. This script does not enable
it for the live server.

The server directory is always a fresh copy. The script refuses if the work
directory overlaps the original world, if the copy is a symlink or hardlink
back to the original, or if a Paper process started from server/ still has
that world open.

Options (measure):
  --world PATH             World directory to copy (must contain level.dat)
  --work-dir PATH          Where copies and logs go
                           (default: .compact-headers-measure/<timestamp>)
  --paper-jar PATH         Paper jar (default: server/paper.jar)
  --warmup SECONDS         Idle time after "Done" before the soak (default: 120)
  --soak SECONDS           Sampling window after warmup (default: 180)
  --sample-interval SECONDS
                           Heap sample period during the soak (default: 15)
  --min-ram SIZE           Same -Xms for both runs (default: 4G)
  --max-ram SIZE           Same -Xmx for both runs (default: 4G)
  --gc g1gc|zgc            Passed through to jvm-opts.sh (default: g1gc)
  --view-distance N        Same for both runs (default: 10)
  --simulation-distance N  Same for both runs (default: 10)
  --port PORT              Listen port, bound to 127.0.0.1 (default: 25566)
  --startup-timeout SECONDS
                           Wait for Paper to print Done (default: 600)
  --shutdown-timeout SECONDS
                           Wait after the console stop command (default: 120)

Environment:
  JAVA_CMD, JCMD_CMD, JSTAT_CMD, SERVER_DIR
  MEASURE_AFTER_COPY_HOOK  Test seam. Command invoked as:
                           hook DEST SOURCE
                           after each copy and before the safety check.

Exit status:
  0  comparison written (see verdict.txt: ACCEPT, REJECT, or INCONCLUSIVE)
  1  refused, or the server did not finish a run

Acceptance (also written into the summary):
  smaller heap after warmup and a lower soak high-water,
  GC pause max and p99 no worse, TPS no worse, MSPT no worse.
  ACCEPT is evidence only. It does not turn the flag on.
EOF
}

normalize_path() {
    local path="$1"
    local old_ifs=$IFS
    local noglob=0
    local part=""
    local stack=""
    case $- in
        *f*) noglob=1 ;;
    esac
    if [[ "$path" != /* ]]; then
        path="$(pwd)/$path"
    fi
    set -f
    IFS=/
    for part in $path; do
        case "$part" in
            ""|.) ;;
            ..) stack="${stack%/*}" ;;
            *) stack="${stack}/${part}" ;;
        esac
    done
    IFS=$old_ifs
    if [[ "$noglob" -eq 0 ]]; then
        set +f
    fi
    if [[ -z "$stack" ]]; then
        stack=/
    fi
    printf '%s\n' "$stack"
}

resolve_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Not a directory: $dir" >&2
        return 1
    fi
    (cd "$dir" && pwd -P)
}

planned_physical_path() {
    local path missing="" phys=""
    path=$(normalize_path "$1")
    while [[ ! -d "$path" ]]; do
        if [[ "$path" == "/" ]]; then
            break
        fi
        missing="/$(basename "$path")${missing}"
        path=$(dirname "$path")
    done
    phys=$(resolve_dir "$path")
    printf '%s%s\n' "$phys" "$missing"
}

inode_of() {
    local out=""
    if out=$(stat -c '%d:%i' "$1" 2>/dev/null); then
        printf '%s\n' "$out"
        return 0
    fi
    stat -f '%d:%i' "$1"
}

# 0 when the two paths are the same or either contains the other.
paths_conflict() {
    local a="$1"
    local b="$2"
    if [[ -z "$a" || -z "$b" ]]; then
        return 1
    fi
    if [[ "$a" == "$b" || "$a" == "/" || "$b" == "/" ]]; then
        return 0
    fi
    case "$a/" in
        "$b"/*) return 0 ;;
    esac
    case "$b/" in
        "$a"/*) return 0 ;;
    esac
    return 1
}

file_checksum() {
    local target="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$target"
    else
        sha256sum "$target"
    fi
}

require_int() {
    local name="$1"
    local value="$2"
    local min="$3"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt "$min" ]]; then
        die "${name} must be an integer >= ${min} (got ${value})"
    fi
}

resolve_link_target() {
    local link="$1"
    local target="" parent="" base="" parent_phys=""
    target=$(readlink "$link") || return 1
    if [[ "$target" != /* ]]; then
        target="$(dirname "$link")/$target"
    fi
    if [[ -d "$target" ]]; then
        (cd "$target" && pwd -P)
        return 0
    fi
    parent=$(dirname "$target")
    base=$(basename "$target")
    if [[ -d "$parent" ]]; then
        parent_phys=$(cd "$parent" && pwd -P)
        printf '%s\n' "${parent_phys}/${base}"
        return 0
    fi
    normalize_path "$target"
}

# Refuse anything that would make the server read or write the original world.
check_copy() {
    local source="$1"
    local dest="$2"
    local source_phys="" dest_phys="" source_inode="" dest_inode=""
    local link="" resolved="" file="" ino="" match="" match_ino=""

    if [[ ! -d "$source" || ! -f "$source/level.dat" ]]; then
        echo "refusing to use the original world: source is not a world directory ($source)" >&2
        return 1
    fi
    if [[ -L "$dest" ]]; then
        echo "refusing to use the original world: server world is a symlink ($dest)" >&2
        return 1
    fi
    if [[ ! -d "$dest" || ! -f "$dest/level.dat" || -L "$dest/level.dat" ]]; then
        echo "refusing to use the original world: copy is missing a real level.dat ($dest)" >&2
        return 1
    fi

    source_phys=$(resolve_dir "$source")
    dest_phys=$(resolve_dir "$dest")
    if paths_conflict "$source_phys" "$dest_phys"; then
        echo "refusing to use the original world: copy path ${dest_phys} overlaps ${source_phys}" >&2
        return 1
    fi

    source_inode=$(inode_of "$source/level.dat")
    dest_inode=$(inode_of "$dest/level.dat")
    if [[ "$source_inode" == "$dest_inode" ]]; then
        echo "refusing to use the original world: level.dat is the same file (hardlink or same path)" >&2
        return 1
    fi

    while IFS= read -r link; do
        [[ -n "$link" ]] || continue
        resolved=$(resolve_link_target "$link" || true)
        if [[ -z "$resolved" ]]; then
            continue
        fi
        if [[ -d "$resolved" ]]; then
            resolved=$(resolve_dir "$resolved")
        fi
        if paths_conflict "$resolved" "$source_phys"; then
            echo "refusing to use the original world: symlink ${link} points at ${resolved}" >&2
            return 1
        fi
    done < <(find "$dest" -type l -print)

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        ino=$(inode_of "$file")
        match=""
        while IFS= read -r candidate; do
            match=$candidate
            break
        done < <(find "$source" -inum "${ino#*:}" -print 2>/dev/null)
        if [[ -n "$match" ]]; then
            match_ino=$(inode_of "$match")
            if [[ "$match_ino" == "$ino" ]]; then
                echo "refusing to use the original world: ${file} is a hardlink to ${match}" >&2
                return 1
            fi
        fi
    done < <(find "$dest" -type f -links +1 -print)

    return 0
}

parse_heap_kb() {
    awk '
        function to_kb(token,    n, u, rest) {
            if (!match(token, /[0-9]+(\.[0-9]+)?/)) {
                return ""
            }
            n = substr(token, RSTART, RLENGTH)
            rest = substr(token, RSTART + RLENGTH)
            u = substr(rest, 1, 1)
            if (u == "M" || u == "m") return n * 1024
            if (u == "G" || u == "g") return n * 1024 * 1024
            if (u == "B" || u == "b") return n / 1024
            return n
        }
        BEGIN { jcmd = "" }
        {
            lower = tolower($0)
            if (jcmd == "" && lower ~ /heap/ && lower !~ /metaspace/ &&
                match($0, /used[[:space:]]+[0-9]+(\.[0-9]+)?[KkMmGgBb]?/)) {
                token = substr($0, RSTART, RLENGTH)
                jcmd = to_kb(token)
            }
            if (NR == 1) {
                for (i = 1; i <= NF; i++) {
                    header[$i] = i
                }
            }
            if (NR == 2 && ("S0U" in header) && ("S1U" in header) &&
                ("EU" in header) && ("OU" in header)) {
                jstat = $(header["S0U"]) + $(header["S1U"]) + $(header["EU"]) + $(header["OU"])
            }
        }
        END {
            if (jcmd != "") {
                printf "%.0f\n", jcmd
                exit 0
            }
            if (jstat != "") {
                printf "%.0f\n", jstat
                exit 0
            }
            exit 1
        }
    '
}

last_gc_uptime() {
    local log="$1"
    [[ -f "$log" ]] || return 1
    awk '
        {
            rest = $0
            while (match(rest, /\[[0-9]+(\.[0-9]+)?s\]/)) {
                last = substr(rest, RSTART + 1, RLENGTH - 3)
                rest = substr(rest, RSTART + RLENGTH)
            }
        }
        END {
            if (last == "") exit 1
            print last
        }
    ' "$log"
}

pause_values() {
    local log="$1"
    local min_uptime="$2"
    [[ -f "$log" ]] || return 0
    awk -v min_uptime="$min_uptime" '
        {
            uptime = ""
            rest = $0
            if (match(rest, /\[[0-9]+(\.[0-9]+)?s\]/)) {
                uptime = substr(rest, RSTART + 1, RLENGTH - 3)
            }
            if (uptime == "" || uptime + 0 <= min_uptime + 0) next
            if ($0 !~ /Pause/) next
            value = ""
            rest = $0
            while (match(rest, /[0-9]+(\.[0-9]+)?ms/)) {
                value = substr(rest, RSTART, RLENGTH - 2)
                rest = substr(rest, RSTART + RLENGTH)
            }
            if (value != "") print value
        }
    ' "$log"
}

percentile_value() {
    local percentile="$1"
    local file="$2"
    local n="" rank=""
    n=$(wc -l < "$file" | tr -d ' ')
    [[ "$n" -gt 0 ]] || return 1
    rank=$(awk -v p="$percentile" -v n="$n" 'BEGIN {
        x = p * n / 100
        r = int(x)
        if (x > r) r++
        if (r < 1) r = 1
        if (r > n) r = n
        print r
    }')
    sort -n "$file" | awk -v rank="$rank" 'NR == rank { print }'
}

max_value() {
    local file="$1"
    awk 'BEGIN { m = -1 } NF { if ($1 + 0 > m) m = $1 + 0 } END { if (m < 0) exit 1; printf "%.3f\n", m }' "$file"
}

parse_tps_1m() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    awk '
        /TPS from last 1m, 5m, 15m:/ {
            line = $0
            sub(/^.*TPS from last 1m, 5m, 15m:/, "", line)
            if (match(line, /[0-9]+([.][0-9]+|[,][0-9]+)?|\*/)) {
                last = substr(line, RSTART, RLENGTH)
            }
        }
        END {
            if (last == "" || last ~ /\*/) exit 1
            gsub(/,/, ".", last)
            if (last !~ /^[0-9]+(\.[0-9]+)?$/) exit 1
            print last
        }
    ' "$file"
}

parse_mspt_1m() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    awk '
        function triplet_avg(s,    num) {
            if (match(s, /[0-9]+([.][0-9]+|[,][0-9]+)?/)) {
                num = substr(s, RSTART, RLENGTH)
                gsub(/,/, ".", num)
                return num
            }
            return ""
        }
        {
            is_header = ($0 ~ /Server tick times/)
            rest = $0
            count = 0
            while (match(rest, /[0-9]+([.][0-9]+|[,][0-9]+)?\/[0-9]+([.][0-9]+|[,][0-9]+)?\/[0-9]+([.][0-9]+|[,][0-9]+)?/)) {
                count++
                trips[count] = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
            }
            labeled = ""
            # The header names the 1m column and must not be treated as a sample.
            if (!is_header && count >= 1 && $0 ~ /(^|[^0-9A-Za-z])1m([^0-9A-Za-z]|$)/) {
                labeled = triplet_avg(trips[1])
            }
            if (is_header) {
                in_block = 1
                block_lines = 0
                block_count = 0
                block_labeled = ""
            }
            if (in_block) {
                block_lines++
                for (i = 1; i <= count; i++) {
                    block_count++
                    block_trips[block_count] = trips[i]
                }
                if (labeled != "") block_labeled = labeled
                if (block_labeled != "" || block_count >= 3 || block_lines >= 5) {
                    if (block_labeled != "") {
                        last = block_labeled
                    } else if (block_count >= 3) {
                        last = triplet_avg(block_trips[3])
                    }
                    in_block = 0
                }
            }
        }
        END {
            if (last == "") exit 1
            print last
        }
    ' "$file"
}

heap_first() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    awk 'NF { printf "%.0f\n", $1; exit }' "$file"
}

heap_high_water() {
    local file="$1"
    [[ -s "$file" ]] || return 1
    awk 'BEGIN { m = -1 } NF { if ($1 + 0 > m) m = $1 + 0 } END { if (m < 0) exit 1; printf "%.0f\n", m }' "$file"
}

kb_to_mb() {
    awk -v kb="$1" 'BEGIN { printf "%.1f", kb / 1024 }'
}

percent_delta() {
    awk -v b="$1" -v c="$2" 'BEGIN {
        if (b + 0 == 0) { printf "n/a"; exit }
        printf "%+.1f%%", (c - b) / b * 100
    }'
}

float_ge_tol() {
    awk -v c="$1" -v b="$2" -v tol="$3" 'BEGIN { exit !((c + tol) >= b) }'
}

float_le_tol() {
    awk -v c="$1" -v b="$2" -v tol="$3" 'BEGIN { exit !(c <= (b + tol)) }'
}

float_lt() {
    awk -v c="$1" -v b="$2" 'BEGIN { exit !(c + 0 < b + 0) }'
}

read_log_metric() {
    local parser="$1"
    local run_dir="$2"
    local value=""
    if [[ -f "$run_dir/logs/latest.log" ]]; then
        value=$("$parser" "$run_dir/logs/latest.log" 2>/dev/null || true)
    fi
    if [[ -z "$value" && -f "$run_dir/stdout.log" ]]; then
        value=$("$parser" "$run_dir/stdout.log" 2>/dev/null || true)
    fi
    printf '%s\n' "$value"
}

read_run_env() {
    local file="$1"
    local line="" key="" value=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        key=${line%%=*}
        value=${line#*=}
        case "$key" in
            WORLD_NAME) WORLD_NAME=$value ;;
            WORLD_SIZE_KB) WORLD_SIZE_KB=$value ;;
            JAVA_VERSION) JAVA_VERSION_TEXT=$value ;;
            WARMUP_SECONDS) WARMUP_SECONDS=$value ;;
            SOAK_SECONDS) SOAK_SECONDS=$value ;;
            MIN_RAM) MIN_RAM=$value ;;
            MAX_RAM) MAX_RAM=$value ;;
            GC_TYPE) GC_TYPE=$value ;;
            VIEW_DISTANCE) VIEW_DISTANCE=$value ;;
            SIMULATION_DISTANCE) SIMULATION_DISTANCE=$value ;;
            SERVER_PORT) SERVER_PORT=$value ;;
            SOURCE_PATH) SOURCE_PATH=$value ;;
        esac
    done < "$file"
}

cmd_summarize() {
    local work="" output=""
    local baseline="" compact=""
    local b_heap="" c_heap="" b_high="" c_high=""
    local b_mark="" c_mark="" b_pauses="" c_pauses=""
    local b_pause_max="" c_pause_max="" b_p99="" c_p99=""
    local b_pause_n="" c_pause_n=""
    local b_tps="" c_tps="" b_mspt="" c_mspt=""
    local verdict="ACCEPT"
    local reasons=""
    local heap_tol_note=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --work)
                work=$2
                shift 2
                ;;
            --output)
                output=$2
                shift 2
                ;;
            *)
                die "Unknown summarize argument: $1"
                ;;
        esac
    done
    [[ -n "$work" && -d "$work/baseline" && -d "$work/compact" ]] || die "summarize needs --work with baseline/ and compact/"
    output=${output:-$work/summary.md}
    baseline=$work/baseline
    compact=$work/compact

    WORLD_NAME=""
    WORLD_SIZE_KB=""
    JAVA_VERSION_TEXT=""
    WARMUP_SECONDS=""
    SOAK_SECONDS=""
    MIN_RAM=""
    MAX_RAM=""
    GC_TYPE=""
    VIEW_DISTANCE=""
    SIMULATION_DISTANCE=""
    SERVER_PORT=""
    SOURCE_PATH=""
    read_run_env "$work/run.env"

    b_heap=$(heap_first "$baseline/heap-samples.txt" || true)
    c_heap=$(heap_first "$compact/heap-samples.txt" || true)
    b_high=$(heap_high_water "$baseline/heap-samples.txt" || true)
    c_high=$(heap_high_water "$compact/heap-samples.txt" || true)

    b_mark=$(awk 'NF { print; exit }' "$baseline/warmup-uptime.txt" 2>/dev/null || true)
    c_mark=$(awk 'NF { print; exit }' "$compact/warmup-uptime.txt" 2>/dev/null || true)
    [[ -n "$b_mark" ]] || b_mark=0
    [[ -n "$c_mark" ]] || c_mark=0

    b_pauses=$(mktemp)
    c_pauses=$(mktemp)
    pause_values "$baseline/gc.log" "$b_mark" > "$b_pauses"
    pause_values "$compact/gc.log" "$c_mark" > "$c_pauses"
    b_pause_n=$(wc -l < "$b_pauses" | tr -d ' ')
    c_pause_n=$(wc -l < "$c_pauses" | tr -d ' ')
    if [[ "$b_pause_n" -gt 0 ]]; then
        b_pause_max=$(max_value "$b_pauses")
        b_p99=$(percentile_value 99 "$b_pauses")
    else
        b_pause_max=0
        b_p99=0
    fi
    if [[ "$c_pause_n" -gt 0 ]]; then
        c_pause_max=$(max_value "$c_pauses")
        c_p99=$(percentile_value 99 "$c_pauses")
    else
        c_pause_max=0
        c_p99=0
    fi

    b_tps=$(read_log_metric parse_tps_1m "$baseline")
    c_tps=$(read_log_metric parse_tps_1m "$compact")
    b_mspt=$(read_log_metric parse_mspt_1m "$baseline")
    c_mspt=$(read_log_metric parse_mspt_1m "$compact")

    if [[ -z "$b_heap" || -z "$c_heap" || -z "$b_high" || -z "$c_high" ]]; then
        verdict=INCONCLUSIVE
        reasons="${reasons}Heap samples are missing (jcmd GC.heap_info or jstat -gc)."$'\n'
    elif ! float_lt "$c_heap" "$b_heap" || ! float_lt "$c_high" "$b_high"; then
        verdict=REJECT
        reasons="${reasons}Heap is not smaller on both the post-warmup sample and the soak high-water."$'\n'
    fi

    if [[ -z "$b_pause_max" || -z "$c_pause_max" || -z "$b_p99" || -z "$c_p99" ]]; then
        verdict=INCONCLUSIVE
        reasons="${reasons}GC pause stats are missing."$'\n'
    elif ! float_le_tol "$c_pause_max" "$b_pause_max" 0 || ! float_le_tol "$c_p99" "$b_p99" 0; then
        verdict=REJECT
        reasons="${reasons}GC pauses are worse (max or p99)."$'\n'
    fi

    if [[ -z "$b_tps" || -z "$c_tps" ]]; then
        verdict=INCONCLUSIVE
        reasons="${reasons}Paper 1m TPS is missing. The server must be up long enough for /tps to print a number, not *."$'\n'
    elif ! float_ge_tol "$c_tps" "$b_tps" 0.05; then
        verdict=REJECT
        reasons="${reasons}TPS is worse."$'\n'
    fi

    if [[ -z "$b_mspt" || -z "$c_mspt" ]]; then
        verdict=INCONCLUSIVE
        reasons="${reasons}Paper 1m MSPT is missing from /mspt."$'\n'
    elif ! float_le_tol "$c_mspt" "$b_mspt" 0.05; then
        verdict=REJECT
        reasons="${reasons}MSPT is worse. TPS can stay at 20 while ticks get slower, so MSPT is part of the TPS check."$'\n'
    fi

    if [[ "$verdict" == "ACCEPT" && -n "$b_high" && -n "$c_high" ]]; then
        heap_tol_note=$(awk -v b="$b_high" -v c="$c_high" 'BEGIN {
            if (b + 0 == 0) exit
            drop = (b - c) / b * 100
            if (drop < 1) print "The high-water drop is under 1%. Repeat the run before treating it as a real win."
        }')
        if [[ -n "$heap_tol_note" ]]; then
            reasons="${reasons}${heap_tol_note}"$'\n'
        fi
    fi

    {
        echo "# Compact object headers"
        echo
        echo "World: ${WORLD_NAME:-unknown}"
        echo
        echo "Source: ${SOURCE_PATH:-unknown}"
        echo
        echo "World size: ${WORLD_SIZE_KB:-unknown} KB"
        echo
        echo "Java: ${JAVA_VERSION_TEXT:-unknown}"
        echo
        echo "Heap: -Xms${MIN_RAM:-unknown} -Xmx${MAX_RAM:-unknown} (${GC_TYPE:-unknown})"
        echo
        echo "Warmup: ${WARMUP_SECONDS:-unknown}s, soak: ${SOAK_SECONDS:-unknown}s, view-distance: ${VIEW_DISTANCE:-unknown}, simulation-distance: ${SIMULATION_DISTANCE:-unknown}, port: ${SERVER_PORT:-unknown}"
        echo
        echo "Both runs use scripts/jvm-opts.sh. The compact run is the only one with COMPACT_OBJECT_HEADERS=true. GC logs add the same -Xlog:gc* options, with a different file path per run. HeapDumpPath differs per run directory."
        echo
        echo "## Flags"
        echo
        echo "Baseline:"
        echo
        echo '```'
        if [[ -f "$baseline/flags.txt" ]]; then
            cat "$baseline/flags.txt"
        else
            echo "(missing flags.txt)"
        fi
        echo '```'
        echo
        echo "Compact:"
        echo
        echo '```'
        if [[ -f "$compact/flags.txt" ]]; then
            cat "$compact/flags.txt"
        else
            echo "(missing flags.txt)"
        fi
        echo '```'
        echo
        echo "## Results"
        echo
        echo "| Metric | Baseline | Compact | Delta | Gate |"
        echo "| --- | --- | --- | --- | --- |"
        if [[ -n "$b_heap" && -n "$c_heap" ]]; then
            echo "| Heap used after warmup (MB) | $(kb_to_mb "$b_heap") | $(kb_to_mb "$c_heap") | $(percent_delta "$b_heap" "$c_heap") | lower |"
        else
            echo "| Heap used after warmup (MB) | ${b_heap:-missing} | ${c_heap:-missing} |  | lower |"
        fi
        if [[ -n "$b_high" && -n "$c_high" ]]; then
            echo "| Heap high-water during soak (MB) | $(kb_to_mb "$b_high") | $(kb_to_mb "$c_high") | $(percent_delta "$b_high" "$c_high") | lower |"
        else
            echo "| Heap high-water during soak (MB) | ${b_high:-missing} | ${c_high:-missing} |  | lower |"
        fi
        echo "| GC pauses in soak (count) | ${b_pause_n} | ${c_pause_n} |  |  |"
        echo "| GC pause max (ms) | ${b_pause_max} | ${c_pause_max} | $(percent_delta "$b_pause_max" "$c_pause_max") | no worse |"
        echo "| GC pause p99 (ms) | ${b_p99} | ${c_p99} | $(percent_delta "$b_p99" "$c_p99") | no worse |"
        echo "| TPS 1m | ${b_tps:-missing} | ${c_tps:-missing} |  | no worse |"
        echo "| MSPT 1m avg | ${b_mspt:-missing} | ${c_mspt:-missing} |  | no worse |"
        echo
        echo "## Verdict"
        echo
        echo "Verdict: ${verdict}"
        echo
        echo "Enable the flag in scripts/jvm-opts.sh and in the Compose JVM_XX_OPTS only if the copy shows a smaller heap and pauses and TPS are no worse. MSPT is included because TPS is capped at 20. Equal pauses, TPS, and MSPT count as no worse. A missing number is inconclusive. This run does not change the default; the flag stays off unless COMPACT_OBJECT_HEADERS is set."
        echo
        if [[ -n "$reasons" ]]; then
            echo "Notes:"
            echo
            printf '%s\n' "$reasons"
        fi
        if [[ "$verdict" == "ACCEPT" ]]; then
            echo "The copy passed. Leave the default off until a follow-up records these numbers and turns the opt-in into the default."
        elif [[ "$verdict" == "REJECT" ]]; then
            echo "Leave the flag out. Record this summary on the measurement issue."
        else
            echo "Do not enable the flag. Capture the missing metric and run the comparison again."
        fi
    } > "$output"

    printf '%s\n' "$verdict" > "$work/verdict.txt"
    rm -f "$b_pauses" "$c_pauses"
    log_info "Wrote ${output}"
    log_info "Verdict: ${verdict}"
}

server_is_running() {
    local server_dir="$1"
    local pid_file="${server_dir}/server.pid"
    local pid="" args=""
    [[ -s "$pid_file" ]] || return 1
    pid=$(tr -d '[:space:]' < "$pid_file")
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    args=$(ps -p "$pid" -o args= 2>/dev/null || true)
    [[ "$args" == *"paper.jar"* ]]
}

java_major_version() {
    local raw="" major=""
    raw=$("$JAVA_CMD" -version 2>&1 | head -n 1 || true)
    major=$(printf '%s\n' "$raw" | cut -d'"' -f2 | cut -d. -f1)
    printf '%s\n' "$major"
}

sample_heap_kb() {
    local pid="$1"
    local variant="$2"
    local out="" kb=""
    local jcmd="${JCMD_CMD:-jcmd}"
    local jstat="${JSTAT_CMD:-jstat}"

    if [[ -x "$jcmd" ]] || command -v "$jcmd" >/dev/null 2>&1; then
        out=$(MEASURE_VARIANT="$variant" "$jcmd" "$pid" GC.heap_info 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out" >> "$HEAP_RAW"
            kb=$(printf '%s\n' "$out" | parse_heap_kb || true)
            if [[ "$kb" =~ ^[0-9]+$ ]]; then
                printf '%s\n' "$kb"
                return 0
            fi
        fi
    fi
    if [[ -x "$jstat" ]] || command -v "$jstat" >/dev/null 2>&1; then
        out=$("$jstat" -gc "$pid" 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out" >> "$HEAP_RAW"
            kb=$(printf '%s\n' "$out" | parse_heap_kb || true)
            if [[ "$kb" =~ ^[0-9]+$ ]]; then
                printf '%s\n' "$kb"
                return 0
            fi
        fi
    fi
    return 1
}

write_server_properties() {
    local file="$1"
    local port="$2"
    local view="$3"
    local simulation="$4"
    cat > "$file" <<EOF
server-ip=127.0.0.1
server-port=${port}
online-mode=false
enable-rcon=false
enable-query=false
enable-status=false
level-name=world
level-type=minecraft:normal
gamemode=survival
difficulty=peaceful
spawn-monsters=false
spawn-protection=0
allow-flight=true
pvp=false
max-players=1
view-distance=${view}
simulation-distance=${simulation}
pause-when-empty-seconds=-1
max-tick-time=-1
sync-chunk-writes=true
enforce-secure-profile=false
initial-enabled-packs=vanilla,bundle
motd=compact-headers-measure
EOF
}

# shellcheck disable=SC2317,SC2329
stop_measured_server() {
    local pid="${JAVA_PID:-}"
    local holder="${HOLDER_PID:-}"
    local fifo="${FIFO_PATH:-}"
    local writer=""
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        if [[ -n "$fifo" && -p "$fifo" ]]; then
            printf 'stop\n' > "$fifo" &
            writer=$!
            sleep 1
            kill "$writer" 2>/dev/null || true
            wait "$writer" 2>/dev/null || true
        fi
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    fi
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        kill "$holder" 2>/dev/null || true
        wait "$holder" 2>/dev/null || true
    fi
}

assert_work_is_safe() {
    local source_phys="$1"
    local work_phys="$2"
    local server_dir="$3"
    local server_phys=""
    if paths_conflict "$source_phys" "$work_phys"; then
        die "refusing to use the original world: work directory ${work_phys} overlaps ${source_phys}"
    fi
    if [[ -d "$server_dir" ]]; then
        server_phys=$(resolve_dir "$server_dir")
        if [[ "$work_phys" == "$server_phys" ]]; then
            die "refusing to use the original world: work directory is the live server directory ${server_phys}"
        fi
    fi
}

run_variant() {
    local variant="$1"
    local work="$2"
    local source_phys="$3"
    local paper_jar="$4"
    local warmup="$5"
    local soak="$6"
    local sample_interval="$7"
    local view="$8"
    local simulation="$9"
    local port="${10}"
    local startup_timeout="${11}"
    local shutdown_timeout="${12}"
    local run="${work}/${variant}"
    local dest="${run}/world"
    local flags_file="${run}/flags.txt"
    local dump="${run}/dumps"
    local compact_value="false"
    local start_epoch="" mark="" deadline="" now="" remain="" nap=""
    local kb="" log_file=""
    local flag=""

    if [[ "$variant" == "compact" ]]; then
        compact_value="true"
    elif [[ "$variant" != "baseline" ]]; then
        die "Unknown variant: ${variant}"
    fi

    log_info "Preparing ${variant} copy at ${dest}"
    mkdir -p "$dest" "$dump" "$run/plugins"
    cp -a "${source_phys}/." "$dest/"
    if [[ -n "${MEASURE_AFTER_COPY_HOOK:-}" ]]; then
        "$MEASURE_AFTER_COPY_HOOK" "$dest" "$source_phys"
    fi
    if ! check_copy "$source_phys" "$dest"; then
        die "refusing to start the server because the ${variant} world is not a safe copy"
    fi

    write_server_properties "$run/server.properties" "$port" "$view" "$simulation"
    if ! grep -q '^level-name=world$' "$run/server.properties"; then
        die "refusing to start: level-name is not world"
    fi
    printf 'eula=true\n' > "$run/eula.txt"
    if [[ -L "$paper_jar" || -f "$paper_jar" ]]; then
        ln -sfn "$paper_jar" "$run/paper.jar"
    else
        die "Paper jar is not a file: ${paper_jar}"
    fi

    COMPACT_OBJECT_HEADERS="$compact_value" \
        HEAP_DUMP_PATH="$dump" \
        MEMORY_MODE=fixed \
        GC_TYPE="$GC_TYPE" \
        MIN_RAM="$MIN_RAM" \
        MAX_RAM="$MAX_RAM" \
        "$JVM_OPTS_SH" > "$flags_file"

    if [[ "$variant" == "baseline" ]]; then
        if grep -F -q -- 'UseCompactObjectHeaders' "$flags_file"; then
            die "baseline flags include UseCompactObjectHeaders"
        fi
    else
        if ! grep -F -x -q -- '-XX:+UseCompactObjectHeaders' "$flags_file"; then
            die "compact flags are missing -XX:+UseCompactObjectHeaders"
        fi
    fi

    # Not local: bash 3.2 on macOS mishandles local arrays, and the server
    # subshell has to see this copy.
    server_flags=()
    while IFS= read -r flag; do
        [[ -n "$flag" ]] || continue
        server_flags+=("$flag")
    done < "$flags_file"
    server_flags+=("-Xlog:gc*:file=${run}/gc.log:time,uptime,level,tags:filecount=1,filesize=64M")

    {
        printf '%q ' "$JAVA_CMD" "${server_flags[@]}" -jar "$run/paper.jar" --nogui
        printf '\n'
    } > "$run/command.txt"

    if ! check_copy "$source_phys" "$dest"; then
        die "refusing to start the server because the ${variant} world is not a safe copy"
    fi

    FIFO_PATH="${run}/console.fifo"
    rm -f "$FIFO_PATH"
    mkfifo "$FIFO_PATH"
    sleep 86400 > "$FIFO_PATH" &
    HOLDER_PID=$!
    JAVA_PID=""

    log_info "Starting ${variant} server"
    (
        cd "$run"
        # shellcheck disable=SC2093
        exec env -u COMPACT_OBJECT_HEADERS "$JAVA_CMD" "${server_flags[@]}" -jar "$run/paper.jar" --nogui
    ) < "$FIFO_PATH" > "$run/stdout.log" 2> "$run/stderr.log" &
    JAVA_PID=$!
    printf '%s\n' "$JAVA_PID" > "$run/server.pid"
    start_epoch=$(date +%s)

    deadline=$((start_epoch + startup_timeout))
    while true; do
        if [[ -f "$run/logs/latest.log" ]] && grep -q 'Done (' "$run/logs/latest.log"; then
            break
        fi
        if [[ -f "$run/stdout.log" ]] && grep -q 'Done (' "$run/stdout.log"; then
            break
        fi
        if ! kill -0 "$JAVA_PID" 2>/dev/null; then
            log_error "Server exited during startup. stdout and stderr follow."
            tail -n 40 "$run/stdout.log" "$run/stderr.log" "$run/logs/latest.log" 2>/dev/null || true
            if grep -Eq 'Address already in use|Failed to bind' "$run/stdout.log" "$run/stderr.log" "$run/logs/latest.log" 2>/dev/null; then
                die "port ${port} is already in use. Re-run with --port set to a free port."
            fi
            die "${variant} server exited during startup"
        fi
        now=$(date +%s)
        if [[ "$now" -ge "$deadline" ]]; then
            tail -n 40 "$run/stdout.log" "$run/stderr.log" "$run/logs/latest.log" 2>/dev/null || true
            die "${variant} server did not reach Done within ${startup_timeout}s"
        fi
        sleep 1
    done

    log_info "${variant} is up. Warming up for ${warmup}s"
    sleep "$warmup"
    mark=$(last_gc_uptime "$run/gc.log" || true)
    if [[ -z "$mark" ]]; then
        mark=$(( $(date +%s) - start_epoch ))
    fi
    printf '%s\n' "$mark" > "$run/warmup-uptime.txt"

    HEAP_RAW="${run}/heap-raw.txt"
    : > "$HEAP_RAW"
    : > "$run/heap-samples.txt"
    log_info "${variant} soak for ${soak}s"
    kb=$(sample_heap_kb "$JAVA_PID" "$variant" || true)
    if [[ -n "$kb" ]]; then
        printf '%s\n' "$kb" >> "$run/heap-samples.txt"
    fi
    deadline=$(( $(date +%s) + soak ))
    while true; do
        now=$(date +%s)
        if [[ "$now" -ge "$deadline" ]]; then
            break
        fi
        remain=$((deadline - now))
        nap=$sample_interval
        if [[ "$nap" -gt "$remain" ]]; then
            nap=$remain
        fi
        sleep "$nap"
        if ! kill -0 "$JAVA_PID" 2>/dev/null; then
            die "${variant} server exited during the soak"
        fi
        kb=$(sample_heap_kb "$JAVA_PID" "$variant" || true)
        if [[ -n "$kb" ]]; then
            printf '%s\n' "$kb" >> "$run/heap-samples.txt"
        fi
    done

    log_info "Requesting tps and mspt from ${variant}"
    if ! kill -0 "$JAVA_PID" 2>/dev/null; then
        die "${variant} server is not running"
    fi
    printf 'tps\n' > "$FIFO_PATH"
    sleep 1
    printf 'mspt\n' > "$FIFO_PATH"
    sleep 1
    printf 'stop\n' > "$FIFO_PATH"

    deadline=$(( $(date +%s) + shutdown_timeout ))
    while kill -0 "$JAVA_PID" 2>/dev/null; do
        now=$(date +%s)
        if [[ "$now" -ge "$deadline" ]]; then
            log_warn "${variant} did not stop after the console stop command. Sending SIGTERM."
            kill -TERM "$JAVA_PID" 2>/dev/null || true
            sleep 2
            if kill -0 "$JAVA_PID" 2>/dev/null; then
                kill -KILL "$JAVA_PID" 2>/dev/null || true
            fi
            break
        fi
        sleep 1
    done
    set +e
    wait "$JAVA_PID"
    set -e
    JAVA_PID=""
    if [[ -n "$HOLDER_PID" ]] && kill -0 "$HOLDER_PID" 2>/dev/null; then
        kill "$HOLDER_PID" 2>/dev/null || true
        wait "$HOLDER_PID" 2>/dev/null || true
    fi
    HOLDER_PID=""
    FIFO_PATH=""

    if [[ -f "$run/logs/latest.log" ]]; then
        tail -n 40 "$run/logs/latest.log" > "$run/commands-excerpt.log" || true
    fi
    log_file=$(resolve_dir "$dest")
    if [[ "$log_file" == "$source_phys" ]]; then
        die "refusing to continue: ${variant} server directory resolved to the original world"
    fi
}

cmd_measure() {
    local world=""
    local work=""
    local paper_jar=""
    local warmup="${WARMUP_SECONDS:-120}"
    local soak="${SOAK_SECONDS:-180}"
    local sample_interval="${SAMPLE_INTERVAL:-15}"
    local view="${VIEW_DISTANCE:-10}"
    local simulation="${SIMULATION_DISTANCE:-10}"
    local port="${SERVER_PORT:-25566}"
    local startup_timeout="${STARTUP_TIMEOUT:-600}"
    local shutdown_timeout="${SHUTDOWN_TIMEOUT:-120}"
    local source_phys="" work_phys="" server_dir="" server_phys="" size_kb="" available="" needed=""
    local checksum_before="" checksum_after="" java_major="" java_version_line=""
    local stamp=""

    MIN_RAM="${MIN_RAM:-4G}"
    MAX_RAM="${MAX_RAM:-4G}"
    GC_TYPE="${GC_TYPE:-g1gc}"
    JAVA_CMD="${JAVA_CMD:-java}"
    SERVER_DIR="${SERVER_DIR:-${REPO_ROOT}/server}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --world)
                world=$2
                shift 2
                ;;
            --work-dir)
                work=$2
                shift 2
                ;;
            --paper-jar)
                paper_jar=$2
                shift 2
                ;;
            --warmup)
                warmup=$2
                shift 2
                ;;
            --soak)
                soak=$2
                shift 2
                ;;
            --sample-interval)
                sample_interval=$2
                shift 2
                ;;
            --min-ram)
                MIN_RAM=$2
                shift 2
                ;;
            --max-ram)
                MAX_RAM=$2
                shift 2
                ;;
            --gc)
                GC_TYPE=$2
                shift 2
                ;;
            --view-distance)
                view=$2
                shift 2
                ;;
            --simulation-distance)
                simulation=$2
                shift 2
                ;;
            --port)
                port=$2
                shift 2
                ;;
            --startup-timeout)
                startup_timeout=$2
                shift 2
                ;;
            --shutdown-timeout)
                shutdown_timeout=$2
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done

    [[ -n "$world" ]] || die "measure requires --world PATH"
    [[ -d "$world" ]] || die "World directory does not exist: ${world}"
    [[ -f "$world/level.dat" ]] || die "World has no level.dat: ${world}"
    require_int warmup "$warmup" 1
    require_int soak "$soak" 1
    require_int sample_interval "$sample_interval" 1
    require_int view "$view" 1
    require_int simulation "$simulation" 1
    require_int port "$port" 1
    require_int startup_timeout "$startup_timeout" 1
    require_int shutdown_timeout "$shutdown_timeout" 1
    if [[ "$port" -gt 65535 || "$view" -gt 32 || "$simulation" -gt 32 ]]; then
        die "port must be <= 65535 and view/simulation distance must be <= 32"
    fi

    source_phys=$(resolve_dir "$world")
    if [[ -z "$work" ]]; then
        stamp=$(date -u +%Y%m%dT%H%M%SZ)
        work="${REPO_ROOT}/.compact-headers-measure/${stamp}"
    fi
    work_phys=$(planned_physical_path "$work")
    server_dir="$SERVER_DIR"
    # Refuse before creating directories or touching the jar, so a bad path
    # cannot write inside the original world.
    assert_work_is_safe "$source_phys" "$work_phys" "$server_dir"

    if server_is_running "$server_dir"; then
        server_phys=$(resolve_dir "$server_dir")
        if paths_conflict "$source_phys" "$server_phys"; then
            die "refusing to use the original world while Paper is running (pid $(tr -d '[:space:]' < "${server_dir}/server.pid")). Stop the server so the copy is not taken from an open world."
        fi
    fi

    if [[ -z "$paper_jar" ]]; then
        paper_jar="${SERVER_DIR}/paper.jar"
    fi
    if [[ "$paper_jar" != /* ]]; then
        paper_jar="$(pwd)/$paper_jar"
    fi
    paper_jar=$(normalize_path "$paper_jar")
    [[ -f "$paper_jar" ]] || die "Paper jar not found at ${paper_jar}. Run ./scripts/update-paper.sh or pass --paper-jar."
    [[ -s "$paper_jar" ]] || die "Paper jar is empty: ${paper_jar}"

    mkdir -p "$work_phys"
    work_phys=$(resolve_dir "$work_phys")
    assert_work_is_safe "$source_phys" "$work_phys" "$server_dir"
    if [[ -d "$work_phys/baseline" || -d "$work_phys/compact" ]]; then
        die "work directory already has baseline/ or compact/: ${work_phys}"
    fi

    size_kb=$(du -sk "$source_phys" | awk '{ print $1 }')
    available=$(df -Pk "$work_phys" | awk 'NR == 2 { print $4 }')
    if [[ "$size_kb" =~ ^[0-9]+$ && "$available" =~ ^[0-9]+$ ]]; then
        needed=$((size_kb * 22 / 10))
        if [[ "$available" -lt "$needed" ]]; then
            die "Not enough free disk for two world copies. Need about ${needed} KB on $(df -Pk "$work_phys" | awk 'NR == 2 { print $6 }'), have ${available} KB."
        fi
    fi

    if [[ -f "${source_phys}/session.lock" ]]; then
        log_warn "session.lock is present in the original world. Stop any server that has this world open before trusting the copy."
    fi

    if [[ ! -x "$JAVA_CMD" ]] && ! command -v "$JAVA_CMD" >/dev/null 2>&1; then
        die "Java not found (${JAVA_CMD}). Paper 26.3 needs Java 25."
    fi
    java_version_line=$("$JAVA_CMD" -version 2>&1 | head -n 1 || true)
    java_major=$(java_major_version)
    if [[ ! "$java_major" =~ ^[0-9]+$ ]] || [[ "$java_major" -lt 25 ]]; then
        die "Java 25 or later is required. Found: ${java_version_line:-unknown}"
    fi

    checksum_before=$(file_checksum "${source_phys}/level.dat")
    log_info "Original world ${source_phys} (${size_kb} KB) will not be the server directory."
    log_info "Copies and logs: ${work_phys}"

    {
        printf 'WORLD_NAME=%s\n' "$(basename "$source_phys")"
        printf 'WORLD_SIZE_KB=%s\n' "$size_kb"
        printf 'JAVA_VERSION=%s\n' "$java_version_line"
        printf 'WARMUP_SECONDS=%s\n' "$warmup"
        printf 'SOAK_SECONDS=%s\n' "$soak"
        printf 'MIN_RAM=%s\n' "$MIN_RAM"
        printf 'MAX_RAM=%s\n' "$MAX_RAM"
        printf 'GC_TYPE=%s\n' "$GC_TYPE"
        printf 'VIEW_DISTANCE=%s\n' "$view"
        printf 'SIMULATION_DISTANCE=%s\n' "$simulation"
        printf 'SERVER_PORT=%s\n' "$port"
        printf 'SOURCE_PATH=%s\n' "$source_phys"
    } > "$work_phys/run.env"

    JAVA_PID=""
    HOLDER_PID=""
    FIFO_PATH=""
    trap stop_measured_server EXIT

    run_variant baseline "$work_phys" "$source_phys" "$paper_jar" \
        "$warmup" "$soak" "$sample_interval" "$view" "$simulation" "$port" \
        "$startup_timeout" "$shutdown_timeout"
    run_variant compact "$work_phys" "$source_phys" "$paper_jar" \
        "$warmup" "$soak" "$sample_interval" "$view" "$simulation" "$port" \
        "$startup_timeout" "$shutdown_timeout"

    checksum_after=$(file_checksum "${source_phys}/level.dat")
    if [[ "$checksum_before" != "$checksum_after" ]]; then
        die "refusing to accept the result: the original world level.dat changed"
    fi

    trap - EXIT
    cmd_summarize --work "$work_phys"
    case "${work_phys}/" in
        "${REPO_ROOT}/.compact-headers-measure/"*)
            ln -sfn "$work_phys" "${REPO_ROOT}/.compact-headers-measure/latest"
            ;;
    esac
    echo
    cat "$work_phys/summary.md"
    echo
    log_info "Summary: ${work_phys}/summary.md"
    log_info "Verdict file: ${work_phys}/verdict.txt"
}

cmd_check_copy() {
    local source="" dest=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source)
                source=$2
                shift 2
                ;;
            --dest)
                dest=$2
                shift 2
                ;;
            *)
                die "Unknown check-copy argument: $1"
                ;;
        esac
    done
    [[ -n "$source" && -n "$dest" ]] || die "check-copy requires --source and --dest"
    if check_copy "$source" "$dest"; then
        echo "copy is safe"
        exit 0
    fi
    exit 1
}

main() {
    local command="measure"
    if [[ $# -gt 0 ]]; then
        case "$1" in
            measure|check-copy|summarize|parse-heap)
                command=$1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
        esac
    fi
    case "$command" in
        measure) cmd_measure "$@" ;;
        check-copy) cmd_check_copy "$@" ;;
        summarize) cmd_summarize "$@" ;;
        parse-heap) parse_heap_kb ;;
        *)
            die "Unknown command: ${command}"
            ;;
    esac
}

main "$@"
