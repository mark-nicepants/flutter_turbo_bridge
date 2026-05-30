import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'models/app_info.dart';
import 'models/find_response.dart';
import 'models/screenshot_result.dart';
import 'models/tap_result.dart';
import 'models/widget_node.dart';

/// HTTP connection to the Turbo Bridge in-app server.
class BridgeConnection {
  final String host;
  final int port;
  final http.Client _httpClient;

  @visibleForTesting
  BridgeConnection.withClient({
    required this.host,
    required this.port,
    required http.Client client,
  }) : _httpClient = client;

  BridgeConnection({
    required this.host,
    required this.port,
  }) : _httpClient = http.Client();

  String get _baseUrl => 'http://$host:$port';

  /// Check if the bridge server is reachable.
  Future<bool> isHealthy() async {
    try {
      final response = await _httpClient.get(Uri.parse('$_baseUrl/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Capture a screenshot from the app. Returns raw PNG bytes with metadata.
  Future<ScreenshotResult> screenshot({
    double pixelRatio = 1.0,
    int delayMs = 0,
  }) async {
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final sw = Stopwatch()..start();

    final uri = Uri.parse('$_baseUrl/screenshot').replace(
      queryParameters: {'pixelRatio': pixelRatio.toString()},
    );
    final response = await _httpClient.get(uri);
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
        'Screenshot failed: ${response.statusCode} ${response.body}',
      );
    }

    return ScreenshotResult(
      bytes: response.bodyBytes,
      captureTimeMs:
          int.tryParse(response.headers['x-capture-time-ms'] ?? '') ?? 0,
      width: int.tryParse(response.headers['x-image-width'] ?? ''),
      height: int.tryParse(response.headers['x-image-height'] ?? ''),
      roundTripMs: sw.elapsedMilliseconds,
    );
  }

  /// Get the widget tree from the app.
  Future<({WidgetNode tree, int captureTimeMs, int roundTripMs})> widgetTree({
    int depth = 10,
    bool compact = true,
    double? x,
    double? y,
    int ancestorLevels = 2,
  }) async {
    if ((x == null) != (y == null)) {
      throw ArgumentError('x and y must be provided together');
    }

    final sw = Stopwatch()..start();

    final uri = Uri.parse('$_baseUrl/tree').replace(
      queryParameters: {
        'depth': depth.toString(),
        'compact': compact.toString(),
        if (x != null) 'x': x.toString(),
        if (y != null) 'y': y.toString(),
        if (x != null && y != null) 'ancestorLevels': ancestorLevels.toString(),
      },
    );
    final response = await _httpClient.get(uri);
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Widget tree failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tree =
        WidgetNode.fromJson(json['rootWidget'] as Map<String, dynamic>);

    return (
      tree: tree,
      captureTimeMs: json['captureTimeMs'] as int,
      roundTripMs: sw.elapsedMilliseconds,
    );
  }

  /// Inject a tap at the given coordinates.
  Future<TapResult> tap(double x, double y) async {
    final sw = Stopwatch()..start();

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/tap'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'x': x, 'y': y}),
    );
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Tap failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TapResult.fromJson(json, sw.elapsedMilliseconds);
  }

  /// Get app metadata.
  Future<AppInfo> appInfo() async {
    final response = await _httpClient.get(Uri.parse('$_baseUrl/info'));

    if (response.statusCode != 200) {
      throw BridgeException(
          'App info failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AppInfo.fromJson(json);
  }

  /// Inject a swipe gesture.
  Future<TapResult> swipe(
    double startX,
    double startY,
    double endX,
    double endY, {
    int steps = 10,
  }) async {
    final sw = Stopwatch()..start();

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/swipe'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
        'steps': steps,
      }),
    );
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Swipe failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TapResult.fromJson(json, sw.elapsedMilliseconds);
  }

  /// Inject a scroll gesture at coordinates.
  Future<TapResult> scroll(double x, double y,
      {double dx = 0, required double dy}) async {
    final sw = Stopwatch()..start();

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/scroll'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'x': x, 'y': y, 'dx': dx, 'dy': dy}),
    );
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Scroll failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TapResult.fromJson(json, sw.elapsedMilliseconds);
  }

  /// Enter text into the currently focused text field.
  Future<TapResult> enterText(String text, {bool replace = false}) async {
    final sw = Stopwatch()..start();

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/input'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'text': text, 'replace': replace}),
    );
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Enter text failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return TapResult.fromJson(json, sw.elapsedMilliseconds);
  }

  /// Find widgets server-side by text, key, or type.
  Future<FindResponse> find({
    String? text,
    String? key,
    String? type,
    int limit = 10,
    bool visibleOnly = true,
    bool currentRouteOnly = false,
    bool interactiveOnly = false,
    double? nearX,
    double? nearY,
  }) async {
    final sw = Stopwatch()..start();

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl/find'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (type != null) 'type': type,
        'limit': limit,
        'visibleOnly': visibleOnly,
        'currentRouteOnly': currentRouteOnly,
        'interactiveOnly': interactiveOnly,
        if (nearX != null) 'nearX': nearX,
        if (nearY != null) 'nearY': nearY,
      }),
    );
    sw.stop();

    if (response.statusCode != 200) {
      throw BridgeException(
          'Find failed: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return FindResponse.fromJson(json, sw.elapsedMilliseconds);
  }

  /// Close the HTTP client connection.
  void close() {
    _httpClient.close();
  }
}

/// Exception thrown by bridge operations.
class BridgeException implements Exception {
  final String message;
  const BridgeException(this.message);

  @override
  String toString() => 'BridgeException: $message';
}
