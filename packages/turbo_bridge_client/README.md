# turbo_bridge_client

Pure Dart client library for connecting to a running Flutter app via Turbo Bridge. Designed for tool builders, CI pipelines, and anyone who needs programmatic access to a Flutter app's UI.

## Installation

```yaml
dependencies:
  turbo_bridge_client: ^0.1.3
```

Or use the CLI:

```bash
dart pub add turbo_bridge_client
```

## Quick Start

```dart
import 'package:turbo_bridge_client/turbo_bridge_client.dart';

void main() async {
  final client = TurboBridgeClient(host: '127.0.0.1', port: 8888);

  // Check connection
  if (!await client.isConnected()) {
    print('App not running or bridge not started');
    return;
  }

  // Take a screenshot
  final screenshot = await client.screenshot();
  File('screenshot.png').writeAsBytesSync(screenshot.bytes);
  print('Screenshot: ${screenshot.width}x${screenshot.height} in ${screenshot.captureTimeMs}ms');

  // Inspect the widget tree
  final tree = await client.widgetTree(depth: 15);
  print('Root: ${tree.type}');
  for (final child in tree.children) {
    print('  ${child.type} ${child.text ?? ""}');
  }

  // Find and tap a button
  await client.tapByText('Submit');

  // Or tap by key
  await client.tapByKey('login_button');

  // Or tap exact coordinates
  await client.tap(195, 422);

  // Get app info
  final info = await client.appInfo();
  print('Screen: ${info.screenWidth}x${info.screenHeight}');
  print('Platform: ${info.platform}');

  await client.dispose();
}
```

## API Reference

### `TurboBridgeClient`

The main entry point. Connects to the bridge HTTP server.

```dart
// Bridge-only connection
final client = TurboBridgeClient(host: '127.0.0.1', port: 8888);

// Bridge + VM Service (for Dart expression evaluation)
final client = TurboBridgeClient.withVmService(
  host: '127.0.0.1',
  port: 8888,
  vmServiceUri: 'ws://127.0.0.1:5678/ws',
);
```

### Screenshots

```dart
final result = await client.screenshot(pixelRatio: 2.0);
final settled = await client.screenshot(pixelRatio: 1.0, delayMs: 75);
result.bytes;          // Uint8List (PNG)
result.width;          // int
result.height;         // int
result.captureTimeMs;  // int (server-side capture time)
result.roundTripMs;    // int (full HTTP round trip)
```

Use `delayMs` when you need to let the UI settle after a tap, swipe, or route transition. The client default stays `0` so direct callers keep full control over latency.

### Widget Tree

```dart
final tree = await client.widgetTree(depth: 10);
tree.type;       // 'MaterialApp'
tree.key;        // String? widget key
tree.text;       // String? text content
tree.rect;       // {x, y, width, height}? layout bounds
tree.children;   // List<WidgetNode>

// Search utilities
tree.findByText('Hello');    // List<WidgetNode>
tree.findByKey('my_button'); // WidgetNode?
tree.findByType('ElevatedButton'); // List<WidgetNode>
```

### Gestures

```dart
// Tap coordinates
final result = await client.tap(100.0, 200.0);
result.success;     // bool
result.durationMs;  // int

// Find widget by text and tap its center
final result = await client.tapByText('Login');

// Find widget by key and tap its center
final result = await client.tapByKey('submit_btn');

// Swipe between two points
await client.swipe(200, 600, 200, 200); // startX, startY, endX, endY

// Scroll at a position
await client.scroll(200, 400, dy: -200); // scroll up

// Enter text into focused field
await client.enterText('hello@example.com');
await client.enterText('new value', replace: true); // replace existing text
```

### Find Widgets (Server-Side)

```dart
// Search by text content
final results = await client.find(text: 'Login');
results.found;   // bool
results.count;   // int
for (final widget in results.results) {
  print('${widget.type} at (${widget.center.$1}, ${widget.center.$2})');
}

// Search by key
final results = await client.find(key: 'submit_button');

// Search by type
final results = await client.find(type: 'ElevatedButton');
```

### App Info

```dart
final info = await client.appInfo();
info.screenWidth;    // double
info.screenHeight;   // double
info.pixelRatio;     // double
info.platform;       // String
info.darkMode;       // bool
info.bridgeVersion;  // String
```

### VM Service (Optional)

```dart
final client = TurboBridgeClient.withVmService(
  host: '127.0.0.1',
  port: 8888,
  vmServiceUri: 'ws://127.0.0.1:5678/ws',
);
await client.connectVmService();

// Evaluate Dart expressions in the running app
final result = await client.evaluate('DateTime.now().toString()');
```

## Use Cases

- **Benchmark tools** — Measure Flutter rendering performance
- **Integration test harnesses** — Drive UI tests from outside the app
- **CI screenshot pipelines** — Capture app states for visual regression
- **Custom developer tools** — Build your own Flutter inspector
- **Bot frameworks** — Programmatic app interaction for automation

## Error Handling

```dart
try {
  final screenshot = await client.screenshot();
} on BridgeException catch (e) {
  print('Bridge error: ${e.message} (status: ${e.statusCode})');
}
```

All methods throw `BridgeException` when the bridge returns an error response (4xx/5xx). Connection failures throw standard `http` package exceptions.
