# turbo_bridge

In-app companion server for Flutter that enables AI agents and external tools to interact with your running app at native speed.

Drop it into any Flutter app to expose HTTP endpoints for screenshots, widget tree inspection, gesture injection, and app metadata — all without touching your app's code.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  turbo_bridge: ^0.1.2
```

Or use the CLI:

```bash
flutter pub add turbo_bridge
```

## Usage

```dart
import 'package:turbo_bridge/turbo_bridge.dart';

void main() {
  runApp(const MyApp());
  TurboBridge.start(); // Starts on port 8888
}
```

With custom configuration:

```dart
TurboBridge.start(
  config: BridgeConfig(
    port: 9000,
    host: '0.0.0.0',        // Allow remote connections
    defaultTreeDepth: 20,
    includeTimingHeaders: true,
  ),
);
```

## HTTP API

Once running, the bridge exposes these endpoints:

### `GET /screenshot`

Captures the current frame as PNG bytes.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pixelRatio` | `1.0` | Device pixel ratio for the capture |

**Response**: Raw PNG bytes with headers:
- `content-type: image/png`
- `x-capture-time-ms: 12`
- `x-image-width: 1170`
- `x-image-height: 2532`

### `GET /tree`

Returns the widget tree as JSON.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `depth` | `10` | Max tree depth |
| `compact` | `true` | Omit framework-internal widgets |
| `x` | — | Optional focus X coordinate in logical pixels |
| `y` | — | Optional focus Y coordinate in logical pixels |
| `ancestorLevels` | `2` | Ancestors to keep above the focused hit node |

The tree response strips the framework shell wrappers above the app and, when `x`/`y` are provided, returns a smaller local subtree around the deepest widget hit at that coordinate.

**Response**: JSON with the widget tree structure including widget types, keys, text content, and layout bounds.

```json
{
  "captureTimeMs": 12,
  "focusPoint": {"x": 220.6, "y": 473.0},
  "ancestorLevels": 2,
  "rootWidget": {
    "type": "Column",
    "children": [
      {
        "type": "Text",
        "text": "Open duties"
      }
    ]
  }
}
```

### `POST /tap`

Injects a tap gesture at the given coordinates.

**Body** (JSON):
```json
{ "x": 195.0, "y": 422.0 }
```

**Response**:
```json
{ "success": true, "executionTimeMs": 3 }
```

### `GET /info`

Returns app metadata.

**Response**:
```json
{
  "screenWidth": 390.0,
  "screenHeight": 844.0,
  "pixelRatio": 3.0,
  "platform": "macos",
  "darkMode": false,
  "bridgeVersion": "0.1.2"
}
```

### `GET /health`

Health check endpoint. Returns `200 OK` when the server is running.

### `POST /swipe`

Injects a swipe gesture between two points.

**Body** (JSON):
```json
{ "startX": 200, "startY": 600, "endX": 200, "endY": 200, "steps": 10 }
```

**Response**:
```json
{ "success": true, "executionTimeMs": 5 }
```

### `POST /scroll`

Injects a scroll gesture at the given position.

**Body** (JSON):
```json
{ "x": 200, "y": 400, "dx": 0, "dy": -200, "steps": 5 }
```

**Response**:
```json
{ "success": true, "executionTimeMs": 3 }
```

### `POST /input`

Injects text into the currently focused text field.

**Body** (JSON):
```json
{ "text": "hello@example.com", "replace": true }
```

**Response**:
```json
{ "success": true, "executionTimeMs": 1 }
```

### `GET /find` or `POST /find`

Finds widgets by text, key, or type. Returns ranked matches biased toward the visible, tappable UI on the current screen.

**Parameters** (query params or JSON body):
- `text` — Find by text content (substring match, case-insensitive)
- `key` — Find by ValueKey
- `type` — Find by widget type name
- `limit` — Max results (default 10)
- `visibleOnly` — Restrict results to matches that intersect the visible viewport (default `true`)
- `currentRouteOnly` — Restrict results to the current top route when possible (default `false`)
- `interactiveOnly` — Restrict results to widgets with an interactive tap target (default `false`)
- `nearX` / `nearY` — Optional point used to bias ranking toward a region

By default the bridge prefers matches that are visible, on the active route, and inside a tappable ancestor.

**Response**:
```json
{
  "found": true,
  "count": 2,
  "results": [
    {
      "type": "Text",
      "text": "Submit",
      "center": { "x": 195.0, "y": 422.0 },
      "bounds": { "x": 100.0, "y": 400.0, "w": 190.0, "h": 44.0 },
      "matchedBy": "text-exact",
      "score": 1523.4,
      "isVisible": true,
      "isCurrentRoute": true,
      "routeName": "/client/reports",
      "tapTargetType": "ListTile",
      "tapTargetKey": "report_row_0"
    }
  ],
  "searchTimeMs": 2
}
```

## Architecture

The bridge runs an in-process HTTP server using [shelf](https://pub.dev/packages/shelf). All operations execute on the main isolate with direct access to Flutter's rendering pipeline — no IPC, no serialization overhead.

```
┌─────────────────────────────────────────────┐
│  Your Flutter App                           │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │  TurboBridge                          │  │
│  │  ├── shelf HTTP server (:8888)        │  │
│  │  ├── ScreenshotService (RenderView)   │  │
│  │  ├── WidgetTreeService (Element tree) │  │
│  │  ├── GestureService (tap/swipe/scroll)│  │
│  │  ├── FindService (route-aware lookup) │  │
│  │  └── AppInfoService (MediaQuery)      │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Performance

All operations target sub-20ms in-process latency:

| Operation | In-process (p95) |
|-----------|-----------------|
| Screenshot | <20ms |
| Widget tree | <15ms |
| Tap | <10ms |
| App info | <1ms |

## Testing

```dart
// Use createForTest to get an instance without starting the HTTP server
final bridge = TurboBridge.createForTest(
  config: const BridgeConfig(),
  screenshotService: mockScreenshot,
);
```

## When to Use

- **AI-assisted development** — Let LLMs see and interact with your app
- **Automated testing** — Drive your app from external test scripts
- **CI/CD visual regression** — Capture screenshots from running builds
- **Remote debugging** — Inspect widget trees from another machine

## Security Note

The bridge exposes full app interaction over HTTP. Only enable it in debug/profile builds or on trusted networks. Do not ship to production with the bridge active.
