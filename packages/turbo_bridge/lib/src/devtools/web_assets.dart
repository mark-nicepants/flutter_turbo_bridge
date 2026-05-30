import 'dart:async';

import 'package:flutter/services.dart';

import 'static_handler.dart';

/// Logical paths that the DevTools UI references, in the order they
/// should be loaded. Source lives in `lib/src/devtools/web/` and is
/// shipped with the package via `flutter.assets` in pubspec.yaml.
///
/// We try two key variants because the asset key differs between
/// consumer apps (where Flutter prefixes `packages/<pkg>/` and strips
/// `lib/`) and the package's own tests (where the key is the raw
/// pubspec-declared path).
const Map<String, _AssetSource> _sources = {
  'index.html': _AssetSource(
    [
      'packages/turbo_bridge/lib/src/devtools/web/index.html',
      'lib/src/devtools/web/index.html',
    ],
    'text/html; charset=utf-8',
  ),
  'styles.css': _AssetSource(
    [
      'packages/turbo_bridge/lib/src/devtools/web/styles.css',
      'lib/src/devtools/web/styles.css',
    ],
    'text/css; charset=utf-8',
  ),
  'app.js': _AssetSource(
    [
      'packages/turbo_bridge/lib/src/devtools/web/app.js',
      'lib/src/devtools/web/app.js',
    ],
    'application/javascript; charset=utf-8',
  ),
};

class _AssetSource {
  final List<String> candidateKeys;
  final String contentType;
  const _AssetSource(this.candidateKeys, this.contentType);
}

/// Loads the DevTools web bundle from the package's Flutter assets.
///
/// Called once at server start. Subsequent calls return the cached map.
/// Returns null entries for assets that fail to load (the static handler
/// then 404s on them) but never throws — a missing asset shouldn't take
/// down the bridge.
class DevToolsWebAssetLoader {
  static Map<String, DevToolsAsset>? _cache;

  static Future<Map<String, DevToolsAsset>> load({
    AssetBundle? bundle,
    bool forceReload = false,
  }) async {
    if (_cache != null && !forceReload) return _cache!;
    final source = bundle ?? rootBundle;
    final result = <String, DevToolsAsset>{};
    for (final entry in _sources.entries) {
      for (final key in entry.value.candidateKeys) {
        try {
          final body = await source.loadString(key);
          result[entry.key] =
              DevToolsAsset.text(body, entry.value.contentType);
          break;
        } catch (_) {
          // Try the next candidate key.
        }
      }
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
