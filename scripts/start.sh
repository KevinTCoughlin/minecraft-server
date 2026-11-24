#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
JAR_NAME="paper.jar"
PID_FILE="${SERVER_DIR}/server.pid"
MIN_RAM="${MIN_RAM:-4G}"
MAX_RAM="${MAX_RAM:-4G}"
GC_TYPE="${GC_TYPE:-g1gc}"  # g1gc or zgc

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$SERVER_DIR"

if [[ -s "$PID_FILE" ]]; then
    EXISTING_PID=$(<"$PID_FILE")
    if [[ "$EXISTING_PID" =~ ^[0-9]+$ ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
        log_error "Server is already running with PID ${EXISTING_PID}."
        exit 1
    fi
    rm -f "$PID_FILE"
fi

# Check if paper.jar exists
if [[ ! -f "$JAR_NAME" ]]; then
    log_warn "Paper JAR not found. Downloading..."
    "${SCRIPT_DIR}/update-paper.sh"
fi

# Accept EULA
if [[ ! -f "eula.txt" ]] || ! grep -q "eula=true" eula.txt; then
    log_info "Accepting EULA..."
    echo "eula=true" > eula.txt
fi

# Determine java command (respect JAVA_HOME if set)
if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    JAVA_CMD="$JAVA_HOME/bin/java"
else
    JAVA_CMD="java"
fi

# Paper 26.x needs Java 25. Java 21 is accepted only for an explicitly tracked older line.
# A missing version file follows update-paper.sh and downloads 26.3.
REQUIRED_JAVA=25
if [[ -s ".paper-version" ]]; then
    TRACKED_MC=$(<".paper-version")
    TRACKED_MC="${TRACKED_MC%%-*}"
    case "$TRACKED_MC" in
        26.*) REQUIRED_JAVA=25 ;;
        *) REQUIRED_JAVA=21 ;;
    esac
fi

# Check Java version
if ! command -v "$JAVA_CMD" &> /dev/null; then
    log_error "Java not found. Please install Java ${REQUIRED_JAVA} or later."
    exit 1
fi

JAVA_VERSION=$("$JAVA_CMD" -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
if [[ "$JAVA_VERSION" -lt "$REQUIRED_JAVA" ]]; then
    log_error "Java ${REQUIRED_JAVA} or later is required. Found Java $JAVA_VERSION"
    exit 1
fi

log_info "Using Java $JAVA_VERSION ($JAVA_CMD)"

# Host starts use a fixed heap (MIN_RAM/MAX_RAM, or MEMORY when it is set).
# Container starts (docker/entrypoint.sh) use a percentage of the limit, or a
# safe default heap when the container has no limit.
MEMORY_MODE="${MEMORY_MODE:-fixed}"
HEAP_DUMP_PATH="${HEAP_DUMP_PATH:-${SERVER_DIR}/dumps}"
mkdir -p "$HEAP_DUMP_PATH"

# Container mode with no limit prints its own banner from jvm-opts.sh.
# A fixed host start with no MEMORY knob still announces MIN_RAM and MAX_RAM.
if [[ "$MEMORY_MODE" == "fixed" && -z "${MEMORY:-}" ]]; then
    log_info "Starting PaperMC server with ${MIN_RAM} - ${MAX_RAM} RAM, GC: ${GC_TYPE^^}..."
else
    log_info "Starting PaperMC server, GC: ${GC_TYPE^^}..."
fi

export MEMORY_MODE HEAP_DUMP_PATH GC_TYPE MIN_RAM MAX_RAM
MAX_RAM_PERCENTAGE="${MAX_RAM_PERCENTAGE:-75.0}"
INITIAL_RAM_PERCENTAGE="${INITIAL_RAM_PERCENTAGE:-$MAX_RAM_PERCENTAGE}"
export MAX_RAM_PERCENTAGE INITIAL_RAM_PERCENTAGE

flags_file=$(mktemp)
if ! "${SCRIPT_DIR}/jvm-opts.sh" > "$flags_file"; then
    log_error "Failed to build JVM flags"
    rm -f "$flags_file"
    exit 1
fi
JVM_FLAGS=()
while IFS= read -r flag; do
    JVM_FLAGS+=("$flag")
done < "$flags_file"
rm -f "$flags_file"

if [[ ${#JVM_FLAGS[@]} -eq 0 ]]; then
    log_error "No JVM flags produced"
    exit 1
fi

echo "$$" > "$PID_FILE"
exec "$JAVA_CMD" "${JVM_FLAGS[@]}" -jar "$JAR_NAME" --nogui
