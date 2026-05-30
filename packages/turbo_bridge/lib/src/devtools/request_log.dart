import 'dart:collection';

/// Cap on captured request/response bodies (bytes). Above this we keep
/// the prefix and mark the entry as truncated so the UI can warn.
const int _bodyExcerptMax = 16 * 1024;

/// One JSON-API request seen by the bridge.
class RequestLogEntry {
  final int id;
  final DateTime timestamp;
  final String method;
  final String path;
  final String? query;
  final int status;
  final int durationMs;
  final String? remoteAddress;
  final Map<String, String>? requestHeaders;
  final String? requestBody;
  final int? requestBodySize;
  final bool requestBodyTruncated;
  final Map<String, String>? responseHeaders;
  final String? responseBody;
  final int? responseBodySize;
  final bool responseBodyTruncated;

  RequestLogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.path,
    required this.query,
    required this.status,
    required this.durationMs,
    required this.remoteAddress,
    this.requestHeaders,
    this.requestBody,
    this.requestBodySize,
    this.requestBodyTruncated = false,
    this.responseHeaders,
    this.responseBody,
    this.responseBodySize,
    this.responseBodyTruncated = false,
  });

  /// Compact summary for log-list views.
  Map<String, dynamic> toSummaryJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'method': method,
        'path': path,
        if (query != null && query!.isNotEmpty) 'query': query,
        'status': status,
        'durationMs': durationMs,
        if (remoteAddress != null) 'remoteAddress': remoteAddress,
        if (responseBodySize != null) 'responseBodySize': responseBodySize,
      };

  /// Full detail for the per-request panel.
  Map<String, dynamic> toDetailJson() => {
        ...toSummaryJson(),
        if (requestHeaders != null) 'requestHeaders': requestHeaders,
        if (requestBody != null) 'requestBody': requestBody,
        if (requestBodySize != null) 'requestBodySize': requestBodySize,
        if (requestBodyTruncated) 'requestBodyTruncated': true,
        if (responseHeaders != null) 'responseHeaders': responseHeaders,
        if (responseBody != null) 'responseBody': responseBody,
        if (responseBodyTruncated) 'responseBodyTruncated': true,
      };

  /// Backwards-compatible alias used by older callers/tests.
  Map<String, dynamic> toJson() => toSummaryJson();
}

/// In-memory ring buffer of recent JSON-API requests, exposed to the
/// DevTools UI via `/api/devtools/requests`.
class RequestLog {
  final int capacity;
  final Queue<RequestLogEntry> _entries = Queue<RequestLogEntry>();
  int _nextId = 1;

  RequestLog({this.capacity = 200});

  int get length => _entries.length;

  List<RequestLogEntry> snapshot() => List.unmodifiable(_entries);

  RequestLogEntry? byId(int id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  RequestLogEntry record({
    required String method,
    required String path,
    required String? query,
    required int status,
    required int durationMs,
    required String? remoteAddress,
    Map<String, String>? requestHeaders,
    List<int>? requestBodyBytes,
    Map<String, String>? responseHeaders,
    List<int>? responseBodyBytes,
  }) {
    final reqExcerpt = _excerpt(requestBodyBytes);
    final resExcerpt = _excerpt(responseBodyBytes);
    final entry = RequestLogEntry(
      id: _nextId++,
      timestamp: DateTime.now().toUtc(),
      method: method,
      path: path,
      query: query,
      status: status,
      durationMs: durationMs,
      remoteAddress: remoteAddress,
      requestHeaders: requestHeaders,
      requestBody: reqExcerpt?.body,
      requestBodySize: requestBodyBytes?.length,
      requestBodyTruncated: reqExcerpt?.truncated ?? false,
      responseHeaders: responseHeaders,
      responseBody: resExcerpt?.body,
      responseBodySize: responseBodyBytes?.length,
      responseBodyTruncated: resExcerpt?.truncated ?? false,
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    return entry;
  }

  void clear() {
    _entries.clear();
  }
}

class _BodyExcerpt {
  final String body;
  final bool truncated;
  const _BodyExcerpt(this.body, this.truncated);
}

_BodyExcerpt? _excerpt(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  final truncated = bytes.length > _bodyExcerptMax;
  final slice =
      truncated ? bytes.sublist(0, _bodyExcerptMax) : bytes;
  // Try UTF-8 first; on failure (binary payload), return base64-ish marker.
  try {
    final s = String.fromCharCodes(slice);
    // Heuristic: if a lot of nulls, treat as binary.
    var nulls = 0;
    for (var i = 0; i < s.length && i < 256; i++) {
      if (s.codeUnitAt(i) == 0) nulls++;
    }
    if (nulls > 4) {
      return _BodyExcerpt('<binary ${bytes.length} bytes>', truncated);
    }
    return _BodyExcerpt(s, truncated);
  } catch (_) {
    return _BodyExcerpt('<binary ${bytes.length} bytes>', truncated);
  }
}
