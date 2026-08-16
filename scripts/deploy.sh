#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# Deploy target configuration (override via environment or .env file)
DEPLOY_HOST="${DEPLOY_HOST:-}"
DEPLOY_USER="${DEPLOY_USER:-$USER}"
DEPLOY_PATH="${DEPLOY_PATH:-minecraft-server}"
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
    while IFS='=' read -r key value; do
        key="${key%$'\r'}"
        value="${value%$'\r'}"
        [[ -z "$key" || "$key" == \#* ]] && continue
        case "$key" in
            DEPLOY_HOST|DEPLOY_USER|DEPLOY_PATH|DEPLOY_PORT)
                printf -v "$key" '%s' "$value"
                ;;
            *)
                log_warn "Ignoring unsupported .env key: $key"
                ;;
        esac
    done < "$ENV_FILE"
fi

# Validate configuration
if [[ -z "$DEPLOY_HOST" ]]; then
    log_error "DEPLOY_HOST not set. Configure via environment variable or .env file."
    echo ""
    echo "Example .env file:"
    echo "  DEPLOY_HOST=192.168.1.100"
    echo "  DEPLOY_USER=minecraft"
    echo "  DEPLOY_PATH=minecraft-server"
    echo ""
    echo "Or set environment variables:"
    echo "  DEPLOY_HOST=myserver.local ./scripts/deploy.sh"
    exit 1
fi
if [[ ! "$DEPLOY_PORT" =~ ^[0-9]+$ ]] ||
   [[ ! "$DEPLOY_USER" =~ ^[A-Za-z0-9._-]+$ ]] ||
   [[ ! "$DEPLOY_HOST" =~ ^[A-Za-z0-9._-]+$ ]] ||
   [[ ! "$DEPLOY_PATH" =~ ^[A-Za-z0-9_./-]+$ ]]; then
    log_error "Deployment settings contain unsupported characters."
    exit 1
fi

DEPLOY_TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"
log_info "Deploying to ${DEPLOY_TARGET}:${DEPLOY_PATH}"

RSYNC_ARGS=(
    -avz
    --progress
    -e "ssh -p ${DEPLOY_PORT}"
)

SERVER_FILES=(
    "server/server.properties"
    "server/bukkit.yml"
    "server/commands.yml"
    "server/help.yml"
    "server/permissions.yml"
    "server/spigot.yml"
    "server/config/paper-global.yml"
    "server/config/paper-world-defaults.yml"
)

shopt -s nullglob
PLUGIN_JARS=("${PROJECT_DIR}"/server/plugins/*.jar)
shopt -u nullglob

# Create remote directory
log_step "Ensuring remote directory exists..."
printf -v REMOTE_PATH '%q' "$DEPLOY_PATH"
ssh -p "$DEPLOY_PORT" "$DEPLOY_TARGET" "mkdir -p ${REMOTE_PATH}/server/plugins ${REMOTE_PATH}/scripts ${REMOTE_PATH}/docker"

# Sync only tracked configuration and built plugin JARs. Runtime worlds and player
# data are intentionally never deployment inputs.
log_step "Syncing server configuration..."
(
    cd "$PROJECT_DIR"
    rsync "${RSYNC_ARGS[@]}" --relative \
        "${SERVER_FILES[@]}" \
        "${DEPLOY_TARGET}:${DEPLOY_PATH}/"
)

if [[ ${#PLUGIN_JARS[@]} -gt 0 ]]; then
    rsync "${RSYNC_ARGS[@]}" \
        "${PLUGIN_JARS[@]}" \
        "${DEPLOY_TARGET}:${DEPLOY_PATH}/server/plugins/"
else
    log_warn "No plugin JARs found in server/plugins; configuration-only deployment."
fi

rsync "${RSYNC_ARGS[@]}" --delete \
    "${PROJECT_DIR}/scripts/" \
    "${DEPLOY_TARGET}:${DEPLOY_PATH}/scripts/"

rsync "${RSYNC_ARGS[@]}" --delete \
    "${PROJECT_DIR}/docker/" \
    "${DEPLOY_TARGET}:${DEPLOY_PATH}/docker/"

# Make scripts executable
log_step "Setting permissions..."
ssh -p "$DEPLOY_PORT" "$DEPLOY_TARGET" "chmod +x ${REMOTE_PATH}/scripts/*.sh"

log_info "Deployment complete!"
echo ""
echo "Next steps on the remote host:"
echo "  1. cd ${DEPLOY_PATH}"
echo "  2. ./scripts/update-paper.sh    # Download Paper JAR"
echo "  3. ./scripts/start.sh           # Start the server"
