import 'dart:collection';

import 'event_bus.dart';

/// Severity for an app-emitted log line.
enum LogLevel { trace, debug, info, warn, error }

String _levelName(LogLevel l) => switch (l) {
      LogLevel.trace => 'trace',
      LogLevel.debug => 'debug',
      LogLevel.info => 'info',
      LogLevel.warn => 'warn',
      LogLevel.error => 'error',
    };

/// One log entry pushed in by the host app.
class LogEntry {
  final int id;
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? category;
  final Map<String, dynamic>? data;
  final String? errorString;
  final String? stackTrace;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    this.category,
    this.data,
    this.errorString,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'level': _levelName(level),
        'message': message,
        if (category != null) 'category': category,
        if (data != null) 'data': data,
        if (errorString != null) 'error': errorString,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

/// Ring buffer for app-emitted log lines.
///
/// Public API for app authors: `TurboBridge.instance.logs.add(...)`. The
/// DevTools UI and MCP tools consume this via the bridge's HTTP endpoints
/// and SSE event stream.
class LogSink {
  final int capacity;
  final DevToolsEventBus _bus;
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  int _nextId = 1;

  LogSink({required DevToolsEventBus bus, this.capacity = 500}) : _bus = bus;

  int get length => _entries.length;

  List<LogEntry> snapshot() => List.unmodifiable(_entries);

  /// Append a log entry. Safe to call from any isolate.
  LogEntry add({
    required String message,
    LogLevel level = LogLevel.info,
    String? category,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
  }) {
    final entry = LogEntry(
      id: _nextId++,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      level: level,
      message: message,
      category: category,
      data: data,
      errorString: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _bus.emit(DevToolsEvent('log', entry.toJson()));
    return entry;
  }

  /// Shortcut for the common levels.
  LogEntry trace(String message,
          {String? category, Map<String, dynamic>? data}) =>
      add(
          level: LogLevel.trace,
          message: message,
          category: category,
          data: data);
  LogEntry debug(String message,
          {String? category, Map<String, dynamic>? data}) =>
      add(
          level: LogLevel.debug,
          message: message,
          category: category,
          data: data);
  LogEntry info(String message,
          {String? category, Map<String, dynamic>? data}) =>
      add(
          level: LogLevel.info,
          message: message,
          category: category,
          data: data);
  LogEntry warn(String message,
          {String? category,
          Map<String, dynamic>? data,
          Object? error,
          StackTrace? stackTrace}) =>
      add(
        level: LogLevel.warn,
        message: message,
        category: category,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );
  LogEntry error(String message,
          {String? category,
          Map<String, dynamic>? data,
          Object? error,
          StackTrace? stackTrace}) =>
      add(
        level: LogLevel.error,
        message: message,
        category: category,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  /// Drop everything. Mainly for tests.
  void clear() => _entries.clear();
}
