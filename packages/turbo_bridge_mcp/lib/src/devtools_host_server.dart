import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'adb_forwarding.dart';
import 'devtools_bundle.g.dart';
import 'package_resolver.dart';

/// Host-side HTTP server for the Turbo Bridge DevTools UI.
///
/// Runs on the developer's machine (not the device) and does two things:
///
/// 1. Serves the embedded single-file UI bundle (HTML + inlined JS/CSS).
/// 2. Reverse-proxies the UI's data calls to the device bridge:
///    - `/api/<rest>`  -> `http://<bridgeHost>:<bridgePort>/<rest>`
///    - `/events`      -> the bridge's SSE stream (streamed, never buffered)
///
/// Because the browser only ever talks to this server's origin, there is no
/// CORS. The bridge port is normally reached via `adb forward` / loopback.
class DevToolsHostServer {
  DevToolsHostServer({
    required this.bridgeHost,
    required this.bridgePort,
    this.projectRoot,
    ProcessRunner? processRunner,
    HttpReachabilityProbe? reachabilityProbe,
  })  : _processRunner = processRunner,
        _reachabilityProbe = reachabilityProbe;

  /// Host/port of the (already reachable, e.g. adb-forwarded) device bridge.
  final String bridgeHost;
  final int bridgePort;

  /// Directory to resolve `package:` source links against (its
  /// `.dart_tool/package_config.json`). Defaults to the current directory.
  final String? projectRoot;

  // Overridable for tests; null = use the real adb / HTTP probes.
  final ProcessRunner? _processRunner;
  final HttpReachabilityProbe? _reachabilityProbe;

  final HttpClient _client = HttpClient();
  HttpServer? _server;

  /// Bound port once [start] completes, else null.
  int? get boundPort => _server?.port;

  /// Decode the embedded UI bundle to raw HTML bytes.
  static List<int> bundleBytes() =>
      gzip.decode(base64.decode(devToolsBundleGzipBase64));

  Future<int> start({String host = '127.0.0.1', int port = 8889}) async {
    _server = await shelf_io.serve(_handle, host, port);
    return _server!.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _client.close(force: true);
  }

  Future<Response> _handle(Request request) async {
    final path = request.url.path;
    // Host-local control endpoints — handled here, never proxied to the
    // device (the device can't run adb on the developer's machine).
    if (path == '__host/status') {
      final status = await probeBridgeStatus(
        host: bridgeHost,
        bridgePort: bridgePort,
        processRunner: _processRunner,
        reachabilityProbe: _reachabilityProbe,
      );
      return _jsonResponse({...status.toJson(), ..._bridgeInfo});
    }
    if (path == '__host/reconnect' && request.method == 'POST') {
      final status = await reconnectBridge(
        host: bridgeHost,
        bridgePort: bridgePort,
        processRunner: _processRunner,
        reachabilityProbe: _reachabilityProbe,
      );
      return _jsonResponse({...status.toJson(), ..._bridgeInfo});
    }
    if (path == '__host/packages') {
      // Resolve `package:` source links against the project's
      // package_config.json — read fresh so a `pub get` mid-session is picked
      // up on the next UI load.
      final resolver =
          PackageResolver.forDirectory(projectRoot ?? Directory.current.path);
      return _jsonResponse(resolver.toJson());
    }
    if (path == 'events') {
      return _proxy(request, 'events');
    }
    if (path.startsWith('api/')) {
      return _proxy(request, path.substring('api/'.length));
    }
    // Everything else: serve the SPA shell. Assets are inlined into the
    // bundle, so there is only ever the one HTML document.
    return Response.ok(
      bundleBytes(),
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Map<String, dynamic> get _bridgeInfo =>
      {'bridgeHost': bridgeHost, 'bridgePort': bridgePort};

  Response _jsonResponse(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  /// Reverse-proxy [request] to `bridgeHost:bridgePort/<devicePath>`,
  /// streaming the response body so SSE (`/events`) is never buffered.
  Future<Response> _proxy(Request request, String devicePath) async {
    final target = Uri(
      scheme: 'http',
      host: bridgeHost,
      port: bridgePort,
      path: devicePath,
      query: request.url.query.isEmpty ? null : request.url.query,
    );

    try {
      final clientReq = await _client.openUrl(request.method, target);
      request.headers.forEach((name, value) {
        final lower = name.toLowerCase();
        if (lower == 'host' ||
            lower == 'content-length' ||
            lower == 'connection') {
          return;
        }
        clientReq.headers.set(name, value);
      });

      // Forward the request body (none for GET/EventSource).
      await for (final chunk in request.read()) {
        clientReq.add(chunk);
      }
      final clientResp = await clientReq.close();

      final headers = <String, String>{};
      clientResp.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'transfer-encoding' ||
            lower == 'content-length' ||
            lower == 'connection') {
          return;
        }
        headers[name] = values.join(', ');
      });

      return Response(
        clientResp.statusCode,
        body: clientResp, // HttpClientResponse is a Stream<List<int>>
        headers: headers,
        // Flush chunks as they arrive instead of buffering — required for SSE.
        context: {'shelf.io.buffer_output': false},
      );
    } catch (e) {
      return Response(
        502,
        body: jsonEncode({
          'error': 'Bridge unreachable at $bridgeHost:$bridgePort: $e',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
