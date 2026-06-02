import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'bridge_config.dart';
import 'devtools/devtools_server.dart';
import 'devtools/event_bus.dart';
import 'devtools/log_sink.dart';
import 'devtools/navigation_log.dart';
import 'devtools/network_log.dart';
import 'devtools/request_log.dart';
import 'devtools/web_assets.dart';
import 'server/router.dart';
import 'services/app_info_service.dart';
import 'services/find_service.dart';
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
    FindService? findService,
  })  : screenshotService = screenshotService ?? ScreenshotService(),
        widgetTreeService = widgetTreeService ??
            WidgetTreeService(defaultDepth: config.defaultTreeDepth),
        gestureService = gestureService ?? GestureService(),
        appInfoService = appInfoService ?? AppInfoService(),
        findService = findService ?? FindService(),
        eventBus = DevToolsEventBus(),
        requestLog = RequestLog(capacity: config.devToolsRequestLogSize) {
    logs = LogSink(bus: eventBus);
    network = NetworkLog(bus: eventBus);
    navigation = NavigationLog(bus: eventBus);
  }

  static TurboBridge? _instance;

  /// Singleton instance. Call [start] to initialize.
  static TurboBridge get instance {
    if (_instance == null) {
      throw StateError(
          'TurboBridge not initialized. Call TurboBridge.start() first.');
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

  /// Service for finding widgets in the element tree.
  final FindService findService;

  /// Pub/sub for DevTools UI events (request log, route changes, ...).
  final DevToolsEventBus eventBus;

  /// Ring buffer of recent JSON-API requests shown in the DevTools log.
  final RequestLog requestLog;

  /// App-side log sink. Push app-emitted log lines here to surface them
  /// in DevTools and over MCP. Example:
  /// `TurboBridge.instance.logs.info('User signed in', category: 'auth');`
  late final LogSink logs;

  /// App-side network-call recorder. Wire your HTTP client interceptors
  /// (Dio, http, GraphQL) into this so DevTools shows what the app is
  /// talking to in addition to bridge JSON-API traffic.
  late final NetworkLog network;

  /// App-side navigation recorder. Push route changes here so the
  /// DevTools timeline shows them next to logs and network calls.
  /// Wire from a `NavigatorObserver`.
  late final NavigationLog navigation;

  HttpServer? _server;
  DevToolsServer? _devToolsServer;

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// The actual port the server is listening on.
  int? get port => _server?.port;

  /// The actual DevTools port, or null when DevTools is disabled or
  /// failed to bind.
  int? get devToolsPort => _devToolsServer?.boundPort;

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
    FindService? findService,
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
      findService: findService,
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
    FindService? findService,
  }) {
    final bridge = TurboBridge._(
      config: config,
      screenshotService: screenshotService,
      widgetTreeService: widgetTreeService,
      gestureService: gestureService,
      appInfoService: appInfoService,
      findService: findService,
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
      findService: findService,
      logs: logs,
      network: network,
      includeTimingHeaders: config.includeTimingHeaders,
      devToolsPortProvider: () => _devToolsServer?.boundPort,
    );

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_devToolsInstrumentation())
        .addHandler(router.handler);

    _server = await shelf_io.serve(handler, config.host, config.port);
    debugPrint(
        'TurboBridge listening on http://${config.host}:${_server!.port}');

    if (config.enableDevTools) {
      final webAssets = await DevToolsWebAssetLoader.load();
      _devToolsServer = DevToolsServer.create(
        config: config,
        bridgeRouter: router,
        eventBus: eventBus,
        requestLog: requestLog,
        logs: logs,
        network: network,
        navigation: navigation,
        webAssets: webAssets,
      );
      await _devToolsServer!.start();
    }
  }

  /// Middleware that records each handled request into [requestLog] and
  /// emits a `request` event onto [eventBus] for DevTools subscribers.
  ///
  /// Buffers the request and response bodies so the DevTools detail panel
  /// can show them; this adds one memcpy per request, acceptable for a
  /// dev-time tool. Skipped when DevTools is disabled.
  shelf.Middleware _devToolsInstrumentation() {
    return (shelf.Handler inner) {
      return (shelf.Request request) async {
        final sw = Stopwatch()..start();

        // Buffer the request body so we can replay it to the inner handler
        // and still capture a copy for the DevTools log.
        final reqBytes = config.enableDevTools
            ? await _drain(request.read())
            : const <int>[];
        final replay =
            config.enableDevTools ? request.change(body: reqBytes) : request;

        final response = await inner(replay);

        List<int> resBytes = const [];
        shelf.Response outgoing = response;
        if (config.enableDevTools) {
          resBytes = await _drain(response.read());
          outgoing = response.change(body: resBytes);
        }

        sw.stop();

        final remote =
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address;
        final entry = requestLog.record(
          method: request.method,
          path: '/${request.url.path}',
          query: request.url.query,
          status: response.statusCode,
          durationMs: sw.elapsedMilliseconds,
          remoteAddress: remote,
          requestHeaders:
              config.enableDevTools ? _flattenHeaders(request.headers) : null,
          requestBodyBytes: config.enableDevTools ? reqBytes : null,
          responseHeaders:
              config.enableDevTools ? _flattenHeaders(response.headers) : null,
          responseBodyBytes: config.enableDevTools ? resBytes : null,
        );
        eventBus.emit(DevToolsEvent('request', entry.toSummaryJson()));

        return outgoing;
      };
    };
  }

  static Future<List<int>> _drain(Stream<List<int>> body) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Map<String, String> _flattenHeaders(Map<String, dynamic> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      if (v is String) {
        out[k] = v;
      } else if (v is List) {
        out[k] = v.join(', ');
      } else {
        out[k] = v.toString();
      }
    });
    return out;
  }

  /// Stop the server and clean up resources.
  Future<void> stop() async {
    await _devToolsServer?.stop();
    _devToolsServer = null;
    await eventBus.close();
    await _server?.close(force: true);
    _server = null;
    _instance = null;
  }
}
