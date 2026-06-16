import 'dart:collection';

import 'event_bus.dart';

/// One outbound HTTP call recorded by the app.
///
/// Request fields are fixed at creation; the response/outcome fields are
/// mutable so an in-flight call (created by [NetworkLog.start]) can be
/// finalized in place when [InFlightNetworkCall.complete] / `.fail` runs,
/// and any held snapshot reflects the live state.
class NetworkCall {
  final int id;
  final DateTime timestamp;
  final String method;
  final String url;
  final Map<String, String>? requestHeaders;
  final String? requestBody;
  final int? requestBodySize;
  int? status;
  Map<String, String>? responseHeaders;
  String? responseBody;
  int? responseBodySize;
  int? durationMs;
  String? error;

  /// True between [NetworkLog.start] and the matching `complete`/`fail`.
  /// The DevTools UI renders in-flight calls as a growing yellow bar.
  bool inFlight;

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
    this.inFlight = false,
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
    'inFlight': inFlight,
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
  /// The call is surfaced on the timeline immediately as an in-flight
  /// entry (`inFlight: true`): a ring-buffer row is added and a `network`
  /// event is emitted right away, so a slow request is visible while it's
  /// still running rather than only after it finishes. `complete()` /
  /// `fail()` then mutate the same entry and re-emit with the final
  /// fields. See `docs/INFLIGHT_NETWORK_PLAN.md`.
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
    final startedAt = timestamp ?? DateTime.now();
    final entry = NetworkCall(
      id: _nextId++,
      timestamp: startedAt.toUtc(),
      method: method,
      url: url,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      requestBodySize: requestBodySize ?? requestBody?.length,
      inFlight: true,
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _bus.emit(DevToolsEvent('network', entry.toSummaryJson()));
    return InFlightNetworkCall._(log: this, entry: entry, startedAt: startedAt);
  }

  /// Re-emit an in-flight entry after it has been finalized. Drops
  /// silently if the entry was evicted from the ring buffer while in
  /// flight (the cap is an explicit "we lose old data" contract).
  void _finalizeInFlight(NetworkCall entry) {
    if (!_entries.contains(entry)) return;
    _bus.emit(DevToolsEvent('network', entry.toSummaryJson()));
  }

  /// Remove an in-flight entry that was cancelled before completing.
  /// Notifies the UI so the growing bar disappears.
  void _removeInFlight(NetworkCall entry) {
    if (!_entries.remove(entry)) return;
    _bus.emit(DevToolsEvent('network', {'id': entry.id, 'removed': true}));
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
///
/// The backing [NetworkCall] is already on the timeline (in-flight) when
/// this handle is created; finalizing mutates that same entry in place.
class InFlightNetworkCall {
  final NetworkLog _log;
  final NetworkCall _entry;
  final DateTime _startedAt;
  bool _done = false;

  InFlightNetworkCall._({
    required NetworkLog log,
    required NetworkCall entry,
    required DateTime startedAt,
  }) : _log = log,
       _entry = entry,
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
    _entry
      ..status = status
      ..responseHeaders = responseHeaders
      ..responseBody = responseBody
      ..responseBodySize = responseBodySize ?? responseBody?.length
      ..durationMs = DateTime.now().difference(_startedAt).inMilliseconds
      ..inFlight = false;
    _log._finalizeInFlight(_entry);
  }

  /// Record a failed request (network error, timeout, etc) and finalize.
  ///
  /// Some clients (such as Dio) route HTTP 4xx/5xx through their error
  /// callback while still exposing a response body. In that case pass the
  /// optional response fields so DevTools can show the server error payload.
  void fail(
    Object error, {
    int? status,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? responseBodySize,
  }) {
    if (_done) return;
    _done = true;
    _entry
      ..status = status
      ..responseHeaders = responseHeaders
      ..responseBody = responseBody
      ..responseBodySize = responseBodySize ?? responseBody?.length
      ..durationMs = DateTime.now().difference(_startedAt).inMilliseconds
      ..error = error.toString()
      ..inFlight = false;
    _log._finalizeInFlight(_entry);
  }

  /// Drop the in-flight call without recording anything. Useful when
  /// the host app decides the request shouldn't be logged after all.
  /// Removes the in-flight entry from the timeline.
  void cancel() {
    if (_done) return;
    _done = true;
    _log._removeInFlight(_entry);
  }
}
