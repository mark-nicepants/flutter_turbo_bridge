/// `package:http` adapter that forwards every request — including
/// failures — into [TurboBridge.instance.network] so it shows up on
/// the DevTools timeline.
///
/// Add `http: ^1.0.0` to your app's pubspec.yaml — this file is only
/// compiled when you import it, so the rest of `turbo_bridge` works
/// without `http`.
///
/// We ship a [Client] wrapper rather than an `http_interceptor`
/// implementation because v3 of that package has no error hook: when
/// `Client.send` throws (DNS, timeout, connection refused),
/// `interceptResponse` never fires, so an in-flight call would be
/// silently dropped from the timeline. A `BaseClient` decorator owns
/// the try/catch and can also tap the response stream to capture body
/// excerpts (which `interceptResponse` cannot, since it receives a
/// `StreamedResponse`).
///
/// ```dart
/// import 'package:http/http.dart' as http;
/// import 'package:turbo_bridge/interceptors/http.dart';
///
/// final client = TurboBridgeHttpClient();
/// await client.get(Uri.parse('https://example.com'));
///
/// // Compose with your existing client (auth headers, retries, etc.):
/// final client = TurboBridgeHttpClient(inner: MyAuthClient());
/// ```
library;

// `http` is intentionally a dev_dependency — consumers add it to their
// own pubspec when they want to use this adapter.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart';

import '../src/bridge.dart';
import '../src/devtools/network_log.dart';

/// `BaseClient` decorator that records every HTTP call (success and
/// failure) into the DevTools timeline.
///
/// Wraps an inner [Client]. Defaults to the platform default
/// (`Client()`); pass your own to compose with auth / retry layers.
class TurboBridgeHttpClient extends BaseClient {
  /// Inner client that actually sends the bytes. We don't extend
  /// `Client` via inheritance because callers may want to plug in an
  /// `IOClient` with custom TLS, an `InterceptedClient` from
  /// `http_interceptor`, etc.
  final Client _inner;

  /// Optional override for the URL to record. Defaults to
  /// `request.url.toString()`. Use this if you want to strip query
  /// strings, mask secrets in the path, or rewrite the host.
  final String Function(BaseRequest request)? urlFor;

  /// Cap on the body size we record (bytes). Bodies above this cap
  /// are truncated. Defaults to 16 KB.
  final int maxBodySize;

  /// When true (the default) the wrapper buffers the response stream
  /// so it can record the body excerpt and emit it to the timeline.
  /// The buffered bytes are then re-emitted as a fresh single-shot
  /// stream so downstream consumers see the response unchanged.
  ///
  /// Set to `false` for callers that consume responses as streams
  /// (large downloads, server-sent events) and don't want the whole
  /// payload held in memory. Only metadata (status, headers, duration)
  /// is recorded in that case.
  final bool captureResponseBody;

  TurboBridgeHttpClient({
    Client? inner,
    this.urlFor,
    this.maxBodySize = 16 * 1024,
    this.captureResponseBody = true,
  }) : _inner = inner ?? Client();

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final nf = _startInFlight(request);

    StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (err) {
      try {
        nf?.fail(err);
      } catch (_) {}
      rethrow;
    }

    if (nf == null) return response;

    if (!captureResponseBody) {
      try {
        nf.complete(
          status: response.statusCode,
          responseHeaders: Map<String, String>.from(response.headers),
          responseBodySize: response.contentLength,
        );
      } catch (_) {}
      return response;
    }

    // Buffer the stream once so we can both log the body and hand the
    // caller an untouched-looking response. Buffering is what
    // `Response.fromStream` already does internally, so for typical
    // JSON APIs this isn't extra overhead.
    final Uint8List bytes;
    try {
      bytes = await response.stream.toBytes();
    } catch (err) {
      try {
        nf.fail(err);
      } catch (_) {}
      rethrow;
    }

    try {
      final body = utf8.decode(bytes, allowMalformed: true);
      nf.complete(
        status: response.statusCode,
        responseHeaders: Map<String, String>.from(response.headers),
        responseBody: _cap(body),
        responseBodySize: bytes.length,
      );
    } catch (_) {}

    return StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  InFlightNetworkCall? _startInFlight(BaseRequest request) {
    final network = _networkOrNull();
    if (network == null) return null;
    try {
      final body = request is Request ? request.body : null;
      return network.start(
        method: request.method,
        url: urlFor?.call(request) ?? request.url.toString(),
        requestHeaders: Map<String, String>.from(request.headers),
        requestBody: body == null ? null : _cap(body),
        requestBodySize: body?.length ?? request.contentLength,
      );
    } catch (_) {
      // Never let logging take down the actual HTTP call.
      return null;
    }
  }

  @override
  void close() => _inner.close();

  NetworkLog? _networkOrNull() {
    try {
      return TurboBridge.instance.network;
    } catch (_) {
      return null;
    }
  }

  String _cap(String s) {
    if (s.length <= maxBodySize) return s;
    return s.substring(0, maxBodySize);
  }
}
