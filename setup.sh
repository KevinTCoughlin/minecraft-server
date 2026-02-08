#!/usr/bin/env bash
# One-click Minecraft server setup
# Designed for Eclipse Temurin (Eclipse Foundation's OpenJDK)
#
# This script:
# - Verifies Java 21+ installation (Eclipse Temurin recommended)
# - Downloads latest PaperMC server
# - Accepts EULA
# - Prepares server for first run
#
# Usage: ./setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_step() { echo -e "${BLUE}▶${NC} $1"; }

echo "🎮 Minecraft Server Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Java
log_step "Checking Java installation..."
if ! command -v java &>/dev/null; then
    log_error "Java not found. Install Java 21+:"
    echo ""
    echo "  macOS:   brew install --cask temurin21"
    echo "  Linux:   apt install temurin-21-jdk"
    echo "  Windows: Download from https://adoptium.net/"
    echo ""
    echo "Eclipse Temurin (Eclipse Foundation's OpenJDK) is recommended."
    exit 1
fi

JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
JAVA_VENDOR=$(java -version 2>&1 | grep -i "runtime" || echo "")

if [[ "$JAVA_VER" -lt 21 ]]; then
    log_error "Java 21+ required (found Java $JAVA_VER)"
    echo "  Please upgrade to Eclipse Temurin 21: https://adoptium.net/"
    exit 1
fi

log_info "Java $JAVA_VER detected"
if echo "$JAVA_VENDOR" | grep -qi "temurin\|eclipse"; then
    log_info "Using Eclipse Temurin ✨"
else
    log_warn "Detected non-Temurin JVM. Eclipse Temurin is recommended."
fi

echo ""

# Download PaperMC
log_step "Downloading PaperMC server..."
./scripts/update-paper.sh

echo ""

# Accept EULA
if [[ ! -f server/eula.txt ]] || ! grep -q "eula=true" server/eula.txt; then
    log_step "Accepting Minecraft EULA..."
    echo "eula=true" > server/eula.txt
    log_info "EULA accepted"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Quick Start:"
echo "  Start server:  ./scripts/start.sh"
echo "  Stop server:   ./scripts/stop.sh"
echo "  Backup world:  ./scripts/backup.sh"
echo ""
echo "Connect to:  localhost:25565"
echo ""
echo "Note: First run takes ~30 seconds to generate world."
echo "      Built with Eclipse Temurin OpenJDK for optimal performance."
echo ""
