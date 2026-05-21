# Flutter Turbo Bridge — Speed Benchmark

Measures VM Service and Turbo Bridge latency against a running Flutter debug app and writes machine-readable output for CI trend tracking.

## Quick Start

```bash
# 1. Start the target app
cd ../target_app
flutter run --debug
# Note the VM Service URI from the output:
#   "A Dart VM Service on ... is available at: ws://127.0.0.1:XXXXX/TOKEN=/ws"

# 2. Run the full benchmark suite
cd ../benchmark
dart pub get
dart run bin/benchmark.dart --vm-uri "ws://127.0.0.1:XXXXX/TOKEN=/ws"

# 3. Or run only the bridge suite
dart run bin/benchmark.dart --bridge-host 127.0.0.1 --bridge-port 8888 --bridge-only
```

## What It Measures

### VM Service Direct

| Operation | Target (p95) | What |
|-----------|-------------|------|
| `vm_service_connect` | <500ms | Initial WebSocket connection |
| `vm_get_vm` | <30ms | Get VM metadata |
| `vm_get_isolate` | <30ms | Get isolate info |
| `vm_evaluate_simple` | <50ms | Evaluate `1 + 1` in the root library |
| `vm_evaluate_widget_tree` | <100ms | Evaluate widget tree access through Dart code |
| `vm_service_extension_tree` | <200ms | Call `ext.flutter.inspector.getRootWidgetTree` |

### Turbo Bridge HTTP

| Operation | Target (p95) | What |
|-----------|-------------|------|
| `bridge_health` | <10ms | Health endpoint round-trip |
| `bridge_screenshot` | <50ms | PNG screenshot capture |
| `bridge_widget_tree` | <40ms | Widget tree serialization |
| `bridge_tap` | <30ms | Tap gesture injection |
| `bridge_app_info` | <10ms | App metadata lookup |
| `bridge_full_loop` | <100ms | Screenshot + tree + tap sequence |

## Output

- Console: colored pass/fail report with p50, p95, p99, min, max, and mean
- `benchmark_results.json`: machine-readable results for CI integration and PR comments
- GitHub Pages dashboard: https://mark-nicepants.github.io/flutter_turbo_bridge/benchmarks/

The dashboard overlays p50, p95, p99, and target lines for each operation so drift and headroom are visible over time.

## Options

```text
--vm-uri, -u      VM Service WebSocket URI
--bridge-host     Turbo Bridge host (default: 127.0.0.1)
--bridge-port, -p Turbo Bridge port (default: 8888)
--iterations, -n  Number of iterations per benchmark (default: 50)
--vm-only         Only run VM Service benchmarks
--bridge-only     Only run Turbo Bridge benchmarks
--help, -h        Show usage
```

## CI Tracking

- Pushes to `main` publish benchmark history to GitHub Pages
- Pull requests receive a benchmark comment comparing current p95 values against the latest `main` baseline
- The CI dashboard currently tracks the bridge suite on macOS to keep runs deterministic and fast

## Interpreting Results

- **Within target** means the latest p95 is at or below the configured budget
- **p50 / p99 spread** shows median behavior versus tail latency
- **Target line** is the performance budget that should stay flat over time
