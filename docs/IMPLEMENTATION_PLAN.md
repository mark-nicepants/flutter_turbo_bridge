# Implementation Plan — Phase 1 MVP + Phase 2 Enhanced

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Flutter App Process                                     │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  TurboBridge (in-app server)                      │  │
│  │                                                   │  │
│  │  ┌─────────────┐  ┌──────────────┐              │  │
│  │  │ HTTP Server  │  │ WS Server    │              │  │
│  │  │ (shelf)      │  │ (shelf_ws)   │              │  │
│  │  └──────┬───────┘  └──────┬───────┘              │  │
│  │         │                  │                      │  │
│  │  ┌──────▼──────────────────▼───────┐              │  │
│  │  │  Bridge Core                     │              │  │
│  │  │  ┌────────────┐ ┌────────────┐  │              │  │
│  │  │  │ Screenshot  │ │ Widget Tree│  │              │  │
│  │  │  │ Service     │ │ Service    │  │              │  │
│  │  │  └────────────┘ └────────────┘  │              │  │
│  │  │  ┌────────────┐ ┌────────────┐  │              │  │
│  │  │  │ Gesture     │ │ App Info   │  │              │  │
│  │  │  │ Service     │ │ Service    │  │              │  │
│  │  │  └────────────┘ └────────────┘  │              │  │
│  │  └─────────────────────────────────┘              │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────┐                               │
│  │ Flutter Framework    │  (WidgetsBinding, RenderTree) │
│  └─────────────────────┘                               │
└─────────────────────────────────────────────────────────┘
          │ HTTP :8888          │ WS :8889
          ▼                     ▼
┌─────────────────────────────────────────────────────────┐
│  TurboBridgeClient                                      │
│                                                         │
│  ┌───────────────────┐  ┌───────────────────┐          │
│  │ BridgeConnection  │  │ VmServiceConnection│          │
│  │ (HTTP + WS)       │  │ (WS direct)       │          │
│  └────────┬──────────┘  └────────┬──────────┘          │
│           │                       │                     │
│  ┌────────▼───────────────────────▼──────────┐          │
│  │  Unified API                               │          │
│  │  screenshot() | widgetTree() | tap()       │          │
│  │  evaluate() | findByText() | appInfo()     │          │
│  └────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────┐
│  TurboBridgeMcp (stdio MCP server)                      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  MCP Protocol Layer (mcp_dart)                    │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐         │   │
│  │  │  Tools   │ │Resources │ │ Prompts  │         │   │
│  │  └──────────┘ └──────────┘ └──────────┘         │   │
│  └──────────────────────────────────────────────────┘   │
│           │                                             │
│  ┌────────▼─────────────────────────────────────────┐   │
│  │  TurboBridgeClient (reused)                       │   │
│  └───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
          │ stdio
          ▼
┌─────────────────────────────────────────────────────────┐
│  LLM Host (Claude Desktop, VS Code, Cursor, etc.)       │
└─────────────────────────────────────────────────────────┘
```

## Package Structure

```
flutter_turbo_bridge/
├── packages/
│   ├── turbo_bridge/           # In-app server (Flutter package)
│   │   ├── lib/
│   │   │   ├── turbo_bridge.dart          # Public API barrel
│   │   │   └── src/
│   │   │       ├── bridge.dart            # Main TurboBridge class
│   │   │       ├── server/
│   │   │       │   ├── http_server.dart   # Shelf HTTP handler
│   │   │       │   └── ws_server.dart     # WebSocket handler
│   │   │       └── services/
│   │   │           ├── screenshot_service.dart
│   │   │           ├── widget_tree_service.dart
│   │   │           ├── gesture_service.dart
│   │   │           ├── find_service.dart
│   │   │           └── app_info_service.dart
│   │   └── test/
│   │
│   ├── turbo_bridge_client/    # Client library (pure Dart)
│   │   ├── lib/
│   │   │   ├── turbo_bridge_client.dart   # Public API barrel
│   │   │   └── src/
│   │   │       ├── client.dart            # Main TurboBridgeClient class
│   │   │       ├── bridge_connection.dart  # HTTP/WS connection
│   │   │       ├── vm_service_connection.dart
│   │   │       └── models/
│   │   │           ├── screenshot_result.dart
│   │   │           ├── widget_node.dart
│   │   │           └── tap_result.dart
│   │   └── test/
│   │
│   └── turbo_bridge_mcp/       # MCP server (pure Dart CLI)
│       ├── bin/
│       │   └── turbo_bridge_mcp.dart      # CLI entry point
│       ├── lib/
│       │   ├── turbo_bridge_mcp.dart      # Public API barrel
│       │   └── src/
│       │       ├── server.dart            # McpServer setup
│       │       ├── tools/
│       │       │   ├── screenshot_tool.dart
│       │       │   ├── widget_tree_tool.dart
│       │       │   ├── tap_tool.dart
│       │       │   ├── app_info_tool.dart
│       │       │   ├── find_widget_tool.dart
│       │       │   ├── swipe_tool.dart
│       │       │   ├── scroll_tool.dart
│       │       │   └── enter_text_tool.dart
│       │       ├── resources/
│       │       │   ├── app_info_resource.dart
│       │       │   └── widget_tree_resource.dart
│       │       └── prompts/
│       │           └── inspect_prompt.dart
│       └── test/
│
├── apps/
│   ├── target_app/             # Reference Flutter app
│   └── benchmark/              # Speed benchmark tool
│
└── docs/
```

## Implementation Steps

### Step 1: Core Bridge Services (in-app)

Priority order (by impact on AI feedback loop):

1. **ScreenshotService** — Capture current frame as PNG bytes
  - In debug mode, prefer `RenderView.debugLayer` plus `OffsetLayer.toImage()` to capture the composed root scene
  - Fall back to `RenderRepaintBoundary.toImage()` on a visible full-surface repaint boundary when the root layer is unavailable
  - Skip offstage subtrees in the fallback path so hidden or previous routes do not win capture selection
   - Return raw bytes (no base64 encoding over HTTP — binary response)
   - Target: <20ms including PNG encoding

2. **WidgetTreeService** — Extract widget tree as compact JSON
   - Walk `WidgetsBinding.instance.rootElement`
  - Normalize away framework shell wrappers above the app root
  - Support optional coordinate-focused subtree capture with ancestor context
  - Output: `{type, key, size, position, children, text, semantics}`
   - Configurable depth limit
   - Target: <15ms for typical app (100-500 widgets)

3. **GestureService** — Inject pointer events
   - Use `WidgetsBinding.instance.handlePointerEvent()`
   - Support: tap (down+up), swipe, scroll, text input
   - Synchronous dispatch for speed (unique pointer IDs per gesture)
   - Target: <10ms per gesture

4. **FindService** — Server-side widget lookup (Phase 2)
   - Walk Element tree, match by ValueKey, text content, or widget type
   - Case-insensitive substring match for text (AI-friendly)
   - Returns center coordinates and bounds for tapping
   - Target: <10ms for typical search

5. **AppInfoService** — Static app metadata
   - Screen size, pixel ratio, platform, dark mode, route
   - Cached, near-zero cost

### MCP Screenshot Settling

- The raw bridge screenshot path stays immediate by default to preserve the low-latency primitive.
- The client exposes an optional `delayMs` argument on `screenshot()` for callers that need a short settle window after gestures.
- The MCP `flutter_screenshot` tool applies a default 75ms delay unless overridden, because AI-driven flows frequently capture immediately after taps.
- This keeps the fast primitive available while making the default MCP experience less prone to stale post-action frames.

### Package Distribution

- Public packages are shaped for pub.dev publication.
- The first release of each package must be published manually; subsequent releases can use GitHub Actions automated publishing.
- The publish workflow relies on GitHub OIDC with `id-token: write`, not long-lived repository secrets.
- `flutter_app_info` and `flutter://app/info` enrich bridge metadata with MCP-local compatibility fields: `mcpServerVersion`, `mcpVersionStatus`, and `updateHint`.

### Step 2: HTTP/WS Server Layer

- **Shelf-based HTTP server** on configurable port (default 8888)
  - `GET /screenshot` → PNG bytes (Content-Type: image/png)
  - `GET /tree?depth=10` → JSON widget tree
  - `POST /tap` → `{x, y}` body → inject tap
  - `POST /swipe` → `{startX, startY, endX, endY, steps}` → swipe gesture
  - `POST /scroll` → `{x, y, dx, dy, steps}` → scroll gesture
  - `POST /input` → `{text, replace}` → text entry
  - `GET /find?text=Login` or `POST /find` → find widgets by text/key/type
  - `GET /info` → app metadata JSON
  - `GET /health` → connection status

- **WebSocket server** on same port at `/ws`
  - Bidirectional JSON messages
  - Event streaming (frame updates, errors, state changes)
  - Command batching for multi-operation sequences

### Step 3: Client Library

- `TurboBridgeClient` — main entry point
  - `connect(host, port)` / `connectWithVmService(vmServiceUri)`
  - `screenshot()` → `Uint8List` (PNG bytes)
  - `widgetTree({depth})` → `WidgetNode` tree
  - `widgetTreeWithTiming({depth, x, y, ancestorLevels})` → tree + timing for full or focused subtree capture
  - `tap(x, y)` → `TapResult`
  - `evaluate(expression)` → `EvalResult` (via VM Service)
  - `dispose()`

- Built-in latency tracking on every operation
- MCP tools and resources attach `_meta.startedAtUtc` and `_meta.completedAtUtc` so runs can derive wall-clock timing directly from responses
- Auto-reconnect with exponential backoff

### Step 4: Integration & Benchmark

- Wire `TurboBridge` into `target_app`
- Update benchmark to test both:
  - Direct VM Service (existing)
  - Turbo Bridge HTTP client (new)
- Compare latencies side-by-side

## Design Principles

1. **Binary over text** — Return PNG bytes directly, not base64 strings
2. **Compute on app side** — The Flutter app has direct access; do work there
3. **Minimal allocations** — Reuse buffers where possible
4. **No framework overhead** — Skip widget rebuild cycles for read operations
5. **Fail fast** — Return errors immediately, don't retry internally
6. **Testable** — Every service is injectable and mockable

## API Contracts

### Screenshot

```
GET /screenshot
Query params:
  - format: png (default) | jpeg
  - quality: 1-100 (jpeg only, default 80)
  - maxWidth: int (optional, downscale)

Response: image/png or image/jpeg binary
Headers:
  X-Capture-Time-Ms: <time to capture in ms>
  X-Image-Width: <px>
  X-Image-Height: <px>
```

### Widget Tree

```
GET /tree
Query params:
  - depth: int (default 10, -1 for unlimited)
  - compact: bool (default true — omit null fields)
  - x: double (optional focus X coordinate)
  - y: double (optional focus Y coordinate)
  - ancestorLevels: int (default 2 — keep this many ancestors above the hit node)

Response: application/json
{
  "captureTimeMs": 12,
  "focusPoint": {"x": 220.6, "y": 473.0},
  "ancestorLevels": 2,
  "rootWidget": {
    "type": "Column",
    "key": null,
    "rect": {"x": 0, "y": 0, "w": 390, "h": 844},
    "children": [...]
  }
}
```

### Tap

```
POST /tap
Content-Type: application/json
{
  "x": 195.0,
  "y": 422.0
}

Response: application/json
{
  "success": true,
  "executionTimeMs": 3
}
```

### App Info

```
GET /info

Response: application/json
{
  "screenWidth": 390,
  "screenHeight": 844,
  "pixelRatio": 3.0,
  "platform": "android",
  "darkMode": false,
  "currentRoute": "/home",
  "bridgeVersion": "0.1.0"
}
```

---

## MCP Server — `turbo_bridge_mcp`

### Overview

The MCP server is a standalone Dart CLI that exposes the Turbo Bridge to any MCP-compatible LLM host (Claude Desktop, VS Code, Cursor, etc.) via the stdio transport.

**SDK**: `mcp_dart` ^2.1.1 — most mature community Dart MCP SDK, full spec 2025-11-25 support.

**Design**: The MCP server is a thin adapter layer. It uses `turbo_bridge_client` for all operations, adding no business logic of its own. This keeps the MCP layer testable and the client reusable.

### MCP Tools

| Tool Name | Description | Input Schema | Output |
|-----------|-------------|-------------|--------|
| `flutter_screenshot` | Capture app screenshot | `{pixelRatio?: number, delayMs?: number}` | `ImageContent` (PNG base64) + `TextContent` metadata |
| `flutter_widget_tree` | Get widget tree | `{depth?: integer, x?: number, y?: number, ancestorLevels?: integer}` | `TextContent` (JSON) |
| `flutter_tap` | Tap at screen coordinates | `{x: number, y: number}` | `TextContent` (result JSON) |
| `flutter_app_info` | Get app metadata | `{}` | `TextContent` (JSON) |
| `flutter_find_widget` | Find widget by text/key/type | `{text?: string, key?: string, type?: string, visibleOnly?: boolean, currentRouteOnly?: boolean, interactiveOnly?: boolean, nearX?: number, nearY?: number, limit?: integer}` | `TextContent` (JSON with ranked coords + diagnostics) |

### MCP Resources

| URI | Description | MIME Type |
|-----|-------------|-----------|
| `flutter://app/info` | Live app metadata | `application/json` |
| `flutter://app/tree` | Current widget tree snapshot | `application/json` |

### MCP Prompts

| Prompt Name | Description | Arguments |
|-------------|-------------|-----------|
| `flutter_inspect` | Inspect current app state — takes screenshot + tree | `{focus?: string}` |

### CLI Usage

```bash
# Run as stdio MCP server (standard way)
dart run turbo_bridge_mcp --bridge-port 8888

# With VM Service for evaluation
dart run turbo_bridge_mcp --bridge-port 8888 --vm-uri ws://127.0.0.1:PORT/TOKEN/ws
```

### MCP Host Configuration

```json
{
  "mcpServers": {
    "flutter-turbo-bridge": {
      "command": "dart",
      "args": ["run", "turbo_bridge_mcp", "--bridge-port", "8888"],
      "cwd": "/path/to/turbo_bridge_mcp"
    }
  }
}
```

### Tool Contracts

#### `flutter_screenshot`
```json
{
  "name": "flutter_screenshot",
  "description": "Capture a screenshot of the running Flutter app. Returns a PNG image.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "pixelRatio": {
        "type": "number",
        "description": "Pixel ratio for the screenshot (1.0 = logical pixels)",
        "default": 1.0
      }
    }
  }
}
```
**Response**: `ImageContent` with base64 PNG data and `image/png` MIME type.
The accompanying metadata content includes `_meta.startedAtUtc`, `_meta.completedAtUtc`, `captureTimeMs`, and `roundTripMs`.

#### `flutter_widget_tree`
```json
{
  "name": "flutter_widget_tree",
  "description": "Get the current widget tree of the running Flutter app as JSON. Includes widget types, keys, text content, and layout bounds.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "depth": {
        "type": "integer",
        "description": "Max depth to traverse (-1 for unlimited)",
        "default": 10
      },
      "x": {
        "type": "number",
        "description": "Optional focus X coordinate in logical pixels"
      },
      "y": {
        "type": "number",
        "description": "Optional focus Y coordinate in logical pixels"
      },
      "ancestorLevels": {
        "type": "integer",
        "description": "Ancestors to keep above the focused hit node",
        "default": 2
      }
    }
  }
}
```
**Response**: `TextContent` with JSON widget tree plus `_meta.startedAtUtc`, `_meta.completedAtUtc`, `captureTimeMs`, and `roundTripMs`.

#### `flutter_tap`
```json
{
  "name": "flutter_tap",
  "description": "Tap at the given screen coordinates in the running Flutter app.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "x": {"type": "number", "description": "X coordinate in logical pixels"},
      "y": {"type": "number", "description": "Y coordinate in logical pixels"}
    },
    "required": ["x", "y"]
  }
}
```
**Response**: `TextContent` with JSON `{success, _meta: {startedAtUtc, completedAtUtc, executionTimeMs, roundTripMs}}`.

#### `flutter_find_widget`
```json
{
  "name": "flutter_find_widget",
  "description": "Find a widget in the Flutter app by text content, ValueKey, or widget type. Returns the widget's position and bounds for tapping.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Find by text content (exact or substring)"},
      "key": {"type": "string", "description": "Find by ValueKey string"},
      "type": {"type": "string", "description": "Find by widget type name"},
      "visibleOnly": {"type": "boolean", "description": "Restrict results to the visible viewport", "default": true},
      "currentRouteOnly": {"type": "boolean", "description": "Restrict results to the current top route when possible", "default": false},
      "interactiveOnly": {"type": "boolean", "description": "Restrict results to widgets with an interactive tap target", "default": false},
      "nearX": {"type": "number", "description": "Optional X coordinate to bias ranking toward"},
      "nearY": {"type": "number", "description": "Optional Y coordinate to bias ranking toward"},
      "limit": {"type": "integer", "description": "Maximum number of matches to return", "default": 10}
    }
  }
}
```
**Response**: `TextContent` with JSON `{found, count, results, _meta: {startedAtUtc, completedAtUtc, searchTimeMs, roundTripMs}}` where each result may also include `matchedBy`, `score`, `isVisible`, `isCurrentRoute`, `routeName`, `tapTargetType`, and `tapTargetKey`.

#### `flutter_app_info`
```json
{
  "name": "flutter_app_info",
  "description": "Get metadata about the running Flutter app: screen size, platform, dark mode, etc.",
  "inputSchema": {
    "type": "object",
    "properties": {}
  }
}
```
**Response**: `TextContent` with JSON app metadata plus `_meta.startedAtUtc` and `_meta.completedAtUtc`.
The MCP response also includes `mcpServerVersion`, `mcpVersionStatus`, and an `updateHint` when the running MCP package is older than the bridge package in the app.

### Timing Calculation

- Action start timestamp: `_meta.startedAtUtc`
- Action end timestamp: `_meta.completedAtUtc`
- Action wall-clock duration: difference between `_meta.completedAtUtc` and `_meta.startedAtUtc`
- End-to-end scenario wall-clock duration: difference between the first tool call's `_meta.startedAtUtc` and the last tool call's `_meta.completedAtUtc`
- Keep `captureTimeMs`, `searchTimeMs`, `executionTimeMs`, and `roundTripMs` as separate operation metrics rather than replacing them with the derived wall-clock delta
