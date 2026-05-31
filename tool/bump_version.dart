// Bumps the shipped version of every package in this workspace plus
// every doc / test that hard-codes a version string.
//
// Usage:
//   dart run tool/bump_version.dart 0.1.5
//
// The version is treated as opaque text; the script just edits known
// locations. Run from the repo root.
//
// What it touches:
//   - packages/turbo_bridge/pubspec.yaml             (version:)
//   - packages/turbo_bridge_client/pubspec.yaml      (version:)
//   - packages/turbo_bridge_mcp/pubspec.yaml         (version: + turbo_bridge_client dep)
//   - packages/turbo_bridge/lib/src/version.dart     (turboBridgeVersion const)
//   - packages/turbo_bridge_mcp/lib/src/version_info.dart (turboBridgeMcpVersion const)
//   - packages/turbo_bridge/README.md                ("bridgeVersion": "...")
//   - packages/turbo_bridge_client/README.md         (install snippet)
//   - docs/IMPLEMENTATION_PLAN.md                    ("bridgeVersion": "...")
//   - packages/turbo_bridge_client/test/bridge_connection_test.dart
//   - packages/turbo_bridge_mcp/test/server_test.dart  (mcpServerVersion expectations
//                                                     + matching bridgeVersion fields,
//                                                     while leaving the
//                                                     "newer than" comparison test
//                                                     untouched — bump that manually
//                                                     if you want it to stay
//                                                     bridge > mcp.)
//
// Tests that exercise version *comparison* logic (the "bridge newer
// than MCP" case in server_test.dart) deliberately use a higher version
// than the MCP version. After running this script, glance at that test
// and bump its bridgeVersion to one above the new MCP version.

import 'dart:io';

const _knownReplacements = <_Edit>[
  _Edit(
    path: 'packages/turbo_bridge/pubspec.yaml',
    pattern: r'^version: .+$',
    replacement: 'version: {VERSION}',
    multiline: true,
  ),
  _Edit(
    path: 'packages/turbo_bridge_client/pubspec.yaml',
    pattern: r'^version: .+$',
    replacement: 'version: {VERSION}',
    multiline: true,
  ),
  _Edit(
    path: 'packages/turbo_bridge_mcp/pubspec.yaml',
    pattern: r'^version: .+$',
    replacement: 'version: {VERSION}',
    multiline: true,
  ),
  _Edit(
    path: 'packages/turbo_bridge_mcp/pubspec.yaml',
    pattern: r'turbo_bridge_client: \^[^\s]+',
    replacement: r'turbo_bridge_client: ^{VERSION}',
  ),
  _Edit(
    path: 'packages/turbo_bridge/lib/src/version.dart',
    pattern: r"const String turboBridgeVersion = '[^']+';",
    replacement: r"const String turboBridgeVersion = '{VERSION}';",
  ),
  _Edit(
    path: 'packages/turbo_bridge_mcp/lib/src/version_info.dart',
    pattern: r"const String turboBridgeMcpVersion = '[^']+';",
    replacement: r"const String turboBridgeMcpVersion = '{VERSION}';",
  ),
  _Edit(
    path: 'packages/turbo_bridge/README.md',
    pattern: r'"bridgeVersion": "[^"]+"',
    replacement: r'"bridgeVersion": "{VERSION}"',
  ),
  _Edit(
    path: 'packages/turbo_bridge_client/README.md',
    pattern: r'turbo_bridge_client: \^[^\s\n]+',
    replacement: r'turbo_bridge_client: ^{VERSION}',
  ),
  _Edit(
    path: 'docs/IMPLEMENTATION_PLAN.md',
    pattern: r'"bridgeVersion": "[^"]+"',
    replacement: r'"bridgeVersion": "{VERSION}"',
  ),
  _Edit(
    path: 'packages/turbo_bridge_client/test/bridge_connection_test.dart',
    pattern: r"'0\.\d+\.\d+'",
    replacement: r"'{VERSION}'",
  ),
  // server_test.dart: the comparison test uses a deliberately higher
  // version. We only sync the "current MCP/bridge" expectations.
  _Edit(
    path: 'packages/turbo_bridge_mcp/test/server_test.dart',
    pattern: r"expect\(json\['mcpServerVersion'\], '[^']+'\);",
    replacement: r"expect(json['mcpServerVersion'], '{VERSION}');",
  ),
];

class _Edit {
  final String path;
  final String pattern;
  final String replacement;
  final bool multiline;
  const _Edit({
    required this.path,
    required this.pattern,
    required this.replacement,
    this.multiline = false,
  });
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/bump_version.dart <new-version>');
    exitCode = 64;
    return;
  }
  final version = args.first.trim();
  if (!RegExp(r'^\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?$').hasMatch(version)) {
    stderr.writeln('"$version" doesn\'t look like a semver string');
    exitCode = 64;
    return;
  }

  for (final edit in _knownReplacements) {
    final file = File(edit.path);
    if (!file.existsSync()) {
      stderr.writeln('skip: ${edit.path} not found');
      continue;
    }
    final before = file.readAsStringSync();
    final regex = RegExp(edit.pattern, multiLine: edit.multiline);
    final after = before.replaceAll(
      regex,
      edit.replacement.replaceAll('{VERSION}', version),
    );
    if (before == after) {
      stdout.writeln('   noop: ${edit.path}');
      continue;
    }
    file.writeAsStringSync(after);
    stdout.writeln('  wrote: ${edit.path}');
  }
  stdout.writeln('done. Don\'t forget:');
  stdout.writeln('  - eyeball server_test.dart "update-recommended" case');
  stdout.writeln('  - add a CHANGELOG.md entry per package');
  stdout.writeln('  - melos run analyze && (cd packages/turbo_bridge && flutter test)');
}
