# Changelog

## Unreleased

- Added an in-app DevTools web UI served on a separate port (default `8889`,
  off by default via `BridgeConfig.enableDevTools`). Tabs for app info,
  live screenshot with click-to-tap and widget inspector mode, widget
  tree, find, app logs, network calls, and a bridge request log — all
  live-streamed via Server-Sent Events.
- Added `LogSink` (`TurboBridge.instance.logs`) and `NetworkLog`
  (`TurboBridge.instance.network`) public APIs so apps can push log lines
  and HTTP-client activity into the bridge. Exposed via `GET /logs` and
  `GET /network` for MCP and external tooling.
- Added `GET/POST /pick` endpoint that hit-tests the widget tree at an
  `(x, y)` point and returns the widget chain with type, key, rect, and
  text.
- Bridge middleware now captures request/response headers and body
  excerpts (16 KB cap) when DevTools is enabled, so the bridge log
  detail panel can show full requests.
- HTML/CSS/JS source for the DevTools UI lives under
  `lib/src/devtools/web/` and is loaded once via `rootBundle` at server
  start; declared in `flutter.assets`.

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