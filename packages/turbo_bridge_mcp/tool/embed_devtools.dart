// Embeds the built DevTools single-file UI bundle into a Dart source file as
// a gzip+base64 const, so the host DevTools server can serve it without any
// filesystem/asset lookup (robust under `dart run`, AOT, and global activate).
//
// Usage (from the repo root, after `npm run build` in devtools_ui):
//   dart run packages/turbo_bridge_mcp/tool/embed_devtools.dart
//
// Or via melos: `melos run build:devtools` (runs the Vite build first).
//
// Input:  packages/turbo_bridge/devtools_ui/dist/index.html
// Output: packages/turbo_bridge_mcp/lib/src/devtools_bundle.g.dart

import 'dart:convert';
import 'dart:io';

void main() {
  final repoRoot = _findRepoRoot();
  final input = File(
    '${repoRoot.path}/packages/turbo_bridge/devtools_ui/dist/index.html',
  );
  if (!input.existsSync()) {
    stderr.writeln(
      'DevTools bundle not found at ${input.path}.\n'
      'Run `npm run build` in packages/turbo_bridge/devtools_ui first.',
    );
    exit(1);
  }

  final html = input.readAsBytesSync();
  final gz = gzip.encode(html);
  final b64 = base64.encode(gz);

  // Chunk the base64 string so the generated source has reasonable line
  // lengths (dart format would otherwise choke on one giant line).
  final buf = StringBuffer();
  const chunk = 100;
  for (var i = 0; i < b64.length; i += chunk) {
    final end = (i + chunk < b64.length) ? i + chunk : b64.length;
    buf.writeln("    '${b64.substring(i, end)}'");
  }

  final out = File(
    '${repoRoot.path}/packages/turbo_bridge_mcp/lib/src/devtools_bundle.g.dart',
  );
  out.writeAsStringSync('''
// GENERATED — do not edit by hand.
// Produced by tool/embed_devtools.dart from
// packages/turbo_bridge/devtools_ui/dist/index.html.
// Regenerate with `melos run build:devtools`.

/// The DevTools single-file web UI (HTML with inlined JS + CSS), stored as a
/// gzip+base64 string. Decode with `devToolsBundleBytes`.
const String devToolsBundleGzipBase64 =
${buf.toString().trimRight()};
''');

  stdout.writeln(
    'Wrote ${out.path} '
    '(${html.length} B html -> ${gz.length} B gz -> ${b64.length} B base64)',
  );
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/melos.yaml').existsSync() ||
        Directory('${dir.path}/packages/turbo_bridge_mcp').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      // Fall back to current dir; paths above will then fail loudly.
      return Directory.current;
    }
    dir = parent;
  }
}
