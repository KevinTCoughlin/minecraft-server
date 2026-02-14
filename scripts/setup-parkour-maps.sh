#!/usr/bin/env bash
#
# setup-parkour-maps.sh - Download and install curated parkour maps
#
# Idempotent: skips maps that already exist in the server directory.
# Downloads from hielkemaps.com and configures for Paper/Multiverse.
#
# Usage: ./scripts/setup-parkour-maps.sh [--dry-run]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-changeme}"
DRY_RUN="${1:-}"

# =============================================================================
# Map Catalog
# =============================================================================
# Each map: folder name, download URL, spawn coordinates (x y z)
# Spawn coords are approximate centers; players land on the starting platform.

MAP_NAMES=(
    "parkour-spiral"
    "parkour-spiral-3"
    "parkour-volcano"
    "parkour-pyramid"
    "parkour-paradise"
)

MAP_URLS=(
    "https://hielkemaps.com/downloads/Parkour Spiral.zip"
    "https://hielkemaps.com/downloads/Parkour Spiral 3.zip"
    "https://hielkemaps.com/downloads/Parkour Volcano.zip"
    "https://hielkemaps.com/downloads/Parkour Pyramid.zip"
    "https://hielkemaps.com/downloads/Parkour Paradise.zip"
)

# Display names for the zip's inner folder (what Hielke zips contain)
MAP_ZIP_FOLDERS=(
    "Parkour Spiral"
    "Parkour Spiral 3"
    "Parkour Volcano"
    "Parkour Pyramid"
    "Parkour Paradise"
)

# =============================================================================
# Helpers
# =============================================================================
log() { echo "[$(date '+%H:%M:%S')] $*"; }

rcon_cmd() {
    if command -v mcrcon &>/dev/null; then
        mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "$1" 2>/dev/null || true
    else
        log "WARN: mcrcon not found, skipping RCON command: $1"
    fi
}

is_server_running() {
    tmux has-session -t "minecraft-server" 2>/dev/null
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Parkour map setup starting..."
    log "Server dir: $SERVER_DIR"

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "DRY RUN - no files will be modified"
    fi

    # Ensure server directory exists
    [[ -d "$SERVER_DIR" ]] || { log "ERROR: Server directory not found: $SERVER_DIR"; exit 1; }

    # Reference paper-world.yml for parkour worlds
    local paper_world_src="$SERVER_DIR/parkour/paper-world.yml"
    if [[ ! -f "$paper_world_src" ]]; then
        log "WARN: $paper_world_src not found, new maps won't get paper-world.yml"
        paper_world_src=""
    fi

    local installed=0
    local skipped=0

    for i in "${!MAP_NAMES[@]}"; do
        local name="${MAP_NAMES[$i]}"
        local url="${MAP_URLS[$i]}"
        local zip_folder="${MAP_ZIP_FOLDERS[$i]}"
        local dest="$SERVER_DIR/$name"

        if [[ -d "$dest" ]]; then
            log "SKIP: $name (already exists)"
            ((skipped++))
            continue
        fi

        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            log "WOULD INSTALL: $name from $url"
            continue
        fi

        log "INSTALLING: $name"

        # Download to temp directory
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        trap "rm -rf '$tmp_dir'" EXIT

        log "  Downloading from $url..."
        if ! curl -fSL -o "$tmp_dir/map.zip" "$url"; then
            log "  ERROR: Download failed for $name, skipping"
            rm -rf "$tmp_dir"
            continue
        fi

        # Extract
        log "  Extracting..."
        unzip -q "$tmp_dir/map.zip" -d "$tmp_dir/extracted"

        # Find the world folder (contains level.dat)
        local world_dir=""
        world_dir="$(find "$tmp_dir/extracted" -name "level.dat" -print -quit 2>/dev/null)"
        if [[ -z "$world_dir" ]]; then
            log "  ERROR: No level.dat found in zip for $name, skipping"
            rm -rf "$tmp_dir"
            continue
        fi
        world_dir="$(dirname "$world_dir")"

        # Move to server directory
        log "  Installing to $dest..."
        mv "$world_dir" "$dest"

        # Copy paper-world.yml (disable mobs/weather for parkour)
        if [[ -n "$paper_world_src" ]]; then
            cp "$paper_world_src" "$dest/paper-world.yml"
            log "  Copied paper-world.yml"
        fi

        # Import into Multiverse if server is running
        if is_server_running; then
            log "  Importing into Multiverse..."
            rcon_cmd "mv import $name normal"
            sleep 2
        else
            log "  Server not running; import with: mv import $name normal"
        fi

        rm -rf "$tmp_dir"
        trap - EXIT
        ((installed++))
        log "  Done: $name"
    done

    echo ""
    log "Setup complete: $installed installed, $skipped skipped"
    log "Available parkour maps: ${MAP_NAMES[*]}"

    if ! is_server_running; then
        echo ""
        log "Server is not running. After starting, import new maps with:"
        for name in "${MAP_NAMES[@]}"; do
            if [[ ! -d "$SERVER_DIR/$name" ]] || [[ "$DRY_RUN" == "--dry-run" ]]; then
                continue
            fi
        done
        log "  (maps will be auto-imported by Multiverse on next startup if configured)"
    fi
}

main
