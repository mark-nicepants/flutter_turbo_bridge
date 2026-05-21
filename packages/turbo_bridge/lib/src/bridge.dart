import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'bridge_config.dart';
import 'server/router.dart';
import 'services/app_info_service.dart';
import 'services/gesture_service.dart';
import 'services/screenshot_service.dart';
import 'services/widget_tree_service.dart';

/// The main Turbo Bridge class. Starts an in-app HTTP server that exposes
/// high-speed endpoints for AI interaction.
class TurboBridge {
  TurboBridge._({
    required this.config,
    ScreenshotService? screenshotService,
    WidgetTreeService? widgetTreeService,
    GestureService? gestureService,
    AppInfoService? appInfoService,
  })  : screenshotService = screenshotService ?? ScreenshotService(),
        widgetTreeService = widgetTreeService ?? WidgetTreeService(defaultDepth: config.defaultTreeDepth),
        gestureService = gestureService ?? GestureService(),
        appInfoService = appInfoService ?? AppInfoService();

  static TurboBridge? _instance;

  /// Singleton instance. Call [start] to initialize.
  static TurboBridge get instance {
    if (_instance == null) {
      throw StateError('TurboBridge not initialized. Call TurboBridge.start() first.');
    }
    return _instance!;
  }

  /// Configuration for this bridge instance.
  final BridgeConfig config;

  /// Service for capturing screenshots.
  final ScreenshotService screenshotService;

  /// Service for inspecting the widget tree.
  final WidgetTreeService widgetTreeService;

  /// Service for injecting gestures.
  final GestureService gestureService;

  /// Service for app metadata.
  final AppInfoService appInfoService;

  HttpServer? _server;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// The actual port the server is listening on.
  int? get port => _server?.port;

  /// Start the Turbo Bridge server.
  ///
  /// Creates a singleton instance with the given config and starts listening.
  /// If [ensureInitialized] is true (default), ensures Flutter bindings are ready.
  static Future<TurboBridge> start({
    BridgeConfig config = const BridgeConfig(),
    ScreenshotService? screenshotService,
    WidgetTreeService? widgetTreeService,
    GestureService? gestureService,
    AppInfoService? appInfoService,
    bool ensureInitialized = true,
  }) async {
    if (_instance != null && _instance!.isRunning) {
      return _instance!;
    }

    if (ensureInitialized) {
      WidgetsFlutterBinding.ensureInitialized();
    }

    final bridge = TurboBridge._(
      config: config,
      screenshotService: screenshotService,
      widgetTreeService: widgetTreeService,
      gestureService: gestureService,
      appInfoService: appInfoService,
    );

    await bridge._startServer();
    _instance = bridge;
    return bridge;
  }

  /// Create a TurboBridge instance without starting the server.
  /// Useful for testing.
  static TurboBridge createForTest({
    BridgeConfig config = const BridgeConfig(),
    ScreenshotService? screenshotService,
    WidgetTreeService? widgetTreeService,
    GestureService? gestureService,
    AppInfoService? appInfoService,
  }) {
    final bridge = TurboBridge._(
      config: config,
      screenshotService: screenshotService,
      widgetTreeService: widgetTreeService,
      gestureService: gestureService,
      appInfoService: appInfoService,
    );
    _instance = bridge;
    return bridge;
  }

  Future<void> _startServer() async {
    final router = BridgeRouter(
      screenshotService: screenshotService,
      widgetTreeService: widgetTreeService,
      gestureService: gestureService,
      appInfoService: appInfoService,
      includeTimingHeaders: config.includeTimingHeaders,
    );

    final handler = const shelf.Pipeline().addMiddleware(shelf.logRequests()).addHandler(router.handler);

    _server = await shelf_io.serve(handler, config.host, config.port);
    debugPrint('TurboBridge listening on http://${config.host}:${_server!.port}');
  }

  /// Stop the server and clean up resources.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _instance = null;
  }
}
