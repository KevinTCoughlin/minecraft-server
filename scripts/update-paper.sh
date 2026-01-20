#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
JAR_NAME="paper.jar"
BACKUP_DIR="${SERVER_DIR}/backups"

# Version options:
#   - "latest"   : Latest stable release (x.y.z format)
#   - "snapshot" : Latest version (may include snapshots/pre-releases)
#   - "1.21.11"  : Specific version
MC_VERSION="${MC_VERSION:-latest}"

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

API_URL="https://api.papermc.io/v2/projects/paper"

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
            echo "  MC_VERSION  Version to download (default: latest)"
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
ALL_VERSIONS=$(curl -s "${API_URL}" | jq -r '.versions[]')

if [[ "$MC_VERSION" == "latest" ]]; then
    # Get latest stable (x.y.z format only)
    MC_VERSION=$(echo "$ALL_VERSIONS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)
    log_info "Resolved 'latest' to ${MC_VERSION}"
elif [[ "$MC_VERSION" == "snapshot" ]]; then
    # Get absolute latest (may include pre-releases)
    MC_VERSION=$(echo "$ALL_VERSIONS" | tail -1)
    log_info "Resolved 'snapshot' to ${MC_VERSION}"
fi

log_info "Fetching PaperMC build for Minecraft ${MC_VERSION}..."

# Verify version exists
VERSIONS=$(echo "$ALL_VERSIONS" | tr '\n' ' ')

if ! echo "$ALL_VERSIONS" | grep -qx "${MC_VERSION}"; then
    log_error "Version ${MC_VERSION} not found. Available versions:"
    echo "$ALL_VERSIONS" | tail -10
    exit 1
fi

# Get latest build for this version
log_step "Finding latest build..."
VERSION_INFO=$(curl -s "${API_URL}/versions/${MC_VERSION}")
LATEST_BUILD=$(echo "$VERSION_INFO" | jq -r '.builds[-1]')

if [[ -z "$LATEST_BUILD" ]] || [[ "$LATEST_BUILD" == "null" ]]; then
    log_error "Could not find builds for version ${MC_VERSION}"
    exit 1
fi

log_info "Latest build: ${LATEST_BUILD}"

# Get download info
BUILD_INFO=$(curl -s "${API_URL}/versions/${MC_VERSION}/builds/${LATEST_BUILD}")
DOWNLOAD_NAME=$(echo "$BUILD_INFO" | jq -r '.downloads.application.name')

if [[ -z "$DOWNLOAD_NAME" ]] || [[ "$DOWNLOAD_NAME" == "null" ]]; then
    log_error "Could not determine download filename"
    exit 1
fi

DOWNLOAD_URL="${API_URL}/versions/${MC_VERSION}/builds/${LATEST_BUILD}/downloads/${DOWNLOAD_NAME}"

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

# Download to temp file first (atomic update)
TEMP_JAR=$(mktemp)
log_step "Downloading ${DOWNLOAD_NAME}..."
if ! curl -L -o "$TEMP_JAR" "$DOWNLOAD_URL"; then
    log_error "Download failed"
    rm -f "$TEMP_JAR"
    exit 1
fi

# Verify download
if [[ ! -s "$TEMP_JAR" ]]; then
    log_error "Downloaded file is empty"
    rm -f "$TEMP_JAR"
    exit 1
fi

# Backup existing jar if present
if [[ -f "$JAR_NAME" ]]; then
    BACKUP_NAME="paper-${CURRENT_BUILD:-unknown}-$(date +%Y%m%d-%H%M%S).jar"
    log_info "Backing up existing JAR to backups/${BACKUP_NAME}"
    mv "$JAR_NAME" "${BACKUP_DIR}/${BACKUP_NAME}"

    # Keep only last 5 backups
    ls -t "${BACKUP_DIR}"/paper-*.jar 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
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

SIZE=$(du -h "$JAR_NAME" | cut -f1)
log_info "Successfully downloaded PaperMC ${MC_VERSION} build ${LATEST_BUILD} (${SIZE})"
log_info "Paper JAR is ready at: ${SERVER_DIR}/${JAR_NAME}"

# Show Java version recommendation
if [[ "$MC_VERSION" =~ ^26\. ]]; then
    log_info "Note: Minecraft ${MC_VERSION} requires Java 25+"
else
    log_info "Note: Minecraft ${MC_VERSION} requires Java 21+"
fi
