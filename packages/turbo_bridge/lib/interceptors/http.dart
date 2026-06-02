/// `http_interceptor` adapter that forwards every request — including
/// 4xx/5xx responses — into [TurboBridge.instance.network] so it shows
/// up on the DevTools timeline.
///
/// Add `http_interceptor: ^3.0.0` to your app's pubspec.yaml — this file
/// is only compiled when you import it, so the rest of `turbo_bridge`
/// works without `http_interceptor`.
///
/// ```dart
/// import 'package:http_interceptor/http_interceptor.dart';
/// import 'package:turbo_bridge/interceptors/http.dart';
///
/// final client = InterceptedClient.build(
///   interceptors: [TurboBridgeHttpInterceptor()],
/// );
/// await client.get(Uri.parse('https://example.com'));
/// ```
///
/// Add [TurboBridgeHttpInterceptor] LAST in the `interceptors` list so it
/// observes the final, fully-decorated request (auth headers, etc.) and
/// so the request instance it tags is the one actually sent.
///
/// `http_interceptor` v3 has no error hook on the interceptor itself — when
/// the underlying `Client.send` throws (DNS failure, timeout, connection
/// refused), `interceptResponse` never fires. To still surface those
/// failures on the timeline, pass [TurboBridgeHttpInterceptor.retryPolicy]
/// as the client's `retryPolicy`: the `RetryPolicy` exception hook *does*
/// fire on a thrown send, and we use it to record the failure (without
/// adding any retries of our own):
///
/// ```dart
/// final interceptor = TurboBridgeHttpInterceptor();
/// final client = InterceptedClient.build(
///   interceptors: [interceptor],
///   retryPolicy: interceptor.retryPolicy(),       // logs send failures
/// );
/// ```
///
/// Already using a `RetryPolicy`? Wrap it and keep its behavior:
/// `interceptor.retryPolicy(wrapping: myPolicy)`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// `http_interceptor` re-exports `package:http`, so `BaseRequest`,
// `StreamedResponse`, `Request` and friends come in with this import.
import 'package:http_interceptor/http_interceptor.dart';

import '../src/bridge.dart';
import '../src/devtools/network_log.dart';

/// [HttpInterceptor] that records every HTTP exchange into the DevTools
/// timeline. Drop it into an `InterceptedClient` / `InterceptedHttp`:
///
/// ```dart
/// final client = InterceptedClient.build(
///   interceptors: [TurboBridgeHttpInterceptor()],
/// );
/// ```
class TurboBridgeHttpInterceptor implements HttpInterceptor {
  /// Optional override for the URL to record. Defaults to
  /// `request.url.toString()`. Use this if you want to strip query
  /// strings, mask secrets in the path, or rewrite the host.
  final String Function(BaseRequest request)? urlFor;

  /// Cap on the body size we record (bytes). Bodies above this cap
  /// are truncated. Defaults to 16 KB.
  final int maxBodySize;

  /// When true (the default) the interceptor buffers the response stream
  /// so it can record the body excerpt and emit it to the timeline. The
  /// buffered bytes are then re-emitted as a fresh single-shot stream so
  /// downstream consumers (and `Response.fromStream`) see the response
  /// unchanged.
  ///
  /// Set to `false` for callers that consume responses as streams (large
  /// downloads, server-sent events) and don't want the whole payload held
  /// in memory. Only metadata (status, headers, duration) is recorded in
  /// that case.
  final bool captureResponseBody;

  TurboBridgeHttpInterceptor({
    this.urlFor,
    this.maxBodySize = 16 * 1024,
    this.captureResponseBody = true,
  });

  /// Carries the in-flight handle from [interceptRequest] to
  /// [interceptResponse] without mutating the request.
  /// `http_interceptor` passes the same [BaseRequest] instance through to
  /// the response's `request`, so keying on identity correlates the two.
  final Expando<InFlightNetworkCall> _inFlight = Expando<InFlightNetworkCall>();

  @override
  FutureOr<bool> shouldInterceptRequest({required BaseRequest request}) => true;

  @override
  FutureOr<bool> shouldInterceptResponse({required BaseResponse response}) =>
      true;

  @override
  FutureOr<BaseRequest> interceptRequest({required BaseRequest request}) {
    final network = _networkOrNull();
    if (network != null) {
      try {
        final body = request is Request ? request.body : null;
        _inFlight[request] = network.start(
          method: request.method,
          url: urlFor?.call(request) ?? request.url.toString(),
          requestHeaders: Map<String, String>.from(request.headers),
          requestBody: body == null ? null : _cap(body),
          requestBodySize: body?.length ?? request.contentLength,
        );
      } catch (_) {
        // Never let logging take down the actual HTTP call.
      }
    }
    return request;
  }

  @override
  FutureOr<BaseResponse> interceptResponse({
    required BaseResponse response,
  }) async {
    final request = response.request;
    final nf = request == null ? null : _inFlight[request];
    if (nf == null) return response;

    // The interceptor chain runs before `Response.fromStream`, so
    // `interceptResponse` always receives a `StreamedResponse`. To record
    // the body we have to drain that one-shot stream ourselves and hand
    // back a fresh response carrying the same bytes.
    if (!captureResponseBody || response is! StreamedResponse) {
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
    // `Response.fromStream` already does internally, so for typical JSON
    // APIs this isn't extra overhead.
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

  /// Builds a [RetryPolicy] that records exchanges whose underlying
  /// `Client.send` threw (DNS failure, timeout, connection refused) into
  /// the timeline — the failures the interceptor's [interceptResponse]
  /// can't see. Pass it as the `InterceptedClient` / `InterceptedHttp`
  /// `retryPolicy`.
  ///
  /// On its own it adds no retries: it reports one allowable attempt
  /// (enough for `http_interceptor` to invoke the exception hook) and then
  /// declines to retry, so the original exception still propagates after a
  /// single send. Pass [wrapping] to delegate the actual retry decision to
  /// your own policy while still logging failures; its retry behavior is
  /// preserved. Note that when a wrapped policy exhausts its retries, the
  /// final failed attempt is rethrown by `http_interceptor` without
  /// consulting the policy, so that last attempt is not recorded.
  RetryPolicy retryPolicy({RetryPolicy? wrapping}) =>
      _FailureLoggingRetryPolicy(_inFlight, wrapping);

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

/// [RetryPolicy] that records send-time failures for
/// [TurboBridgeHttpInterceptor] and otherwise defers to an optional inner
/// policy. Created via [TurboBridgeHttpInterceptor.retryPolicy] so it
/// shares the interceptor's in-flight handle map.
class _FailureLoggingRetryPolicy implements RetryPolicy {
  _FailureLoggingRetryPolicy(this._inFlight, this._inner);

  final Expando<InFlightNetworkCall> _inFlight;
  final RetryPolicy? _inner;

  @override
  int get maxRetryAttempts {
    // Must be >= 1 so `http_interceptor` actually calls our exception hook
    // (it rethrows without consulting the policy once attempts are
    // exhausted). When wrapping, never report fewer attempts than the inner
    // policy wants, so its retry behavior is preserved.
    final inner = _inner?.maxRetryAttempts ?? 0;
    return inner < 1 ? 1 : inner;
  }

  @override
  FutureOr<bool> shouldAttemptRetryOnException(
    Exception reason,
    BaseRequest request,
  ) {
    // The interceptor's interceptResponse never fires when send throws, so
    // this is our only chance to record the failure. `fail()` finalizes the
    // handle; if the inner policy retries, the next attempt opens a fresh
    // handle, so each real attempt yields its own timeline entry.
    final nf = _inFlight[request];
    if (nf != null) {
      try {
        nf.fail(reason);
      } catch (_) {}
    }
    return _inner?.shouldAttemptRetryOnException(reason, request) ?? false;
  }

  @override
  FutureOr<bool> shouldAttemptRetryOnResponse(BaseResponse response) =>
      _inner?.shouldAttemptRetryOnResponse(response) ?? false;

  @override
  Duration delayRetryAttemptOnException({required int retryAttempt}) =>
      _inner?.delayRetryAttemptOnException(retryAttempt: retryAttempt) ??
      Duration.zero;

  @override
  Duration delayRetryAttemptOnResponse({required int retryAttempt}) =>
      _inner?.delayRetryAttemptOnResponse(retryAttempt: retryAttempt) ??
      Duration.zero;
}
