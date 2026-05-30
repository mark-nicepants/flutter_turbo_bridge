import 'bridge_connection.dart';
import 'models/app_info.dart';
import 'models/find_response.dart';
import 'models/screenshot_result.dart';
import 'models/tap_result.dart';
import 'models/widget_node.dart';
import 'vm_service_connection.dart';

/// Unified client for AI-Flutter interaction via Turbo Bridge.
///
/// Combines the in-app HTTP bridge for fast binary operations (screenshots,
/// gestures) with the VM Service for evaluation and deep inspection.
class TurboBridgeClient {
  final BridgeConnection _bridge;
  final VmServiceConnection? _vmService;

  /// Create a client connected to just the bridge HTTP server.
  TurboBridgeClient({
    required String host,
    int port = 8888,
  })  : _bridge = BridgeConnection(host: host, port: port),
        _vmService = null;

  /// Create a client connected to both bridge and VM Service.
  TurboBridgeClient.withVmService({
    required String host,
    int port = 8888,
    required String vmServiceUri,
  })  : _bridge = BridgeConnection(host: host, port: port),
        _vmService = VmServiceConnection(vmServiceUri: vmServiceUri);

  /// Create with injected dependencies (for testing).
  TurboBridgeClient.withConnections({
    required BridgeConnection bridge,
    VmServiceConnection? vmService,
  })  : _bridge = bridge,
        _vmService = vmService;

  /// Check if the bridge is reachable.
  Future<bool> isConnected() => _bridge.isHealthy();

  /// Connect to the VM Service (if configured).
  Future<void> connectVmService() async {
    await _vmService?.connect();
  }

  /// Capture a screenshot of the app.
  Future<ScreenshotResult> screenshot({
    double pixelRatio = 1.0,
    int delayMs = 0,
  }) {
    return _bridge.screenshot(pixelRatio: pixelRatio, delayMs: delayMs);
  }

  /// Get the widget tree.
  Future<WidgetNode> widgetTree({
    int depth = 10,
    double? x,
    double? y,
    int ancestorLevels = 2,
  }) async {
    final result = await _bridge.widgetTree(
      depth: depth,
      x: x,
      y: y,
      ancestorLevels: ancestorLevels,
    );
    return result.tree;
  }

  /// Get the widget tree with timing metadata.
  Future<({WidgetNode tree, int captureTimeMs, int roundTripMs})>
      widgetTreeWithTiming({
    int depth = 10,
    double? x,
    double? y,
    int ancestorLevels = 2,
  }) {
    return _bridge.widgetTree(
      depth: depth,
      x: x,
      y: y,
      ancestorLevels: ancestorLevels,
    );
  }

  /// Inject a tap at the given coordinates.
  Future<TapResult> tap(double x, double y) {
    return _bridge.tap(x, y);
  }

  /// Find a widget by text and tap its center.
  Future<TapResult?> tapByText(String text, {int depth = 15}) async {
    final tree = await widgetTree(depth: depth);
    final matches = tree.findByText(text);
    if (matches.isEmpty) return null;

    final target = matches.first;
    final center = target.center;
    if (center == null) return null;

    return tap(center.x, center.y);
  }

  /// Find a widget by key and tap its center.
  Future<TapResult?> tapByKey(String key, {int depth = 15}) async {
    final tree = await widgetTree(depth: depth);
    final target = tree.findByKey(key);
    if (target == null) return null;

    final center = target.center;
    if (center == null) return null;

    return tap(center.x, center.y);
  }

  /// Get app metadata.
  Future<AppInfo> appInfo() {
    return _bridge.appInfo();
  }

  /// Fetch recent app-pushed log lines.
  Future<List<Map<String, dynamic>>> recentLogs({
    int limit = 100,
    String? level,
  }) {
    return _bridge.recentLogs(limit: limit, level: level);
  }

  /// Fetch recent app-recorded network calls.
  Future<List<Map<String, dynamic>>> recentNetwork({int limit = 100}) {
    return _bridge.recentNetwork(limit: limit);
  }

  /// Inject a swipe gesture from start to end coordinates.
  Future<TapResult> swipe(
    double startX,
    double startY,
    double endX,
    double endY, {
    int steps = 10,
  }) {
    return _bridge.swipe(startX, startY, endX, endY, steps: steps);
  }

  /// Inject a scroll gesture at the given position.
  ///
  /// Positive [dy] scrolls content up (finger moves up); negative scrolls down.
  Future<TapResult> scroll(double x, double y,
      {double dx = 0, required double dy}) {
    return _bridge.scroll(x, y, dx: dx, dy: dy);
  }

  /// Enter text into the currently focused text field.
  ///
  /// If [replace] is true, replaces existing text; otherwise appends.
  Future<TapResult> enterText(String text, {bool replace = false}) {
    return _bridge.enterText(text, replace: replace);
  }

  /// Find widgets server-side by text, key, or type.
  ///
  /// More efficient than fetching the full tree when you only need
  /// specific widget locations.
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
  }) {
    return _bridge.find(
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
  }

  /// Evaluate a Dart expression via VM Service.
  ///
  /// Requires [connectVmService] to be called first.
  Future<String> evaluate(String expression) async {
    if (_vmService == null || !_vmService.isConnected) {
      throw StateError(
          'VM Service not connected. Call connectVmService() first.');
    }
    final result = await _vmService.evaluate(expression);
    return result.json?['valueAsString']?.toString() ?? result.toString();
  }

  /// Clean up resources.
  Future<void> dispose() async {
    _bridge.close();
    await _vmService?.dispose();
  }
}
