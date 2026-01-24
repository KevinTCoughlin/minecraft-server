#!/usr/bin/env bash
# One-click Minecraft server setup for busy dads
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🎮 Setting up Minecraft server..."

# Check Java
if ! command -v java &>/dev/null; then
    echo "❌ Java not found. Install Java 21+:"
    echo "   brew install openjdk@21"
    exit 1
fi

JAVA_VER=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
if [[ "$JAVA_VER" -lt 21 ]]; then
    echo "❌ Java 21+ required (found $JAVA_VER)"
    exit 1
fi

echo "✓ Java $JAVA_VER"

# Download PaperMC
echo "📦 Downloading PaperMC..."
./scripts/update-paper.sh

# Accept EULA
if [[ ! -f server/eula.txt ]] || ! grep -q "eula=true" server/eula.txt; then
    echo "📝 Accepting EULA..."
    echo "eula=true" > server/eula.txt
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start:  ./scripts/start.sh"
echo "To stop:   ./scripts/stop.sh"
echo "Connect:   localhost:25565"
echo ""
echo "First run takes ~30 seconds to generate world."
