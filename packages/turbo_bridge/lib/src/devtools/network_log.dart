import 'dart:collection';

import 'event_bus.dart';

/// One outbound HTTP call recorded by the app.
class NetworkCall {
  final int id;
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String>? requestHeaders;
  final String? requestBody;
  final int? requestBodySize;
  final int? status;
  final Map<String, String>? responseHeaders;
  final String? responseBody;
  final int? responseBodySize;
  final int? durationMs;
  final String? error;

  NetworkCall({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    this.requestHeaders,
    this.requestBody,
    this.requestBodySize,
    this.status,
    this.responseHeaders,
    this.responseBody,
    this.responseBodySize,
    this.durationMs,
    this.error,
  });

  Map<String, dynamic> toSummaryJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'method': method,
        'url': url,
        if (status != null) 'status': status,
        if (durationMs != null) 'durationMs': durationMs,
        if (error != null) 'error': error,
        if (responseBodySize != null) 'responseBodySize': responseBodySize,
      };

  Map<String, dynamic> toDetailJson() => {
        ...toSummaryJson(),
        if (requestHeaders != null) 'requestHeaders': requestHeaders,
        if (requestBody != null) 'requestBody': requestBody,
        if (requestBodySize != null) 'requestBodySize': requestBodySize,
        if (responseHeaders != null) 'responseHeaders': responseHeaders,
        if (responseBody != null) 'responseBody': responseBody,
      };
}

/// Ring buffer for app-recorded HTTP/network activity.
///
/// Public API: `TurboBridge.instance.network.record(...)`. Apps wire this
/// into their Dio interceptor / http hooks / GraphQL client to surface
/// what the app is talking to behind the scenes.
class NetworkLog {
  final int capacity;
  final DevToolsEventBus _bus;
  final Queue<NetworkCall> _entries = Queue<NetworkCall>();
  int _nextId = 1;

  NetworkLog({required DevToolsEventBus bus, this.capacity = 300}) : _bus = bus;

  int get length => _entries.length;

  List<NetworkCall> snapshot() => List.unmodifiable(_entries);

  NetworkCall? byId(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Record a completed (or failed) network call.
  ///
  /// Apps that want streaming updates (request started, then completed)
  /// should call [record] once at completion. We don't track "in-flight"
  /// calls in v1.
  NetworkCall record({
    required String method,
    required String url,
    Map<String, String>? requestHeaders,
    String? requestBody,
    int? requestBodySize,
    int? status,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? responseBodySize,
    int? durationMs,
    Object? error,
    DateTime? timestamp,
  }) {
    final entry = NetworkCall(
      id: _nextId++,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      requestBodySize: requestBodySize ?? requestBody?.length,
      status: status,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      responseBodySize: responseBodySize ?? responseBody?.length,
      durationMs: durationMs,
      error: error?.toString(),
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _bus.emit(DevToolsEvent('network', entry.toSummaryJson()));
    return entry;
  }

  void clear() => _entries.clear();
}
