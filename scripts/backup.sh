#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/../backups}"
MAX_BACKUPS="${MAX_BACKUPS:-10}"

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

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="minecraft-backup-${TIMESTAMP}.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if world directories exist
cd "$SERVER_DIR"

WORLDS=()
for world in world world_nether world_the_end; do
    if [[ -d "$world" ]]; then
        WORLDS+=("$world")
    fi
done

if [[ ${#WORLDS[@]} -eq 0 ]]; then
    log_error "No world directories found to backup"
    exit 1
fi

log_info "Found ${#WORLDS[@]} world(s) to backup: ${WORLDS[*]}"

# Optional: Notify server about backup (if RCON is available)
RCON_PASSWORD="${RCON_PASSWORD:-changeme}"
if command -v mcrcon &> /dev/null; then
    log_step "Notifying server and saving worlds..."
    mcrcon -H localhost -P 25575 -p "$RCON_PASSWORD" "say Backup starting..." || true
    mcrcon -H localhost -P 25575 -p "$RCON_PASSWORD" "save-all" || true
    mcrcon -H localhost -P 25575 -p "$RCON_PASSWORD" "save-off" || true
    sleep 2
fi

# Create backup
log_step "Creating backup: ${BACKUP_NAME}"
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}" "${WORLDS[@]}"

# Re-enable saving if RCON was used
if command -v mcrcon &> /dev/null; then
    mcrcon -H localhost -P 25575 -p "$RCON_PASSWORD" "save-on" || true
    mcrcon -H localhost -P 25575 -p "$RCON_PASSWORD" "say Backup complete!" || true
fi

# Calculate backup size
SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
log_info "Backup created: ${BACKUP_DIR}/${BACKUP_NAME} (${SIZE})"

# Cleanup old backups
log_step "Cleaning up old backups (keeping last ${MAX_BACKUPS})..."
cd "$BACKUP_DIR"
BACKUP_COUNT=$(ls -1 minecraft-backup-*.tar.gz 2>/dev/null | wc -l)

if [[ $BACKUP_COUNT -gt $MAX_BACKUPS ]]; then
    DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
    ls -1t minecraft-backup-*.tar.gz | tail -n "$DELETE_COUNT" | xargs rm -f
    log_info "Removed ${DELETE_COUNT} old backup(s)"
fi

log_info "Backup complete!"
