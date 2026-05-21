# Flutter Turbo Bridge — Speed Benchmark

Validates the latency assumptions in [ARCHITECTURE.md](../ARCHITECTURE.md) by measuring real operation times against a running Flutter debug app.

## Quick Start

```bash
# 1. Start the target app
cd target_app
flutter run --debug
# Note the VM Service URI from the output:
#   "A Dart VM Service on ... is available at: ws://127.0.0.1:XXXXX/TOKEN=/ws"

# 2. Run the benchmark
cd ../
dart pub get
dart run bin/benchmark.dart --uri "ws://127.0.0.1:XXXXX/TOKEN=/ws"
```

## What It Measures

| Operation | Target (p95) | What |
|-----------|-------------|------|
| `vm_service_connect` | <500ms | Initial WebSocket connection |
| `get_vm` | <30ms | Get VM metadata |
| `get_isolate` | <30ms | Get isolate info |
| `evaluate_simple` | <50ms | Evaluate `1 + 1` in isolate |
| `evaluate_widget_tree` | <100ms | Evaluate widget tree access |
| `service_extension_get_widget_tree` | <200ms | Call Flutter inspector getRootWidgetTree |
| `service_extension_screenshot` | <300ms | Call Flutter inspector screenshot |
| `stream_listen_setup` | <50ms | Subscribe/unsubscribe to event stream |

## Output

- Console: colored pass/fail report with percentile stats
- `benchmark_results.json`: machine-readable results for CI integration

## Options

```
--uri, -u       VM Service WebSocket URI (required)
--iterations, -n  Number of iterations per benchmark (default: 50)
--help, -h      Show usage
```

## Interpreting Results

- **✓ Green**: Operation meets the target latency at p95
- **✗ Red**: Operation exceeds target or failed

If service extensions fail, your Flutter app may not have the inspector enabled (requires debug mode).

## Next Steps

Once baseline numbers are established, this benchmark will be extended with:
- In-app companion server measurements (HTTP + WebSocket)
- Gesture injection latency (tap, swipe)
- Concurrent operation throughput
- Memory overhead monitoring
