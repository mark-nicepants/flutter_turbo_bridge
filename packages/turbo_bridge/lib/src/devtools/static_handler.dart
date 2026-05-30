import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Serves the DevTools web bundle from a pre-loaded asset map.
///
/// Assets are loaded once at server start via [DevToolsWebAssetLoader] and
/// passed in here; this handler is purely synchronous so it does not block
/// shelf's request pipeline.
class DevToolsStaticHandler {
  final Map<String, DevToolsAsset> assets;

  DevToolsStaticHandler({required this.assets});

  Response handle(Request request) {
    final raw = request.url.path;
    final path = raw.isEmpty || raw == '/' ? 'index.html' : raw;
    final asset = assets[path];
    if (asset == null) {
      // SPA fallback — unknown deep links resolve to the shell.
      final index = assets['index.html'];
      if (index != null) {
        return Response.ok(
          index.body,
          headers: {'content-type': index.contentType},
        );
      }
      return Response.notFound('Not found: /$path');
    }
    return Response.ok(
      asset.bytes ?? asset.body,
      headers: {'content-type': asset.contentType},
    );
  }
}

class DevToolsAsset {
  final String? body;
  final List<int>? bytes;
  final String contentType;

  const DevToolsAsset.text(this.body, this.contentType) : bytes = null;
  const DevToolsAsset.binary(List<int> data, this.contentType)
      : bytes = data,
        body = null;
}

/// Convenience for tests that want to assert a textual response body.
String decodeAssetBody(DevToolsAsset asset) {
  if (asset.body != null) return asset.body!;
  return utf8.decode(asset.bytes!);
}
