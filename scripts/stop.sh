#!/usr/bin/env bash
set -euo pipefail

# Configuration
RCON_HOST="${RCON_HOST:-localhost}"
RCON_PORT="${RCON_PORT:-25575}"
RCON_PASSWORD="${RCON_PASSWORD:-changeme}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if mcrcon is available
if command -v mcrcon &> /dev/null; then
    log_info "Sending stop command via RCON..."
    mcrcon -H "$RCON_HOST" -P "$RCON_PORT" -p "$RCON_PASSWORD" "stop"
    log_info "Stop command sent. Server is shutting down..."
    exit 0
fi

# Fallback: Try using Python rcon library
if command -v python3 &> /dev/null; then
    log_info "Attempting to stop via Python RCON..."
    python3 << EOF
import socket
import struct

def rcon_command(host, port, password, command):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect((host, port))

        # Login
        payload = password.encode('utf-8') + b'\x00\x00'
        packet = struct.pack('<III', len(payload) + 10, 0, 3) + payload
        sock.send(packet)
        response = sock.recv(4096)

        # Send command
        payload = command.encode('utf-8') + b'\x00\x00'
        packet = struct.pack('<III', len(payload) + 10, 1, 2) + payload
        sock.send(packet)

        print("Stop command sent successfully")
    except Exception as e:
        print(f"Error: {e}")
        return False
    finally:
        sock.close()
    return True

rcon_command("$RCON_HOST", $RCON_PORT, "$RCON_PASSWORD", "stop")
EOF
    exit 0
fi

# Final fallback: Direct signal if process can be found
log_warn "RCON tools not available. Attempting to find server process..."

PID=$(pgrep -f "paper.jar" || true)
if [[ -n "$PID" ]]; then
    log_info "Found server process (PID: $PID). Sending SIGTERM..."
    kill -TERM "$PID"
    log_info "Signal sent. Server should shut down gracefully."
else
    log_error "Could not find running server process."
    log_info "Install mcrcon for proper RCON support: brew install mcrcon (macOS) or your package manager"
    exit 1
fi
