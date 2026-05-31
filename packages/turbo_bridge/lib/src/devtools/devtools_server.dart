import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../bridge_config.dart';
import '../server/router.dart';
import 'devtools_router.dart';
import 'event_bus.dart';
import 'log_sink.dart';
import 'navigation_log.dart';
import 'network_log.dart';
import 'request_log.dart';
import 'static_handler.dart';

/// Owns the secondary HTTP server that backs the DevTools web UI.
///
/// Lifecycle: created with [BridgeConfig.enableDevTools] true, started via
/// [start], stopped via [stop]. Binding errors are logged but never thrown,
/// so the main bridge keeps running even if the DevTools port is in use.
class DevToolsServer {
  final BridgeConfig config;
  final DevToolsRouter router;

  HttpServer? _server;
  bool _stopped = false;

  DevToolsServer._({required this.config, required this.router});

  static DevToolsServer create({
    required BridgeConfig config,
    required BridgeRouter bridgeRouter,
    required DevToolsEventBus eventBus,
    required RequestLog requestLog,
    required LogSink logs,
    required NetworkLog network,
    required NavigationLog navigation,
    required Map<String, DevToolsAsset> webAssets,
  }) {
    final router = DevToolsRouter(
      bridgeRouter: bridgeRouter,
      eventBus: eventBus,
      requestLog: requestLog,
      logs: logs,
      network: network,
      navigation: navigation,
      staticHandler: DevToolsStaticHandler(assets: webAssets),
    );
    return DevToolsServer._(config: config, router: router);
  }

  /// Currently bound port, or null if [start] hasn't completed yet.
  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_stopped) {
      throw StateError('DevToolsServer already stopped; create a new one.');
    }
    try {
      _server = await shelf_io.serve(
        router.handler,
        config.devToolsHost,
        config.devToolsPort,
      );
      if (config.devToolsHost != '127.0.0.1' &&
          config.devToolsHost != 'localhost') {
        debugPrint(
          '[turbo_bridge] DevTools bound to ${config.devToolsHost}:'
          '${_server!.port} — exposed beyond loopback. Do not enable in '
          'production builds.',
        );
      } else {
        debugPrint(
          '[turbo_bridge] DevTools UI ready at '
          'http://${config.devToolsHost}:${_server!.port}/',
        );
      }
    } catch (e, stack) {
      debugPrint('[turbo_bridge] DevTools failed to start on '
          '${config.devToolsHost}:${config.devToolsPort}: $e\n$stack');
      _server = null;
    }
  }

  Future<void> stop() async {
    _stopped = true;
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close(force: true);
  }
}
