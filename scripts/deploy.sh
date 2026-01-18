#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# Deploy target configuration (override via environment or .env file)
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-$USER}"
DEPLOY_PATH="${DEPLOY_PATH:-~/minecraft-server}"
DEPLOY_PORT="${DEPLOY_PORT:-22}"

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

# Load .env file if present
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading configuration from .env"
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# Validate configuration
if [[ -z "$DEPLOY_HOST" ]]; then
    log_error "DEPLOY_HOST not set. Configure via environment variable or .env file."
    echo ""
    echo "Example .env file:"
    echo "  DEPLOY_HOST=192.168.1.100"
    echo "  DEPLOY_USER=minecraft"
    echo "  DEPLOY_PATH=~/minecraft-server"
    echo ""
    echo "Or set environment variables:"
    echo "  DEPLOY_HOST=myserver.local ./scripts/deploy.sh"
    exit 1
fi

DEPLOY_TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"
log_info "Deploying to ${DEPLOY_TARGET}:${DEPLOY_PATH}"

# Files and directories to sync
INCLUDES=(
    "server/server.properties"
    "server/paper-global.yml"
    "server/paper-world-defaults.yml"
    "server/bukkit.yml"
    "server/spigot.yml"
    "server/plugins/*.jar"
    "scripts/"
    "docker/"
)

# Build rsync include/exclude args
RSYNC_ARGS=(
    -avz
    --progress
    -e "ssh -p ${DEPLOY_PORT}"
    --delete
)

# Excludes
RSYNC_ARGS+=(
    --exclude=".git/"
    --exclude=".gradle/"
    --exclude="build/"
    --exclude="*/build/"
    --exclude="server/*.jar"
    --exclude="!server/plugins/*.jar"
    --exclude="server/world/"
    --exclude="server/world_nether/"
    --exclude="server/world_the_end/"
    --exclude="server/logs/"
    --exclude="server/cache/"
    --exclude="backups/"
    --exclude="*.log"
    --exclude=".env"
    --exclude=".env.local"
)

# Create remote directory
log_step "Ensuring remote directory exists..."
ssh -p "$DEPLOY_PORT" "$DEPLOY_TARGET" "mkdir -p ${DEPLOY_PATH}"

# Sync configuration and scripts
log_step "Syncing configuration files and scripts..."
rsync "${RSYNC_ARGS[@]}" \
    "${PROJECT_DIR}/server/" \
    "${DEPLOY_TARGET}:${DEPLOY_PATH}/server/"

rsync "${RSYNC_ARGS[@]}" \
    "${PROJECT_DIR}/scripts/" \
    "${DEPLOY_TARGET}:${DEPLOY_PATH}/scripts/"

rsync "${RSYNC_ARGS[@]}" \
    "${PROJECT_DIR}/docker/" \
    "${DEPLOY_TARGET}:${DEPLOY_PATH}/docker/"

# Make scripts executable
log_step "Setting permissions..."
ssh -p "$DEPLOY_PORT" "$DEPLOY_TARGET" "chmod +x ${DEPLOY_PATH}/scripts/*.sh"

log_info "Deployment complete!"
echo ""
echo "Next steps on the remote host:"
echo "  1. cd ${DEPLOY_PATH}"
echo "  2. ./scripts/update-paper.sh    # Download Paper JAR"
echo "  3. ./scripts/start.sh           # Start the server"
