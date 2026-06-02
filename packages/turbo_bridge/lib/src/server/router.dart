import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shelf/shelf.dart';

import '../devtools/log_sink.dart';
import '../devtools/network_log.dart';
import '../services/app_info_service.dart';
import '../services/find_service.dart';
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
  final FindService findService;
  final LogSink? logs;
  final NetworkLog? network;
  final bool includeTimingHeaders;
  final int? Function()? devToolsPortProvider;

  /// Optional absolute project root on the developer's machine, advertised
  /// via `/info` so the DevTools UI can resolve `package:` source links
  /// without the developer entering it by hand. See [BridgeConfig.projectRoot].
  final String? projectRoot;

  BridgeRouter({
    required this.screenshotService,
    required this.widgetTreeService,
    required this.gestureService,
    required this.appInfoService,
    required this.findService,
    this.logs,
    this.network,
    this.includeTimingHeaders = true,
    this.devToolsPortProvider,
    this.projectRoot,
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
        ('POST', 'swipe') => await _handleSwipe(request),
        ('POST', 'scroll') => await _handleScroll(request),
        ('POST', 'input') => await _handleInput(request),
        ('GET', 'find') => _handleFind(request),
        ('POST', 'find') => await _handleFindPost(request),
        ('GET', 'info') => _handleInfo(request),
        ('GET', 'pick') => _handlePick(request),
        ('POST', 'pick') => await _handlePickPost(request),
        ('GET', 'logs') => _handleLogs(request),
        ('GET', 'network') => _handleNetwork(request),
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

    final pixelRatio =
        double.tryParse(request.url.queryParameters['pixelRatio'] ?? '') ?? 1.0;

    final bytes = await screenshotService.capture(pixelRatio: pixelRatio);
    sw.stop();

    if (bytes == null) {
      return Response(
        503,
        body: jsonEncode({'error': 'No render tree available'}),
        headers: {'content-type': 'application/json'},
      );
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

    final depth =
        int.tryParse(request.url.queryParameters['depth'] ?? '') ??
        widgetTreeService.defaultDepth;
    final compact = request.url.queryParameters['compact'] != 'false';
    final focusX = double.tryParse(request.url.queryParameters['x'] ?? '');
    final focusY = double.tryParse(request.url.queryParameters['y'] ?? '');
    final ancestorLevels =
        int.tryParse(request.url.queryParameters['ancestorLevels'] ?? '') ?? 2;

    if ((focusX == null) != (focusY == null)) {
      return Response(
        400,
        body: jsonEncode({'error': 'x and y must be provided together'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final tree = widgetTreeService.capture(
      depth: depth,
      compact: compact,
      focusX: focusX,
      focusY: focusY,
      ancestorLevels: ancestorLevels,
    );
    sw.stop();

    if (tree == null) {
      return Response(
        503,
        body: jsonEncode({'error': 'No element tree available'}),
        headers: {'content-type': 'application/json'},
      );
    }

    final body = jsonEncode({
      'captureTimeMs': sw.elapsedMilliseconds,
      if (focusX != null && focusY != null)
        'focusPoint': {'x': focusX, 'y': focusY},
      if (focusX != null && focusY != null) 'ancestorLevels': ancestorLevels,
      'rootWidget': tree.toJson(compact: compact),
    });

    final headers = <String, String>{'content-type': 'application/json'};
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
    final info = Map<String, dynamic>.from(appInfoService.getInfo());
    final devToolsPort = devToolsPortProvider?.call();
    final root = projectRoot?.trim();
    info['devTools'] = {
      'enabled': devToolsPort != null,
      'port': devToolsPort,
      if (root != null && root.isNotEmpty) 'projectRoot': root,
    };
    return Response.ok(
      jsonEncode(info),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handlePick(Request request) {
    final x = double.tryParse(request.url.queryParameters['x'] ?? '');
    final y = double.tryParse(request.url.queryParameters['y'] ?? '');
    if (x == null || y == null) {
      return Response(
        400,
        body: jsonEncode({'error': 'x and y query params required'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final chain = widgetTreeService.pickAt(x, y);
    return Response.ok(
      jsonEncode({'chain': chain}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handlePickPost(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final x = (json['x'] as num).toDouble();
    final y = (json['y'] as num).toDouble();
    final chain = widgetTreeService.pickAt(x, y);
    return Response.ok(
      jsonEncode({'chain': chain}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleLogs(Request request) {
    final sink = logs;
    if (sink == null) {
      return Response.ok(
        jsonEncode({'entries': const []}),
        headers: {'content-type': 'application/json'},
      );
    }
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final minLevel = request.url.queryParameters['level'];
    final order = const {
      'trace': 0,
      'debug': 1,
      'info': 2,
      'warn': 3,
      'error': 4,
    };
    final entries = sink
        .snapshot()
        .where(
          (e) =>
              minLevel == null ||
              (order[e.level.name] ?? 0) >= (order[minLevel] ?? 0),
        )
        .toList();
    final tail = entries.length > limit
        ? entries.sublist(entries.length - limit)
        : entries;
    return Response.ok(
      jsonEncode({'entries': tail.map((e) => e.toJson()).toList()}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleNetwork(Request request) {
    final log = network;
    if (log == null) {
      return Response.ok(
        jsonEncode({'entries': const []}),
        headers: {'content-type': 'application/json'},
      );
    }
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final entries = log.snapshot();
    final tail = entries.length > limit
        ? entries.sublist(entries.length - limit)
        : entries;
    return Response.ok(
      jsonEncode({'entries': tail.map((e) => e.toSummaryJson()).toList()}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleHealth() {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleSwipe(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final startX = (json['startX'] as num).toDouble();
    final startY = (json['startY'] as num).toDouble();
    final endX = (json['endX'] as num).toDouble();
    final endY = (json['endY'] as num).toDouble();
    final steps = (json['steps'] as int?) ?? 10;

    final result = gestureService.swipe(
      startX,
      startY,
      endX,
      endY,
      steps: steps,
    );

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleScroll(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final x = (json['x'] as num).toDouble();
    final y = (json['y'] as num).toDouble();
    final dx = (json['dx'] as num?)?.toDouble() ?? 0;
    final dy = (json['dy'] as num).toDouble();

    final result = gestureService.scroll(x, y, dx: dx, dy: dy);

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleInput(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final text = json['text'] as String;
    final replace = json['replace'] as bool? ?? false;

    final result = await gestureService.enterText(
      text,
      replaceExisting: replace,
    );

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleFind(Request request) {
    final params = request.url.queryParameters;
    final text = params['text'];
    final key = params['key'];
    final type = params['type'];
    final limit = int.tryParse(params['limit'] ?? '') ?? 10;
    final visibleOnly = _parseBool(params['visibleOnly']) ?? true;
    final currentRouteOnly = _parseBool(params['currentRouteOnly']) ?? false;
    final interactiveOnly = _parseBool(params['interactiveOnly']) ?? false;
    final nearX = double.tryParse(params['nearX'] ?? '');
    final nearY = double.tryParse(params['nearY'] ?? '');

    final result = findService.find(
      text: text,
      key: key,
      type: type,
      limit: limit,
      visibleOnly: visibleOnly,
      currentRouteOnly: currentRouteOnly,
      interactiveOnly: interactiveOnly,
      nearX: nearX,
      nearY: nearY,
    );

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleFindPost(Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final text = json['text'] as String?;
    final key = json['key'] as String?;
    final type = json['type'] as String?;
    final limit = json['limit'] as int? ?? 10;
    final visibleOnly = json['visibleOnly'] as bool? ?? true;
    final currentRouteOnly = json['currentRouteOnly'] as bool? ?? false;
    final interactiveOnly = json['interactiveOnly'] as bool? ?? false;
    final nearX = (json['nearX'] as num?)?.toDouble();
    final nearY = (json['nearY'] as num?)?.toDouble();

    final result = findService.find(
      text: text,
      key: key,
      type: type,
      limit: limit,
      visibleOnly: visibleOnly,
      currentRouteOnly: currentRouteOnly,
      interactiveOnly: interactiveOnly,
      nearX: nearX,
      nearY: nearY,
    );

    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  bool? _parseBool(String? value) {
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }
}
