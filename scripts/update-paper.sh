#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
MC_VERSION="${MC_VERSION:-1.21.4}"
JAR_NAME="paper.jar"

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

log_info "Fetching latest PaperMC build for Minecraft ${MC_VERSION}..."

# Get available versions
log_step "Checking available versions..."
VERSIONS=$(curl -s "${API_URL}" | grep -o '"versions":\[[^]]*\]' | grep -o '"[0-9.]*"' | tr -d '"')

if ! echo "$VERSIONS" | grep -q "^${MC_VERSION}$"; then
    log_error "Version ${MC_VERSION} not found. Available versions:"
    echo "$VERSIONS" | tail -10
    exit 1
fi

# Get latest build for this version
log_step "Finding latest build..."
VERSION_INFO=$(curl -s "${API_URL}/versions/${MC_VERSION}")
LATEST_BUILD=$(echo "$VERSION_INFO" | grep -o '"builds":\[[^]]*\]' | grep -o '[0-9]*' | tail -1)

if [[ -z "$LATEST_BUILD" ]]; then
    log_error "Could not find builds for version ${MC_VERSION}"
    exit 1
fi

log_info "Latest build: ${LATEST_BUILD}"

# Get download info
BUILD_INFO=$(curl -s "${API_URL}/versions/${MC_VERSION}/builds/${LATEST_BUILD}")
DOWNLOAD_NAME=$(echo "$BUILD_INFO" | grep -o '"name":"paper-[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$DOWNLOAD_NAME" ]]; then
    log_error "Could not determine download filename"
    exit 1
fi

DOWNLOAD_URL="${API_URL}/versions/${MC_VERSION}/builds/${LATEST_BUILD}/downloads/${DOWNLOAD_NAME}"

# Create server directory if needed
mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

# Backup existing jar if present
if [[ -f "$JAR_NAME" ]]; then
    BACKUP_NAME="paper-backup-$(date +%Y%m%d-%H%M%S).jar"
    log_info "Backing up existing JAR to ${BACKUP_NAME}"
    mv "$JAR_NAME" "$BACKUP_NAME"
fi

# Download new jar
log_step "Downloading ${DOWNLOAD_NAME}..."
curl -L -o "$JAR_NAME" "$DOWNLOAD_URL"

# Verify download
if [[ -f "$JAR_NAME" ]] && [[ -s "$JAR_NAME" ]]; then
    SIZE=$(du -h "$JAR_NAME" | cut -f1)
    log_info "Successfully downloaded PaperMC ${MC_VERSION} build ${LATEST_BUILD} (${SIZE})"
else
    log_error "Download failed or file is empty"
    exit 1
fi

log_info "Paper JAR is ready at: ${SERVER_DIR}/${JAR_NAME}"
