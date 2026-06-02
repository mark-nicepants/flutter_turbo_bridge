# DevTools: serve the UI from the host (Option 3)

Status: in progress · Target: **v0.3.0** (breaking)

## Why

The DevTools web UI was served by a second in-app HTTP server (`:8889`) from a
Flutter **asset** (`lib/src/devtools/web/index.html`). Flutter only bundles a
package's assets when it is a regular `dependency`, so `turbo_bridge` could not
be a `dev_dependency` without the UI 404-ing (`Not found: /index.html`).

Moving the UI to a **host-side** server removes the asset entirely, lets
`turbo_bridge` be a `dev_dependency`, collapses ADB forwarding to a single
port, and (follow-up) lets the host resolve `package:` source links itself.

## Architecture

Before: device runs `:8888` (JSON API) **and** `:8889` (DevTools UI: static
asset + `api/devtools/*` data + `/events` SSE + `api/*` proxy). Host forwards
both ports.

After:

```
Browser ──▶ host:8889  (turbo_bridge_mcp host UI server)
              ├─ GET /            → embedded UI bundle (Dart const string)
              ├─ /api/*           → reverse-proxy → device:8888 (strip "api/")
              └─ /events (SSE)    → streaming reverse-proxy → device:8888/events
Device:8888 (single server) — BridgeRouter + DevTools data + /events SSE,
   gated by enableDevTools. No second port, no static asset, no rootBundle.
```

The browser only talks to the host origin → **no CORS**.

## Work breakdown

### A. `turbo_bridge` (device) — drop the UI, keep the data
- Delete `lib/src/devtools/web_assets.dart`, `static_handler.dart`,
  `devtools_server.dart`, `lib/src/devtools/web/index.html`, and the
  `flutter: assets:` block in `pubspec.yaml`.
- Fold the DevTools data + SSE handlers into the single `:8888` server
  (root paths `devtools/requests[/:id]`, `devtools/logs`,
  `devtools/navigation`, `devtools/network[/:id]`, `events`), gated by
  `enableDevTools`. Remove `DevToolsServer` wiring from `bridge.dart`.
- `BridgeConfig`: keep `enableDevTools` (now = "expose DevTools data + SSE on
  the API port"); remove `devToolsPort` / `devToolsHost`; keep `projectRoot`.
- `/info` `devTools` block becomes `{ enabled, projectRoot? }` (no `port`).
- Drop the `x-turbo-devtools` mutating guard (it guarded the removed `:8889`).

### B. `turbo_bridge_mcp` (host) — serve UI + reverse-proxy
- `lib/src/devtools_host_server.dart`: shelf server on a host port (default
  `8889`) that serves the embedded bundle, reverse-proxies `/api/<rest>` →
  `device/<rest>` (strip leading `api/`), and **streams** `/events`
  (hand-rolled streaming proxy to avoid SSE buffering).
- `lib/src/devtools_bundle.g.dart`: the single-file `index.html` embedded as a
  gzip+base64 Dart const (robust under `dart run` / AOT / global activate).
- `bin/devtools.dart`: standalone entrypoint — single ADB forward + host UI
  server + auto-open browser. Declared under `executables:` →
  `turbo_bridge_devtools`. Flags: `--bridge-host/-h`, `--bridge-port/-p`,
  `--devtools-port`, `--no-open`, `--project-root`.
- `bin/turbo_bridge_mcp.dart`: also start the host UI server automatically
  (no auto-open), `--no-devtools` to opt out; URL logged to stderr.
- `adb_forwarding.dart`: simplify to a single forwarded bridge port
  (`ensureBridgeReachable`); delete the DevTools-port discovery + second
  forward.

### C. `devtools_ui` — retarget build
- No UI source changes: it already uses relative URLs (`api/…`, `events`) so
  served same-origin from the host it Just Works.
- Build: after `vite build`, wrap the single-file output into
  `turbo_bridge_mcp/lib/src/devtools_bundle.g.dart` (codegen step + melos
  script). Mock dev server (`npm run dev`, `mock.ts`) is unaffected.

### D. Run / open UX
- Primary: `dart pub global activate turbo_bridge_mcp` → `turbo_bridge_devtools`
  (forwards, serves, auto-opens browser). In-repo: `dart run
  turbo_bridge_mcp:devtools` or a `melos run devtools` script.
- Automatic: the MCP server starts the UI server too and logs the URL (no
  auto-open). Optionally expose the URL via an MCP tool/resource.

### E. Tests
- Device: DevTools data/SSE asserted on the `:8888` router; remove
  `DevToolsServer`/static-handler tests; `/info` no longer has `port`.
- Host: `devtools_host_server` tests — static serve, `api/` strip+proxy,
  `/events` streaming pass-through against a fake device server.
- `adb_forwarding_test.dart`: single-port.

## Follow-up — DONE
- Dropped `projectRoot` / `TURBO_BRIDGE_PROJECT_ROOT` entirely. The host
  server reads `.dart_tool/package_config.json` (`PackageResolver`) and
  serves a package→`lib/` map at `GET /__host/packages`; the UI fetches it
  once and resolves `package:` source links for **all** packages with zero
  config. Also added host-local control endpoints `GET /__host/status` and
  `POST /__host/reconnect` (re-runs `adb forward`) behind a connection-help
  popup in the UI.

## Risks
- **SSE through the proxy** — must stream unbuffered end-to-end. Hand-roll the
  `/events` proxy; verify against the browser EventSource.
- Non-MCP users now need the host server (standalone bin covers this).
- `enableDevTools` semantics change (port → data-exposure toggle): breaking,
  intended for v0.3.0.
