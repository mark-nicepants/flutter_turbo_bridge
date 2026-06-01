/// `http_interceptor` adapter that forwards every request into
/// [TurboBridge.instance.network] so it shows up on the DevTools
/// timeline.
///
/// Add `http_interceptor: ^3.0.0` to your app's pubspec.yaml — this
/// file is only compiled when you import it, so the rest of
/// `turbo_bridge` works without `http_interceptor`.
///
/// ```dart
/// import 'package:http_interceptor/http_interceptor.dart';
/// import 'package:turbo_bridge/interceptors/http_interceptor.dart';
///
/// final client = InterceptedClient.build(
///   interceptors: [TurboBridgeHttpInterceptor()],
/// );
/// ```
library;

// `http_interceptor` is intentionally a dev_dependency — consumers add
// it to their own pubspec when they want to use this adapter.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:http_interceptor/http_interceptor.dart';

import '../src/bridge.dart';
import '../src/devtools/network_log.dart';

class TurboBridgeHttpInterceptor implements HttpInterceptor {
  /// Optional override for the URL to record. Defaults to
  /// `request.url.toString()`. Use this if you want to strip query
  /// strings, mask secrets in the path, or rewrite the host.
  final String Function(BaseRequest request)? urlFor;

  /// Cap on the body size we record (bytes). Bodies above this cap
  /// are truncated. Defaults to 16 KB.
  final int maxBodySize;

  TurboBridgeHttpInterceptor({this.urlFor, this.maxBodySize = 16 * 1024});

  /// `BaseRequest` has no `extra`/`tag` field, so we correlate requests
  /// to responses via an [Expando] keyed on the request instance. The
  /// expando holds entries weakly, so cancelled/dropped requests don't
  /// leak.
  static final Expando<InFlightNetworkCall> _inflight =
      Expando<InFlightNetworkCall>('turbo_bridge_inflight');

  @override
  FutureOr<BaseRequest> interceptRequest({required BaseRequest request}) {
    final network = _networkOrNull();
    if (network != null) {
      try {
        final body = _requestBody(request);
        _inflight[request] = network.start(
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
  FutureOr<bool> shouldInterceptRequest({required BaseRequest request}) => true;

  @override
  FutureOr<bool> shouldInterceptResponse({required BaseResponse response}) =>
      true;

  @override
  FutureOr<BaseResponse> interceptResponse({required BaseResponse response}) {
    final req = response.request;
    if (req != null) {
      final nf = _inflight[req];
      _inflight[req] = null;
      if (nf != null) {
        try {
          final body = _responseBody(response);
          nf.complete(
            status: response.statusCode,
            responseHeaders: Map<String, String>.from(response.headers),
            responseBody: body == null ? null : _cap(body),
            responseBodySize: body?.length ?? response.contentLength,
          );
        } catch (_) {}
      }
    }
    return response;
  }

  NetworkLog? _networkOrNull() {
    try {
      return TurboBridge.instance.network;
    } catch (_) {
      return null;
    }
  }

  String? _requestBody(BaseRequest request) {
    if (request is Request) return request.body;
    return null;
  }

  String? _responseBody(BaseResponse response) {
    if (response is Response) return response.body;
    return null;
  }

  String _cap(String s) {
    if (s.length <= maxBodySize) return s;
    return s.substring(0, maxBodySize);
  }
}
