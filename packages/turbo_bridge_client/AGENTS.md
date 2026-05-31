# AGENTS.md — `turbo_bridge_client`

> Local guide for AI agents working inside this package. See the
> repo-root `AGENTS.md` for cross-package rules (formatting, version
> bumps, performance targets).

## What this package does

**Pure Dart** client library for talking to a running `turbo_bridge`
instance. No Flutter dependency — usable from CLI tools, CI, MCP
servers, and integration test harnesses. Two transports:

- `BridgeConnection` — plain HTTP over the bridge's JSON-API port.
- `VmServiceConnection` (optional) — Dart VM Service for evaluation
  and deep inspection.

`TurboBridgeClient` is the unified facade.

## Layout

```
lib/
├── turbo_bridge_client.dart            # Public barrel
└── src/
    ├── client.dart                     # TurboBridgeClient facade
    ├── bridge_connection.dart          # HTTP transport (uses package:http)
    ├── vm_service_connection.dart      # Dart VM Service transport
    └── models/
        ├── app_info.dart
        ├── find_response.dart
        ├── screenshot_result.dart
        ├── tap_result.dart
        └── widget_node.dart
test/
├── bridge_connection_test.dart         # Mocks the HTTP client
└── models_test.dart
```

## Conventions

### No Flutter import — ever

This package targets the pure Dart SDK (`sdk: ^3.5.0`). It must build
without Flutter installed. Don't `import 'package:flutter/…'`. If you
need a type that lives in Flutter, mirror it as a plain Dart class in
`src/models/`.

### Public API is via `lib/turbo_bridge_client.dart`

Export only what consumers need. Add tests to the package's `test/`
directory whenever you add a public method.

### Use the existing HTTP client abstraction

`BridgeConnection` takes a `http.Client` via constructor. In tests
we inject a `MockClient` from `package:http/testing.dart`. Don't
create a `http.Client()` inside methods — that defeats testability.

### Method naming mirrors the JSON-API endpoints

`screenshot()`, `widgetTree()`, `tap()`, `appInfo()`, `find()`, etc.
When you add a new bridge endpoint (in `turbo_bridge`), add the
matching client method here with the same parameters. Keep the
mapping 1:1 — no transformations beyond JSON ↔ Dart.

### Errors are `BridgeException`

Non-2xx HTTP responses throw `BridgeException(message, statusCode)`.
Network errors propagate as standard `http` package exceptions. Don't
swallow them — let the caller decide whether to retry.

### Models are plain Dart classes with `fromJson` / `toJson`

No `freezed`, no `json_serializable`. Hand-written constructors and
`fromJson` factories. They're small and stable enough.

## Tests

Pure-Dart tests. Run them with `dart test` (or `melos run test:dart
--no-select` from the repo root).

```bash
dart test
dart test test/bridge_connection_test.dart
```

When you add a new method on `BridgeConnection` or `TurboBridgeClient`,
add a test that:
1. Mocks the underlying HTTP response.
2. Asserts the URL + method are right.
3. Asserts the response parses into the right Dart type.

## Version coupling

The `bridgeVersion` field on `AppInfo` is whatever the bridge sent
us — we don't compare it to anything in this package. Tests use the
literal `'0.1.5'` (kept in sync by `dart run tool/bump_version.dart`
from the repo root) just to assert JSON parsing — they're not version
assertions about *this* package.

## What NOT to do

- **Don't** add `dart:io` to anything in `lib/`. The client should
  work on any Dart platform. `dart:io` is fine in `test/` and CLI
  entry points.
- **Don't** depend on `turbo_bridge` or `turbo_bridge_mcp`. This
  package is the lower layer; the dependency graph only flows
  upward.
- **Don't** add per-call retries or timeout policies inside the
  client. That's the consumer's call. Expose tunables, don't decide
  for them.

## When you finish

1. `dart format --line-length 80 .`
2. `dart analyze`
3. `dart test`
4. Updated `README.md` if you added / changed a public method.
