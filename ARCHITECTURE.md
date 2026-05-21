# Flutter AI Speed Architecture — Research & Proposal

## Problem Statement

Current tools for LLM-Flutter interaction (Dart MCP, flutter_driver, ADB) introduce **2-5+ seconds per operation**. For an effective AI developer loop, we need **<100ms per operation** — approaching human interaction speed.

---

## Research Findings

### Why Current Tools Are Slow

| Tool | Bottleneck | Typical Latency |
|------|-----------|----------------|
| **Dart MCP** (dart tooling mcp) | Launches processes, serializes through stdio, full DevTools protocol overhead | 2-5s per call |
| **flutter_driver** | Requires `flutter drive`, out-of-process, JSON-RPC over WebSocket via DDS middleware | 1-3s per action |
| **ADB commands** | Process spawn per command, USB/network bridge, shell overhead | 0.5-2s per command |
| **DevTools Service Extensions** | WebSocket → DDS → VM Service → Isolate → Extension → Response. Multiple hops. | 0.5-2s |
| **Patrol MCP** | Runs tests end-to-end, designed for CI not interactive loops | 5-30s per test |

### Key Insight: The Speed Is in the Dart VM Service Protocol

The **Dart VM Service Protocol** (v4.22) exposes a direct WebSocket connection to a running Dart VM with:
- `evaluate()` — execute arbitrary Dart expressions in-isolate (~5-20ms)
- `invoke()` — call methods on live objects (~5-20ms)
- `getObject()` — inspect any object by ID (~2-10ms)
- `streamListen()` — subscribe to real-time events (0ms, push-based)
- Service extensions — custom RPCs registered by the Flutter framework

The magic: **once connected, the WebSocket is persistent and operations are ~10-50ms** when you skip the DDS/DevTools middleware layer.

### Flutter's Built-in Service Extensions (instant, in-process)

Flutter registers these service extensions that run **in the app's isolate**:
- `ext.flutter.inspector.getRootWidgetTree` — full widget tree as JSON
- `ext.flutter.inspector.getDetailsSubtree` — subtree with constraints, sizes, render info
- `ext.flutter.inspector.screenshot` — PNG screenshot of any RenderObject
- `ext.flutter.inspector.getSelectedWidget` — current selection
- `ext.flutter.inspector.getLayoutExplorerNode` — layout details
- `ext.flutter.inspector.setFlexFit/setFlexFactor/setFlexProperties` — live property mutation

### Screenshot Approaches (ranked by speed)

1. **`RenderRepaintBoundary.toImageSync()`** — **<1ms**, synchronous, returns `dart:ui.Image` immediately. Requires being called in-process.
2. **`RenderRepaintBoundary.toImage()`** — **~5-10ms**, async, in-process.
3. **`ext.flutter.inspector.screenshot`** — **~50-200ms**, via service extension, returns base64 PNG.
4. **`flutter screenshot` CLI** — **1-3s**, spawns process, writes to disk.
5. **ADB screencap** — **0.5-2s**, system-level, full device screenshot.

### Widget Tree Inspection (ranked by speed)

1. **In-process `WidgetsBinding.instance.rootElement.toDiagnosticsNode()`** — **<5ms**, direct access to the element tree.
2. **`evaluate()` via VM Service** — **~10-30ms**, evaluate expression in the running isolate.
3. **`ext.flutter.inspector.getRootWidgetTree`** — **~50-200ms**, serialized JSON through service extension.
4. **Dart MCP getRenderTree** — **2-5s**, full protocol overhead.

---

## Proposed Architecture: "Flutter Turbo Bridge"

### Design Principles

1. **In-process companion** — embed a lightweight agent inside the Flutter app
2. **Direct WebSocket** — bypass DDS, connect straight to VM Service
3. **Binary protocol** — avoid JSON serialization for screenshots
4. **Persistent connection** — no connection setup per operation
5. **Batch operations** — combine multiple queries in single round-trips
6. **Push over pull** — subscribe to frame events, get updates proactively

### Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│  LLM Agent (Python/TS)                              │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Turbo Bridge Client                        │    │
│  │  - Persistent WebSocket to VM Service       │    │
│  │  - Persistent WebSocket to Companion        │    │
│  │  - Operation batching                       │    │
│  │  - Screenshot cache (diff-based)            │    │
│  └───────────┬──────────────────┬──────────────┘    │
└──────────────┼──────────────────┼───────────────────┘
               │ ws://            │ ws://
               │ (VM Service)    │ (Companion)
               ▼                  ▼
┌──────────────────────┐  ┌──────────────────────────────┐
│  Dart VM Service     │  │  In-App Companion Server     │
│  (built-in)          │  │  (dart:io HttpServer)         │
│                      │  │                              │
│  - evaluate()        │  │  - /screenshot (raw bytes)   │
│  - invoke()          │  │  - /widget-tree (msgpack)    │
│  - getObject()       │  │  - /tap {x,y}               │
│  - streamListen()    │  │  - /type {text}              │
│  - Extension RPCs    │  │  - /scroll {dx,dy}           │
│                      │  │  - /evaluate {expr}           │
└──────────────────────┘  │  - /hot-reload               │
                          │  - /semantic-tree             │
                          │  - SSE: frame-updates        │
                          └──────────────────────────────┘
                                    │
                                    ▼
                          ┌──────────────────────────────┐
                          │  Flutter App (debug mode)    │
                          │                              │
                          │  Companion mixin:            │
                          │  - GestureBinding hooks      │
                          │  - RenderView access         │
                          │  - toImageSync() for speed   │
                          │  - Element tree traversal    │
                          │  - Semantics tree access     │
                          └──────────────────────────────┘
```

### Component 1: In-App Companion Package (`flutter_turbo_bridge`)

A debug-only package added to the Flutter app that provides:

```dart
// In main.dart (debug only)
import 'package:flutter_turbo_bridge/flutter_turbo_bridge.dart';

void main() {
  TurboBridge.init(port: 8888); // starts WebSocket server in-app
  runApp(const MyApp());
}
```

The companion runs an HTTP/WebSocket server **inside the app process** giving:
- **Direct access to the render tree** without serialization overhead
- **Synchronous screenshots** via `toImageSync()` (sub-millisecond)
- **Touch injection** via `GestureBinding` (no ADB needed)
- **Widget tree as structured data** with full type info
- **Live frame notifications** via Server-Sent Events

### Component 2: VM Service Direct Client

A lightweight client (TypeScript or Python) that:
- Connects directly to the VM Service WebSocket (skipping DDS when possible)
- Uses `evaluate()` to execute arbitrary Dart in the running app
- Can inspect any object's state without the overhead of service extensions
- Subscribes to `Extension` stream for real-time event notifications

### Component 3: Hybrid Protocol

For maximum speed, use a tiered approach:

| Operation | Method | Expected Latency |
|-----------|--------|-----------------|
| Screenshot (full) | Companion `/screenshot` (raw RGBA → compress client-side) | **5-15ms** |
| Screenshot (diff) | Companion `/screenshot-diff` (only changed regions) | **2-8ms** |
| Widget tree (structural) | Companion `/widget-tree` (pre-serialized msgpack) | **3-10ms** |
| Tap/gesture | Companion `/tap` → `GestureBinding.handlePointerEvent()` | **<5ms** |
| Text input | Companion `/type` → `TextInput.setEditingState()` | **<5ms** |
| Evaluate expression | VM Service `evaluate()` | **10-30ms** |
| Get object state | VM Service `getObject()` | **5-15ms** |
| Hot reload | VM Service `reloadSources()` | **200-500ms** |
| Semantics tree | Companion `/semantic-tree` | **5-15ms** |

### Why Not Just Use Patrol MCP?

Patrol MCP is designed for **test execution** (run test → get result), not **interactive development loops**. It:
- Starts/stops tests as full processes
- Has cold-start overhead per test
- Doesn't support arbitrary exploration of the running app
- Screenshots require a full test context

Our approach keeps the app running and interacts with it **continuously**.

---

## Validation Strategy

### Speed Metrics Test Suite

We need a benchmark script that measures actual operation latency for each approach:

```
Target Metrics (p95):
  - Screenshot capture: <20ms
  - Widget tree fetch: <15ms
  - Tap injection: <10ms
  - Text input: <10ms
  - Object inspection: <20ms
  - Full feedback loop (screenshot + tree + decision): <100ms
```

### Comparison Baseline

The test will also measure current approaches for direct comparison:
- ADB screencap latency
- flutter_driver action latency
- Dart MCP operation latency
- Service extension call latency
- Direct VM Service call latency
- In-process companion latency

### Test Script Design

A Dart benchmark script that:
1. Starts a Flutter app in debug mode
2. Connects via each method (VM Service, service extensions, companion)
3. Performs 100 iterations of each operation
4. Reports p50, p95, p99 latencies
5. Validates correctness (screenshot isn't blank, tree has nodes, tap registers)

---

## Implementation Phases

### Phase 1: Proof of Concept (validate speed assumptions)
- Build minimal Companion server (screenshot + tap + widget tree)
- Build VM Service direct client
- Run benchmark comparing all approaches
- **Goal: prove <50ms operations are achievable**

### Phase 2: Full Bridge Package
- Implement all operations in the Companion
- Add msgpack serialization (faster than JSON)
- Add screenshot diffing (reduce data transfer)
- Add semantic tree access (for LLM understanding)
- Hot reload integration

### Phase 3: LLM Integration Layer
- MCP server wrapping the Turbo Bridge
- Structured tool definitions for the LLM
- Screenshot → vision model pipeline
- Widget tree → text description pipeline
- Action planning → execution pipeline

### Phase 4: Self-Healing Loop
- Error detection from widget tree (overflow indicators, error widgets)
- Automatic hot-reload after code changes
- Visual regression detection via screenshot diffs
- Performance monitoring via frame timing

---

## Key Technical Decisions

### 1. Why an in-app server instead of just VM Service?

The VM Service's `evaluate()` is powerful but:
- Returns serialized strings, not binary data (slow for screenshots)
- Each evaluation has compilation overhead for complex expressions
- Can't easily stream binary data (images)

The in-app server provides:
- Direct binary transfer for screenshots
- Pre-compiled access paths (no expression compilation)
- WebSocket for bidirectional streaming

### 2. Why not modify flutter_driver?

flutter_driver is out-of-process by design. It:
- Communicates via the VM Service (adding a hop)
- Uses a finder-based API (requires serialization)
- Was designed for CI testing, not interactive loops

### 3. Screenshot format choice

- **Raw RGBA**: Fastest to produce (no encoding), largest to transfer
- **Raw RGB with zlib**: Good balance — ~5ms encode, ~60% size reduction
- **PNG**: Slow to encode (~50-100ms) but standard
- **JPEG**: Fast encode (~10ms) but lossy

**Recommendation**: Use raw RGBA over localhost (transfer is fast), optionally compress with zlib for larger screens. Let the client decode. For LLM vision: convert to JPEG client-side at quality 80 (good enough for understanding).

### 4. Widget tree representation for LLM

Full widget tree is too verbose. Provide a **summary tree** (same as DevTools uses) that:
- Only shows user-created widgets
- Includes size/position/constraints
- Includes text content
- Includes semantic labels
- Omits implementation details

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| In-app server impacts app performance | Only active in debug mode, minimal overhead when idle, lazy serialization |
| WebSocket connection instability | Auto-reconnect with exponential backoff, connection health monitoring |
| Screenshot too large for LLM context | Downsample to 720p, use JPEG quality 60, implement region-of-interest capture |
| Widget tree too deep for LLM | Use summary tree, limit depth, include only relevant subtrees |
| Security (exposing app internals) | Debug-only, localhost-only binding, no production builds |
| Hot reload breaks companion state | Companion re-initializes on reload, stateless design |

---

## Prior Art & References

- **Dart VM Service Protocol v4.22**: https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md
- **Flutter Widget Inspector source**: `packages/flutter/lib/src/widgets/widget_inspector.dart`
- **RenderRepaintBoundary.toImageSync()**: Synchronous screenshot, <1ms
- **Patrol MCP**: https://patrol.leancode.co/patrol-mcp-announcement (test runner, not interactive)
- **Flutter Service Extensions**: `ext.flutter.inspector.*` registered in WidgetInspectorService
- **vm_service Dart package**: Client library for Dart VM Service Protocol
