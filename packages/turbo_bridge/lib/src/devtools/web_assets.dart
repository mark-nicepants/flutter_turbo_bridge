import 'dart:async';

import 'package:flutter/services.dart';

import 'static_handler.dart';

/// Loads the DevTools single-file web bundle.
///
/// The TypeScript / Tailwind source lives under
/// `packages/turbo_bridge/devtools_ui/`. `npm run build` (or
/// `melos run build:devtools`) bundles it via Vite + vite-plugin-singlefile
/// into a single self-contained `index.html` written into
/// `lib/src/devtools/web/index.html`. That file is declared in
/// `pubspec.yaml` under `flutter.assets` and loaded here at server start.
const List<String> _indexCandidates = [
  'packages/turbo_bridge/lib/src/devtools/web/index.html',
  'lib/src/devtools/web/index.html',
];

class DevToolsWebAssetLoader {
  static Map<String, DevToolsAsset>? _cache;

  static Future<Map<String, DevToolsAsset>> load({
    AssetBundle? bundle,
    bool forceReload = false,
  }) async {
    if (_cache != null && !forceReload) return _cache!;
    final source = bundle ?? rootBundle;
    String? body;
    for (final key in _indexCandidates) {
      try {
        body = await source.loadString(key);
        break;
      } catch (_) {
        // try next candidate
      }
    }
    final result = <String, DevToolsAsset>{};
    if (body != null) {
      result['index.html'] =
          DevToolsAsset.text(body, 'text/html; charset=utf-8');
    }
    _cache = result;
    return result;
  }

  /// Test seam: replace the cached map with a synchronous fixture.
  static void seedForTests(Map<String, DevToolsAsset> assets) {
    _cache = assets;
  }

  static void resetForTests() {
    _cache = null;
  }
}
