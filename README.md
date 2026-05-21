# Flutter Turbo Bridge

Ultra-fast bridge between AI agents and Flutter apps. Enables LLMs to see, understand, and interact with running Flutter applications in real-time.

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
- **Understand the UI** — inspect the full widget tree with layout bounds
- **Interact** — tap any coordinate or find-and-tap by text/key
- **Query state** — get app metadata, screen size, current route, platform info

## Packages

| Package | Description | Audience |
|---------|-------------|----------|
| [`turbo_bridge`](packages/turbo_bridge/) | In-app HTTP server for Flutter | Flutter developers |
| [`turbo_bridge_client`](packages/turbo_bridge_client/) | Pure Dart client library | Tool/CI builders |
| [`turbo_bridge_mcp`](packages/turbo_bridge_mcp/) | MCP server for LLM integration | AI/LLM developers |

## Quick Start

### 1. Add the bridge to your Flutter app

```dart
// In your Flutter app's main.dart
import 'package:turbo_bridge/turbo_bridge.dart';

void main() {
  runApp(const MyApp());
  TurboBridge.start(); // Starts HTTP server on port 8888
}
```

### 2. Connect from an AI agent (MCP)

Add to your Claude Desktop / Cursor MCP config:

```json
{
  "mcpServers": {
    "flutter": {
      "command": "dart",
      "args": ["run", "packages/turbo_bridge_mcp/bin/turbo_bridge_mcp.dart"],
      "env": {}
    }
  }
}
```

### 3. Or use the client directly

```dart
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

final client = TurboBridgeClient(host: '127.0.0.1', port: 8888);
final screenshot = await client.screenshot();
final tree = await client.widgetTree();
await client.tapByText('Submit');
```

## Performance

All operations are designed for <50ms round-trip latency:

| Operation | Target (p95) |
|-----------|-------------|
| Screenshot | <50ms |
| Widget tree | <40ms |
| Tap gesture | <30ms |
| App info | <10ms |

Historical benchmark trends with p50, p95, p99, and target lines are published at https://mark-nicepants.github.io/flutter_turbo_bridge/benchmarks/.

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
