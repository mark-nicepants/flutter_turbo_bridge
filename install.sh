#!/bin/bash
# Flutter Turbo Bridge — One-line installer
# Usage: curl -fsSL https://raw.githubusercontent.com/mark-nicepants/flutter_turbo_bridge/main/install.sh | bash
#
# What this does:
# 1. Installs the MCP server globally from pub.dev
# 2. Prints MCP config you can paste into your AI tool

set -e

echo "🚀 Installing Flutter Turbo Bridge..."
echo ""

# Check prerequisites
if ! command -v dart &> /dev/null; then
    echo "❌ Dart SDK not found. Install Flutter first: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "📦 Installing turbo_bridge_mcp from pub.dev..."
dart pub global activate turbo_bridge_mcp > /dev/null

echo ""
echo "✅ Installation complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Step 1: Add turbo_bridge to your Flutter app:"
echo ""
echo "   flutter pub add turbo_bridge"
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
echo '         "command": "turbo_bridge_mcp"'
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "   VS Code (.vscode/mcp.json):"
echo '   {'
echo '     "servers": {'
echo '       "flutter": {'
echo '         "command": "turbo_bridge_mcp"'
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If your MCP host does not inherit the Dart pub cache bin path, use the"
echo "absolute executable path printed by 'dart pub global activate turbo_bridge_mcp'."
echo ""
echo "📋 Step 3: Run your Flutter app, then ask the AI:"
echo '   "Take a screenshot and tell me what you see"'
echo ""
