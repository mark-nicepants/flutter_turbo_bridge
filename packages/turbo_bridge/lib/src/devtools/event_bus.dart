import 'dart:async';

/// A single DevTools event pushed to subscribers via SSE.
class DevToolsEvent {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  DevToolsEvent(this.type, this.payload, {DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'payload': payload,
      };
}

/// Broadcasts DevTools events to any number of SSE subscribers.
///
/// Producers (the request-log instrumentation, route observer, etc.) call
/// [emit]. The DevTools router exposes [stream] as a broadcast stream so
/// multiple browser tabs can subscribe at once.
class DevToolsEventBus {
  final StreamController<DevToolsEvent> _controller =
      StreamController<DevToolsEvent>.broadcast();

  Stream<DevToolsEvent> get stream => _controller.stream;

  void emit(DevToolsEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
