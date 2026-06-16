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

import 'dart:convert';

import 'package:dio/dio.dart';

import '../src/bridge.dart';
import '../src/devtools/network_log.dart';

class TurboBridgeDioInterceptor extends Interceptor {
  /// Optional override for the URL to record. Defaults to
  /// `requestOptions.uri.toString()`. Use this if you want to strip
  /// query strings, mask secrets in the path, or rewrite the host.
  final String Function(RequestOptions options)? urlFor;

  /// Cap on the body size we record (bytes). Bodies above this cap
  /// are truncated to the prefix. Defaults to 512 KB.
  final int maxBodySize;

  TurboBridgeDioInterceptor({this.urlFor, this.maxBodySize = 512 * 1024});

  /// Key used to stash the in-flight handle on `RequestOptions.extra`.
  static const String _key = '__turbo_bridge_inflight';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final network = _networkOrNull();
    if (network != null) {
      try {
        final rawBody = _serializeBody(options.data);
        final body = _bodyToDisplayString(
          options.data,
          contentType: _requestContentType(options),
        );
        options.extra[_key] = network.start(
          method: options.method,
          url: urlFor?.call(options) ?? options.uri.toString(),
          requestHeaders: _flattenHeaders(options.headers),
          requestBody: body == null ? null : _cap(body),
          requestBodySize: rawBody?.length,
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
        final rawBody = _serializeBody(response.data);
        final body = _bodyToDisplayString(
          response.data,
          contentType: _responseContentType(response),
        );
        nf.complete(
          status: response.statusCode,
          responseHeaders: _flattenStringListHeaders(response.headers.map),
          responseBody: body == null ? null : _cap(body),
          responseBodySize: rawBody?.length,
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
        final response = err.response;
        final rawBody = _serializeBody(response?.data);
        final body = response == null
            ? null
            : _bodyToDisplayString(
                response.data,
                contentType: _responseContentType(response),
              );
        nf.fail(
          err,
          status: response?.statusCode,
          responseHeaders: response == null
              ? null
              : _flattenStringListHeaders(response.headers.map),
          responseBody: body == null ? null : _cap(body),
          responseBodySize: rawBody?.length,
        );
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

  String? _serializeBody(Object? data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is FormData) {
      try {
        return jsonEncode(_formDataSummary(data));
      } catch (_) {
        return data.toString();
      }
    }
    if (data is Map || data is List) {
      try {
        return jsonEncode(data);
      } catch (_) {}
    }
    return data.toString();
  }

  String? _bodyToDisplayString(Object? data, {String? contentType}) {
    if (data is FormData) {
      try {
        return const JsonEncoder.withIndent(
          '  ',
        ).convert(_formDataSummary(data));
      } catch (_) {
        // Fall back when FormData contains values we cannot serialize.
        return _serializeBody(data);
      }
    }

    final serialized = _serializeBody(data);
    if (serialized == null) return null;

    final isJson =
        _isJsonContentType(contentType) || data is Map || data is List;
    if (!isJson) return serialized;

    try {
      final decoded = jsonDecode(serialized);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      // Fall back to the raw serialized body when JSON parsing fails.
      return serialized;
    }
  }

  String? _requestContentType(RequestOptions options) {
    final fromOptions = options.contentType;
    if (fromOptions != null && fromOptions.isNotEmpty) return fromOptions;
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() == Headers.contentTypeHeader) {
        return entry.value.toString();
      }
    }
    return null;
  }

  String? _responseContentType(Response<dynamic> response) {
    for (final entry in response.headers.map.entries) {
      if (entry.key.toLowerCase() == Headers.contentTypeHeader) {
        final values = entry.value;
        if (values.isNotEmpty) return values.first;
      }
    }
    return null;
  }

  bool _isJsonContentType(String? contentType) {
    if (contentType == null) return false;
    final value = contentType.toLowerCase();
    return value.contains('/json') || value.contains('+json');
  }

  Map<String, Object?> _formDataSummary(FormData data) {
    return {
      'type': 'multipart/form-data',
      'fieldCount': data.fields.length,
      'fields': [
        for (final field in data.fields)
          {'name': field.key, 'value': field.value},
      ],
      'fileCount': data.files.length,
      'files': [
        for (final file in data.files)
          {'field': file.key, ..._multipartFileSummary(file.value)},
      ],
    };
  }

  Map<String, Object?> _multipartFileSummary(MultipartFile file) {
    return {
      if (file.filename != null) 'filename': file.filename,
      'length': file.length,
      if (file.contentType != null) 'contentType': file.contentType.toString(),
      if (file.headers != null && file.headers!.isNotEmpty)
        'headers': file.headers!.map((k, v) => MapEntry(k, v.join(', '))),
    };
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
