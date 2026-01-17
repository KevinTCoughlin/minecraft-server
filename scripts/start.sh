#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
JAR_NAME="paper.jar"
MIN_RAM="${MIN_RAM:-2G}"
MAX_RAM="${MAX_RAM:-4G}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cd "$SERVER_DIR"

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

# Check Java version
if ! command -v java &> /dev/null; then
    log_error "Java not found. Please install Java 21 or later."
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
if [[ "$JAVA_VERSION" -lt 21 ]]; then
    log_error "Java 21 or later is required. Found Java $JAVA_VERSION"
    exit 1
fi

log_info "Starting PaperMC server with ${MIN_RAM} - ${MAX_RAM} RAM..."

# Optimized JVM flags for Minecraft (Aikar's flags)
# See: https://docs.papermc.io/paper/aikars-flags
exec java \
    -Xms${MIN_RAM} \
    -Xmx${MAX_RAM} \
    -XX:+UseG1GC \
    -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch \
    -XX:G1NewSizePercent=30 \
    -XX:G1MaxNewSizePercent=40 \
    -XX:G1HeapRegionSize=8M \
    -XX:G1ReservePercent=20 \
    -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 \
    -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem \
    -XX:MaxTenuringThreshold=1 \
    -Dusing.aikars.flags=https://mcflags.emc.gs \
    -Daikars.new.flags=true \
    -jar "$JAR_NAME" \
    --nogui
