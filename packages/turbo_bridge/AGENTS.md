# AGENTS.md — `turbo_bridge` package

> Local guide for AI agents working inside this package. See the
> repo-root `AGENTS.md` for cross-package rules (version bumps,
> formatting, performance targets, etc.).

## What this package does

In-app companion server. A Flutter package that you drop into a host
app. Starts a `shelf` HTTP server on `:8888` (JSON API for AI agents +
external tooling) and optionally a second HTTP server on `:8889`
serving the DevTools web UI.

```
TurboBridge.start(config: BridgeConfig(enableDevTools: true))
   ├── shelf server :8888   ← AI/MCP/external clients hit this
   └── shelf server :8889   ← optional DevTools browser UI
```

## Layout

```
lib/
├── turbo_bridge.dart                   # Public exports (the barrel — keep it
│                                       #   minimal; export only types
│                                       #   consumers should use)
└── src/
    ├── bridge.dart                     # TurboBridge singleton + lifecycle
    ├── bridge_config.dart              # BridgeConfig (host/port/DevTools flags)
    ├── version.dart                    # turboBridgeVersion — central constant
    ├── server/
    │   └── router.dart                 # JSON-API shelf router (port 8888)
    ├── services/                       # One service per capability
    │   ├── app_info_service.dart
    │   ├── find_service.dart
    │   ├── gesture_service.dart
    │   ├── screenshot_service.dart
    │   └── widget_tree_service.dart
    └── devtools/                       # Everything for the :8889 UI
        ├── devtools_server.dart        # Owns the second HTTP server
        ├── devtools_router.dart        # /api/* proxy + /events SSE
        ├── static_handler.dart         # Serves the bundled index.html
        ├── event_bus.dart              # Pub/sub for SSE
        ├── request_log.dart            # Ring buffer for /api/devtools/requests
        ├── log_sink.dart               # Public LogSink (TurboBridge.instance.logs)
        ├── network_log.dart            # Public NetworkLog
        ├── navigation_log.dart         # Public NavigationLog
        ├── turbo_navigation_observer.dart  # NavigatorObserver helper
        ├── web_assets.dart             # rootBundle loader for the bundle
        └── web/
            └── index.html              # ← Generated; do NOT hand-edit
devtools_ui/                            # TypeScript source for the UI
└── …                                   # See packages/turbo_bridge/devtools_ui/AGENTS.md
test/
├── services_test.dart                  # WidgetTester-based tests
└── devtools_test.dart                  # Mostly pure-Dart, plus one E2E
```

## Conventions

### Public API is via `lib/turbo_bridge.dart`

If you add a new public type, **explicitly add an `export` line** in
`turbo_bridge.dart` (with a `show …` if the file exports more than you
want surfaced). Prefer `show` over bare `export 'x.dart';` so the
public surface stays auditable.

### Version is a constant, not a hardcoded string

Any code that needs the bridge version reads `turboBridgeVersion` from
`src/version.dart` (re-exported from the barrel). Never hardcode
`'0.1.x'` in service code, tests, or response payloads. If you need to
bump the version, see the root `AGENTS.md` (`dart run tool/bump_version.dart`).

### Services are injectable + side-effect-free at construction

`BridgeRouter` and `DevToolsRouter` take services via constructor
parameters. `TurboBridge.createForTest()` builds one with mocks, but
production code uses defaults. Don't add `static` mutable state to any
service.

### DevTools UI source lives in `devtools_ui/`, output in `lib/src/devtools/web/`

- Edit TS/CSS/HTML in `devtools_ui/`. See its own `AGENTS.md`.
- The bundled `lib/src/devtools/web/index.html` is a **build artifact**
  (single-file Vite output). Re-generate it after any DevTools UI
  change: `melos run build:devtools` from the repo root, or
  `npm run build` inside `devtools_ui/`. Commit the regenerated
  `index.html` together with the source change so consumers don't
  have to run npm.

### Asset loading uses `rootBundle`

`DevToolsWebAssetLoader.load()` reads `index.html` once at server
start via Flutter's `rootBundle`. Two candidate keys are tried
(`packages/turbo_bridge/lib/…` and `lib/…`) so the loader works both
in a consuming app and in our own `flutter test` runs. Don't change
this contract without updating both call sites and the
`flutter.assets:` block in `pubspec.yaml`.

### Bodies, headers, and timing

When DevTools is enabled the bridge middleware buffers request +
response bodies up to a 16 KB cap and includes headers in the
`/api/devtools/requests/:id` detail endpoint. This is where the
Postman-style network detail and the cURL export get their data. If
you add new shelf middleware that wraps requests, make sure it
preserves the `'shelf.io.connection_info'` context entry — the
detail-view's remote-address column relies on it.

## Tests

```bash
flutter test                                  # all tests
flutter test test/devtools_test.dart          # DevTools-only
flutter test --plain-name 'pickAt returns'    # one
```

- `services_test.dart` uses `testWidgets` and needs a Flutter binding.
- `devtools_test.dart` runs mostly without a binding (uses plain `test()`)
  and has one end-to-end test that boots a real `TurboBridge` on
  loopback. Avoid widget-dependent assertions in that file.

When you add a new field to `LogEntry`/`NetworkCall`/`NavigationEntry`,
add at least one test that asserts the field round-trips through
`toJson()` (and `toDetailJson()` for the larger ones).

## What NOT to do

- **Don't** add `print()` — use `debugPrint`. The bridge runs inside a
  user's app and we don't want spam.
- **Don't** block the main isolate. All service methods must return
  fast enough to stay under the performance targets (see root
  `AGENTS.md`).
- **Don't** add a new endpoint without:
  1. Wiring it into `server/router.dart`
  2. Adding it to the HTTP API section of the package README
  3. Adding a test (router-level or service-level)
- **Don't** reach across packages. This package never imports
  `turbo_bridge_client` or `turbo_bridge_mcp`.

## When you finish

1. `melos run format --no-select`
2. `melos run analyze --no-select`
3. `flutter test`
4. Updated the relevant README section if behavior changed
5. If you touched the DevTools UI, also rebuilt the bundle
