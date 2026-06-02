import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'event_bus.dart';
import 'log_sink.dart';
import 'navigation_log.dart';
import 'network_log.dart';
import 'request_log.dart';

/// Device-side DevTools data + event endpoints, served on the bridge port
/// when `BridgeConfig.enableDevTools` is on.
///
/// The DevTools web UI is **not** served from the app — it runs on the
/// developer's machine (e.g. `turbo_bridge_devtools` / the MCP server) and
/// consumes these endpoints over the (loopback / adb-forwarded) bridge port:
///
/// - `GET devtools/requests` / `devtools/requests/:id` — JSON-API request log
/// - `GET devtools/logs` — app-emitted log lines
/// - `GET devtools/navigation` — route changes
/// - `GET devtools/network` / `devtools/network/:id` — app HTTP calls
/// - `GET events` — Server-Sent Events stream of all of the above
///
/// These paths are mounted ahead of (and bypass the instrumentation of) the
/// main `BridgeRouter`; in particular `events` must not be drained/buffered.
class DevToolsApi {
  final DevToolsEventBus eventBus;
  final RequestLog requestLog;
  final LogSink logs;
  final NetworkLog network;
  final NavigationLog navigation;

  DevToolsApi({
    required this.eventBus,
    required this.requestLog,
    required this.logs,
    required this.network,
    required this.navigation,
  });

  /// Whether [path] (a `request.url.path`, no leading slash) is one this
  /// handler owns. Used by the composed server handler to route requests
  /// here instead of the main bridge router.
  static bool handles(String path) =>
      path == 'events' || path.startsWith('devtools/');

  Handler get handler => _handle;

  Future<Response> _handle(Request request) async {
    final path = request.url.path;

    if (path == 'events') {
      return _handleSse(request);
    }
    if (path == 'devtools/requests') {
      final entries = requestLog
          .snapshot()
          .map((e) => e.toSummaryJson())
          .toList();
      return _json({'entries': entries});
    }
    if (path == 'devtools/logs') {
      final entries = logs.snapshot().map((e) => e.toJson()).toList();
      return _json({'entries': entries});
    }
    if (path == 'devtools/navigation') {
      final entries = navigation.snapshot().map((e) => e.toJson()).toList();
      return _json({'entries': entries});
    }
    if (path == 'devtools/network') {
      final entries = network.snapshot().map((e) => e.toSummaryJson()).toList();
      return _json({'entries': entries});
    }
    if (path.startsWith('devtools/network/')) {
      final id = int.tryParse(path.substring('devtools/network/'.length));
      if (id == null) return Response.notFound('Bad network id');
      final call = network.byId(id);
      if (call == null) {
        return _json({'error': 'Not found'}, status: 404);
      }
      return _json(call.toDetailJson());
    }
    if (path.startsWith('devtools/requests/')) {
      final id = int.tryParse(path.substring('devtools/requests/'.length));
      if (id == null) return Response.notFound('Bad request id');
      final entry = requestLog.byId(id);
      if (entry == null) {
        return _json({'error': 'Not found'}, status: 404);
      }
      return _json(entry.toDetailJson());
    }
    return Response.notFound('Not found: /$path');
  }

  Response _json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  Response _handleSse(Request request) {
    final controller = StreamController<List<int>>();

    // Initial comment line so the browser knows the stream is open.
    controller.add(utf8.encode(': connected\n\n'));

    final subscription = eventBus.stream.listen((event) {
      final data = jsonEncode(event.toJson());
      controller.add(
        utf8.encode(
          'event: ${event.type}\n'
          'data: $data\n\n',
        ),
      );
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
