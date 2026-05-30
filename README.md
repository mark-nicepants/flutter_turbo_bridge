# Flutter Turbo Bridge

Ultra-fast bridge between AI agents and Flutter apps. Enables LLMs to see, understand, and interact with running Flutter applications in real-time.

**One-line install:**

```bash
curl -fsSL https://raw.githubusercontent.com/mark-nicepants/flutter_turbo_bridge/main/install.sh | bash
```

```
┌──────────────┐     stdio      ┌──────────────────┐    HTTP     ┌────────────────┐
│   LLM Host   │◄──────────────►│ turbo_bridge_mcp │◄───────────►│  Flutter App   │
│  (Claude,    │                │  (MCP server)    │   :8888     │  + turbo_bridge│
│   Cursor)    │                └──────────────────┘             └────────────────┘
└──────────────┘                         │
                                         │ uses
                                         ▼
                                ┌──────────────────┐
                                │turbo_bridge_client│
                                │  (Dart library)  │
                                └──────────────────┘
```

## What Can AI Do With This?

- **See the app** — capture screenshots as PNG in <20ms
- **Understand the UI** — inspect the widget tree with layout bounds, or focus on a smaller subtree around screen coordinates
- **Find widgets** — server-side search by text, key, or type with coordinates
- **Interact** — tap, swipe, scroll, and enter text
- **Query state** — get app metadata, screen size, current route, platform info

## Packages

| Package | Description | Audience |
|---------|-------------|----------|
| [`turbo_bridge`](packages/turbo_bridge/) | In-app HTTP server for Flutter | Flutter developers |
| [`turbo_bridge_client`](packages/turbo_bridge_client/) | Pure Dart client library | Tool/CI builders |
| [`turbo_bridge_mcp`](packages/turbo_bridge_mcp/) | MCP server for LLM integration | AI/LLM developers |

## Quick Start (3 Steps)

### 1. Add the bridge to your Flutter app

```bash
# From your Flutter project root:
flutter pub add turbo_bridge --git-url=https://github.com/mark-nicepants/flutter_turbo_bridge.git --git-path=packages/turbo_bridge
```

Then start the bridge in your `main.dart`:

```dart
import 'package:turbo_bridge/turbo_bridge.dart';

void main() {
  runApp(const MyApp());
  TurboBridge.start(); // Starts HTTP server on port 8888
}
```

### 2. Connect your AI agent

Add to `.vscode/mcp.json` (committable to version control):

```json
{
  "servers": {
    "flutter": {
      "command": "dart",
      "args": ["run", "packages/turbo_bridge_mcp/bin/turbo_bridge_mcp.dart"]
    }
  }
}
```

Or for Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "flutter": {
      "command": "dart",
      "args": ["run", "/path/to/flutter_turbo_bridge/packages/turbo_bridge_mcp/bin/turbo_bridge_mcp.dart"]
    }
  }
}
```

> **Tip:** The MCP server auto-connects to `localhost:8888`. Pass `--bridge-port` if you changed the default.

### 3. Talk to your app

Once connected, ask the AI:

> "Take a screenshot and describe what you see"

> "Find the Submit button and tap it"

> "Scroll down in the list and find item 50"

> "Enter 'hello@example.com' in the email field"

### Alternative: Use the client library directly

```dart
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

final client = TurboBridgeClient(host: '127.0.0.1', port: 8888);
final screenshot = await client.screenshot();
await client.tapByText('Submit');
final results = await client.find(text: 'Login');
await client.swipe(200, 600, 200, 200); // Swipe up
await client.enterText('hello@example.com');
```

## Performance

All operations are designed for <50ms round-trip latency:

| Operation | Target (p95) |
|-----------|-------------|
| Screenshot | <50ms |
| Widget tree | <40ms |
| Tap gesture | <30ms |
| Swipe | <30ms |
| Scroll | <30ms |
| Find widget | <20ms |
| Enter text | <30ms |
| App info | <10ms |

Historical benchmark trends with p50, p95, p99, and target lines are published at https://mark-nicepants.github.io/flutter_turbo_bridge/benchmarks/.

## MCP Timing Metadata

Turbo MCP tool and resource responses include a `_meta` object with UTC wall-clock stamps:

- `startedAtUtc` — when the MCP tool or resource began handling the request
- `completedAtUtc` — when the MCP tool or resource finished handling the request
- operation-specific timing fields when available, such as `captureTimeMs`, `searchTimeMs`, `executionTimeMs`, and `roundTripMs`

For multi-step runs, compute total wall-clock duration from the first response's `startedAtUtc` to the last response's `completedAtUtc`. Keep the lower-level timing fields separately for per-action analysis.

## Development

This is a Dart/Flutter monorepo managed with [Melos](https://melos.invertase.dev/).

```bash
# Install melos
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run analysis
melos run analyze

# Run tests
melos run test:dart    # Pure Dart packages
melos run test:flutter # Flutter package

# Format
melos run format
```

## CI/CD

- **CI** runs on every push/PR: analyze, format check, test all packages, benchmark on macOS
- **Publish** triggered on `v*` tags: publishes all packages to pub.dev

## License

MIT
