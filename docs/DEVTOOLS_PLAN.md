# Turbo Bridge DevTools — Design Document

Status: **shipped** — see `packages/turbo_bridge/README.md` for current
usage. This document is preserved as the implementation history and
decision log.
Owner: @mark-nicepants
Last updated: 2026-05-30

## Implementation status

| Phase | Status |
|---|---|
| Phase 0 — config + scaffolding | ✅ shipped |
| Phase 1 — read-only MVP (Overview, Screenshot, Tree, Bridge log) | ✅ shipped |
| Phase 2 — interactive control (tap, find, gesture, CSRF guard) | ✅ shipped |
| Phase 3a — app logs + network ingestion (DevTools + MCP) | ✅ shipped |
| Phase 3b — widget inspector mode (`/pick` + UI) | ✅ shipped (source-location lookup deferred) |
| Phase 3c — request/response detail view | ✅ shipped |

Deviations from the original plan:

- **Vanilla HTML/JS instead of Preact + Vite.** Avoids the npm/node
  dependency for contributors. Files live in `lib/src/devtools/web/` and
  are loaded once via `rootBundle` at server start (declared in
  `flutter.assets` in the package pubspec).
- **Source-location resolution deferred.** `WidgetTreeService.pickAt`
  returns the widget chain with `type`, `key`, `rect`, `text`. Adding
  `creationLocation` requires VM-Service plumbing; left as a follow-up.



## 1. Background

`turbo_bridge` already exposes a JSON/HTTP API on port `8888` for AI agents
(screenshots, widget tree, gestures, find, app info). When a developer is
debugging an integration, the only way to see what the bridge sees is to
hit endpoints with `curl`/Postman or rely on the MCP client.

A built-in web UI would let a developer point a browser at the running app
and visually explore the same surface area the AI sees — without changing
the app code, installing a Flutter DevTools extension, or starting a second
process. It is also a powerful demo and onboarding tool.

## 2. Goals & non-goals

### Goals

- Ship a browser-based DevTool inside the `turbo_bridge` package itself —
  no extra dependency the user must add.
- Serve it on a **different port** from the JSON API (default `8889`),
  configurable, opt-in via `BridgeConfig`.
- Show live data from the running app: latest screenshot, widget tree,
  app info, request log, gestures replayed visually.
- Support a developer "drive the app" workflow: click on the screenshot
  → fire a tap; pick a widget in the tree → highlight it on the screenshot.
- Stay lightweight: no heavy framework, fast cold-load, runs on a phone
  or tablet browser if needed.
- Keep the surface area testable from Dart side without a headless browser.

### Non-goals (initial)

- We are **not** building a replacement for Flutter DevTools (no VM service
  proxying, no memory/perf tooling, no source-level debugging).
- Not building an authentication layer beyond the existing
  loopback-binding guard. DevTools is dev-only and assumes the network
  trust model that the bridge already assumes.
- Not building multi-session / collaborative editing.
- Not building an extension/plugin system in v1.

## 3. Architecture

### 3.1 High level

```
+-----------------------+              +---------------------+
|  Flutter app          |              |  Browser            |
|  (debug/profile)      |              |                     |
|  ┌─────────────────┐  |   :8888 JSON |  ┌───────────────┐  |
|  │ TurboBridge     │<─┼──────────────┤  │ DevTools SPA  │  |
|  │  - REST router  │  |              |  │ (HTML+JS)     │  |
|  │  - SSE stream   │  |   :8889 UI   |  │ - tabs        │  |
|  │  - DevTools     │<─┼──────────────┤  │ - canvas      │  |
|  │    static srv   │  |              |  │ - tree view   │  |
|  │  - DevTools API │<─┼──────────────┤  │ - log         │  |
|  └─────────────────┘  |   :8889 /api │  └───────────────┘  |
+-----------------------+              +---------------------+
```

- **Two ports**:
  - `8888` — existing JSON API (unchanged, AI-agent facing).
  - `8889` — new DevTools port. Serves the static SPA at `/`, a
    DevTools-only JSON API under `/api/*`, and a Server-Sent Events
    stream at `/events`.
- The DevTools port internally proxies most calls to the same service
  layer the JSON API uses (`ScreenshotService`, `WidgetTreeService`, etc.),
  so we get the UI for free as services grow.

Why a separate port?
- Explicit opt-in: defaults to **disabled**, so it never opens an extra
  socket on a release/CI build.
- Keeps the AI-agent surface (8888) free of HTML, CORS quirks, and
  preflight requests.
- Easy to firewall or LAN-share independently (e.g. user might want
  DevTools reachable from a colleague's machine but keep 8888 loopback).

### 3.2 Dart-side components

New under `packages/turbo_bridge/lib/src/devtools/`:

| File | Responsibility |
| --- | --- |
| `devtools_server.dart` | Owns the second shelf server, lifecycle, bind/release. |
| `devtools_router.dart` | Routes `/`, `/assets/...`, `/api/...`, `/events`. |
| `static_handler.dart` | Reads pre-built web assets from `rootBundle`. |
| `event_bus.dart` | In-process stream that other services emit into (request log, route changes). |
| `request_log.dart` | Ring buffer of recent JSON API requests + timings. |

Bridge wiring:

- `BridgeConfig` gains `enableDevTools` (default `false`),
  `devToolsPort` (default `8889`), `devToolsHost` (default `127.0.0.1`).
- `TurboBridge.start()` starts the DevTools server after the main
  server is up. Failure to bind the second port logs a warning but does
  not abort startup.
- The main router (`server/router.dart`) is wrapped to push entries
  into the shared `request_log` and `event_bus` (timing, status, path).

### 3.3 Frontend tech choice

**Recommendation: Preact + htm + Vite, prebuilt and shipped as a
Flutter asset bundle.**

Rationale:

- Preact gives us components and a real reactive update model without
  the bundle weight of React (~3 KB gzipped vs ~45 KB).
- `htm` removes the JSX build step from authoring but Vite still gives
  us module bundling, CSS handling, and dev-time HMR.
- Final output is a static `index.html` + a couple of JS/CSS chunks,
  which Flutter can ship via `assets:` in `pubspec.yaml`.
- No runtime dependency on a CDN — fully air-gapped, works offline.

Alternatives considered:
- **Vanilla JS only**: lowest weight but the widget tree view, panels,
  and SSE handling get unwieldy fast.
- **Lit / Web Components**: viable, but the team has no existing Lit
  code; Preact ecosystem is more familiar.
- **Svelte / Vue**: fine, but mixing in Vue runtime is more weight than
  Preact and adds a build dependency without clear benefit.
- **Flutter web build**: tempting (reuse Dart) but adds many MB to the
  package — non-starter.

Page styling: a single CSS file using CSS custom properties; ship a
dark theme by default, support `prefers-color-scheme`. No CSS
framework — keep total CSS under ~10 KB.

### 3.4 Asset packaging

- Frontend source lives in `packages/turbo_bridge/devtools_ui/`
  (separate from the Dart `lib/`), with its own `package.json`.
- `npm run build` outputs to
  `packages/turbo_bridge/lib/src/devtools/assets/`.
- These built assets are declared in `pubspec.yaml` under `flutter.assets`.
- At runtime, `static_handler.dart` resolves a path → asset key,
  reads via `rootBundle.load`, returns the bytes with the right
  content-type.
- A pre-publish step (Melos script) runs `npm ci && npm run build`
  and asserts the asset folder is clean — so we never publish a stale
  bundle.

### 3.5 Real-time data flow

Two channels:

1. **REST `/api/*`** for snapshot fetches (screenshot, tree, info, find).
   These mirror the existing 8888 endpoints but are colocated for
   same-origin convenience.
2. **SSE `/events`** for push updates:
   - `request` — every JSON API call (timestamp, method, path, status, ms).
   - `route` — current route changed (hook into a `RouteObserver`).
   - `frame` — periodic heartbeat (optional, used for "live screenshot"
     mode at ~2 fps).
   - `widgetTreeChanged` — coarse signal that the tree probably changed
     (debounced from a `WidgetsBinding.addPersistentFrameCallback`).

Why SSE over WebSocket: one-way push only, simpler reconnect semantics,
no extra dependency (shelf can stream a `text/event-stream` body). If
we later need bidirectional control (e.g. record/replay), upgrade to
WebSocket on a new endpoint without changing existing ones.

## 4. Feature set

Prioritized. P1 = MVP, P2 = nice next, P3 = stretch.

### 4.1 P1 — must have for v1

- **App overview tab**
  - App info card: platform, screen size, pixel ratio, dark mode,
    current route, bridge version.
  - Health badge (green/red) with last ping timestamp.
- **Live screenshot tab**
  - Click "Capture" to pull the latest screenshot via `/screenshot`.
  - Auto-refresh toggle (off / 1 fps / 2 fps).
  - Click on the screenshot → fires a tap at that coordinate
    (translated through pixel ratio). Confirmation toast with result.
  - Right-click → context menu: "Find widget under here", "Copy coord".
- **Widget tree tab**
  - Collapsible JSON tree of `/tree` output.
  - Filter box (matches widget type / text content).
  - Depth slider, "compact" toggle.
  - Selecting a node draws its bounding rect overlay on the latest
    screenshot in a side-by-side view.
- **Request log**
  - Tail of recent JSON API calls (method, path, status, ms, source IP).
  - Filter by status / method / path-substring.
  - Click to expand → show request query/body and response summary.
- **Find tool**
  - Form for `/find` parameters.
  - Results list with bounding rects highlighted on screenshot.
- **Gesture pad**
  - Buttons for swipe up/down/left/right at current screen center.
  - Text-input field with "send" button using `/input`.

### 4.2 P2 — high-value follow-ups

- **Action recorder** — record clicks + finds in DevTools, export as a
  Dart `flutter_test` script or a `curl` sequence.
- **Routes timeline** — list of route changes with timestamps, jump to
  the screenshot snapshot at that moment if we cache them.
- **Theme / locale toggles** — POST to a new bridge endpoint to flip
  brightness or locale for quick QA without rebuilding.
- **Snapshot bookmarks** — save a screenshot + tree + info as a single
  zip/json for filing bug reports.
- **Diff view** — compare two captures (tree diff + image diff).

### 4.3 P3 — speculative

- **Tap heat map** — overlay where taps have landed over a session.
- **Performance overlay mirror** — pull frame timings from VM service
  through the bridge and graph them.
- **Embedded mcp playground** — let the developer manually call the
  MCP tools and see the same JSON the AI sees.
- **Mobile companion mode** — DevTools UI optimized for a phone
  browser pointing at a desktop-running app.

## 5. Security & UX considerations

- DevTools is **off by default**. Enabling requires explicitly setting
  `BridgeConfig(enableDevTools: true)`. Document loudly that this opens
  another port and should never ship in a production build (same
  guidance as the main bridge).
- Default bind host is loopback (`127.0.0.1`). A separate
  `devToolsHost: '0.0.0.0'` is required to expose to LAN, and we log
  a `[WARN]` line when binding to a non-loopback interface.
- All DevTools API endpoints are read-mostly, but `tap`/`swipe`/etc.
  do mutate the app. We add a CSRF-style same-origin check: the
  DevTools SPA always issues requests with a custom header
  `x-turbo-devtools: 1` and the server rejects mutating verbs without
  it. This prevents drive-by browser pages from puppeting the app via
  a leaked LAN address.
- No persistent storage of captured screenshots on disk — everything
  lives in memory and is dropped on bridge shutdown. We can add an
  opt-in "save to disk" later.

## 6. Build & release pipeline

- A new Melos script `melos run build:devtools` runs
  `npm ci && npm run build` in `devtools_ui/`.
- CI gains a step before the existing analyze/test:
  - Run `build:devtools`
  - `git diff --exit-code` on the assets folder, to ensure committed
    assets match source.
- The pre-publish workflow (`publish.yml`) runs `build:devtools` first
  so what gets uploaded to pub.dev is always the fresh bundle.
- Frontend code is tested with Vitest (unit) and a single Playwright
  smoke test that boots a stub bridge and clicks through the tabs.

## 7. Phased implementation plan

### Phase 0 — scaffolding (1–2 days)

- Add `BridgeConfig.enableDevTools`, `devToolsPort`, `devToolsHost`.
- Stand up `devtools_server.dart` with a hard-coded `Hello DevTools`
  HTML response. Verify it binds, opens on `8889`, and can be hit
  from a browser while the main `8888` server keeps running.
- Add a Melos script and asset glob, even if assets are stubbed.

### Phase 1 — read-only MVP (3–5 days)

- Build Preact app shell with three tabs: Overview, Screenshot, Tree.
- Implement `/api/info`, `/api/screenshot`, `/api/tree` as thin
  proxies onto existing services (or rebind the existing handlers
  under the new prefix).
- Implement SSE `/events` with `request` events only.
- Ship the static bundle, wire `static_handler.dart`.
- Documentation: README section, screenshot, "how to enable".

### Phase 2 — interactive control (3–4 days)

- Add tap-on-screenshot, gesture pad, find form, input field.
- Add CSRF header guard on mutating endpoints.
- Add request log UI with filters.

### Phase 3 — polish & follow-ups (open-ended)

- P2 features (recorder, routes timeline, theme/locale toggles).
- Mobile-friendly layout.
- Performance budget review and dead-code stripping.

## 8. Open questions / decisions to make before coding

1. **Frontend framework lock-in**: Preact + htm + Vite is the
   recommendation. Confirm or pick an alternative before Phase 1.
2. **SSE vs WebSocket** for the event stream — SSE keeps it simpler
   but blocks future bidirectional needs. Decide whether to plan for
   a later WS upgrade or just start with WS from the beginning.
3. **Hosting the screenshot stream**: cheapest is "client polls", but
   we could push a base64 PNG over SSE at 1–2 fps. PNG over SSE is
   wasteful but trivial — acceptable for v1?
4. **Bundle size budget**: target gzipped `index.html + js + css +
   svgs` under 60 KB. Need a `npm run analyze` step to track this.
5. **Asset packaging cost**: shipping built assets in the published
   pub package adds size; estimate after Phase 1 and decide if
   alternative delivery (download-on-first-run from GitHub Releases)
   is worth the complexity. Default answer: no, keep it self-contained.
6. **Compatibility with `turbo_bridge_mcp`**: should the MCP server
   expose a `/devtools_url` tool so the LLM can surface the link
   to the developer? Probably yes, low cost.
7. **Naming**: "DevTools" overloads the Flutter DevTools brand.
   Consider `turbo_bridge_inspector` or `bridge_console` to avoid
   confusion. Decide before public docs land.
