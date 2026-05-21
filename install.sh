#!/bin/bash
# Flutter Turbo Bridge — One-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/mark-nicepants/flutter_turbo_bridge/main/install.sh | bash
#
# What this does:
# 1. Clones the repo to ~/.turbo-bridge
# 2. Resolves dependencies
# 3. Prints MCP config you can paste into your AI tool

set -e

INSTALL_DIR="$HOME/.turbo-bridge"
REPO_URL="https://github.com/mark-nicepants/flutter_turbo_bridge.git"

echo "🚀 Installing Flutter Turbo Bridge..."
echo ""

# Check prerequisites
if ! command -v dart &> /dev/null; then
    echo "❌ Dart SDK not found. Install Flutter first: https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
    echo "📦 Updating existing installation..."
    cd "$INSTALL_DIR" && git pull --quiet
else
    echo "📦 Cloning repository..."
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# Resolve dependencies for the MCP server
echo "📦 Resolving dependencies..."
cd "$INSTALL_DIR/packages/turbo_bridge_mcp"
dart pub get --no-precompile > /dev/null 2>&1

MCP_PATH="$INSTALL_DIR/packages/turbo_bridge_mcp/bin/turbo_bridge_mcp.dart"

echo ""
echo "✅ Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Step 1: Add turbo_bridge to your Flutter app:"
echo ""
echo "   flutter pub add turbo_bridge \\"
echo "     --git-url=https://github.com/mark-nicepants/flutter_turbo_bridge.git \\"
echo "     --git-path=packages/turbo_bridge"
echo ""
echo "   Then in your main.dart:"
echo ""
echo "     import 'package:turbo_bridge/turbo_bridge.dart';"
echo "     void main() {"
echo "       runApp(const MyApp());"
echo "       TurboBridge.start();"
echo "     }"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Step 2: Add MCP config to your AI tool:"
echo ""
echo "   Claude Desktop (~/.config/claude/claude_desktop_config.json):"
echo '   {'
echo '     "mcpServers": {'
echo '       "flutter": {'
echo '         "command": "dart",'
echo "         \"args\": [\"run\", \"$MCP_PATH\"]"
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "   VS Code (.vscode/mcp.json):"
echo '   {'
echo '     "servers": {'
echo '       "flutter": {'
echo '         "command": "dart",'
echo "         \"args\": [\"run\", \"$MCP_PATH\"]"
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Step 3: Run your Flutter app, then ask the AI:"
echo '   "Take a screenshot and tell me what you see"'
echo ""
