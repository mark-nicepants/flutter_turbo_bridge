import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../server/router.dart';
import 'event_bus.dart';
import 'log_sink.dart';
import 'network_log.dart';
import 'request_log.dart';
import 'static_handler.dart';

/// HTTP router for the DevTools web UI port.
///
/// Three responsibilities:
/// 1. Serve the embedded static bundle (`/`, `/styles.css`, `/app.js`, ...).
/// 2. Expose a small `/api/*` surface that proxies onto the same
///    [BridgeRouter] used by the JSON-API port, plus DevTools-only
///    endpoints under `/api/devtools/*`.
/// 3. Stream `/events` as Server-Sent Events.
class DevToolsRouter {
  final BridgeRouter bridgeRouter;
  final DevToolsStaticHandler staticHandler;
  final DevToolsEventBus eventBus;
  final RequestLog requestLog;
  final LogSink logs;
  final NetworkLog network;

  DevToolsRouter({
    required this.bridgeRouter,
    required this.eventBus,
    required this.requestLog,
    required this.logs,
    required this.network,
    required this.staticHandler,
  });

  Handler get handler => _handle;

  Future<Response> _handle(Request request) async {
    final path = request.url.path;

    if (path == 'events') {
      return _handleSse(request);
    }
    if (path == 'api/devtools/requests') {
      return _handleRequestLog();
    }
    if (path == 'api/devtools/logs') {
      final entries = logs.snapshot().map((e) => e.toJson()).toList();
      return Response.ok(jsonEncode({'entries': entries}),
          headers: {'content-type': 'application/json'});
    }
    if (path == 'api/devtools/network') {
      final entries =
          network.snapshot().map((e) => e.toSummaryJson()).toList();
      return Response.ok(jsonEncode({'entries': entries}),
          headers: {'content-type': 'application/json'});
    }
    if (path.startsWith('api/devtools/network/')) {
      final idStr = path.substring('api/devtools/network/'.length);
      final id = int.tryParse(idStr);
      if (id == null) return Response.notFound('Bad network id');
      final call = network.byId(id);
      if (call == null) {
        return Response.notFound(jsonEncode({'error': 'Not found'}),
            headers: {'content-type': 'application/json'});
      }
      return Response.ok(jsonEncode(call.toDetailJson()),
          headers: {'content-type': 'application/json'});
    }
    if (path.startsWith('api/devtools/requests/')) {
      final idStr = path.substring('api/devtools/requests/'.length);
      final id = int.tryParse(idStr);
      if (id == null) {
        return Response.notFound('Bad request id');
      }
      final entry = requestLog.byId(id);
      if (entry == null) {
        return Response.notFound(jsonEncode({'error': 'Not found'}),
            headers: {'content-type': 'application/json'});
      }
      return Response.ok(jsonEncode(entry.toDetailJson()),
          headers: {'content-type': 'application/json'});
    }
    if (path.startsWith('api/')) {
      // Mutating endpoints require the same-origin DevTools header so
      // a stray LAN browser can't drive the app via DevTools.
      if (request.method != 'GET' &&
          request.headers['x-turbo-devtools'] != '1') {
        return Response.forbidden(jsonEncode({
          'error': 'Missing x-turbo-devtools header. '
              'Mutating DevTools API calls must originate from the '
              'DevTools UI.',
        }), headers: {'content-type': 'application/json'});
      }
      // Re-issue the request to the main BridgeRouter with the `api/`
      // prefix stripped, so it sees the same paths the JSON-API port does.
      final stripped = request.change(path: 'api');
      return bridgeRouter.handler(stripped);
    }
    return staticHandler.handle(request);
  }

  Response _handleRequestLog() {
    final entries =
        requestLog.snapshot().map((e) => e.toSummaryJson()).toList();
    return Response.ok(
      jsonEncode({'entries': entries}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleSse(Request request) {
    final controller = StreamController<List<int>>();

    // Initial comment line so the browser knows the stream is open.
    controller.add(utf8.encode(': connected\n\n'));

    final subscription = eventBus.stream.listen((event) {
      final data = jsonEncode(event.toJson());
      controller.add(utf8.encode('event: ${event.type}\n'
          'data: $data\n\n'));
    });

    // Heartbeat so proxies don't close the connection on idle.
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!controller.isClosed) {
        controller.add(utf8.encode(': ping\n\n'));
      }
    });

    controller.onCancel = () async {
      heartbeat.cancel();
      await subscription.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return Response.ok(
      controller.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }
}
