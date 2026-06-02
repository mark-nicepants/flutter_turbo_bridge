/// Dio interceptor that forwards every request into
/// [TurboBridge.instance.network] so it shows up on the DevTools
/// timeline.
///
/// Add `dio: ^5.0.0` to your app's pubspec.yaml — this file is only
/// compiled when you import it, so the rest of `turbo_bridge` works
/// without Dio.
///
/// ```dart
/// import 'package:dio/dio.dart';
/// import 'package:turbo_bridge/interceptors/dio.dart';
///
/// final dio = Dio();
/// dio.interceptors.add(TurboBridgeDioInterceptor());
/// ```
library;

import 'package:dio/dio.dart';

import '../src/bridge.dart';
import '../src/devtools/network_log.dart';

class TurboBridgeDioInterceptor extends Interceptor {
  /// Optional override for the URL to record. Defaults to
  /// `requestOptions.uri.toString()`. Use this if you want to strip
  /// query strings, mask secrets in the path, or rewrite the host.
  final String Function(RequestOptions options)? urlFor;

  /// Cap on the body size we record (bytes). Bodies above this cap
  /// are recorded as `<body N bytes>`. Defaults to 16 KB.
  final int maxBodySize;

  TurboBridgeDioInterceptor({this.urlFor, this.maxBodySize = 16 * 1024});

  /// Key used to stash the in-flight handle on `RequestOptions.extra`.
  static const String _key = '__turbo_bridge_inflight';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final network = _networkOrNull();
    if (network != null) {
      try {
        final body = _bodyToString(options.data);
        options.extra[_key] = network.start(
          method: options.method,
          url: urlFor?.call(options) ?? options.uri.toString(),
          requestHeaders: _flattenHeaders(options.headers),
          requestBody: body == null ? null : _cap(body),
          requestBodySize: body?.length,
        );
      } catch (_) {
        // Never let logging take down the actual HTTP call.
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final nf = response.requestOptions.extra.remove(_key);
    if (nf is InFlightNetworkCall) {
      try {
        final body = _bodyToString(response.data);
        nf.complete(
          status: response.statusCode,
          responseHeaders: _flattenStringListHeaders(response.headers.map),
          responseBody: body == null ? null : _cap(body),
          responseBodySize: body?.length,
        );
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final nf = err.requestOptions.extra.remove(_key);
    if (nf is InFlightNetworkCall) {
      try {
        nf.fail(err, status: err.response?.statusCode);
      } catch (_) {}
    }
    handler.next(err);
  }

  NetworkLog? _networkOrNull() {
    try {
      return TurboBridge.instance.network;
    } catch (_) {
      return null;
    }
  }

  String? _bodyToString(Object? data) {
    if (data == null) return null;
    if (data is String) return data;
    return data.toString();
  }

  String _cap(String s) {
    if (s.length <= maxBodySize) return s;
    return s.substring(0, maxBodySize);
  }

  Map<String, String> _flattenHeaders(Map<String, dynamic> headers) {
    return headers.map((k, v) {
      if (v is List) return MapEntry(k, v.join(', '));
      return MapEntry(k, v.toString());
    });
  }

  Map<String, String> _flattenStringListHeaders(
    Map<String, List<String>> headers,
  ) {
    return headers.map((k, v) => MapEntry(k, v.join(', ')));
  }
}
