import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shelf/shelf.dart';

import '../services/app_info_service.dart';
import '../services/gesture_service.dart';
import '../services/screenshot_service.dart';
import '../services/widget_tree_service.dart';

/// HTTP router for the Turbo Bridge server.
///
/// Maps HTTP endpoints to service calls with minimal overhead.
class BridgeRouter {
  final ScreenshotService screenshotService;
  final WidgetTreeService widgetTreeService;
  final GestureService gestureService;
  final AppInfoService appInfoService;
  final bool includeTimingHeaders;

  BridgeRouter({
    required this.screenshotService,
    required this.widgetTreeService,
    required this.gestureService,
    required this.appInfoService,
    this.includeTimingHeaders = true,
  });

  /// The shelf [Handler] for this router.
  Handler get handler => _handle;

  Future<Response> _handle(Request request) async {
    final path = request.url.path;
    final method = request.method;

    try {
      return switch ((method, path)) {
        ('GET', 'screenshot') => await _handleScreenshot(request),
        ('GET', 'tree') => _handleTree(request),
        ('POST', 'tap') => await _handleTap(request),
        ('GET', 'info') => _handleInfo(request),
        ('GET', 'health') => _handleHealth(),
        _ => Response.notFound('Not found: $method /$path'),
      };
    } catch (e, stack) {
      debugPrint('TurboBridge error: $e\n$stack');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleScreenshot(Request request) async {
    final sw = Stopwatch()..start();

    final pixelRatio = double.tryParse(request.url.queryParameters['pixelRatio'] ?? '') ?? 1.0;

    final bytes = await screenshotService.capture(pixelRatio: pixelRatio);
    sw.stop();

    if (bytes == null) {
      return Response(503,
          body: jsonEncode({'error': 'No render tree available'}), headers: {'content-type': 'application/json'});
    }

    final headers = <String, String>{
      'content-type': 'image/png',
      'content-length': bytes.length.toString(),
    };

    if (includeTimingHeaders) {
      headers['x-capture-time-ms'] = sw.elapsedMilliseconds.toString();
    }

    // Include dimensions if available
    final size = screenshotService.surfaceSize;
    if (size != null) {
      headers['x-image-width'] = (size.width * pixelRatio).round().toString();
      headers['x-image-height'] = (size.height * pixelRatio).round().toString();
    }

    return Response.ok(bytes, headers: headers);
  }

  Response _handleTree(Request request) {
    final sw = Stopwatch()..start();

    final depth = int.tryParse(request.url.queryParameters['depth'] ?? '') ?? widgetTreeService.defaultDepth;
    final compact = request.url.queryParameters['compact'] != 'false';

    final tree = widgetTreeService.capture(depth: depth, compact: compact);
    sw.stop();

    if (tree == null) {
      return Response(503,
          body: jsonEncode({'error': 'No element tree available'}), headers: {'content-type': 'application/json'});
    }

    final body = jsonEncode({
      'captureTimeMs': sw.elapsedMilliseconds,
      'rootWidget': tree.toJson(compact: compact),
    });

    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (includeTimingHeaders) {
      headers['x-capture-time-ms'] = sw.elapsedMilliseconds.toString();
    }

    return Response.ok(body, headers: headers);
  }

  Future<Response> _handleTap(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final x = (json['x'] as num).toDouble();
    final y = (json['y'] as num).toDouble();

    final result = gestureService.tap(x, y);

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleInfo(Request request) {
    final info = appInfoService.getInfo();
    return Response.ok(
      jsonEncode(info),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleHealth() {
    return Response.ok(
      jsonEncode({'status': 'ok', 'timestamp': DateTime.now().toIso8601String()}),
      headers: {'content-type': 'application/json'},
    );
  }
}
