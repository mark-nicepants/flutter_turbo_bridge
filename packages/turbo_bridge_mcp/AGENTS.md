# AGENTS.md — `turbo_bridge_mcp`

> Local guide for AI agents working inside this package. See the
> repo-root `AGENTS.md` for cross-package rules (formatting, version
> bumps).

## What this package does

**Pure Dart CLI** that runs as a Model Context Protocol (MCP) server
over stdio. Translates MCP `tools` / `resources` / `prompts` calls
from an LLM host (Claude Desktop, Cursor, VS Code Copilot, …) into
HTTP calls against `turbo_bridge` via `turbo_bridge_client`.

```
LLM host  ⇆ stdio ⇆  turbo_bridge_mcp  ⇆ HTTP ⇆  turbo_bridge  (in-app)
```

## Layout

```
bin/
└── turbo_bridge_mcp.dart           # CLI entry point (stdio MCP server)
lib/
├── turbo_bridge_mcp.dart           # Public barrel
└── src/
    ├── server.dart                 # Wires tools/resources/prompts into McpServer
    ├── version_info.dart           # turboBridgeMcpVersion + bridge-vs-mcp
    │                               # compatibility helper
    ├── response_metadata.dart      # Shared startedAtUtc/completedAtUtc envelope
    ├── tools/                      # One file per MCP tool
    │   ├── app_info_tool.dart
    │   ├── enter_text_tool.dart
    │   ├── find_widget_tool.dart
    │   ├── recent_logs_tool.dart
    │   ├── recent_network_tool.dart
    │   ├── screenshot_tool.dart
    │   ├── scroll_tool.dart
    │   ├── swipe_tool.dart
    │   ├── tap_tool.dart
    │   └── widget_tree_tool.dart
    ├── resources/
    │   ├── app_info_resource.dart
    │   └── widget_tree_resource.dart
    └── prompts/
        └── inspect_prompt.dart
test/
└── server_test.dart                # mcp_dart-driven integration tests
```

## Conventions

### One file per tool / resource / prompt

Each tool is its own `register*` function that takes
`(McpServer server, TurboBridgeClient client)`. The function builds
the input schema, registers the callback, and returns nothing. Tools
should be ~60 lines or less — if a tool grows, factor its body into
a private helper rather than splitting the registration.

### Every response goes through `response_metadata.dart`

Use `encodeResponse(...)` (or `encodeErrorResponse(...)` on failure)
so every MCP response carries `startedAtUtc` / `completedAtUtc`
fields. The benchmark suite and timing assertions rely on these.

### Compatibility metadata

`buildMcpCompatibilityInfo(bridgeVersion: ...)` in `version_info.dart`
compares the bridge version to `turboBridgeMcpVersion` and embeds a
`mcpVersionStatus` ('up-to-date' / 'update-recommended' /
'bridge-update-recommended' / 'unknown') in `flutter_app_info`
responses. Whenever you bump either side's version (via `dart run
tool/bump_version.dart` from the repo root), eyeball the
"update-recommended" test case in `server_test.dart` — its
`bridgeVersion` fixture must be **strictly greater** than the new
`turboBridgeMcpVersion` for the test to still exercise that branch.

### Tool naming: `flutter_*`

All tool names are prefixed `flutter_` (e.g. `flutter_screenshot`,
`flutter_recent_logs`) so they group together in MCP host UIs and
don't collide with other servers.

### Schemas use `mcp_dart`'s `JsonSchema` builders

Don't build raw JSON schemas. Use `JsonSchema.object(properties: {…})`,
`JsonSchema.integer(...)`, etc. — the helpers ensure compatibility
with every MCP host's validator.

### Optional args are read with `args['key'] as Type?`

The runtime gives you a non-nullable `Map`. Don't write
`args?['key']` — the linter rejects it as `invalid_null_aware_operator`.

## Tests

```bash
dart test
```

Tests use `mocktail` to stub the underlying `TurboBridgeClient`. When
you add a new tool, add at least:
1. A happy-path test that asserts the response JSON shape.
2. An error test that asserts `isError: true` is set and the message
   is captured.

## What NOT to do

- **Don't** import `turbo_bridge` (the Flutter package). This is a
  pure Dart CLI. The only allowed bridge-side import is via
  `turbo_bridge_client`.
- **Don't** add `print()` to anything that runs in `bin/`. MCP uses
  stdio for the protocol — stray stdout bytes will break the host.
  Use `stderr.writeln(...)` for diagnostics.
- **Don't** add long-running state. Each MCP call is independent.
- **Don't** rename a tool without bumping the package version and
  documenting the change in `CHANGELOG.md` — LLM host configs pin to
  tool names.

## When you finish

1. `dart format --line-length 80 .`
2. `dart analyze`
3. `dart test`
4. Updated `README.md`'s `## MCP Tools` (or Resources / Prompts)
   section if you added/changed anything user-visible.
