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

  /// Mark the start of a network call. Returns a handle to call
  /// `complete()` or `fail()` on when the response arrives.
  ///
  /// Today this only buffers the request fields; the entry doesn't
  /// appear in the timeline until you call `complete()` (or `fail()`).
  /// See `docs/INFLIGHT_NETWORK_PLAN.md` for the planned evolution to
  /// also surface in-flight requests in the DevTools timeline.
  ///
  /// Use this in HTTP interceptors (Dio, http_interceptor, GraphQL
  /// clients) so request/response correlation is automatic and the
  /// recorded `durationMs` matches the real wall-clock time spent.
  InFlightNetworkCall start({
    required String method,
    required String url,
    Map<String, String>? requestHeaders,
    String? requestBody,
    int? requestBodySize,
    DateTime? timestamp,
  }) {
    return InFlightNetworkCall._(
      log: this,
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      requestBodySize: requestBodySize ?? requestBody?.length,
      startedAt: timestamp ?? DateTime.now(),
    );
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

/// Handle returned by `NetworkLog.start`. Call exactly one of
/// `complete`, `fail`, or `cancel`. Subsequent calls are no-ops, so
/// the same handle is safe to share with both response and error
/// hooks of an HTTP client.
class InFlightNetworkCall {
  final NetworkLog _log;
  final String _method;
  final String _url;
  final Map<String, String>? _requestHeaders;
  final String? _requestBody;
  final int? _requestBodySize;
  final DateTime _startedAt;
  bool _done = false;

  InFlightNetworkCall._({
    required NetworkLog log,
    required String method,
    required String url,
    required Map<String, String>? requestHeaders,
    required String? requestBody,
    required int? requestBodySize,
    required DateTime startedAt,
  })  : _log = log,
        _method = method,
        _url = url,
        _requestHeaders = requestHeaders,
        _requestBody = requestBody,
        _requestBodySize = requestBodySize,
        _startedAt = startedAt;

  /// Whether this call has been finalized (completed, failed, or cancelled).
  bool get isDone => _done;

  /// Record the response and finalize.
  void complete({
    int? status,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? responseBodySize,
  }) {
    if (_done) return;
    _done = true;
    final endedAt = DateTime.now();
    _log.record(
      method: _method,
      url: _url,
      requestHeaders: _requestHeaders,
      requestBody: _requestBody,
      requestBodySize: _requestBodySize,
      status: status,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      responseBodySize: responseBodySize,
      durationMs: endedAt.difference(_startedAt).inMilliseconds,
      timestamp: _startedAt,
    );
  }

  /// Record a failed request (network error, timeout, etc) and finalize.
  void fail(Object error, {int? status}) {
    if (_done) return;
    _done = true;
    final endedAt = DateTime.now();
    _log.record(
      method: _method,
      url: _url,
      requestHeaders: _requestHeaders,
      requestBody: _requestBody,
      requestBodySize: _requestBodySize,
      status: status,
      durationMs: endedAt.difference(_startedAt).inMilliseconds,
      error: error,
      timestamp: _startedAt,
    );
  }

  /// Drop the in-flight call without recording anything. Useful when
  /// the host app decides the request shouldn't be logged after all.
  void cancel() {
    _done = true;
  }
}
