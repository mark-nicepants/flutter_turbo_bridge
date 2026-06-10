# Changelog

## 0.3.1

- Fixed `TurboBridgeHttpInterceptor` triggering `Bad state: Can't finalize a
  finalized Request` when a `RetryPolicy` retries the request (e.g. a
  token-refresh retry). The interceptor now hands the inner client a fresh
  copy of the request on each attempt, so retries no longer re-finalize the
  same request.
- Raised the captured request/response body cap from 16 KB to 512 KB — for the
  DevTools request log and the `Dio` / `http` interceptor defaults — so larger
  JSON payloads are shown in full instead of being truncated.

## 0.3.0

- **Breaking — the DevTools web UI is no longer served by the app.** It now
  runs on the developer's machine (the `turbo_bridge_mcp` host server /
  `turbo_bridge_devtools`), so the app no longer bundles the UI as a Flutter
  asset and `turbo_bridge` can be added as a `dev_dependency`. With
  `enableDevTools: true` the bridge exposes the DevTools data endpoints
  (`devtools/requests`, `devtools/logs`, `devtools/navigation`,
  `devtools/network`) and the `events` SSE stream on its single port.
- **Breaking — `BridgeConfig` lost `devToolsPort` and `devToolsHost`** (there's
  no second in-app server anymore), and `/info`'s `devTools` block is now just
  `{ "enabled": <bool> }`.
- **Breaking — removed `BridgeConfig.projectRoot` / the
  `TURBO_BRIDGE_PROJECT_ROOT` dart-define.** Source-link resolution now happens
  host-side: the DevTools UI resolves `package:` locations from the project's
  `package_config.json`, for every package, with no configuration.
- Fixed the scroll direction in `GestureService`.

## 0.2.0

- **DevTools source links.** App log entries now capture their call site
  (file, line, column) from the stack trace and surface it in the DevTools
  log view. `package:<app>/…` locations resolve to ⌘-clickable editor links
  using the project root (below); `file://` locations resolve directly. The
  app no longer attempts to resolve `package:` URIs itself — that can't work
  on a real device (DDS blocks in-app VM service access), so resolution
  happens in the DevTools UI where the source files live.
- **`BridgeConfig.projectRoot`.** New option giving the DevTools UI the
  absolute path of your Flutter project on the host so it can turn
  `package:` source locations into `file://` editor links. Defaults to the
  `TURBO_BRIDGE_PROJECT_ROOT` dart-define, so you can wire it up with no
  code change:
  `flutter run --dart-define=TURBO_BRIDGE_PROJECT_ROOT="$(pwd)"`. The value
  is advertised on `/info` under `devTools.projectRoot`; the DevTools UI
  auto-applies it and also remembers a manually-entered root per app
  package.
- **In-flight network timeline.** `NetworkLog.start()` now emits an entry
  immediately and `complete()` / `fail()` mutate it in place, so in-flight
  requests appear on the DevTools timeline as growing, pulsing bars rather
  than only showing up once they finish.

## 0.1.6

- **HTTP interceptor adapters** for the two most common Flutter clients,
  shipped as optional entry points under `lib/interceptors/`:
  - `TurboBridgeDioInterceptor` (`package:turbo_bridge/interceptors/dio.dart`) —
    drop into `Dio.interceptors`; hooks `onRequest` / `onResponse` /
    `onError` and stashes the in-flight handle on `RequestOptions.extra`.
  - `TurboBridgeHttpInterceptor` (`package:turbo_bridge/interceptors/http.dart`) —
    an `HttpInterceptor` (from `http_interceptor` >= 3.0) for
    `InterceptedClient` / `InterceptedHttp`. `interceptRequest` opens the
    in-flight handle (correlated to its response via an `Expando` keyed on
    the request), and `interceptResponse` buffers the `StreamedResponse`
    to record the body before re-emitting it unchanged. Add it last in the
    `interceptors` list so it sees the final, fully-decorated request.
    Successful exchanges (including 4xx/5xx) capture request and response
    bodies. `http_interceptor` v3 has no error hook on the interceptor, so
    to surface failures whose underlying `Client.send` throws (DNS,
    timeout, connection refused), pass `interceptor.retryPolicy()` as the
    client's `retryPolicy` — the `RetryPolicy` exception hook fires on a
    thrown send and records the failure without adding retries. Wrap an
    existing policy with `interceptor.retryPolicy(wrapping: myPolicy)` to
    keep its retry behavior.
  Both adapters share a body-size cap (16 KB default) and an optional
  URL rewriter for stripping secrets / query strings, and no-op safely
  when `TurboBridge` isn't initialized. The host app adds `dio` or
  `http_interceptor` to its own pubspec — they are not transitive
  dependencies of `turbo_bridge`. Adding the http adapter bumps the
  package's Dart floor to 3.8.0 (Flutter 3.32+), which `http_interceptor`
  3.0 requires.
- **`NetworkLog.start()` / `InFlightNetworkCall` primitive** as the
  canonical entry path for HTTP interceptors. Returns a handle whose
  `complete()` / `fail()` / `cancel()` finalize the call with accurate
  wall-clock `durationMs`. `NetworkLog.record()` is unchanged for
  one-shot use sites.
- **In-flight requests on the DevTools timeline**: `start()` now surfaces
  the call immediately as an in-flight entry (`inFlight: true` in the
  `network` summary JSON) and `complete()` / `fail()` mutate that same
  entry in place and re-emit, so a slow request is visible while it runs
  instead of only after it finishes. The UI renders in-flight calls as a
  growing, pulsing **yellow** bar that grows toward "now" and settles to
  its final status colour on completion; `cancel()` retracts the entry.
  `NetworkCall` gained a mutable `inFlight` flag.
- **Smooth follow ticker in DevTools UI**: when "follow" is on, a
  ~30fps `requestAnimationFrame` loop pins `windowStart` to
  `Date.now() - windowDuration`, so the timeline glides forward
  continuously even when no new events are arriving.
- **Settings popup + multi-IDE picker**: gear icon top-right opens a
  persisted settings panel; "open in editor" links now support VS Code,
  Cursor, IntelliJ / Android Studio, and Zed via the picker.
- **Log source-location capture**: log lines now record the caller's
  file:line via `StackTrace.current` parsing. The log detail modal
  surfaces a clickable `vscode://` (or chosen IDE) link when the source
  resolves to a `file://` path; `package:` URIs render as plain text
  with a tooltip.
- **Modal polish**: detail modals stick at a stable top position so the
  page doesn't jump as content streams in. JSON syntax highlighting in
  bodies escapes HTML exactly once.
- See `docs/INFLIGHT_NETWORK_PLAN.md` for the design of an upcoming
  feature that renders in-flight requests as growing bars on the
  timeline.

## 0.1.5

- **Unified timeline DevTools** served on a separate port (default
  `8889`, off by default via `BridgeConfig.enableDevTools`). Replaces
  the previous tab-based UI with a single-page timeline showing
  Network / Logs / Navigation / Errors / Bridge API tracks above a
  draggable minimap and a scroll-anchored event list. Wheel-zoom,
  drag-pan, click-to-toggle and double-click-to-solo on rows,
  status-filter chips, configurable retention (10s/30s/1m/5m/30m/∞).
- **Postman-style network detail** modal: Response / Request / Timing /
  cURL / Raw tabs. The cURL tab exports a copy-pastable command with
  `Authorization`, `Cookie`, and `*-api-key` / `*-token` headers
  automatically masked as `##TOKEN##` / `##VALUE##`.
- **`TurboNavigationObserver`** — drop into `MaterialApp.navigatorObservers`
  to surface every `didPush` / `didPop` / `didReplace` on the timeline.
- **`LogSink`** (`TurboBridge.instance.logs`) and **`NetworkLog`**
  (`TurboBridge.instance.network`) public APIs so apps can push log
  lines and HTTP-client activity into the bridge. Exposed via
  `GET /logs` and `GET /network` for MCP and external tooling.
- **`GET/POST /pick`** endpoint that hit-tests the widget tree at an
  `(x, y)` point and returns the widget chain with type, key, rect,
  and text. Backs the inspector mode that earlier shipped in 0.1.4 and
  is still available via the underlying API.
- **Bridge middleware** now captures request/response headers and body
  excerpts (16 KB cap) when DevTools is enabled.
- **Bridge API row** (the bridge's own JSON-API traffic from MCP /
  DevTools / external clients) is now a separate, distinctly-colored
  category — off by default so it doesn't drown out app traffic.
- **TypeScript + Tailwind v4 + Vite build** for the DevTools UI under
  `packages/turbo_bridge/devtools_ui/`. `npm run dev` spins up Vite
  with a fake "mock device" so the UI can be developed without a
  Flutter app attached.
- Centralized the package version constant in `lib/src/version.dart`
  (`turboBridgeVersion`); used by `AppInfoService` and tests. A
  `tool/bump_version.dart` script keeps every version reference in
  sync — see the script's docstring for usage.

## 0.1.4

- Wire up `dart-lang/setup-dart` in the publish workflow so pub.dev OIDC trusted publishing is used instead of falling back to interactive OAuth.
- Bump reported `bridgeVersion` to keep the app-side compatibility metadata aligned with the released package version.

## 0.1.3

- Update install guidance to prefer `flutter pub add`, document the FVM path, and show non-release bridge startup.
- Refresh package dependencies, including `shelf_web_socket` 3.x.
- Raise the minimum Dart SDK to 3.5 and align Flutter support with the Melos 7 workspace tooling.

## 0.1.2

- Improve benchmark startup readiness for CI-driven screenshot and bridge runs.
- Prepare package metadata for the first automated pub.dev release.

## 0.1.1

- Update hosted-install guidance for pub.dev consumption.

## 0.1.0

- Initial public release of the in-app Flutter bridge server.