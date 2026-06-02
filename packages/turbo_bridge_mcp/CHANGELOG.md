# Changelog

## Unreleased

- DevTools UI: reorganized the network detail into a primary
  Request / Response / Curl nav plus a secondary Headers / Params / Body nav
  with counts, and added a Params view listing query + form parameters. The
  body now scrolls in a single region (no more nested scrollbars) and shows
  larger payloads in full.
- DevTools UI: fixed live-follow / timeline-overview dragging during an idle
  session. Following is now anchored to wall-clock time, so dragging the
  overview back into history works immediately (it no longer snaps back to the
  end or sticks the viewport to the right edge until you reach an event), and
  releasing at the right edge re-engages following.

## 0.3.0

- Serves the Turbo Bridge **DevTools web UI on the host**. New
  `turbo_bridge_devtools` executable (`dart run turbo_bridge_mcp:devtools` or,
  after `dart pub global activate`, `turbo_bridge_devtools`) starts a local
  server that serves the UI and reverse-proxies the app's DevTools endpoints
  and `events` SSE stream over the bridge port. The MCP server also starts it
  automatically (disable with `--no-devtools`).
- Resolves `package:` source links to absolute file paths from the project's
  `package_config.json`, so DevTools call-site links are ⌘-clickable for every
  package with no configuration.
- Added a connection helper for the UI: status + one-click `adb forward`
  reconnect when the device drops.
- Simplified ADB forwarding to the single bridge port (the DevTools port is no
  longer forwarded — the UI is hosted locally).
- Bumped reported `mcpServerVersion` to `0.3.0`.

## 0.2.0

- Added automatic ADB port forwarding: the MCP server sets up the
  `adb forward` tunnels it needs to reach the in-app bridge on a connected
  Android device or emulator, instead of requiring them to be wired up by
  hand.
- Bumped reported `mcpServerVersion` to `0.2.0` so compatibility metadata
  aligns with the released package.

## 0.1.6

- Bumped reported `mcpServerVersion` to `0.1.6` so compatibility
  metadata aligns with the released package. No MCP tool changes.

## 0.1.5

- Added `flutter_recent_logs` MCP tool: returns recent app-emitted log
  lines from `TurboBridge.instance.logs`, with optional level filter.
- Added `flutter_recent_network` MCP tool: returns recent network calls
  the app pushed into `TurboBridge.instance.network`.
- Bumped reported `mcpServerVersion` to `0.1.5` so compatibility
  metadata aligns with the released package.

## 0.1.4

- Bump reported MCP server version to `0.1.4` so compatibility metadata aligns with the released package version.
- Released alongside `turbo_bridge` 0.1.4 via the fixed pub.dev OIDC trusted publishing flow.

## 0.1.3

- Rename the recommended MCP server key from `flutter` to `turbo_bridge` across host configuration examples.
- Refresh MCP package dependencies, including `mcp_dart` 2.2 and the matching `turbo_bridge_client` release.
- Raise the minimum Dart SDK to 3.5 for the Melos 7 workspace migration.

## 0.1.2

- Share package checks with CI before tagged pub.dev publishes.
- Align MCP compatibility metadata and docs for the automated release.

## 0.1.1

- Align package and MCP server version reporting.
- Update hosted-install guidance for pub.dev and global MCP activation.

## 0.1.0

- Initial public release of the Turbo Bridge MCP server.
- Added app info compatibility metadata to nudge hosts when the MCP package lags behind the app bridge version.