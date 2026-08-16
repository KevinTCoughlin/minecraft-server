#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SERVER_DIR:-${SCRIPT_DIR}/../server}"
JAR_NAME="paper.jar"
BACKUP_DIR="${SERVER_DIR}/backups"

# Version options:
#   - "latest"   : Latest stable release
#   - "snapshot" : Latest version (may include snapshots/pre-releases)
#   - "1.21.11"  : Specific version
TRACKED_VERSION=""
if [[ -s "${SERVER_DIR}/.paper-version" ]]; then
    TRACKED_BUILD=$(<"${SERVER_DIR}/.paper-version")
    TRACKED_VERSION="${TRACKED_BUILD%-*}"
fi
MC_VERSION="${MC_VERSION:-${TRACKED_VERSION:-1.21.11}}"

# Hot swap mode: update JAR while server is running (requires restart)
HOT_SWAP="${HOT_SWAP:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

verify_sha256() {
    local expected=$1
    local file=$2
    local actual

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        log_error "SHA-256 verification requires sha256sum or shasum."
        return 1
    fi

    [[ "$actual" == "$expected" ]]
}

API_URL="https://fill.papermc.io/v3"
API_ORIGIN="https://fill.papermc.io"
USER_AGENT="minecraft-server-update/1.0 (https://github.com/KevinTCoughlin/minecraft-server)"

# Parse command line args
while [[ $# -gt 0 ]]; do
    case $1 in
        --version|-v)
            MC_VERSION="$2"
            shift 2
            ;;
        --hot-swap|-H)
            HOT_SWAP="true"
            shift
            ;;
        --latest|-l)
            MC_VERSION="latest"
            shift
            ;;
        --snapshot|-s)
            MC_VERSION="snapshot"
            shift
            ;;
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --version VERSION  Specific MC version (e.g., 1.21.11)"
            echo "  -l, --latest           Latest stable release"
            echo "  -s, --snapshot         Latest version (including snapshots)"
            echo "  -H, --hot-swap         Prepare for hot swap (atomic update)"
            echo "  -h, --help             Show this help"
            echo ""
            echo "Environment variables:"
            echo "  MC_VERSION  Version to download (default: tracked server version)"
            echo "  HOT_SWAP    Enable hot swap mode (default: false)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Resolve version aliases
log_step "Checking available versions..."
PROJECT_JSON=$(curl -fsSL --retry 3 \
    -H "User-Agent: ${USER_AGENT}" "${API_URL}/projects/paper")
ALL_VERSIONS=$(jq -r '.versions[] | .[]' <<< "$PROJECT_JSON")

if [[ -z "$ALL_VERSIONS" ]]; then
    log_error "Paper API returned no versions"
    exit 1
fi

if [[ "$MC_VERSION" == "latest" ]]; then
    MC_VERSION=$(jq -r '
        [.versions[] | .[]
            | select(test("^[0-9]+(\\.[0-9]+){1,2}$"))
            | {version: ., parts: (split(".") | map(tonumber))}]
        | sort_by(.parts)
        | last.version
    ' <<< "$PROJECT_JSON")
    log_info "Resolved 'latest' to ${MC_VERSION}"
elif [[ "$MC_VERSION" == "snapshot" ]]; then
    # Paper returns version families and versions newest-first.
    MC_VERSION=$(jq -r '[.versions[] | .[]] | first' <<< "$PROJECT_JSON")
    log_info "Resolved 'snapshot' to ${MC_VERSION}"
fi

log_info "Fetching PaperMC build for Minecraft ${MC_VERSION}..."

# Verify version exists
if ! grep -qx "${MC_VERSION}" <<< "$ALL_VERSIONS"; then
    log_error "Version ${MC_VERSION} not found. Available versions:"
    tail -10 <<< "$ALL_VERSIONS"
    exit 1
fi

# Get latest build for this version
log_step "Finding latest build..."
BUILDS_JSON=$(curl -fsSL --retry 3 \
    -H "User-Agent: ${USER_AGENT}" \
    "${API_URL}/projects/paper/versions/${MC_VERSION}/builds")
BUILD_INFO=$(jq -cr '
    . as $builds
    | ($builds | map(select(.channel == "STABLE" and .downloads["server:default"] != null)) | max_by(.id)) //
      ($builds | map(select(.downloads["server:default"] != null)) | max_by(.id)) //
      empty
' <<< "$BUILDS_JSON")

if [[ -z "$BUILD_INFO" ]]; then
    log_error "Could not find builds for version ${MC_VERSION}"
    exit 1
fi

LATEST_BUILD=$(jq -r '.id' <<< "$BUILD_INFO")
log_info "Latest build: ${LATEST_BUILD}"

# Get download info
DOWNLOAD_NAME=$(jq -r '.downloads["server:default"].name' <<< "$BUILD_INFO")
DOWNLOAD_URL=$(jq -r '.downloads["server:default"].url' <<< "$BUILD_INFO")
DOWNLOAD_SHA256=$(jq -r '.downloads["server:default"].checksums.sha256' <<< "$BUILD_INFO")

if [[ -z "$DOWNLOAD_NAME" || "$DOWNLOAD_NAME" == "null" ||
      -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ||
      -z "$DOWNLOAD_SHA256" || "$DOWNLOAD_SHA256" == "null" ]]; then
    log_error "Could not determine download metadata"
    exit 1
fi

if [[ "$DOWNLOAD_URL" != http://* && "$DOWNLOAD_URL" != https://* ]]; then
    DOWNLOAD_URL="${API_ORIGIN}${DOWNLOAD_URL}"
fi

# Create directories
mkdir -p "$SERVER_DIR"
mkdir -p "$BACKUP_DIR"
cd "$SERVER_DIR"

# Check current version
CURRENT_BUILD=""
if [[ -f ".paper-version" ]]; then
    CURRENT_BUILD=$(cat .paper-version)
fi

if [[ "$CURRENT_BUILD" == "${MC_VERSION}-${LATEST_BUILD}" ]]; then
    log_info "Already at latest version: ${MC_VERSION} build ${LATEST_BUILD}"
    exit 0
fi

# Download beside the destination so the final rename is atomic.
TEMP_JAR="${SERVER_DIR}/.${JAR_NAME}.download.$$"
cleanup() {
    rm -f "$TEMP_JAR"
}
trap cleanup EXIT

log_step "Downloading ${DOWNLOAD_NAME}..."
if ! curl -fL --retry 3 \
    -H "User-Agent: ${USER_AGENT}" -o "$TEMP_JAR" "$DOWNLOAD_URL"; then
    log_error "Download failed"
    exit 1
fi

# Verify download
if [[ ! -s "$TEMP_JAR" ]] ||
   ! verify_sha256 "$DOWNLOAD_SHA256" "$TEMP_JAR" ||
   ! jar tf "$TEMP_JAR" >/dev/null; then
    log_error "Downloaded file failed checksum or JAR validation"
    exit 1
fi

# Backup existing jar if present
if [[ -f "$JAR_NAME" ]]; then
    BACKUP_NAME="paper-${CURRENT_BUILD:-unknown}-$(date +%Y%m%d-%H%M%S).jar"
    log_info "Backing up existing JAR to backups/${BACKUP_NAME}"
    mv "$JAR_NAME" "${BACKUP_DIR}/${BACKUP_NAME}"

    # Keep only last 5 backups
    OLD_BACKUPS=()
    # Backup names are generated by this script and cannot contain whitespace.
    # shellcheck disable=SC2012
    while IFS= read -r backup; do
        [[ -n "$backup" ]] && OLD_BACKUPS+=("$backup")
    done < <(ls -1t "$BACKUP_DIR"/paper-*.jar 2>/dev/null || true)
    for ((i = 5; i < ${#OLD_BACKUPS[@]}; i++)); do
        rm -f -- "${OLD_BACKUPS[$i]}"
    done
fi

# Atomic move (hot swap safe)
if [[ "$HOT_SWAP" == "true" ]]; then
    log_info "Hot swap mode: preparing atomic update..."
    # Move new JAR into place atomically
    mv "$TEMP_JAR" "$JAR_NAME"
    log_warn "JAR updated. Restart server to apply changes."
else
    mv "$TEMP_JAR" "$JAR_NAME"
fi

# Record version
echo "${MC_VERSION}-${LATEST_BUILD}" > .paper-version
trap - EXIT

SIZE=$(du -h "$JAR_NAME" | cut -f1)
log_info "Successfully downloaded PaperMC ${MC_VERSION} build ${LATEST_BUILD} (${SIZE})"
log_info "Paper JAR is ready at: ${SERVER_DIR}/${JAR_NAME}"

# Show Java version recommendation
if [[ "$MC_VERSION" =~ ^26\. ]]; then
    log_info "Note: Minecraft ${MC_VERSION} requires Java 25+"
else
    log_info "Note: Minecraft ${MC_VERSION} requires Java 21+"
fi
