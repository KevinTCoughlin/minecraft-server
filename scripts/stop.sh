#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/../server"
PID_FILE="${SERVER_DIR}/server.pid"
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ -n "$RCON_PASSWORD" ]] && command -v mcrcon &>/dev/null; then
    log_info "Sending stop command via RCON..."
    if mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "stop"; then
        log_info "Stop command sent."
        exit 0
    fi
    log_warn "RCON stop failed; trying the recorded server process."
fi

if [[ ! -s "$PID_FILE" ]]; then
    log_error "No server PID file found at ${PID_FILE}."
    log_info "Set RCON_PASSWORD to use RCON, or start the server with scripts/start.sh."
    exit 1
fi

PID=$(<"$PID_FILE")
if [[ ! "$PID" =~ ^[0-9]+$ ]] || ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PID_FILE"
    log_error "The recorded server process is not running."
    exit 1
fi

COMMAND=$(ps -p "$PID" -o args= 2>/dev/null || true)
if [[ "$COMMAND" != *"paper.jar"* ]]; then
    log_error "PID ${PID} does not appear to be the Paper server; refusing to signal it."
    exit 1
fi

log_info "Sending SIGTERM to Paper server PID ${PID}..."
kill -TERM "$PID"
rm -f "$PID_FILE"
log_info "Signal sent. The server is shutting down gracefully."
