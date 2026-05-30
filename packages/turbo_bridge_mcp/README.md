# turbo_bridge_mcp

MCP (Model Context Protocol) server that gives LLMs direct access to running Flutter apps. Connect Claude, Cursor, VS Code Copilot, or any MCP-compatible host to see, understand, and interact with Flutter UIs.

## What It Does
# Global install for MCP hosts
dart pub global activate turbo_bridge_mcp
```

Or install it per project:

```bash
dart pub add --dev turbo_bridge_mcp
An LLM connected via this server can:
- Take screenshots and see the app's current state
- Inspect the widget tree to understand UI structure
- Tap buttons and interact with the app
- Find specific widgets by text, key, or type
- Query app metadata (screen size, platform, theme)

## Setup

### Prerequisites

1. A Flutter app with `turbo_bridge` running (see [turbo_bridge](../turbo_bridge/))
2. An MCP-compatible LLM host
3. Dart SDK (comes with Flutter)

### Quick Install

```bash
# Clone the repo (one-time setup)
git clone https://github.com/mark-nicepants/flutter_turbo_bridge.git
cd flutter_turbo_bridge && dart pub get --directory=packages/turbo_bridge_mcp
```

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "turbo_bridge": {
      "command": "turbo_bridge_mcp"
    }
  }
}
```

> **Note:** If Claude Desktop does not inherit your Dart pub cache bin path, replace `turbo_bridge_mcp` with the absolute executable path reported by `dart pub global activate turbo_bridge_mcp`.

### VS Code (GitHub Copilot)

Add to `.vscode/mcp.json` in your project (committable to version control):

```json
{
  "servers": {
    "turbo_bridge": {
      "command": "dart",
      "args": ["run", "turbo_bridge_mcp"]
    }
  }
}
```

> **Tip:** Prefer `dart run turbo_bridge_mcp` for project-local installs and `turbo_bridge_mcp` for globally activated installs.

### VS Code From Another App Workspace

If you are working in an app repo outside this monorepo and want to point at a local checkout of `flutter_turbo_driver`, define the MCP server with a relative or absolute path to the CLI entrypoint.

Example from an external Flutter app workspace:

```json
{
  "servers": {
    "turbo_bridge": {
      "command": "turbo_bridge_mcp",
      "args": ["--bridge-port", "8888"]
    }
  }
}
```

This setup is useful when the app under test and `flutter_turbo_driver` live in sibling folders on the same machine and you want the MCP server definition checked into the app workspace.

### Cursor

Add to `.cursor/mcp.json` in your project (committable):

```json
{
  "mcpServers": {
    "turbo_bridge": {
      "command": "dart",
      "args": ["run", "turbo_bridge_mcp"]
    }
  }
}
```

### Android Devices / Emulators

The bridge server runs inside the app on the device, so `localhost:8888` on the host can't reach it directly. The MCP server **automatically detects** this and sets up ADB port forwarding — no extra configuration needed.

How it works:
1. On startup, the MCP server tries to reach the bridge at `localhost:8888`
2. If unreachable, it checks for a connected Android device via `adb devices`
3. If found, it runs `adb forward tcp:8888 tcp:8888` automatically
4. On exit, it cleans up the forwarding

No changes to your MCP config are needed — the same setup works for both desktop and Android.

### CLI Options

```
dart run bin/turbo_bridge_mcp.dart [options]

-h, --bridge-host    Turbo Bridge host (default: localhost)
-p, --bridge-port    Turbo Bridge port (default: 8888)
    --vm-uri         Dart VM Service URI (optional, for expression evaluation)
    --help           Show usage
```

## MCP Tools

### `screenshot`

Captures the app's current screen as a PNG image.

**Parameters:**
- `pixelRatio` (number, optional) — Device pixel ratio, default 1.0
- `delayMs` (number, optional) — Wait before capture, default 75ms

**Returns:** PNG image plus JSON metadata. The JSON metadata includes `_meta.startedAtUtc`, `_meta.completedAtUtc`, `captureTimeMs`, and `roundTripMs`.

### `widget_tree`

Returns the full widget tree as structured JSON.

**Parameters:**
- `depth` (number, optional) — Max tree depth, default 10
- `x` (number, optional) — Focus X coordinate in logical pixels
- `y` (number, optional) — Focus Y coordinate in logical pixels
- `ancestorLevels` (number, optional) — Ancestors to keep above the focused hit node, default 2

**Returns:** Indented JSON tree with widget types, keys, text, and bounds. Responses include `_meta.startedAtUtc`, `_meta.completedAtUtc`, `captureTimeMs`, and `roundTripMs`. When `x` and `y` are provided together, the tool asks the bridge for a smaller local subtree around that coordinate.

### `tap`

Injects a tap at exact screen coordinates.

**Parameters:**
- `x` (number, required) — X coordinate
- `y` (number, required) — Y coordinate

**Returns:** Success status plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `executionTimeMs`, and `roundTripMs`

### `app_info`

Returns app metadata: screen size, pixel ratio, platform, dark mode, bridge version, and MCP compatibility hints.

**Returns:** App metadata plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `mcpServerVersion`, `mcpVersionStatus`, and an `updateHint` when the bridge is newer than the MCP server

### `find_widget`

Searches the widget tree by text, key, or type. Returns matching widgets with their center coordinates for tapping.

**Parameters:**
- `text` (string, optional) — Find by text content
- `key` (string, optional) — Find by widget key
- `type` (string, optional) — Find by widget type name

**Returns:** Up to 10 matching widgets with bounds and center coordinates, plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `searchTimeMs`, and `roundTripMs`

### `flutter_swipe`

Performs a swipe gesture between two points.

**Parameters:**
- `startX` (number, required) — Start X coordinate
- `startY` (number, required) — Start Y coordinate
- `endX` (number, required) — End X coordinate
- `endY` (number, required) — End Y coordinate
- `steps` (number, optional) — Number of move events, default 10

**Returns:** Success status plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `executionTimeMs`, and `roundTripMs`

### `flutter_scroll`

Scrolls at a specific position.

**Parameters:**
- `x` (number, required) — Scroll position X
- `y` (number, required) — Scroll position Y
- `dy` (number, optional) — Vertical scroll delta (negative = down)
- `dx` (number, optional) — Horizontal scroll delta

**Returns:** Success status plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `executionTimeMs`, and `roundTripMs`

### `flutter_enter_text`

Enters text into the currently focused text field.

**Parameters:**
- `text` (string, required) — Text to enter
- `replace` (boolean, optional) — Replace existing text, default false

**Returns:** Success status plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `executionTimeMs`, and `roundTripMs`

### `flutter_recent_logs`

Returns recent app-emitted log lines that the app pushed into
`TurboBridge.instance.logs`. Use this to inspect what the running app
has been doing without hooking into the device's system logs.

**Parameters:**
- `limit` (integer, optional) — Max entries to return (default 50)
- `level` (string, optional) — Minimum severity: `trace`, `debug`, `info`, `warn`, `error`

**Returns:** `{ entries: [{ id, timestamp, level, message, category?, data?, error?, stackTrace? }], count }`

### `flutter_recent_network`

Returns recent network calls that the app pushed into
`TurboBridge.instance.network` from its HTTP client interceptors.

**Parameters:**
- `limit` (integer, optional) — Max calls to return (default 50)

**Returns:** `{ entries: [{ id, timestamp, method, url, status, durationMs, error?, responseBodySize? }], count }`

## Timing Model

Every MCP tool and resource response now includes a `_meta` object with UTC start and completion stamps. Use it like this:

- action start: `_meta.startedAtUtc`
- action end: `_meta.completedAtUtc`
- action wall-clock duration: difference between `_meta.completedAtUtc` and `_meta.startedAtUtc`
- operation-specific timing: keep `captureTimeMs`, `searchTimeMs`, `executionTimeMs`, and `roundTripMs` as separate fields for transport and bridge analysis

For a full scenario or benchmark run, compute total wall-clock duration from the first tool call's `startedAtUtc` to the last tool call's `completedAtUtc`.

## MCP Resources

### `flutter://app/info`

Live app metadata (screen size, platform, theme).

### `flutter://app/tree`

Current widget tree snapshot.

## MCP Prompts

### `flutter_inspect`

Generates a structured inspection workflow prompt. Useful for guiding an LLM through systematic app exploration.

**Arguments:**
- `focus` (string, optional) — Specific area or feature to focus inspection on

## Example Conversation

Once connected, you can ask the LLM things like:

> "Take a screenshot of the app and tell me what you see"

> "Find the login button and tap it"

> "Scroll down in the list to find item 50"

> "Swipe left to dismiss the notification"

> "Enter 'hello@example.com' in the email field"

> "Inspect the widget tree and describe the navigation structure"

> "What's the current screen size and platform?"

The LLM will use the MCP tools autonomously to answer.

## Architecture

```
LLM Host ──stdio──► turbo_bridge_mcp ──HTTP──► Flutter App
                          │                        │
                    mcp_dart server          turbo_bridge
                          │                   (in-app)
                    turbo_bridge_client
                     (Dart HTTP client)
```

The MCP server communicates with LLM hosts via stdio (stdin/stdout JSON-RPC) and with the Flutter app via the Turbo Bridge HTTP API. It's a thin adapter layer — all the heavy lifting happens in the Flutter app process.
