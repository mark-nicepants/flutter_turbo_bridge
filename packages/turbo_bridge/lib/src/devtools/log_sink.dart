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

  /// File URI of the call site that produced this log (e.g.
  /// `file:///Users/.../main.dart` or `package:foo/bar.dart`). Captured
  /// from `StackTrace.current` inside `LogSink.add`; null when the
  /// stack frame can't be parsed (release builds, AOT obfuscation).
  final String? sourceFile;

  /// 1-based line number of the call site.
  final int? sourceLine;

  /// 1-based column number of the call site.
  final int? sourceColumn;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    this.category,
    this.data,
    this.errorString,
    this.stackTrace,
    this.sourceFile,
    this.sourceLine,
    this.sourceColumn,
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
        if (sourceFile != null) 'sourceFile': sourceFile,
        if (sourceLine != null) 'sourceLine': sourceLine,
        if (sourceColumn != null) 'sourceColumn': sourceColumn,
      };
}

/// Parsed call-site location.
class _SourceFrame {
  final String file;
  final int line;
  final int column;
  const _SourceFrame(this.file, this.line, this.column);
}

/// Parse the first user frame from a `StackTrace.current` string.
///
/// Frames produced by `LogSink.add` itself (or one of the public
/// shortcut methods like `info`/`warn`) are skipped so we land on the
/// caller's code. Returns null when no usable frame is found —
/// typically in release/AOT builds where line info is stripped.
_SourceFrame? _firstUserFrame(StackTrace trace) {
  // Standard VM frames look like:
  //   #2      MyClass.doStuff (file:///abs/path.dart:42:5)
  //   #3      _RootZone.runUnary (dart:async/zone.dart:1407:47)
  // Web frames have a different shape; we still try the same regex.
  final pattern = RegExp(r'\(([^()]+):(\d+):(\d+)\)');
  for (final raw in trace.toString().split('\n')) {
    // Skip the bookkeeping frames inside this file.
    if (raw.contains('log_sink.dart')) continue;
    final m = pattern.firstMatch(raw);
    if (m == null) continue;
    final file = m.group(1)!;
    // Drop `dart:` core frames — they're internals, not user code.
    if (file.startsWith('dart:')) continue;
    final line = int.tryParse(m.group(2)!);
    final col = int.tryParse(m.group(3)!);
    if (line == null || col == null) continue;
    return _SourceFrame(file, line, col);
  }
  return null;
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
  ///
  /// The call site (file + line + column) is captured automatically by
  /// peeking at `StackTrace.current` and skipping frames inside this
  /// file. DevTools renders the result as a `vscode://` link so you
  /// can ⌘-click straight into the editor. Pass `captureSource: false`
  /// to opt out (cheap, but not free).
  LogEntry add({
    required String message,
    LogLevel level = LogLevel.info,
    String? category,
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
    bool captureSource = true,
  }) {
    _SourceFrame? source;
    if (captureSource) {
      source = _firstUserFrame(StackTrace.current);
    }
    final entry = LogEntry(
      id: _nextId++,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      level: level,
      message: message,
      category: category,
      data: data,
      errorString: error?.toString(),
      stackTrace: stackTrace?.toString(),
      sourceFile: source?.file,
      sourceLine: source?.line,
      sourceColumn: source?.column,
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
